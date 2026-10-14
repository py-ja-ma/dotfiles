# install/windows/dram-windows/dram.ps1 - dram on Windows (docs/platforms/windows/dram-ps1.md).
#
# The flake renders a Windows host into windows/build/<host>/ (the winget documents and
# manifest.json). bin/push-windows.sh on the Mac stages that render and every file its manifest
# lists in C:\ProgramData\dram\incoming and runs `receive` with the incoming copy of this script,
# which checks every file's sha256 and switches C:\ProgramData\dram to the release. `apply`
# converges the PC to the live release as converge.ps1 did: each phase's documents through
# `winget configure`, then its scripts, then the look on the signed-in desktop. Commands, options
# and exit codes mirror Arch's dram (dotfiles/.local/bin/dram); `dram help` lists them. receive
# installs this file as C:\ProgramData\dram\dram.ps1 and a dram.cmd shim in
# C:\ProgramData\dram\bin on the machine PATH, so `ssh <host> dram version -Json` works.
#
# C:\ProgramData\dram, as receive leaves it:
#   dram.ps1, bin\dram.cmd   this script and its shim
#   build\                   the live render: manifest.json and the documents, plus what
#                            push-windows.sh adds: packages.tsv (the winget and Store ids the
#                            documents declare) and push.json (the version, build and commit it
#                            pushed); and files.sha256, every file the release put here
#   build.previous\          the render before it (rollback reads it)
#   state.json               version, build, commit, received, applied, previous, channel, doctor
#   incoming\                what push-windows.sh staged, until a receive takes it
#   the release's files      scripts at the top (their tasks name them there), fonts\, cursors\,
#                            letterpress\, avatar\ ...
#   the scripts' own state   logs, icons\, start-tidy\, cache\ ... never touched by receive
# A file the release before listed and this one does not is deleted; nothing else is.
#
# Windows PowerShell 5.1 (no ??, ternary or && between commands), ASCII only. Files go through
# .NET or -LiteralPath: font names hold [ and ], which -Path reads as wildcards. Messages go to
# Write-Host, so a function returns only what it returns (Write-Output inside one joins its
# return value: the trap wsl.ps1 documents). receive, update, apply and channel need an elevated
# PowerShell (an administrator's ssh login is one; doctor skips what needs it without); apply
# never runs as SYSTEM, which would write SYSTEM's HKCU and has no winget.
#   powershell -ExecutionPolicy Bypass -File C:\ProgramData\dram\dram.ps1 <command> [options]
# Exit: 0 ok - 1 the command failed, or doctor found a warning - 2 bad usage

$ErrorActionPreference = 'Continue'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
try { [Console]::OutputEncoding = $Utf8 } catch { }
# Windows PowerShell 5.1's type data gives arrays a Count that ConvertTo-Json would write as
# {"value": [...], "Count": n}; without it they stay arrays (look.ps1 does the same)
if ($PSVersionTable.PSVersion.Major -lt 6) { Remove-TypeData -TypeName System.Array -ErrorAction SilentlyContinue }

$Argv = @($args)
$Self = $PSCommandPath
$Here = Split-Path -Parent $Self
# the incoming copy (push-windows.sh runs it for the receive) works on the folder above it
$Root = $Here
if ((Split-Path -Leaf $Here) -eq 'incoming') { $Root = Split-Path -Parent $Here }
$Build = Join-Path $Root 'build'
$Prev = Join-Path $Root 'build.previous'
$Incoming = Join-Path $Root 'incoming'
$StateFile = Join-Path $Root 'state.json'
$BinDir = Join-Path $Root 'bin'
$LogFile = Join-Path $Root 'dram.log'
$PSExe = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
$PhaseNames = [ordered]@{ '00' = 'debloat'; '10' = 'system'; '20' = 'user'; '30' = 'apps'; '40' = 'autostart'; '50' = 'ask' }
$StateKeys = 'host', 'channel', 'version', 'tagged', 'ahead', 'build', 'commit', 'branch', 'date', 'pushed_at', 'received_at', 'render', 'applied', 'previous', 'doctor'
# what winget configure prints that says something (converge.ps1's filter)
$WingetLines = '^\S.*\[|^\s+(Unit |The |System\.)|successfully|not in the desired|is in the desired|was not'
# a -DryRun line that would change something: "[would] app: ..." (look, icons), or "would ..."
# after an optional date and time (debloat, autostart, account-picture, boot-guard); never the
# summary lines, which start with "=="
$WouldLine = '^(\d{4}-\d\d-\d\d\s+)?(\d\d:\d\d:\d\d\s+)?\s*(\[would\]|would\s)'

$Help = @'
usage: dram <command> [options]   (Windows: C:\ProgramData\dram\dram.ps1)
  status                   the live release, its last apply, what the last doctor saw
  version [-Json]          the live release: version, build, commit, channel, received, applied
  channel [stable|main]    which pushes receive takes: stable = tagged releases only (bin/release.sh),
                           main = any commit pushed from the Mac (the default)
  receive [-DryRun] [-Force]
                           check what bin/push-windows.sh staged in incoming\ (every file's sha256,
                           the manifest, every script parses) and switch C:\ProgramData\dram to it;
                           -DryRun checks only; -Force takes a push the channel or this PC's name
                           would refuse
  update [-Force]          receive what is staged (when something is), then apply
  apply [-DryRun] [-Phase <list>]
                           converge to the live release: each phase's documents (winget configure),
                           then its scripts, then the look on the signed-in desktop; phase 50 (ask)
                           only when named. -DryRun: winget configure test and the scripts' -DryRun,
                           nothing applied. Phases, by number or name, comma-separated: 00 debloat,
                           10 system, 20 user, 30 apps, 40 autostart, 50 ask
  doctor [-Json] [-Brief]  read-only drift report: winget configure test per document, the scripts'
                           -DryRun lines, every file's sha256, the boot guard, the case panel, the
                           masthead; every warning names its fix; exit 1 when one fired
  harvest                  installed winget and Store packages no document of the release declares
  rollback                 the release before this one: its apply plan, what going back would undo
                           (uninstall lines printed, never run), and the way back
  help                     this text
Options are -Name or --name. exit: 0 ok - 1 failed (doctor: a warning) - 2 bad usage
'@

# --- output ---------------------------------------------------------------------------------
function Say([string]$m) { Write-Host ''; Write-Host "==> $m" }
function Ok([string]$m) { Write-Host "[ok] $m" }
function Warn([string]$m) { Write-Host "[!] $m" }
function Die([string]$m) { [Console]::Error.WriteLine("[x] $m"); exit 1 }
function Show-Usage([string]$why) {
  if ($why) { [Console]::Error.WriteLine("[x] $why") }
  [Console]::Error.WriteLine($Help)
  exit 2
}
function Write-Log([string]$m) {
  try { Add-Content -LiteralPath $LogFile -Value ('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $m) -Encoding UTF8 } catch { }
}

# --- small readers ----------------------------------------------------------------------------
# the words after the command: -Name or --name (any case); a valued option takes the next word;
# other words are positional (at most $max); -h, -Help print the help
function Get-Opts([object[]]$a, [string[]]$switches, [string[]]$valued, [int]$max) {
  $o = @{}
  $words = New-Object System.Collections.ArrayList
  $i = 0
  while ($i -lt $a.Count) {
    $t = [string]$a[$i]
    if ($t -match '^-{1,2}([A-Za-z][A-Za-z-]*)$') {
      $n = ($Matches[1] -replace '-', '').ToLower()
      if ($n -eq 'h' -or $n -eq 'help') { Write-Host $Help; exit 0 }
      if ($switches -contains $n) { $o[$n] = $true }
      elseif ($valued -contains $n) {
        $i++
        if ($i -ge $a.Count) { Show-Usage "$t needs a value" }
        $o[$n] = [string]$a[$i]
      }
      else { Show-Usage "unknown option: $t" }
    }
    else { [void]$words.Add($t) }
    $i++
  }
  if ($words.Count -gt $max) { Show-Usage ('unexpected: ' + ($words -join ' ')) }
  $o['words'] = $words.ToArray()
  return $o
}
function Read-Json([string]$path) {
  if (-not [IO.File]::Exists($path)) { return $null }
  try { return (ConvertFrom-Json ([IO.File]::ReadAllText($path))) } catch { return $null }
}
function Get-State {
  $h = [ordered]@{}
  foreach ($k in $StateKeys) { $h[$k] = $null }
  $s = Read-Json $StateFile
  if ($s) { foreach ($p in $s.PSObject.Properties) { $h[$p.Name] = $p.Value } }
  return $h
}
function Save-State($h) {
  $tmp = "$StateFile.new"
  [IO.File]::WriteAllText($tmp, ($h | ConvertTo-Json -Depth 6), $Utf8)
  [IO.File]::Copy($tmp, $StateFile, $true)
  [IO.File]::Delete($tmp)
}
function Get-Now { (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz', [Globalization.CultureInfo]::InvariantCulture) }
function Show-Date($v) {
  if (-not $v) { return 'never' }
  try { return ([datetime]$v).ToString('yyyy-MM-dd HH:mm') } catch { return [string]$v }
}
function Get-Count($v) { $n = 0; foreach ($x in $v) { $n++ }; return $n }
function Get-Sha256([string]$path) {
  try {
    $s = [IO.File]::OpenRead($path)
    try { return ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($s)) -replace '-', '').ToLower() }
    finally { $s.Dispose() }
  }
  catch { return '' }
}
# "<sha256>  <path>" lines (push-windows.sh's stage.sha256, build\files.sha256), paths with /:
# @{ order = the paths as listed; sha = path -> sha256; bad = the first problem, or '' }
function Read-Sums([string]$path) {
  $r = @{ order = (New-Object System.Collections.ArrayList); sha = @{}; bad = '' }
  if (-not [IO.File]::Exists($path)) { return $r }
  foreach ($l in [IO.File]::ReadAllLines($path)) {
    if (-not $l) { continue }
    if ($l -match '^([0-9a-f]{64})  (.+)$') {
      $p = $Matches[2]
      if ($r.sha.ContainsKey($p)) { if (-not $r.bad) { $r.bad = "$p is listed twice" }; continue }
      $r.sha[$p] = $Matches[1]
      [void]$r.order.Add($p)
    }
    elseif (-not $r.bad) { $r.bad = "a malformed line: $l" }
  }
  return $r
}
# build\packages.tsv (push-windows.sh): id, source, ensure, document -> @{ <id, lowercased> = ... }
function Read-Packages([string]$dir) {
  $m = @{}
  $path = Join-Path $dir 'packages.tsv'
  if (-not [IO.File]::Exists($path)) { return $m }
  foreach ($l in [IO.File]::ReadAllLines($path)) {
    if (-not $l -or $l.StartsWith('#')) { continue }
    $c = $l.Split([char]9)
    if ($c.Count -lt 3) { continue }
    $doc = ''
    if ($c.Count -gt 3) { $doc = $c[3] }
    $m[$c[0].ToLower()] = @{ id = $c[0]; source = $c[1]; ensure = $c[2]; document = $doc }
  }
  return $m
}
# a path a release may write: relative, no .. or drive, not dram's own bookkeeping
function Test-SafePath([string]$p) {
  if (-not $p -or $p -match '^[\\/]|:|[\x00-\x1f*?"<>|]') { return $false }
  $segs = $p -split '[\\/]'
  foreach ($s in $segs) { if ($s -eq '' -or $s -eq '.' -or $s -eq '..') { return $false } }
  return -not (@('incoming', 'build.previous', 'bin', 'state.json', 'state.json.new', 'dram.log') -contains $segs[0])
}
function Get-LocalPath([string]$rel) { return (Join-Path $Root ($rel -replace '/', '\')) }
function Test-Admin { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
function Assert-Admin([string]$what) {
  if (-not (Test-Admin)) { Die "dram $what needs an elevated PowerShell: an administrator's ssh login is one, or Terminal (Admin)" }
}
function Get-Channel($st) {
  if ($st.channel -eq 'stable' -or $st.channel -eq 'main') { return [string]$st.channel }
  return 'main'
}
# the first parse error of a .ps1, '' when it parses: a merge once left look.ps1 a brace short,
# so nothing runs from a release before its scripts parse
function Get-ParseError([string]$path) {
  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tok, [ref]$err)
  if ($err -and $err.Count -gt 0) { return ('line {0}: {1}' -f $err[0].Extent.StartLineNumber, $err[0].Message) }
  return ''
}
function Test-DryRunParam([string]$path) {
  $tok = $null
  $err = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tok, [ref]$err)
  if (-not $ast -or -not $ast.ParamBlock) { return $false }
  foreach ($p in $ast.ParamBlock.Parameters) { if ($p.Name.VariablePath.UserPath -eq 'DryRun') { return $true } }
  return $false
}
function Get-Winget {
  $w = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
  if (Test-Path -LiteralPath $w) { return $w }
  $c = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { return $c.Source }
  return $null
}
# another Windows PowerShell for a script: its output straight through (Out-Host keeps it out of
# this function's return value), its exit code back
function Invoke-Child([string]$script, [string[]]$a) {
  & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script @a | Out-Host
  return $LASTEXITCODE
}

# --- the plan: the manifest's documents and scripts ------------------------------------------
# A document's or script's file is looked up in the render first (build\, or the render given),
# then under C:\ProgramData\dram, where the scripts live (their tasks and $Here name them there).
function Resolve-Entry([string]$file, [string]$renderDir) {
  if (-not (Test-SafePath $file)) { return $null }
  $n = $file -replace '/', '\'
  foreach ($c in @((Join-Path $renderDir $n), (Join-Path $Root $n))) { if ([IO.File]::Exists($c)) { return $c } }
  return $null
}
function Get-Plan($man, [string]$renderDir) {
  $items = New-Object System.Collections.ArrayList
  foreach ($d in $man.documents) {
    [void]$items.Add(@{ phase = [string]$d.phase; kind = 'document'; file = [string]$d.file; scope = [string]$d.scope; args = @(); path = (Resolve-Entry ([string]$d.file) $renderDir) })
  }
  foreach ($s in $man.scripts) {
    $sa = @(foreach ($x in $s.args) { if ($null -ne $x -and [string]$x -ne '') { [string]$x } })
    [void]$items.Add(@{ phase = [string]$s.phase; kind = 'script'; file = [string]$s.file; scope = ''; args = $sa; path = (Resolve-Entry ([string]$s.file) $renderDir) })
  }
  return @{ items = $items }   # in a hashtable: a returned list would be unrolled
}
function Get-PhaseItems($plan, [string]$phase) {
  $docs = @($plan | Where-Object { $_.phase -eq $phase -and $_.kind -eq 'document' })
  $scripts = @($plan | Where-Object { $_.phase -eq $phase -and $_.kind -eq 'script' })
  return @{ items = ($docs + $scripts) }
}
function Format-Item($it) {
  $t = [string]$it.file
  if ($it.kind -eq 'document' -and $it.scope) { $t += ' (' + $it.scope + ' scope)' }
  if (@($it.args).Count -gt 0) { $t += ' ' + (@($it.args) -join ' ') }
  return $t
}

# --- receive ------------------------------------------------------------------------------------
# dram.cmd on the machine PATH: Windows' OpenSSH runs cmd.exe, which finds it, and it hands every
# word to this script (its exit code is the script's). New ssh sessions read the machine PATH;
# the desktop takes it at the next sign-in, or from apply-live.ps1's "Environment" broadcast.
function Install-Shim {
  [void][IO.Directory]::CreateDirectory($BinDir)
  $cmd = Join-Path $BinDir 'dram.cmd'
  $ps1 = Join-Path $Root 'dram.ps1'
  $want = "@echo off`r`nrem dram on Windows: $ps1 (written by dram receive; docs/platforms/windows/dram-ps1.md)`r`n" +
    "`"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ps1`" %*`r`n" +
    "exit /b %ERRORLEVEL%`r`n"
  $have = ''
  if ([IO.File]::Exists($cmd)) { $have = [IO.File]::ReadAllText($cmd) }
  if ($have -cne $want) { [IO.File]::WriteAllText($cmd, $want, [Text.Encoding]::ASCII); Ok "the dram command: $cmd" }
  $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
  # unexpanded, so %SystemRoot% and friends stay what they are
  $raw = [string](Get-Item -LiteralPath $key).GetValue('Path', '', 'DoNotExpandEnvironmentNames')
  $parts = @($raw -split ';' | ForEach-Object { $_.Trim().TrimEnd('\') })
  if ($parts -contains $BinDir) { return }
  if (-not $raw) { Warn "could not read the machine Path: add $BinDir to it by hand"; return }
  $new = $raw + ';' + $BinDir
  if ($raw.EndsWith(';')) { $new = $raw + $BinDir }
  New-ItemProperty -LiteralPath $key -Name Path -PropertyType ExpandString -Value $new -Force | Out-Null
  Ok "$BinDir is on the machine PATH: a new ssh session finds dram"
}
function Remove-EmptyDirs([string]$d) {
  while ($d -and $d.Length -gt $Root.Length -and $d.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase) -and [IO.Directory]::Exists($d)) {
    if ([IO.Directory]::GetFileSystemEntries($d).Length -gt 0) { return }
    [IO.Directory]::Delete($d)
    $d = [IO.Path]::GetDirectoryName($d)
  }
}
function Test-Entry([string]$kind, $e, $stage, $bad) {
  $f = ([string]$e.file) -replace '\\', '/'
  if (-not $PhaseNames.Contains([string]$e.phase)) { [void]$bad.Add(('{0} {1}: phase "{2}" is none of 00 10 20 30 40 50' -f $kind, $f, $e.phase)) }
  if (-not ($stage.sha.ContainsKey("build/$f") -or $stage.sha.ContainsKey($f))) { [void]$bad.Add("$kind $f is not in the release") }
}
function Invoke-Receive([bool]$dry, [bool]$force) {
  if (-not [IO.Directory]::Exists($Incoming)) { Die "nothing staged in $Incoming - from the Mac: bin/push-windows.sh <host>" }
  # the incoming engine receives its own release, so a release can change how receive works
  $eng = Join-Path $Incoming 'dram.ps1'
  if ($Here -ne $Incoming -and [IO.File]::Exists($eng) -and (Get-Sha256 $eng) -ne (Get-Sha256 $Self)) {
    $a = @('receive')
    if ($dry) { $a += '-DryRun' }
    if ($force) { $a += '-Force' }
    exit (Invoke-Child $eng $a)
  }
  Assert-Admin 'receive'
  $stage = Read-Sums (Join-Path $Incoming 'stage.sha256')
  if ($stage.order.Count -eq 0) { Die "$Incoming\stage.sha256 is missing or empty: the push was cut short - push again" }
  if ($stage.bad) { Die "stage.sha256: $($stage.bad) - push again" }
  $man = Read-Json (Join-Path $Incoming 'build\manifest.json')
  $push = Read-Json (Join-Path $Incoming 'build\push.json')
  if (-not $man) { Die "$Incoming\build\manifest.json is missing or not JSON - push again" }
  if (-not $push) { Die "$Incoming\build\push.json is missing or not JSON - push again (bin/push-windows.sh writes it)" }
  $st = Get-State
  $live = Read-Sums (Join-Path $Build 'files.sha256')
  $tag = ''
  if ($push.tagged) { $tag = ', a tagged release' }
  Say ('Release {0} (build {1}{2}) for {3}, pushed {4}' -f $push.version, $push.build, $tag, $man.host, (Show-Date $push.pushed_at))
  $bad = New-Object System.Collections.ArrayList
  # 1) every file: arrived with its sha256, or already here with it (push-windows.sh sends only
  #    what changed; the render and this script always travel)
  $arrived = 0
  $kept = 0
  foreach ($p in $stage.order) {
    if (-not (Test-SafePath $p)) { [void]$bad.Add("$p is outside what dram may write"); continue }
    $want = $stage.sha[$p]
    $inc = Join-Path $Incoming ($p -replace '/', '\')
    if ([IO.File]::Exists($inc)) {
      if ((Get-Sha256 $inc) -eq $want) { $arrived++ } else { [void]$bad.Add("$p arrived with another sha256 (cut short?)") }
      continue
    }
    if ($p -like 'build/*' -or $p -eq 'dram.ps1') { [void]$bad.Add("$p did not arrive"); continue }
    $cur = Get-LocalPath $p
    if ([IO.File]::Exists($cur) -and (Get-Sha256 $cur) -eq $want) { $kept++ } else { [void]$bad.Add("$p is neither staged nor here with its sha256") }
  }
  # 2) the render's own list: each files[] entry in the release with the same sha256, each
  #    document and script in it, in a known phase
  $nf = 0
  foreach ($f in $man.files) {
    $nf++
    $p = ([string]$f.path) -replace '\\', '/'
    if (-not $stage.sha.ContainsKey($p)) { [void]$bad.Add("the manifest lists $p, which the push did not stage"); continue }
    if ($stage.sha[$p] -ne ([string]$f.sha256).ToLower()) { [void]$bad.Add(('{0}: the manifest says sha256 {1}, the push staged {2}' -f $p, $f.sha256, $stage.sha[$p])) }
  }
  foreach ($d in $man.documents) { Test-Entry 'document' $d $stage $bad }
  foreach ($s in $man.scripts) { Test-Entry 'script' $s $stage $bad }
  # 3) this PC: cabin-win is the PC called CABIN (the -win names its Windows side, as the Mac's
  #    HostKeyAlias does)
  $hn = [string]$man.host
  if ($hn -ne $env:COMPUTERNAME -and ($hn -replace '-win$', '') -ne $env:COMPUTERNAME) {
    $m = "the release is for $hn, and this PC is $env:COMPUTERNAME"
    if ($force) { Warn "$m (-Force)" } else { [void]$bad.Add("$m (-Force takes it anyway)") }
  }
  # 4) the channel: stable takes tagged releases only
  if ((Get-Channel $st) -eq 'stable' -and -not $push.tagged) {
    $m = ('channel stable takes tagged releases only; this push is {0} + {1} commit(s), build {2}' -f $push.version, $push.ahead, $push.build)
    if ($force) { Warn "$m (-Force)" } else { [void]$bad.Add("$m (bin/release.sh on the Mac, dram channel main, or -Force)") }
  }
  # 5) every script of the release parses, by Windows PowerShell 5.1's own parser
  $np = 0
  foreach ($p in $stage.order) {
    if ($p -notlike '*.ps1') { continue }
    $f = Join-Path $Incoming ($p -replace '/', '\')
    if (-not [IO.File]::Exists($f)) { $f = Get-LocalPath $p }
    if (-not [IO.File]::Exists($f)) { continue }
    $e = Get-ParseError $f
    if ($e) { [void]$bad.Add("$p does not parse ($e)") } else { $np++ }
  }
  if ($bad.Count -gt 0) {
    foreach ($b in $bad) { Write-Host "[x] $b" }
    Die "refused: nothing was switched, $Root is as it was"
  }
  Ok ('{0} files, each with its sha256: {1} arrived, {2} already here' -f $stage.order.Count, $arrived, $kept)
  Ok ('the manifest: {0} document(s), {1} script(s), {2} files listed; {3} script(s) parse' -f (Get-Count $man.documents), (Get-Count $man.scripts), $nf, $np)
  $gone = New-Object System.Collections.ArrayList
  foreach ($p in $live.order) { if ($p -notlike 'build/*' -and -not $stage.sha.ContainsKey($p)) { [void]$gone.Add($p) } }
  $same = [bool]($st.commit -and $st.commit -eq $push.commit)
  $from = 'nothing received yet'
  if ($st.version) { $from = ('{0} (build {1})' -f $st.version, $st.build) }
  Write-Host ('    {0} -> {1} (build {2})' -f $from, $push.version, $push.build)
  if ($gone.Count -gt 0) { Write-Host ('    {0} file(s) the release no longer lists go: {1}' -f $gone.Count, (@($gone | Select-Object -First 6) -join ', ')) }
  if ($dry) { Ok 'dry run: nothing switched; dram receive (or dram update) takes it'; exit 0 }

  try {
    foreach ($p in $stage.order) {
      if ($p -like 'build/*') { continue }
      $inc = Join-Path $Incoming ($p -replace '/', '\')
      if (-not [IO.File]::Exists($inc)) { continue }
      $dst = Get-LocalPath $p
      [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dst))
      [IO.File]::Copy($inc, $dst, $true)
    }
    foreach ($p in $gone) {
      $f = Get-LocalPath $p
      if ([IO.File]::Exists($f)) { [IO.File]::Delete($f) }
      Remove-EmptyDirs ([IO.Path]::GetDirectoryName($f))
    }
    # the render: the live one becomes the previous (a push of the same commit again keeps the
    # previous it had), the incoming one goes live with the full list beside it
    if ([IO.Directory]::Exists($Build)) {
      if ($same) { [IO.Directory]::Delete($Build, $true) }
      else {
        if ([IO.Directory]::Exists($Prev)) { [IO.Directory]::Delete($Prev, $true) }
        [IO.Directory]::Move($Build, $Prev)
      }
    }
    [IO.Directory]::Move((Join-Path $Incoming 'build'), $Build)
    [IO.File]::Copy((Join-Path $Incoming 'stage.sha256'), (Join-Path $Build 'files.sha256'), $true)
  }
  catch {
    Write-Log ('receive {0} (build {1}) stopped: {2}' -f $push.version, $push.build, $_.Exception.Message)
    Die ('the switch stopped: {0}. Part of {1} is the new release: push again' -f $_.Exception.Message, $Root)
  }
  Install-Shim
  if (-not $same -and $st.commit) {
    $st['previous'] = [ordered]@{ version = $st.version; tagged = $st.tagged; build = $st.build; commit = $st.commit; received_at = $st.received_at; applied = $st.applied }
  }
  foreach ($k in 'version', 'tagged', 'ahead', 'build', 'commit', 'branch', 'date', 'pushed_at') { $st[$k] = $push.$k }
  $st['host'] = $hn
  $st['received_at'] = Get-Now
  $st['render'] = [ordered]@{ version = [string]$man.release; commit = [string]$man.commit }
  Save-State $st
  try { [IO.Directory]::Delete($Incoming, $true) } catch { Warn "could not remove $Incoming ($($_.Exception.Message)); the next push replaces it" }
  Write-Log ('receive {0} (build {1}, {2}): {3} arrived, {4} kept, {5} removed' -f $push.version, $push.build, $push.commit, $arrived, $kept, $gone.Count)
  Ok ('received {0} (build {1}): dram apply converges this PC to it' -f $push.version, $push.build)
  exit 0
}

# --- update -------------------------------------------------------------------------------------
# Each step in its own process, so the engine a receive just installed runs the apply.
function Invoke-Update([bool]$force) {
  Assert-Admin 'update'
  if ([IO.Directory]::Exists($Incoming)) {
    $eng = Join-Path $Incoming 'dram.ps1'
    if (-not [IO.File]::Exists($eng)) { $eng = $Self }
    $a = @('receive')
    if ($force) { $a += '-Force' }
    if ((Invoke-Child $eng $a) -ne 0) { Die 'the staged release was not received (above): nothing else ran' }
  }
  else {
    $st = Get-State
    Ok ('nothing staged in {0}; the live release is {1} (build {2})' -f $Incoming, $st.version, $st.build)
  }
  exit (Invoke-Child (Join-Path $Root 'dram.ps1') @('apply'))
}

# --- apply ----------------------------------------------------------------------------------------
$script:Rc = 0
function Note([int]$code) { if ($code -ne 0 -and $script:Rc -eq 0) { $script:Rc = $code } }
function Invoke-Document([string]$w, $it, [bool]$dry) {
  $name = [IO.Path]::GetFileNameWithoutExtension($it.path)
  $log = Join-Path $Root "configure-$name.log"
  $verb = 'winget configure'
  if ($dry) { $verb = 'winget configure test' }
  $cargs = @('configure') + @(if ($dry) { 'test' }) + @('-f', $it.path, '--accept-configuration-agreements', '--disable-interactivity')
  & $w @cargs *> $log
  $code = $LASTEXITCODE
  Note $code
  Get-Content -LiteralPath $log -Encoding UTF8 | Where-Object { $_ -match $WingetLines } | ForEach-Object { Write-Host $_ }
  if ($code -eq 0) { Ok ('{0} {1}: exit 0' -f $verb, (Format-Item $it)) }
  else { Warn ('{0} {1}: exit {2} (log: {3})' -f $verb, (Format-Item $it), $code, $log) }
}
function Invoke-Script($it, [bool]$dry) {
  $a = @($it.args)
  if ($dry) {
    if (-not (Test-DryRunParam $it.path)) { Write-Host ('[skip] {0}: it has no -DryRun' -f (Format-Item $it)); return }
    $a += '-DryRun'
  }
  $code = Invoke-Child $it.path ([string[]]$a)
  Note $code
  if ($code -eq 0) { Ok ('{0}: exit 0' -f (Format-Item $it)) } else { Warn ('{0}: exit {1}' -f (Format-Item $it), $code) }
}
# the look on the signed-in desktop now, as converge.ps1 does it: apply-live.ps1 in a one-off task
# with that user's token, hidden (conhost --headless: Windows Terminal would otherwise host its
# console); it reports through apply-live.log
function Invoke-DesktopStep {
  $live = Join-Path $Root 'apply-live.ps1'
  if (-not [IO.File]::Exists($live)) { Write-Host '   live: no apply-live.ps1 in this release; the look shows at the next sign-in'; return }
  $user = (Get-CimInstance Win32_ComputerSystem).UserName
  if (-not $user) { Write-Host '   live: nobody is signed in at the PC; the look shows at the next sign-in'; return }
  if ($user -notmatch ('\\' + [regex]::Escape($env:USERNAME) + '$')) {
    Write-Host ('   live: {0} is signed in, not {1}; the look shows at the next sign-in of {1}' -f $user, $env:USERNAME)
    return
  }
  $t = 'dram-apply-live'
  $log = Join-Path $Root 'apply-live.log'
  $since = Get-Date
  $act = New-ScheduledTaskAction -Execute (Join-Path $env:windir 'System32\conhost.exe') -Argument "--headless `"$PSExe`" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$live`""
  Register-ScheduledTask -TaskName $t -Action $act -Principal (New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive) -Force | Out-Null
  Start-ScheduledTask -TaskName $t
  $deadline = $since.AddSeconds(60)
  while ((Get-Date) -lt $deadline -and -not ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).LastWriteTime -ge $since)) { Start-Sleep -Milliseconds 500 }
  Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
  if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).LastWriteTime -ge $since) {
    Get-Content -LiteralPath $log -Encoding UTF8 | ForEach-Object { Write-Host ($_ -replace '^\S+ \S+ ', '') }
  }
  else { Warn 'live: apply-live.ps1 did not report within 60 s; the look shows at the next sign-in' }
}
function Invoke-Apply([bool]$dry, [string]$phaseArg) {
  Assert-Admin 'apply'
  if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
    Die 'dram apply runs as the user whose settings it converges (user-scope documents write HKCU, and winget is that user''s App Installer), never as SYSTEM'
  }
  $man = Read-Json (Join-Path $Build 'manifest.json')
  if (-not $man) { Die "no release here yet ($Build\manifest.json) - from the Mac: bin/push-windows.sh <host>" }
  $st = Get-State
  # the phases: the ones named, else every one but 50 (ask)
  $run = @()
  foreach ($word in ($phaseArg -split '[,\s]+')) {
    if (-not $word) { continue }
    $code = $null
    foreach ($k in $PhaseNames.Keys) { if ($word -eq $k -or $word -eq $PhaseNames[$k]) { $code = $k } }
    if (-not $code) { Show-Usage "-Phase ${word}: one of 00 10 20 30 40 50 (debloat system user apps autostart ask)" }
    $run += $code
  }
  if ($run.Count -eq 0) { $run = @('00', '10', '20', '30', '40') }
  $plan = (Get-Plan $man $Build).items
  $missing = @($plan | Where-Object { -not $_.path } | ForEach-Object { $_.file })
  if ($missing.Count -gt 0) { Die ('not in the release: {0} - push again (bin/push-windows.sh)' -f ($missing -join ', ')) }
  # every script this run starts parses first: nothing half-runs on a file a merge broke
  $parse = @($plan | Where-Object { $_.kind -eq 'script' -and $run -contains $_.phase } | ForEach-Object { $_.path })
  if (-not $dry -and [IO.File]::Exists((Join-Path $Root 'apply-live.ps1'))) { $parse += (Join-Path $Root 'apply-live.ps1') }
  foreach ($f in $parse) {
    $e = Get-ParseError $f
    if ($e) { Die "$f does not parse ($e): nothing ran - fix it in the repo and push again" }
  }
  $w = Get-Winget
  if (-not $w) { Die 'winget missing (App Installer, from the Store)' }
  Add-Type -Namespace DramCli -Name Power -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags);'
  [void][DramCli.Power]::SetThreadExecutionState([uint32]2147483649)   # ES_CONTINUOUS | ES_SYSTEM_REQUIRED, until this process ends
  $how = ''
  if ($dry) { $how = ' -DryRun' }
  Say ('dram apply{0}: {1} (build {2}) on {3}, phases {4}' -f $how, $st.version, $st.build, $env:COMPUTERNAME, ($run -join ' '))
  # winget's extended features (DSC) once; `configure --enable` takes no other flags
  $first = @($plan | Where-Object { $_.kind -eq 'document' } | Select-Object -First 1)
  if ($first.Count -gt 0) {
    & $w configure validate -f $first[0].path --disable-interactivity *> $null
    if ($LASTEXITCODE -eq -1978335127) { & $w configure --enable *> $null; Ok "winget configure: extended features enabled (exit $LASTEXITCODE)" }
  }
  foreach ($ph in $PhaseNames.Keys) {
    $items = (Get-PhaseItems $plan $ph).items
    if ($items.Count -eq 0) { continue }
    if ($run -notcontains $ph) {
      if ($ph -eq '50') { foreach ($it in $items) { Write-Host ('[ask] phase 50: {0} - dram apply -Phase 50 runs it' -f (Format-Item $it)) } }
      continue
    }
    Write-Host ''
    Write-Host ('== phase {0} ({1})' -f $ph, $PhaseNames[$ph])
    foreach ($it in $items) {
      if ($it.kind -eq 'document') { Invoke-Document $w $it $dry } else { Invoke-Script $it $dry }
    }
  }
  if (-not $dry) {
    Invoke-DesktopStep
    $st = Get-State
    $st['applied'] = [ordered]@{ version = $st.version; build = $st.build; commit = $st.commit; at = (Get-Now); rc = $script:Rc; user = $env:USERNAME; phases = ($run -join ' ') }
    Save-State $st
    Write-Log ('apply {0} (build {1}) phases {2}: exit {3}' -f $st.version, $st.build, ($run -join ' '), $script:Rc)
  }
  $how = ''
  if ($dry) { $how = ' (dry run)' }
  Write-Host ''
  Write-Host ('== apply{0}: exit {1}' -f $how, $script:Rc)
  # 1, not the step's own code: ssh hands the Mac only its low byte, and winget's 0x8A15....
  # codes can end in 00
  if ($script:Rc -ne 0) { exit 1 }
  exit 0
}

# --- doctor -------------------------------------------------------------------------------------
# Read-only but for its own records: each check is kept for -Json, printed as Arch's doctor
# prints ([ok], [!] with its fix, [i], [skip]); -Brief prints only the warnings. A warning is
# drift when the PC (or C:\ProgramData\dram) differs from the release.
$script:Checks = New-Object System.Collections.ArrayList
$script:DQuiet = $false
$script:DBrief = $false
function Check([string]$section, [string]$status, [string]$what, [string]$fix, [bool]$drift) {
  $f = $null
  if ($fix) { $f = $fix }
  [void]$script:Checks.Add([ordered]@{ section = $section; status = $status; check = $what; fix = $f; drift = $drift })
  if ($script:DQuiet) { return }
  if ($status -eq 'warn') {
    Write-Host "[!] $what"
    if ($fix) { Write-Host "      fix: $fix" }
    return
  }
  if ($script:DBrief) { return }
  if ($status -eq 'ok') { Write-Host "[ok] $what" } elseif ($status -eq 'skip') { Write-Host "[skip] $what" } else { Write-Host "[i] $what" }
}
function Section([string]$name) { if (-not $script:DQuiet -and -not $script:DBrief) { Write-Host ''; Write-Host $name } }
# the units a `winget configure test` log reports out of their state: a unit's header line is
# "<resource> [<id>]", its result lines follow (the document's exit code decides either way)
function Get-DriftedUnits([string]$log) {
  $units = New-Object System.Collections.ArrayList
  $unit = $null
  if ([IO.File]::Exists($log)) {
    foreach ($l in (Get-Content -LiteralPath $log -Encoding UTF8)) {
      if ($l -match '^\S.*\[([^\]]+)\]\s*$') { $unit = $Matches[1] }
      elseif ($unit -and $l -match 'not in the desired state' -and -not $units.Contains($unit)) { [void]$units.Add($unit) }
    }
  }
  if ($units.Count -eq 0) { return '' }
  return ': ' + (@($units | Select-Object -First 8) -join ', ')
}
function Complete-Doctor($st, [bool]$save) {
  $nw = 0
  $nd = 0
  foreach ($c in $script:Checks) { if ($c.status -eq 'warn') { $nw++; if ($c.drift) { $nd++ } } }
  if ($save) {
    $s = Get-State
    $s['doctor'] = [ordered]@{ at = (Get-Now); version = $s.version; commit = $s.commit; warnings = $nw; drift = $nd }
    try { Save-State $s } catch { }
  }
  if ($script:DQuiet) {
    $o = [ordered]@{ id = 'dram'; platform = 'windows'; host = $st.host; computer = $env:COMPUTERNAME; version = $st.version; build = $st.build; commit = $st.commit; at = (Get-Now); drift = $nd; warnings = $nw; ok = ($nw -eq 0); checks = $script:Checks }
    Write-Output ($o | ConvertTo-Json -Depth 5 -Compress)
  }
  elseif ($nw -gt 0) { Write-Host ''; Write-Host ('{0} warning(s), {1} of them drift - each line above names its fix. Full report: dram doctor' -f $nw, $nd) }
  elseif ($script:DBrief) { Ok 'doctor: all clear' }
  else { Write-Host ''; Ok 'doctor: no drift, nothing to fix' }
  if ($nw -gt 0) { exit 1 }
  exit 0
}
function Invoke-Doctor([bool]$json, [bool]$brief) {
  $script:DQuiet = $json
  $script:DBrief = $brief
  $st = Get-State
  $man = Read-Json (Join-Path $Build 'manifest.json')
  $admin = Test-Admin

  Section 'release'
  if (-not $man -or -not $st.commit) {
    Check 'release' 'warn' 'no release received yet' 'from the Mac: bin/push-windows.sh <host> (docs/platforms/windows/dram-ps1.md)' $false
    Complete-Doctor $st $false
  }
  Check 'release' 'info' ('{0} (build {1}) received {2}; channel {3}' -f $st.version, $st.build, (Show-Date $st.received_at), (Get-Channel $st)) '' $false
  $ap = $st.applied
  if (-not $ap) { Check 'release' 'warn' "$($st.version) was received and never applied" 'dram apply' $true }
  elseif ($ap.commit -ne $st.commit) { Check 'release' 'warn' ('{0} is received; the last apply was of {1} ({2})' -f $st.version, $ap.version, (Show-Date $ap.at)) 'dram apply' $true }
  elseif ([int]$ap.rc -ne 0) { Check 'release' 'warn' ('the last apply ({0}) exited {1}' -f (Show-Date $ap.at), $ap.rc) 'dram apply: its lines name the step' $false }
  else { Check 'release' 'ok' ('{0} applied {1} (phases {2})' -f $ap.version, (Show-Date $ap.at), $ap.phases) '' $false }
  if ($ap -and $ap.user -and $ap.user -ne $env:USERNAME) {
    Check 'release' 'info' ('the last apply ran as {0}: the user-scope documents test the settings of {1} here' -f $ap.user, $env:USERNAME) '' $false
  }

  Section 'engine'
  $shim = Join-Path $BinDir 'dram.cmd'
  $raw = [string](Get-Item -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment').GetValue('Path', '', 'DoNotExpandEnvironmentNames')
  $onPath = @($raw -split ';' | ForEach-Object { $_.Trim().TrimEnd('\') }) -contains $BinDir
  if ([IO.File]::Exists($shim) -and $onPath) { Check 'engine' 'ok' "dram: $shim, on the machine PATH" '' $false }
  else { Check 'engine' 'warn' "the dram command is not installed ($shim on the machine PATH)" 'dram receive installs it (from the Mac: bin/push-windows.sh <host>)' $false }
  $w = Get-Winget
  if ($w) { Check 'engine' 'info' ('winget {0}' -f (@(& $w --version) -join ' ')) '' $false }
  else { Check 'engine' 'warn' 'winget missing' 'App Installer, from the Store' $false }
  if (-not $admin) { Check 'engine' 'info' 'not elevated: the document, script and boot checks are skipped (an administrator''s ssh login is elevated)' '' $false }

  Section 'files'
  $live = Read-Sums (Join-Path $Build 'files.sha256')
  $diff = New-Object System.Collections.ArrayList
  foreach ($p in $live.order) {
    $f = Get-LocalPath $p
    if (-not [IO.File]::Exists($f)) { [void]$diff.Add("$p (missing)") }
    elseif ((Get-Sha256 $f) -ne $live.sha[$p]) { [void]$diff.Add($p) }
  }
  if ($diff.Count -eq 0) { Check 'files' 'ok' ('{0} files as received (sha256)' -f $live.order.Count) '' $false }
  else { Check 'files' 'warn' ('{0} of {1} files differ from the release: {2}' -f $diff.Count, $live.order.Count, (@($diff | Select-Object -First 6) -join ', ')) 'bin/push-windows.sh <host> (the Mac) puts them back' $true }

  $plan = (Get-Plan $man $Build).items
  Section 'documents (winget configure test)'
  if (-not $admin -or -not $w) { Check 'documents' 'skip' 'not elevated, or no winget' '' $false }
  else {
    foreach ($it in $plan) {
      if ($it.kind -ne 'document') { continue }
      if (-not $it.path) { Check 'documents' 'warn' "$($it.file) is not in the release" 'bin/push-windows.sh <host>' $true; continue }
      $log = Join-Path $Root ('doctor-{0}.log' -f [IO.Path]::GetFileNameWithoutExtension($it.path))
      & $w configure test -f $it.path --accept-configuration-agreements --disable-interactivity *> $log
      $code = $LASTEXITCODE
      if ($code -eq 0) { Check 'documents' 'ok' ('{0}: in the desired state' -f (Format-Item $it)) '' $false }
      elseif ($it.phase -eq '50') { Check 'documents' 'info' ('{0}: phase 50 (ask), not in its state{1} - dram apply -Phase 50 when wanted' -f (Format-Item $it), (Get-DriftedUnits $log)) '' $false }
      else { Check 'documents' 'warn' ('{0}: not in the desired state (exit {1}){2}' -f (Format-Item $it), $code, (Get-DriftedUnits $log)) "dram apply (log: $log)" $true }
    }
  }

  Section 'scripts (-DryRun)'
  if (-not $admin) { Check 'scripts' 'skip' 'not elevated' '' $false }
  else {
    foreach ($it in $plan) {
      if ($it.kind -ne 'script' -or $it.phase -eq '50') { continue }
      if (-not $it.path) { Check 'scripts' 'warn' "$($it.file) is not in the release" 'bin/push-windows.sh <host>' $true; continue }
      if (-not (Test-DryRunParam $it.path)) { Check 'scripts' 'skip' ('{0}: it has no -DryRun' -f (Format-Item $it)) '' $false; continue }
      $sa = [string[]](@($it.args) + '-DryRun')
      $out = @(& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $it.path @sa)
      $code = $LASTEXITCODE
      $would = @($out | Where-Object { [string]$_ -match $WouldLine } | ForEach-Object { ([string]$_).Trim() })
      if ($code -ne 0) { Check 'scripts' 'warn' ('{0} -DryRun exited {1}: {2}' -f (Format-Item $it), $code, (@($out | Select-Object -Last 1) -join '')) ('powershell -File {0} -DryRun' -f $it.path) $false }
      elseif ($would.Count -gt 0) { Check 'scripts' 'warn' ('{0}: {1} change(s) waiting: {2}' -f (Format-Item $it), $would.Count, (@($would | Select-Object -First 4) -join '; ')) 'dram apply' $true }
      else { Check 'scripts' 'ok' ('{0}: nothing to change' -f (Format-Item $it)) '' $false }
    }
  }

  if ($live.sha.ContainsKey('boot-guard.ps1')) {
    Section 'boot'
    $t = Get-ScheduledTask -TaskPath '\dram\' -TaskName 'boot-guard' -ErrorAction SilentlyContinue
    if (-not $t) { Check 'boot' 'warn' 'no \dram\boot-guard task (rEFInd first at every Windows start)' 'dram apply (its document registers it)' $true }
    elseif ([string]$t.State -eq 'Disabled') { Check 'boot' 'warn' '\dram\boot-guard is disabled' 'Enable-ScheduledTask -TaskPath \dram\ -TaskName boot-guard' $true }
    else {
      $ti = Get-ScheduledTaskInfo -TaskPath '\dram\' -TaskName 'boot-guard' -ErrorAction SilentlyContinue
      $last = 'never'
      if ($ti) { $last = ('{0}, result {1}' -f (Show-Date $ti.LastRunTime), $ti.LastTaskResult) }
      Check 'boot' 'ok' "\dram\boot-guard runs at every start (last: $last)" '' $false
    }
    if ($admin) {
      $out = @(& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Get-LocalPath 'boot-guard.ps1') -DryRun)
      $code = $LASTEXITCODE
      if ($code -ne 0) { Check 'boot' 'warn' ('boot-guard.ps1 -DryRun: {0}' -f (@($out | Select-Object -Last 1) -join '')) 'the rEFInd entry comes from Arch: system/apply-refind.sh' $false }
      elseif (@($out | Where-Object { [string]$_ -match 'would put' }).Count -gt 0) { Check 'boot' 'warn' 'the firmware boot order changed: rEFInd is not first, or Windows Boot Manager not last' 'Start-ScheduledTask -TaskPath \dram\ -TaskName boot-guard (or restart Windows)' $true }
      else { Check 'boot' 'ok' 'firmware boot order: rEFInd first, Windows Boot Manager last' '' $false }
    }
  }

  $panel = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match '^HID\\VID_2022&PID_0522' })
  $task = Get-ScheduledTask -TaskName 'dram-case-display' -ErrorAction SilentlyContinue
  if ($panel.Count -gt 0 -or $task) {
    Section 'case panel'
    if ($panel.Count -eq 0) { Check 'case' 'skip' 'the case panel (USB 2022:0522) is not plugged in' '' $false }
    elseif (-not $task) { Check 'case' 'warn' 'the case panel is plugged in, and no dram-case-display task drives it' 'dram apply (the document with the case-display-task unit)' $true }
    elseif ([string]$task.State -eq 'Running') { Check 'case' 'ok' 'dram-case-display runs: the panel shows both temperatures' '' $false }
    else { Check 'case' 'warn' ('dram-case-display is {0}, not running: the panel stays dark' -f $task.State) 'Start-ScheduledTask -TaskName dram-case-display' $false }
  }

  $pk = Read-Packages $Build
  $z = $pk['glzr-io.zebar']
  if ($z -and $z.ensure -ne 'Absent') {
    Section 'masthead'
    $user = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
    if (-not $user) { Check 'masthead' 'skip' 'nobody is signed in at the PC: Zebar starts at sign-in' '' $false }
    elseif (@(Get-Process -Name zebar -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -ne 0 }).Count -gt 0) { Check 'masthead' 'ok' "Zebar (the masthead) runs on the desktop of $user" '' $false }
    else { Check 'masthead' 'warn' "$user is signed in, and Zebar (the masthead) is not running" 'dram apply (its desktop step starts it), or sign out and in' $true }
  }
  Complete-Doctor $st $true
}

# --- status, version, channel ---------------------------------------------------------------------
function Invoke-Status {
  $st = Get-State
  if (-not $st.commit) { Warn 'no release received yet - from the Mac: bin/push-windows.sh <host> (docs/platforms/windows/dram-ps1.md)'; exit 1 }
  Write-Host ('dram {0} - build {1} - channel {2} - {3} ({4})' -f $st.version, $st.build, (Get-Channel $st), $st.host, $env:COMPUTERNAME)
  $tag = ''
  if ($st.tagged) { $tag = ', a tagged release' }
  Write-Host ('  {0,-10} {1} (pushed {2}{3})' -f 'received', (Show-Date $st.received_at), (Show-Date $st.pushed_at), $tag)
  $ap = $st.applied
  if (-not $ap) { Warn 'never applied: dram apply' }
  elseif ($ap.commit -ne $st.commit) { Warn ('the last apply was of {0} ({1}), not of {2}: dram apply' -f $ap.version, (Show-Date $ap.at), $st.version) }
  elseif ([int]$ap.rc -ne 0) { Warn ('applied {0}, exit {1}: dram apply again (its lines name the step)' -f (Show-Date $ap.at), $ap.rc) }
  else { Write-Host ('  {0,-10} {1}, exit 0 (phases {2})' -f 'applied', (Show-Date $ap.at), $ap.phases) }
  $live = Read-Sums (Join-Path $Build 'files.sha256')
  $n = 0
  foreach ($p in $live.order) {
    $f = Get-LocalPath $p
    if (-not [IO.File]::Exists($f) -or (Get-Sha256 $f) -ne $live.sha[$p]) { $n++ }
  }
  if ($n -gt 0) { Warn ('{0} of {1} files differ from the release: dram doctor names them' -f $n, $live.order.Count) }
  else { Write-Host ('  {0,-10} {1}, as received' -f 'files', $live.order.Count) }
  $d = $st.doctor
  if (-not $d) { Write-Host ('  {0,-10} never run: dram doctor' -f 'doctor') }
  elseif ($d.commit -ne $st.commit) { Warn ('the last doctor checked {0}, not {1}: dram doctor' -f $d.version, $st.version) }
  elseif ([int]$d.warnings -gt 0) { Warn ('doctor {0}: {1} warning(s), {2} drift - dram doctor' -f (Show-Date $d.at), $d.warnings, $d.drift) }
  else { Write-Host ('  {0,-10} {1}: no drift' -f 'doctor', (Show-Date $d.at)) }
  if ($st.previous) { Write-Host ('  {0,-10} {1} (build {2}): dram rollback shows the way back' -f 'previous', $st.previous.version, $st.previous.build) }
  exit 0
}
function Invoke-Version([bool]$json) {
  $st = Get-State
  if (-not $st.commit) { Die 'no release received yet - from the Mac: bin/push-windows.sh <host>' }
  $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
  $win = ''
  if ($cv) { $win = ('{0} {1}.{2}' -f $cv.DisplayVersion, $cv.CurrentBuild, $cv.UBR) }
  $ap = $st.applied
  if ($json) {
    $o = [ordered]@{ id = 'dram'; platform = 'windows'; version = $st.version; tagged = $st.tagged; ahead = $st.ahead; build = $st.build; commit = $st.commit; branch = $st.branch; channel = (Get-Channel $st); host = $st.host; computer = $env:COMPUTERNAME; received = $st.received_at; applied = $null; applied_version = $null; applied_rc = $null; render_version = $null; render_commit = $null; windows = $win }
    if ($ap) { $o['applied'] = $ap.at; $o['applied_version'] = $ap.version; $o['applied_rc'] = $ap.rc }
    if ($st.render) { $o['render_version'] = $st.render.version; $o['render_commit'] = $st.render.commit }
    Write-Output ($o | ConvertTo-Json -Compress)
    exit 0
  }
  $after = ''
  if ($st.tagged) { $after = ' (the tagged release)' } elseif ([int]$st.ahead -gt 0) { $after = (' ({0} commit(s) after {1})' -f $st.ahead, $st.version) }
  Write-Host ('dram {0} - build {1} - channel {2}' -f $st.version, $st.build, (Get-Channel $st))
  Write-Host ('  {0,-10} {1}{2}' -f 'commit', $st.commit, $after)
  Write-Host ('  {0,-10} {1} ({2}), from {3}' -f 'host', $st.host, $env:COMPUTERNAME, $st.branch)
  Write-Host ('  {0,-10} {1}' -f 'received', (Show-Date $st.received_at))
  if ($ap) { Write-Host ('  {0,-10} {1} ({2}, exit {3})' -f 'applied', (Show-Date $ap.at), $ap.version, $ap.rc) } else { Write-Host ('  {0,-10} never' -f 'applied') }
  if ($st.render) { Write-Host ('  {0,-10} {1} {2} (the manifest)' -f 'rendered', $st.render.version, $st.render.commit) }
  Write-Host ('  {0,-10} {1}' -f 'windows', $win)
  if ($ap -and $ap.commit -ne $st.commit) { Warn 'the received release is not the applied one: dram apply' }
  exit 0
}
function Invoke-Channel([object[]]$words) {
  $st = Get-State
  if ($words.Count -eq 0) {
    if ((Get-Channel $st) -eq 'stable') { Write-Host 'stable - receive takes tagged releases only (bin/release.sh on the Mac)' }
    else { Write-Host 'main - receive takes any commit pushed from the Mac' }
    if (-not $st.channel) { Write-Host '    (the default: main; dram channel stable|main sets it)' }
    exit 0
  }
  $want = ([string]$words[0]).ToLower()
  if ($want -ne 'stable' -and $want -ne 'main') { Show-Usage ('dram channel: stable or main, not {0}' -f $words[0]) }
  Assert-Admin 'channel'
  $st['channel'] = $want
  Save-State $st
  if ($want -eq 'stable') { Ok 'channel: stable - receive takes tagged releases only (bin/release.sh)' }
  else { Ok 'channel: main - receive takes any commit pushed from the Mac' }
  exit 0
}

# --- harvest, rollback --------------------------------------------------------------------------------
function Invoke-Harvest {
  $st = Get-State
  $w = Get-Winget
  if (-not $w) { Die 'winget missing (App Installer, from the Store)' }
  $decl = Read-Packages $Build
  # the host's unmanaged names (windows/hosts/<host>.nix): installed by hand, kept out of the build
  $um = @{}
  $mf = Read-Json (Join-Path $Build 'manifest.json')
  if ($mf) { foreach ($u in @($mf.unmanaged)) { if ($u) { $um[(([string]$u -split ':', 2)[-1]).ToLower()] = 1 } } }
  $left = 0
  if ($decl.Count -eq 0) { Warn "no $Build\packages.tsv (bin/push-windows.sh writes it): every package shows as undeclared" }
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ('dram-harvest-{0}.json' -f $PID)
  & $w export -o $tmp --accept-source-agreements --disable-interactivity *> $null
  $ex = Read-Json $tmp
  if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) }
  if (-not $ex) { Die 'winget export wrote nothing readable' }
  $extra = New-Object System.Collections.ArrayList
  $absent = New-Object System.Collections.ArrayList
  $n = 0
  foreach ($src in $ex.Sources) {
    $sn = [string]$src.SourceDetails.Name
    foreach ($pkg in $src.Packages) {
      $id = [string]$pkg.PackageIdentifier
      if (-not $id) { continue }
      $n++
      if ($um.ContainsKey($id.ToLower())) { $left++; continue }
      $d = $decl[$id.ToLower()]
      if (-not $d) { [void]$extra.Add(('{0,-9} {1}' -f $sn, $id)) }
      elseif ($d.ensure -eq 'Absent') { [void]$absent.Add($id) }
    }
  }
  Say ('Installed from winget and the Store, declared by no document of {0} (winget export; read-only)' -f $st.version)
  foreach ($x in @($extra | Sort-Object)) { Write-Host "    $x" }
  Ok ('{0} installed from a source: {1} declared, {2} not, {3} left alone (unmanaged)' -f $n, ($n - $extra.Count - $left), $extra.Count, $left)
  if ($absent.Count -gt 0) { Warn ('declared Absent and still installed: {0} - dram apply removes them' -f ($absent -join ', ')) }
  if ($extra.Count -gt 0) {
    Write-Host '    keep one: a winget:<id> (or msstore:<id>) line in packages/winget/<role>.txt and a register row'
    Write-Host '    (bin/check-register.py), then render and push; drop one: winget uninstall --id <id> --exact'
  }
  Write-Host '    (a manual: entry - a Script unit, a launcher installed by hand - can show here under the id winget matched it to)'
  exit 0
}
function Invoke-Rollback {
  $st = Get-State
  $pm = Read-Json (Join-Path $Prev 'manifest.json')
  if (-not $st.previous -or -not $pm) {
    $v = 'this one'
    if ($st.version) { $v = $st.version }
    Warn "no release before $v is recorded here (a receive keeps the one it replaces)"
    exit 1
  }
  $pv = $st.previous
  $when = 'never applied'
  if ($pv.applied) { $when = 'applied ' + (Show-Date $pv.applied.at) }
  Say ('The release before: {0} (build {1}), received {2}, {3}' -f $pv.version, $pv.build, (Show-Date $pv.received_at), $when)
  Write-Host '  its apply plan, phase by phase (documents, then scripts):'
  $plan = (Get-Plan $pm $Prev).items
  foreach ($ph in $PhaseNames.Keys) {
    $names = @((Get-PhaseItems $plan $ph).items | ForEach-Object { Format-Item $_ })
    if ($names.Count -gt 0) { Write-Host ('    {0} {1,-9} {2}' -f $ph, $PhaseNames[$ph], ($names -join ', ')) }
  }
  Write-Host '  what going back would undo (printed, never run):'
  $cur = Read-Packages $Build
  $old = Read-Packages $Prev
  $n = 0
  foreach ($k in @($cur.Keys | Sort-Object)) {
    $c = $cur[$k]
    $o = $old[$k]
    if ($c.ensure -ne 'Absent' -and (-not $o -or $o.ensure -eq 'Absent')) {
      Write-Host ('    winget uninstall --id {0} --exact --source {1}    # {2} declares it, {3} does not' -f $c.id, $c.source, $st.version, $pv.version)
      $n++
    }
  }
  foreach ($k in @($old.Keys | Sort-Object)) {
    $o = $old[$k]
    $c = $cur[$k]
    if ($o.ensure -ne 'Absent' -and (-not $c -or $c.ensure -eq 'Absent')) {
      Write-Host ('    {0} comes back: {1} declares it, and dram apply after going back installs it' -f $o.id, $pv.version)
      $n++
    }
  }
  if ($n -eq 0) { Write-Host '    no package differs' }
  $a = Read-Sums (Join-Path $Build 'files.sha256')
  $b = Read-Sums (Join-Path $Prev 'files.sha256')
  $chg = 0
  $add = 0
  $del = 0
  foreach ($p in $a.order) { if ($p -like 'build/*') { continue }; if (-not $b.sha.ContainsKey($p)) { $add++ } elseif ($b.sha[$p] -ne $a.sha[$p]) { $chg++ } }
  foreach ($p in $b.order) { if ($p -notlike 'build/*' -and -not $a.sha.ContainsKey($p)) { $del++ } }
  Write-Host ('    files in {0}: {1} differ, {2} only in {3}, {4} only in {5}' -f $Root, $chg, $add, $st.version, $del, $pv.version)
  Write-Host '    settings: what this release set stays set unless the older documents set it back'
  Write-Host '    (winget configure undoes nothing a document no longer declares)'
  $force = ''
  if ((Get-Channel $st) -eq 'stable' -and -not $pv.tagged) { $force = ' --force' }
  Write-Host '  the way back, on the Mac, from a clean tree:'
  Write-Host ('    git -C ~/git/dotfiles checkout --detach {0}' -f $pv.commit)
  Write-Host ('    bin/push-windows.sh {0} --apply{1}' -f $st.host, $force)
  Write-Host '    git -C ~/git/dotfiles checkout -    (where you were; here, dram rollback then shows the way forward)'
  Write-Host '  then here, the uninstall lines above that you want.'
  exit 0
}

# --- dispatch -------------------------------------------------------------------------------------
$Command = 'help'
$Rest = @()
if ($Argv.Count -gt 0) {
  $Command = [string]$Argv[0]
  $Rest = @($Argv | Select-Object -Skip 1)
}
switch ($Command.ToLower()) {
  'status' { $null = Get-Opts $Rest @() @() 0; Invoke-Status; break }
  'version' { $o = Get-Opts $Rest @('json') @() 0; Invoke-Version ([bool]$o['json']); break }
  'channel' { $o = Get-Opts $Rest @() @() 1; Invoke-Channel $o['words']; break }
  'receive' { $o = Get-Opts $Rest @('dryrun', 'force') @() 0; Invoke-Receive ([bool]$o['dryrun']) ([bool]$o['force']); break }
  'update' { $o = Get-Opts $Rest @('force') @() 0; Invoke-Update ([bool]$o['force']); break }
  'apply' { $o = Get-Opts $Rest @('dryrun') @('phase') 0; Invoke-Apply ([bool]$o['dryrun']) ([string]$o['phase']); break }
  'doctor' { $o = Get-Opts $Rest @('json', 'brief') @() 0; Invoke-Doctor ([bool]$o['json']) ([bool]$o['brief']); break }
  'harvest' { $null = Get-Opts $Rest @() @() 0; Invoke-Harvest; break }
  'rollback' { $null = Get-Opts $Rest @() @() 0; Invoke-Rollback; break }
  'help' { Write-Host $Help; exit 0 }
  '-h' { Write-Host $Help; exit 0 }
  '-help' { Write-Host $Help; exit 0 }
  '--help' { Write-Host $Help; exit 0 }
  default { Show-Usage "unknown command: $Command" }
}
exit 0

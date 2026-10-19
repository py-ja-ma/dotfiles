# install/windows/dram-windows/look.ps1 - the Letterpress look inside the apps
# (docs/design/themes/windows.md).
#
# What `winget configure` cannot own: files and keys inside each app's settings, for the user
# the converge runs as (pj). The sources are what install/windows/apply-windows.sh staged in
# C:\ProgramData\dram: letterpress\ (bin/gen-windows-look.py) and the files Arch shares
# (starship.toml, both userChrome.css, letterpress-colors.css, user.js.default,
# librewolf.overrides.cfg, settings.json.default). converge.ps1 runs it after the winget
# configurations. The rules: a file that is ours alone (a theme, a stylesheet, the profile) is
# rewritten whenever it differs; keys inside a file an app owns (or under its registry key) are
# merged only while that app is closed - for PowerToys, while its Settings window is - otherwise
# the line reads [deferred] and the next converge tries again; an app whose settings do not
# exist yet is skipped until it has run once; the first time a file of the app's is changed, a
# copy is kept as <file>.before-dram (registry values: <app>.before-dram.json beside this
# script). Everything is written as UTF-8 without a BOM (Vesktop's JSON.parse rejects one); an
# INI or XML file keeps the BOM it had.
# One line per app, every run:
#   [ok] app             as declared, nothing written     [themed] app: what was written
#   [would] app: what    (-DryRun)                        [deferred] app: running, what waits
#   [skip] app: why      [follows] app: how               [cannot] app: why     [!] app: error
#   powershell -ExecutionPolicy Bypass -File C:\ProgramData\dram\look.ps1 [-DryRun]
# Exit: 0, or 1 when an app's step failed ([!]). Log: look.log beside it. Windows PowerShell
# 5.1 and PowerShell 7; ASCII only ([char]0x2014 where an em dash is meant).

param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1's type data gives arrays a Count that ConvertTo-Json would write as
# {"value": [...], "Count": n}; without it they stay arrays (PowerShell 6+ never had it)
if ($PSVersionTable.PSVersion.Major -lt 6) { Remove-TypeData -TypeName System.Array -ErrorAction SilentlyContinue }
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Lp = Join-Path $Here 'letterpress'
$Log = Join-Path $Here 'look.log'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:Count = @{ ok = 0; themed = 0; would = 0; deferred = 0; skip = 0; follows = 0; cannot = 0; '!' = 0 }

# --- helpers (nothing here writes to the pipeline: functions return values) ------------------
function Say([string]$tag, [string]$app, [string]$msg) {
  $l = '[{0}] {1}' -f $tag, $app
  if ($msg) { $l += ': ' + $msg }
  $script:Count[$tag]++
  Add-Content -LiteralPath $Log -Value ('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $l) -Encoding UTF8
  Write-Host $l
}
function Done([string]$app, [string[]]$what, [string]$note) {
  # the closing line for an app: what changed (or would), else ok
  $what = @($what | Where-Object { $_ })
  if ($what.Count -eq 0) { Say 'ok' $app $note; return }
  $msg = $what -join ', '
  if ($note) { $msg += " ($note)" }
  if ($DryRun) { Say 'would' $app $msg } else { Say 'themed' $app $msg }
}
function Test-Running([string[]]$names) { [bool](Get-Process -Name $names -ErrorAction SilentlyContinue) }
function Invoke-Native([scriptblock]$sb) {
  # Windows PowerShell 5.1 turns a native command's stderr into a terminating error under Stop
  $ErrorActionPreference = 'Continue'
  & $sb
}
function Read-Raw([string]$path) {
  # the text and whether it began with a UTF-8 BOM
  $b = [IO.File]::ReadAllBytes($path)
  $bom = ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
  $off = if ($bom) { 3 } else { 0 }
  return @{ Text = $Utf8.GetString($b, $off, $b.Length - $off); Bom = $bom }
}
function Write-Raw([string]$path, [string]$text, [bool]$bom) {
  if ($DryRun) { return }
  [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
  [IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($bom)))
}
function Save-Original([string]$path) {
  $b = "$path.before-dram"
  if (-not $DryRun -and (Test-Path -LiteralPath $path) -and -not (Test-Path -LiteralPath $b)) { Copy-Item -LiteralPath $path -Destination $b }
}
function Sync-File([string]$src, [string]$dst) {
  # a file that is ours alone; $true when it was (or would be) written
  if (-not (Test-Path -LiteralPath $src)) { throw "$src is missing (install/windows/apply-windows.sh stages it)" }
  if ((Test-Path -LiteralPath $dst) -and ((Get-FileHash -LiteralPath $src).Hash -eq (Get-FileHash -LiteralPath $dst).Hash)) { return $false }
  if (-not $DryRun) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $dst))
    Copy-Item -LiteralPath $src -Destination $dst -Force
  }
  return $true
}
function Read-Json([string]$path) { return ((Read-Raw $path).Text | ConvertFrom-Json) }
function Write-Json([string]$path, $obj) { Write-Raw $path ((ConvertTo-Json -InputObject $obj -Depth 100) + "`n") $false }
function Get-Prop($obj, [string]$name) {
  if ($null -eq $obj) { return $null }
  $p = $obj.PSObject.Properties[$name]
  if ($p) { return $p.Value }
  return $null
}
function Set-Prop($obj, [string]$name, $value) {
  # in place, so the key keeps its position (Add-Member -Force would move it to the end)
  $p = $obj.PSObject.Properties[$name]
  if ($p) { $p.Value = $value } else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}
function Get-Json($obj) { return (ConvertTo-Json -InputObject $obj -Depth 100 -Compress) }
function Set-IniValue([string]$text, [string]$section, [string]$key, [string]$value, [switch]$Commented) {
  # key=value inside [section] (added, or the section appended, when missing); with -Commented a
  # "#key=" default line (vlcrc) is taken over too
  $nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }
  $lines = New-Object System.Collections.Generic.List[string]
  if ($text.Length) { $lines.AddRange([string[]]($text -split "`r?`n")) }
  if ($lines.Count -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
  $keyRe = '^\s*' + $(if ($Commented) { '#?\s*' } else { '' }) + [regex]::Escape($key) + '\s*='
  $in = $false; $last = -1; $done = $false
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*\[([^\]]+)\]') {
      if ($in) { break }
      $in = ($matches[1] -eq $section)
      if ($in) { $last = $i }
      continue
    }
    if (-not $in) { continue }
    if ($lines[$i] -match $keyRe) { $lines[$i] = "$key=$value"; $done = $true; break }
    if ($lines[$i].Trim()) { $last = $i }
  }
  if (-not $done) {
    if ($last -ge 0) { $lines.Insert($last + 1, "$key=$value") }
    else {
      if ($lines.Count -and $lines[$lines.Count - 1].Trim()) { $lines.Add('') }
      $lines.Add("[$section]"); $lines.Add("$key=$value")
    }
  }
  return (($lines -join $nl) + $nl)
}
function Set-JsoncValue([string]$text, [string]$key, $value) {
  # one top-level "key": scalar in a JSON-with-comments file, edited in place; the literal is
  # built here (5.1's ConvertTo-Json would turn every single quote into a unicode escape)
  if ($value -is [bool]) { $lit = $(if ($value) { 'true' } else { 'false' }) }
  elseif ($value -is [string]) { $lit = '"' + (($value -replace '\\', '\\') -replace '"', '\"') + '"' }
  else { $lit = [string]$value }
  $re = '(?m)^(\s*"' + [regex]::Escape($key) + '"\s*:\s*)("(?:[^"\\]|\\.)*"|true|false|null|-?\d+(?:\.\d+)?)'
  $m = [regex]::Match($text, $re)
  if ($m.Success) {
    $g = $m.Groups[2]
    if ($value -is [string] -and $g.Value.StartsWith('"')) {
      if ([regex]::Unescape($g.Value.Substring(1, $g.Value.Length - 2)) -ceq $value) { return $text }
    } elseif ($g.Value -ceq $lit) { return $text }
    return $text.Substring(0, $g.Index) + $lit + $text.Substring($g.Index + $g.Length)
  }
  $i = $text.IndexOf('{')
  if ($i -lt 0) { throw "no JSON object" }
  $nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }
  return $text.Substring(0, $i + 1) + $nl + '  "' + $key + '": ' + $lit + ',' + $text.Substring($i + 1)
}
function Get-Profiles([string]$root) {
  # Firefox-family profile folders that have been used (prefs.js written)
  if (-not (Test-Path -LiteralPath $root)) { return @() }
  return @(Get-ChildItem -LiteralPath $root -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'prefs.js') })
}
function Set-PrefValue([string]$text, [string]$key, [string]$value) {
  # "key: value" in Wireshark's preferences: the live line, else its commented-out default, else
  # appended; a value Wireshark wrote back in full ("Monaspace Xenon,10,-1,5,...") counts as asked
  $nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }
  $k = [regex]::Escape($key)
  $m = [regex]::Match($text, '(?m)^' + $k + ':[ \t]*([^\r\n]*)')
  if ($m.Success) {
    $g = $m.Groups[1]
    if ($g.Value -ceq $value -or $g.Value.StartsWith($value + ',')) { return $text }
    return $text.Substring(0, $g.Index) + $value + $text.Substring($g.Index + $g.Length)
  }
  $m = [regex]::Match($text, '(?m)^#[ \t]*' + $k + ':[^\r\n]*')
  if ($m.Success) { return $text.Substring(0, $m.Index) + $key + ': ' + $value + $text.Substring($m.Index + $m.Length) }
  if ($text.Length -and -not $text.EndsWith("`n")) { $text += $nl }
  return $text + $key + ': ' + $value + $nl
}
function Set-PropertiesValue([string]$text, [string]$key, [string]$value) {
  # key=value in a Java .properties file (RuneLite's profiles): the line in place, else appended
  $nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }
  $m = [regex]::Match($text, '(?m)^' + [regex]::Escape($key) + '[ \t]*[=:][ \t]*([^\r\n]*)')
  if ($m.Success) {
    if ($m.Groups[1].Value -ceq $value) { return $text }
    return $text.Substring(0, $m.Index) + $key + '=' + $value + $text.Substring($m.Index + $m.Length)
  }
  if ($text.Length -and -not $text.EndsWith("`n")) { $text += $nl }
  return $text + $key + '=' + $value + $nl
}

# --- Windows Terminal: the schemes, the settings keys we own, the old fragment ---------------
function Set-Terminal {
  $app = 'terminal'
  $did = @()
  if (Sync-File (Join-Path $Lp 'wt-schemes.json') (Join-Path $env:ProgramData 'Microsoft\Windows Terminal\Fragments\dram\letterpress.json')) { $did += 'schemes' }
  $old = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\dram\washi.json'
  if (Test-Path -LiteralPath $old) {
    if (-not $DryRun) {
      Remove-Item -LiteralPath $old -Force
      $od = Split-Path -Parent $old
      if (-not (Get-ChildItem -LiteralPath $od -Force)) { Remove-Item -LiteralPath $od -Force }
    }
    $did += 'the old washi fragment retired'
  }
  $want = Read-Json (Join-Path $Lp 'wt-settings.json')
  $pwsh = (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe')) -or [bool](Get-Command pwsh.exe -ErrorAction SilentlyContinue)
  $homes = @(
    @{ Pkg = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe'; Dir = 'LocalState' },
    @{ Pkg = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe'; Dir = 'LocalState' },
    @{ Pkg = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal'; Dir = '' }
  )
  $seen = 0
  foreach ($h in $homes) {
    $d = if ($h.Dir) { Join-Path $h.Pkg $h.Dir } else { $h.Pkg }
    $s = Join-Path $d 'settings.json'
    # packaged: the package folder says it is installed; unpackaged: only a settings.json does
    if ($h.Dir) { if (-not (Test-Path -LiteralPath $h.Pkg)) { continue } } elseif (-not (Test-Path -LiteralPath $s)) { continue }
    $seen++
    $j = $null
    if (Test-Path -LiteralPath $s) {
      $raw = (Read-Raw $s).Text
      $plain = (($raw -split "`r?`n") | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
      try { $j = $plain | ConvertFrom-Json } catch { Say '!' $app "$s is not plain JSON, left alone: $($_.Exception.Message)"; continue }
    }
    if ($null -eq $j) { $j = [pscustomobject]@{} }
    $before = Get-Json $j
    if ($pwsh) { Set-Prop $j 'defaultProfile' $want.defaultProfile }
    Set-Prop $j 'theme' $want.theme
    $others = @(@(Get-Prop $j 'themes') | Where-Object { $_ -and (Get-Prop $_ 'name') -ne 'letterpress' })
    Set-Prop $j 'themes' (@($others) + @($want.themes))
    $profiles = Get-Prop $j 'profiles'
    if ($profiles -is [array]) { $profiles = [pscustomobject]@{ list = $profiles } }
    if ($null -eq $profiles) { $profiles = [pscustomobject]@{} }
    $defaults = Get-Prop $profiles 'defaults'
    if ($null -eq $defaults) { $defaults = [pscustomobject]@{} }
    foreach ($p in $want.profiles.defaults.PSObject.Properties) { Set-Prop $defaults $p.Name $p.Value }
    Set-Prop $profiles 'defaults' $defaults
    Set-Prop $j 'profiles' $profiles
    if ((Get-Json $j) -ceq $before) { continue }
    Save-Original $s
    Write-Json $s $j
    $did += "settings.json ($(Split-Path -Leaf $h.Pkg))"
  }
  if ($seen -eq 0) { Say 'skip' $app 'Windows Terminal is not installed for this user'; return }
  Done $app $did $(if ($pwsh) { '' } else { 'PowerShell 7 missing: the default profile left as it is' })
}

# --- PowerShell: one profile for 5.1 and 7 ---------------------------------------------------
function Set-PowerShell {
  $app = 'powershell'
  $text = @'
# dram: the Letterpress prompt - written by install/windows/dram-windows/look.ps1, and rewritten
# by every converge; your own lines go in profile.local.ps1 beside this file.
if ($Host.Name -eq 'ConsoleHost') {
  [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
  if (Get-Command starship -ErrorAction SilentlyContinue) {
    if (-not $env:STARSHIP_CONFIG) { $env:STARSHIP_CONFIG = 'C:\ProgramData\dram\starship.toml' }
    Invoke-Expression (& starship init powershell)
  }
  if (Test-Path -LiteralPath 'C:\ProgramData\dram\letterpress\psreadline.ps1') { . 'C:\ProgramData\dram\letterpress\psreadline.ps1' }
}
$dramLocal = Join-Path (Split-Path -Parent $PSCommandPath) 'profile.local.ps1'
if (Test-Path -LiteralPath $dramLocal) { . $dramLocal }
Remove-Variable -Name dramLocal
'@
  $text = ($text -replace "`r`n", "`n")
  $docs = [Environment]::GetFolderPath('MyDocuments')
  if (-not $docs) { Say '!' $app 'no Documents folder for this user'; return }
  $did = @()
  foreach ($rel in 'PowerShell\profile.ps1', 'WindowsPowerShell\profile.ps1') {
    $p = Join-Path $docs $rel
    if ((Test-Path -LiteralPath $p) -and ((Read-Raw $p).Text -ceq $text)) { continue }
    Save-Original $p
    Write-Raw $p $text $false
    $did += $rel
  }
  Done $app $did ''
}

# --- VSCodium: the extension, the settings keys ------------------------------------------------
function Set-VSCodium {
  $app = 'vscodium'
  $cli = @((Join-Path $env:ProgramFiles 'VSCodium\bin\codium.cmd'), (Join-Path $env:LOCALAPPDATA 'Programs\VSCodium\bin\codium.cmd')) |
    Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if (-not $cli) { Say 'skip' $app 'not installed'; return }
  $did = @()
  $vsix = Get-ChildItem -LiteralPath $Lp -Filter 'pj.letterpress-themes-*.vsix' | Select-Object -First 1
  if (-not $vsix) { throw "no pj.letterpress-themes-*.vsix in $Lp" }
  $ver = $vsix.BaseName.Substring('pj.letterpress-themes-'.Length)
  $have = @(Invoke-Native { & $cli --list-extensions --show-versions 2>$null })
  if ($have -notcontains "pj.letterpress-themes@$ver") {
    if (-not $DryRun) {
      Invoke-Native { & $cli --install-extension $vsix.FullName --force 2>&1 } | Out-Null
      if ($LASTEXITCODE -ne 0) { Say '!' $app "codium --install-extension failed (exit $LASTEXITCODE)"; return }
    }
    $did += "pj.letterpress-themes $ver"
  }
  $s = Join-Path $env:APPDATA 'VSCodium\User\settings.json'
  $seed = Join-Path $Here 'vscodium\settings.json.default'
  if (Test-Path -LiteralPath $s) { $r = Read-Raw $s }
  elseif (Test-Path -LiteralPath $seed) { $r = Read-Raw $seed; $did += 'settings.json seeded' }
  else { $r = @{ Text = "{`n}`n"; Bom = $false } }
  $text = $r.Text
  $want = Read-Json (Join-Path $Lp 'vscodium-settings.json')
  foreach ($p in $want.PSObject.Properties) { $text = Set-JsoncValue $text $p.Name $p.Value }
  if (-not (Test-Path -LiteralPath $s) -or ($text -cne $r.Text)) {
    Save-Original $s
    Write-Raw $s $text $false
    if ($did -notcontains 'settings.json seeded') { $did += 'settings.json' }
  }
  Done $app $did ''
}

# --- LibreWolf and Thunderbird: Arch's userChrome.css and colours ------------------------------
function Set-LibreWolf {
  $app = 'librewolf'
  $root = Join-Path $env:APPDATA 'librewolf'
  if (-not (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'LibreWolf\librewolf.exe')) -and -not (Test-Path -LiteralPath $root)) { Say 'skip' $app 'not installed'; return }
  $did = @()
  if (Sync-File (Join-Path $Here 'librewolf\librewolf.overrides.cfg') (Join-Path $env:USERPROFILE '.librewolf\librewolf.overrides.cfg')) { $did += 'librewolf.overrides.cfg' }
  $profiles = Get-Profiles (Join-Path $root 'Profiles')
  foreach ($p in $profiles) {
    $c = Join-Path $p.FullName 'chrome'
    if (Sync-File (Join-Path $Here 'librewolf\userChrome.css') (Join-Path $c 'userChrome.css')) { $did += "$($p.Name)\chrome\userChrome.css" }
    if (Sync-File (Join-Path $Here 'letterpress-colors.css') (Join-Path $c 'letterpress-colors.css')) { $did += "$($p.Name)\chrome\letterpress-colors.css" }
  }
  if ($profiles.Count -eq 0) { Say 'skip' $app "start it once (no profile yet)$(if ($did) { '; written: ' + ($did -join ', ') })"; return }
  Done $app $did $(if ($did) { 'read at start: restart it' })
}
function Set-Thunderbird {
  $app = 'thunderbird'
  $root = Join-Path $env:APPDATA 'Thunderbird'
  if (-not (Test-Path -LiteralPath $root)) { Say 'skip' $app 'start it once (no profile yet)'; return }
  $profiles = Get-Profiles (Join-Path $root 'Profiles')
  if ($profiles.Count -eq 0) { Say 'skip' $app 'start it once (no profile yet)'; return }
  $did = @()
  foreach ($p in $profiles) {
    $c = Join-Path $p.FullName 'chrome'
    if (Sync-File (Join-Path $Here 'thunderbird\userChrome.css') (Join-Path $c 'userChrome.css')) { $did += "$($p.Name)\chrome\userChrome.css" }
    if (Sync-File (Join-Path $Here 'letterpress-colors.css') (Join-Path $c 'letterpress-colors.css')) { $did += "$($p.Name)\chrome\letterpress-colors.css" }
    $u = Join-Path $p.FullName 'user.js'
    if (-not (Test-Path -LiteralPath $u)) {   # a seed: only when the profile has none
      if (-not $DryRun) { Copy-Item -LiteralPath (Join-Path $Here 'thunderbird\user.js.default') -Destination $u }
      $did += "$($p.Name)\user.js"
    }
  }
  Done $app $did $(if ($did) { 'read at start: restart it' })
}

# --- Vesktop: the Vencord theme, enabled ------------------------------------------------------
function Set-Vesktop {
  $app = 'vesktop'
  $d = Join-Path $env:APPDATA 'vesktop'
  $vs = Join-Path $d 'settings\settings.json'   # Vencord's
  $ks = Join-Path $d 'settings.json'            # Vesktop's own
  if (-not (Test-Path -LiteralPath $vs)) { Say 'skip' $app 'start it once (no settings yet)'; return }
  $did = @()
  if (Sync-File (Join-Path $Lp 'vesktop\letterpress.theme.css') (Join-Path $d 'themes\letterpress.theme.css')) { $did += 'letterpress.theme.css' }
  $v = Read-Json $vs
  $themes = @(@(Get-Prop $v 'enabledThemes') | Where-Object { $_ })
  $k = if (Test-Path -LiteralPath $ks) { Read-Json $ks } else { $null }
  $wantV = $themes -notcontains 'letterpress.theme.css'
  $wantK = ($null -ne $k) -and ((Get-Prop $k 'transparencyOption') -ne 'none')
  if ($wantV -or $wantK) {
    if (Test-Running 'vesktop') { Say 'deferred' $app "running: the theme is enabled after it closes$(if ($did) { '; written: ' + ($did -join ', ') })"; return }
    if ($wantV) { Set-Prop $v 'enabledThemes' (@($themes) + @('letterpress.theme.css')); Save-Original $vs; Write-Json $vs $v; $did += 'enabledThemes' }
    if ($wantK) { Set-Prop $k 'transparencyOption' 'none'; Save-Original $ks; Write-Json $ks $k; $did += 'transparencyOption' }
  }
  Done $app $did ''
}

# --- OBS Studio: a Yami variant, selected ----------------------------------------------------
function Set-OBS {
  $app = 'obs'
  $d = Join-Path $env:APPDATA 'obs-studio'
  $ini = Join-Path $d 'user.ini'
  if (-not (Test-Path -LiteralPath $ini)) { Say 'skip' $app 'start it once (no user.ini yet)'; return }
  $did = @()
  if (Sync-File (Join-Path $Lp 'obs\Letterpress.ovt') (Join-Path $d 'themes\Letterpress.ovt')) { $did += 'Letterpress.ovt' }
  $r = Read-Raw $ini
  $new = Set-IniValue $r.Text 'Appearance' 'Theme' 'com.pj.Yami.Letterpress'
  if ($new -cne $r.Text) {
    if (Test-Running 'obs64', 'obs32', 'obs') { Say 'deferred' $app "running: user.ini waits$(if ($did) { '; written: ' + ($did -join ', ') })"; return }
    Save-Original $ini
    Write-Raw $ini $new $r.Bom
    $did += 'user.ini [Appearance] Theme'
  }
  Done $app $did ''
}

# --- Notepad++: the theme (compared by its colours), dark mode, the updater off ------------------
function Get-StyleMap([xml]$x) {
  $m = @{}
  foreach ($lt in @($x.SelectNodes('/NotepadPlus/LexerStyles/LexerType'))) {
    foreach ($w in @($lt.SelectNodes('WordsStyle'))) {
      $m['L|' + $lt.GetAttribute('name') + '|' + $w.GetAttribute('styleID') + '|' + $w.GetAttribute('name')] =
        $w.GetAttribute('fgColor') + '|' + $w.GetAttribute('bgColor') + '|' + $w.GetAttribute('fontStyle')
    }
  }
  foreach ($w in @($x.SelectNodes('/NotepadPlus/GlobalStyles/WidgetStyle'))) {
    $m['G|' + $w.GetAttribute('name') + '|' + $w.GetAttribute('styleID')] = ($w.GetAttribute('fgColor'), $w.GetAttribute('bgColor'),
      $w.GetAttribute('fontStyle'), $w.GetAttribute('fontName'), $w.GetAttribute('fontSize')) -join '|'
  }
  return $m
}
function Set-NotepadPlusPlus {
  $app = 'notepad++'
  $d = Join-Path $env:APPDATA 'Notepad++'
  $cfg = Join-Path $d 'config.xml'
  if (-not (Test-Path -LiteralPath $cfg)) { Say 'skip' $app 'start it once (no config.xml yet)'; return }
  $did = @()
  $src = Join-Path $Lp 'notepad++\Letterpress.xml'
  $dst = Join-Path $d 'themes\Letterpress.xml'
  # Notepad++ restamps its theme at startup (modelFileLastModifiedDate): compare the colours
  $same = $false
  if (Test-Path -LiteralPath $dst) {
    try {
      $a = Get-StyleMap ([xml]((Read-Raw $src).Text)); $b = Get-StyleMap ([xml]((Read-Raw $dst).Text))
      $same = $true
      foreach ($k in $a.Keys) { if ($b[$k] -cne $a[$k]) { $same = $false; break } }
    } catch { $same = $false }
  }
  if (-not $same) {
    if (-not $DryRun) { [void][IO.Directory]::CreateDirectory((Split-Path -Parent $dst)); Copy-Item -LiteralPath $src -Destination $dst -Force }
    $did += 'themes\Letterpress.xml'
  }
  $want = Read-Json (Join-Path $Lp 'notepad++\darkmode.json')
  $r = Read-Raw $cfg
  $x = New-Object System.Xml.XmlDocument
  $x.PreserveWhitespace = $true
  $x.LoadXml($r.Text)
  $gui = $x.SelectSingleNode('/NotepadPlus/GUIConfigs')
  if ($null -eq $gui) { Say '!' $app 'config.xml has no GUIConfigs'; return }
  $edits = 0
  foreach ($grp in $want.PSObject.Properties) {
    $n = $gui.SelectSingleNode("GUIConfig[@name='$($grp.Name)']")
    if ($null -eq $n) { $n = $x.CreateElement('GUIConfig'); [void]$n.SetAttribute('name', $grp.Name); [void]$gui.AppendChild($n); $edits++ }
    foreach ($a in $grp.Value.PSObject.Properties) {
      if ($a.Name -eq '#text') { if ($n.InnerText -cne $a.Value) { $n.InnerText = $a.Value; $edits++ }; continue }
      if ($n.GetAttribute($a.Name) -cne $a.Value) { [void]$n.SetAttribute($a.Name, $a.Value); $edits++ }
    }
  }
  if ($edits -gt 0) {
    if (Test-Running 'notepad++') { Say 'deferred' $app "running: config.xml waits (it is rewritten on exit)$(if ($did) { '; written: ' + ($did -join ', ') })"; return }
    Save-Original $cfg
    if (-not $DryRun) {
      $ws = New-Object System.Xml.XmlWriterSettings
      $ws.Encoding = New-Object System.Text.UTF8Encoding($r.Bom)
      $ws.Indent = $false
      $ws.NewLineHandling = [System.Xml.NewLineHandling]::None
      $w = [System.Xml.XmlWriter]::Create($cfg, $ws)
      try { $x.Save($w) } finally { $w.Close() }
    }
    $did += 'config.xml (dark mode, font, updater off)'
  }
  Done $app $did ''
}

# --- Mumble: a theme folder, selected ------------------------------------------------------------
function Set-Mumble {
  $app = 'mumble'
  $base = Join-Path $env:APPDATA 'Mumble\Mumble'
  $cands = @((Join-Path $env:LOCALAPPDATA 'Mumble\Mumble\mumble_settings.json'), (Join-Path $base 'mumble_settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Mumble\mumble_settings.json'), (Join-Path $env:APPDATA 'Mumble\mumble_settings.json'))
  $s = $cands | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if (-not $s) { Say 'skip' $app 'start it once (no mumble_settings.json yet)'; return }
  $did = @()
  foreach ($f in 'theme.ini', 'Letterpress.qss') {
    if (Sync-File (Join-Path $Lp "mumble\Letterpress\$f") (Join-Path $base "Themes\Letterpress\$f")) { $did += "Themes\Letterpress\$f" }
  }
  $style = if ((Read-Raw (Join-Path $Lp 'mumble\Letterpress\theme.ini')).Text -match '(?m)^name=(Dark|Lite)\s*$') { $matches[1] } else { 'Dark' }
  $j = Read-Json $s
  $ui = Get-Prop $j 'ui'
  if ((Get-Prop $ui 'theme') -ne 'Letterpress' -or (Get-Prop $ui 'theme_style') -ne $style) {
    if (Test-Running 'mumble') { Say 'deferred' $app "running: the theme is selected after it closes$(if ($did) { '; written: ' + ($did -join ', ') })"; return }
    if ($null -eq $ui) { $ui = [pscustomobject]@{}; Set-Prop $j 'ui' $ui }
    Set-Prop $ui 'theme' 'Letterpress'
    Set-Prop $ui 'theme_style' $style
    Save-Original $s
    Write-Json $s $j
    $did += 'ui.theme'
  }
  Done $app $did ''
}

# --- Halloy: a theme file, the root key -------------------------------------------------------------
function Set-Halloy {
  $app = 'halloy'
  $d = Join-Path $env:APPDATA 'halloy'
  $cfg = Join-Path $d 'config.toml'
  if (-not (Test-Path -LiteralPath $cfg)) { Say 'skip' $app 'start it once (no config.toml yet)'; return }
  $did = @()
  if (Sync-File (Join-Path $Lp 'halloy\letterpress.toml') (Join-Path $d 'themes\letterpress.toml')) { $did += 'themes\letterpress.toml' }
  $r = Read-Raw $cfg
  $nl = if ($r.Text -match "`r`n") { "`r`n" } else { "`n" }
  $lines = [string[]]($r.Text -split "`r?`n")
  $root = $lines.Count
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*\[') { $root = $i; break } }
  $want = 'theme = "letterpress"'
  $at = -1
  for ($i = 0; $i -lt $root; $i++) { if ($lines[$i] -match '^\s*theme\s*=') { $at = $i; break } }
  $new = $r.Text
  if ($at -ge 0) { if ($lines[$at] -cne $want) { $lines[$at] = $want; $new = $lines -join $nl } }
  else { $new = $want + $nl + $r.Text }
  if ($new -cne $r.Text) { Save-Original $cfg; Write-Raw $cfg $new $r.Bom; $did += 'config.toml theme' }
  Done $app $did $(if ($did) { 'reload the config, or restart it' })
}

# --- qBittorrent: dark, and a folder theme in the palette -------------------------------------------
# (not run: qBittorrent gave way to Transmission on 2026-10-12; kept for a host that keeps it)
function Set-QBittorrent {
  $app = 'qbittorrent'
  $d = Join-Path $env:APPDATA 'qBittorrent'
  $ini = Join-Path $d 'qBittorrent.ini'
  if (-not (Test-Path -LiteralPath $ini)) { Say 'skip' $app 'start it once (no qBittorrent.ini yet)'; return }
  $did = @()
  $theme = Join-Path $d 'themes\letterpress\config.json'
  if (Sync-File (Join-Path $Lp 'qbittorrent\letterpress\config.json') $theme) { $did += 'themes\letterpress' }
  $scheme = if ((Read-Raw (Join-Path $Lp 'qbittorrent\letterpress\config.json')).Text -match '"colors\.dark"') { 'Dark' } else { 'Light' }
  $r = Read-Raw $ini
  $t = Set-IniValue $r.Text 'Appearance' 'ColorScheme' $scheme
  $t = Set-IniValue $t 'Preferences' 'General\UseCustomUITheme' 'true'
  $t = Set-IniValue $t 'Preferences' 'General\CustomUIThemePath' ($theme -replace '\\', '/')
  if ($t -cne $r.Text) {
    if (Test-Running 'qbittorrent') { Say 'deferred' $app "running: qBittorrent.ini waits (it is rewritten on exit)$(if ($did) { '; written: ' + ($did -join ', ') })"; return }
    Save-Original $ini
    Write-Raw $ini $t $r.Bom
    $did += 'qBittorrent.ini'
  }
  Done $app $did ''
}

# --- calibre: a named palette, chosen ------------------------------------------------------------------
function Set-Calibre {
  $app = 'calibre'
  $g = Join-Path $env:APPDATA 'calibre\gui.json'
  if (-not (Test-Path -LiteralPath $g)) { Say 'skip' $app 'start it once (no gui.json yet)'; return }
  $want = Read-Json (Join-Path $Lp 'calibre\palette.json')
  $j = Read-Json $g
  $before = Get-Json $j
  foreach ($p in $want.PSObject.Properties) {
    if ($p.Name -like '*_palettes') {
      $all = Get-Prop $j $p.Name
      if ($null -eq $all) { $all = [pscustomobject]@{} }
      foreach ($q in $p.Value.PSObject.Properties) { Set-Prop $all $q.Name $q.Value }
      Set-Prop $j $p.Name $all
    } else { Set-Prop $j $p.Name $p.Value }
  }
  if ((Get-Json $j) -ceq $before) { Done $app @() ''; return }
  if (Test-Running 'calibre*') { Say 'deferred' $app 'running: gui.json waits (it is rewritten on exit)'; return }
  Save-Original $g
  Write-Json $g $j
  Done $app @('gui.json palette') ''
}

# --- VLC: the dark palette (its highlight is the Windows accent) ------------------------------------
function Set-VLC {
  $app = 'vlc'
  $rc = Join-Path $env:APPDATA 'vlc\vlcrc'
  if (-not (Test-Path -LiteralPath $rc)) { Say 'skip' $app 'start it once (no vlcrc yet)'; return }
  $r = Read-Raw $rc
  $t = Set-IniValue $r.Text 'qt' 'qt-dark-palette' '1' -Commented
  if ($t -ceq $r.Text) { Say 'follows' $app 'the dark palette; its highlight is the Windows accent'; return }
  if (Test-Running 'vlc') { Say 'deferred' $app 'running: vlcrc waits'; return }
  Save-Original $rc
  Write-Raw $rc $t $r.Bom
  Done $app @('vlcrc qt-dark-palette') 'its highlight is the Windows accent'
}

# --- LocalSend: colours from the Windows accent ----------------------------------------------------
function Set-LocalSend {
  $app = 'localsend'
  $s = @((Join-Path $env:APPDATA 'LocalSend\settings.json'), (Join-Path $env:APPDATA 'org.localsend\localsend_app\shared_preferences.json')) |
    Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if (-not $s) { Say 'skip' $app 'start it once (no settings yet)'; return }
  $j = Read-Json $s
  if ((Get-Prop $j 'flutter.ls_color') -eq 'system') { Say 'follows' $app 'the Windows accent'; return }
  if (Test-Running 'localsend*') { Say 'deferred' $app 'running: its colour setting waits'; return }
  Set-Prop $j 'flutter.ls_color' 'system'
  Save-Original $s
  Write-Json $s $j
  Done $app @('colour: system (the Windows accent)') ''
}

# --- Vortex, mintty --------------------------------------------------------------------------------
function Set-Vortex {
  $app = 'vortex'
  $d = Join-Path $env:APPDATA 'Vortex'
  if (-not (Test-Path -LiteralPath $d)) { Say 'skip' $app 'start it once'; return }
  $did = @()
  if (Sync-File (Join-Path $Lp 'vortex\letterpress\variables.scss') (Join-Path $d 'themes\letterpress\variables.scss')) { $did += 'themes\letterpress' }
  Done $app $did 'pick "letterpress" once in Settings > Theme'
}
function Set-Mintty {
  $app = 'mintty'
  if (-not (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'Git\usr\bin\mintty.exe'))) { Say 'skip' $app 'Git for Windows is not installed'; return }
  $did = @()
  if (Sync-File (Join-Path $Lp 'mintty\letterpress') (Join-Path $env:APPDATA 'mintty\themes\letterpress')) { $did += 'themes\letterpress' }
  $rcFile = Join-Path $env:USERPROFILE '.minttyrc'
  $r = if (Test-Path -LiteralPath $rcFile) { Read-Raw $rcFile } else { @{ Text = ''; Bom = $false } }
  $t = $r.Text
  foreach ($kv in @(@('ThemeFile', 'letterpress'), @('Font', 'Monaspace Xenon'), @('FontHeight', '12'))) {
    $re = '(?m)^' + [regex]::Escape($kv[0]) + '=.*$'
    if ($t -match $re) { $t = [regex]::Replace($t, $re, ($kv[0] + '=' + $kv[1])) }
    else { $t = $t + $(if ($t -and -not $t.EndsWith("`n")) { "`n" } else { '' }) + $kv[0] + '=' + $kv[1] + "`n" }
  }
  if ($t -cne $r.Text) {
    if (Test-Running 'mintty') { Say 'deferred' $app "running: .minttyrc waits$(if ($did) { '; written: ' + ($did -join ', ') })"; return }
    Save-Original $rcFile
    Write-Raw $rcFile $t $r.Bom
    $did += '.minttyrc'
  }
  Done $app $did ''
}

# --- PowerToys: the utilities' colours, each in its own settings file -------------------------------
# PowerToys loads a utility's settings.json when it starts it (FancyZones and Always On Top also
# reread it when it changes). Only its Settings window writes these files, from what it holds in
# memory, so the merge waits for that window, not for PowerToys, which runs from sign-in on;
# Microsoft's own PowerToys.DSC.exe writes the same files the same way. A utility never set up
# has no file yet: it is named, not created.
function Set-PowerToys {
  $app = 'powertoys'
  $root = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys'
  if (-not (Test-Path -LiteralPath $root)) { Say 'skip' $app 'start it once (no settings yet)'; return }
  $want = Read-Json (Join-Path $Lp 'powertoys.json')
  $todo = @(); $none = @()
  foreach ($m in $want.PSObject.Properties) {
    $s = Join-Path $root "$($m.Name)\settings.json"
    if (-not (Test-Path -LiteralPath $s)) { $none += $m.Name; continue }
    $j = Read-Json $s
    $props = Get-Prop $j 'properties'
    if ($null -eq $props) { $props = [pscustomobject]@{}; Set-Prop $j 'properties' $props }
    $n = 0
    foreach ($p in $m.Value.PSObject.Properties) {
      # each key is {"value": ...}; a string is compared without case ("#c0442b" is "#C0442B")
      $cur = Get-Prop $props $p.Name
      if ($cur -is [System.Management.Automation.PSCustomObject]) {
        if ((Get-Json (Get-Prop $cur 'value')) -eq (Get-Json $p.Value)) { continue }
        Set-Prop $cur 'value' $p.Value
      } else { Set-Prop $props $p.Name ([pscustomobject]@{ value = $p.Value }) }
      $n++
    }
    if ($n -gt 0) { $todo += @{ Path = $s; Json = $j; Name = $m.Name } }
  }
  $note = if ($none.Count) { "no settings yet for $($none -join ', ') (open each once in PowerToys Settings)" } else { '' }
  if ($todo.Count -eq 0) { Done $app @() $note; return }
  if (Test-Running 'PowerToys.Settings') { Say 'deferred' $app 'its Settings window is open: the colours wait until it closes'; return }
  foreach ($e in $todo) { Save-Original $e.Path; Write-Json $e.Path $e.Json }
  $msg = 'PowerToys reads them when it next starts each one'
  if ($note) { $msg += '; ' + $note }
  Done $app @($todo | ForEach-Object { $_.Name }) $msg
}

# --- Command Palette: the list on the theme's paper ----------------------------------------------
# Its settings.json is in its package's redirected local app data (BaseSettingsPath under app-data
# redirection; which of the folders below that is, is UNVERIFIED on the host, so the first that
# holds Command Palette's own keys is used). It loads the file at start and writes it whole when
# it saves, and it runs from sign-in on: the merge waits until it is quit from the tray.
function Set-CommandPalette {
  $app = 'command palette'
  $pkg = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -Filter 'Microsoft.CommandPalette_*' -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $pkg) { Say 'skip' $app 'not installed (it comes with PowerToys)'; return }
  $s = $null; $j = $null
  foreach ($c in @((Join-Path $pkg.FullName 'LocalCache\Local\settings.json'), (Join-Path $pkg.FullName 'LocalState\settings.json'),
      (Join-Path $pkg.FullName 'LocalCache\Local\Microsoft.CmdPal\settings.json'), (Join-Path $env:LOCALAPPDATA 'Microsoft.CmdPal\settings.json'))) {
    if (-not (Test-Path -LiteralPath $c)) { continue }
    try { $x = Read-Json $c } catch { continue }
    if ($null -ne (Get-Prop $x 'Hotkey') -or $null -ne (Get-Prop $x 'ProviderSettings')) { $s = $c; $j = $x; break }
  }
  if (-not $s) { Say 'skip' $app 'start it once (no settings.json yet)'; return }
  $want = Read-Json (Join-Path $Lp 'cmdpal.json')
  $diff = @($want.PSObject.Properties | Where-Object { (Get-Json (Get-Prop $j $_.Name)) -ne (Get-Json $_.Value) } | ForEach-Object { $_.Name })
  if ($diff.Count -eq 0) { Done $app @() ''; return }
  if (Test-Running 'Microsoft.CmdPal.UI') { Say 'deferred' $app 'running: its colour waits (quit it from the tray, then converge)'; return }
  foreach ($p in $want.PSObject.Properties) { Set-Prop $j $p.Name $p.Value }
  Save-Original $s
  Write-Json $s $j
  Done $app @("settings.json $($diff -join ', ')") 'from its next start'
}

# --- TeamSpeak 3: our own style, picked once -----------------------------------------------------
# Per-user styles live in %APPDATA%\TS3Client\styles (addons install per user since 3.1); the
# pick itself is kept in its settings.db (SQLite, names unknown), so it is made by hand, once.
function Set-TeamSpeak {
  $app = 'teamspeak 3'
  $d = Join-Path $env:APPDATA 'TS3Client'
  if (-not (Test-Path -LiteralPath $d)) { Say 'skip' $app 'start it once (no TS3Client folder yet)'; return }
  $did = @()
  foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $Lp 'teamspeak') -Filter '*.qss' | Sort-Object Name)) {
    if (Sync-File $f.FullName (Join-Path $d "styles\$($f.Name)")) { $did += "styles\$($f.Name)" }
  }
  Done $app $did 'pick "Letterpress" once in Tools > Options > Design'
}

# --- nomacs: a theme beside its own, selected ------------------------------------------------------
# nomacs reads themes only from the first themes folder holding System.css, its own in Program
# Files, so the theme file needs the converge's elevation; settings.ini is rewritten on exit.
function Set-Nomacs {
  $app = 'nomacs'
  $dirs = @((Join-Path $env:ProgramFiles 'nomacs\bin'), (Join-Path $env:LOCALAPPDATA 'Programs\nomacs\bin'))
  if (${env:ProgramFiles(x86)}) { $dirs += Join-Path ${env:ProgramFiles(x86)} 'nomacs\bin' }
  $bin = $dirs | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'themes\System.css') } | Select-Object -First 1
  if (-not $bin) { Say 'skip' $app 'not installed (no nomacs\bin\themes)'; return }
  $theme = Get-ChildItem -LiteralPath (Join-Path $Lp 'nomacs') -Filter 'Letterpress-*.css' | Select-Object -First 1
  if (-not $theme) { throw "no nomacs\Letterpress-*.css in $Lp" }
  $did = @()
  try { if (Sync-File $theme.FullName (Join-Path $bin "themes\$($theme.Name)")) { $did += "themes\$($theme.Name)" } }
  catch { Say '!' $app "cannot write $bin\themes (the converge runs elevated; this run is not): $($_.Exception.Message)"; return }
  $ini = Join-Path $env:APPDATA 'nomacs\Image Lounge\settings.ini'
  if (-not (Test-Path -LiteralPath $ini)) { Say 'skip' $app "start it once (no settings.ini yet)$(if ($did) { '; written: ' + ($did -join ', ') })"; return }
  $want = Read-Json (Join-Path $Lp 'nomacs\settings.json')
  $r = Read-Raw $ini
  $t = $r.Text
  foreach ($sec in $want.PSObject.Properties) { foreach ($kv in $sec.Value.PSObject.Properties) { $t = Set-IniValue $t $sec.Name $kv.Name ([string]$kv.Value) } }
  if ($t -cne $r.Text) {
    if (Test-Running 'nomacs') { Say 'deferred' $app "running: settings.ini waits (it is rewritten on exit)$(if ($did) { '; written: ' + ($did -join ', ') })"; return }
    Save-Original $ini
    Write-Raw $ini $t $r.Bom
    $did += 'settings.ini (theme)'
  }
  Done $app $did ''
}

# --- WinDirStat: its colours in the registry ----------------------------------------------------
# HKCU\Software\WinDirStat\WinDirStat\<section>, written back by WinDirStat on exit, so the same
# rule as a file it owns; the values first replaced are kept in windirstat.before-dram.json here.
function Set-WinDirStat {
  $app = 'windirstat'
  $root = 'HKCU:\Software\WinDirStat\WinDirStat'
  if (-not (Test-Path -LiteralPath $root)) { Say 'skip' $app 'start it once (no settings yet)'; return }
  $want = Read-Json (Join-Path $Lp 'windirstat.json')
  $diff = @()
  foreach ($sec in $want.PSObject.Properties) {
    $k = Join-Path $root $sec.Name
    foreach ($v in $sec.Value.PSObject.Properties) {
      $cur = $null
      try { $cur = Get-ItemPropertyValue -LiteralPath $k -Name $v.Name -ErrorAction Stop } catch { }
      $bin = $v.Value -is [array]
      if ($bin) { $same = ($null -ne $cur) -and ((@($cur) -join ',') -eq (@($v.Value) -join ',')) }
      else { $same = ($null -ne $cur) -and ([string]$cur -eq [string]$v.Value) }
      if (-not $same) { $diff += @{ Key = $k; Name = $v.Name; Value = $v.Value; Bin = $bin; Was = $(if ($null -ne $cur) { @($cur | ForEach-Object { [int]$_ }) } else { $null }) } }
    }
  }
  if ($diff.Count -eq 0) { Done $app @() ''; return }
  if (Test-Running 'windirstat') { Say 'deferred' $app 'running: its colours wait (it writes its settings on exit)'; return }
  if (-not $DryRun) {
    $bk = Join-Path $Here 'windirstat.before-dram.json'
    if (-not (Test-Path -LiteralPath $bk)) {
      $old = [ordered]@{}
      foreach ($e in $diff) { $old["$($e.Key)\$($e.Name)"] = $e.Was }
      Write-Json $bk $old
    }
    foreach ($e in $diff) {
      if (-not (Test-Path -LiteralPath $e.Key)) { New-Item -Path $e.Key -Force | Out-Null }
      if ($e.Bin) { New-ItemProperty -LiteralPath $e.Key -Name $e.Name -PropertyType Binary -Value ([byte[]]@($e.Value)) -Force | Out-Null }
      else { New-ItemProperty -LiteralPath $e.Key -Name $e.Name -PropertyType DWord -Value ([int]$e.Value) -Force | Out-Null }
    }
  }
  Done $app @("$($diff.Count) colour value(s) under HKCU\Software\WinDirStat") 'its dark mode follows Windows'
}

# --- Wireshark: the preference keys, our colouring rules ------------------------------------------
# preferences is Wireshark's (rewritten whole when its preferences are saved): its keys are
# merged while it is closed. colorfilters is ours alone: the stock rules recoloured; the user's
# first copy is kept as colorfilters.before-dram.
function Set-Wireshark {
  $app = 'wireshark'
  $d = Join-Path $env:APPDATA 'Wireshark'
  if (-not (Test-Path -LiteralPath $d)) { Say 'skip' $app 'start it once (no profile folder yet)'; return }
  $did = @()
  $src = Join-Path $Lp 'wireshark\colorfilters'
  $cf = Join-Path $d 'colorfilters'
  if ((Test-Path -LiteralPath $cf) -and ((Get-FileHash -LiteralPath $cf).Hash -ne (Get-FileHash -LiteralPath $src).Hash)) { Save-Original $cf }
  if (Sync-File $src $cf) { $did += 'colorfilters' }
  $p = Join-Path $d 'preferences'
  $r = if (Test-Path -LiteralPath $p) { Read-Raw $p } else { @{ Text = ''; Bom = $false } }
  $t = $r.Text
  $want = Read-Json (Join-Path $Lp 'wireshark\preferences.json')
  foreach ($kv in $want.PSObject.Properties) { $t = Set-PrefValue $t $kv.Name ([string]$kv.Value) }
  if ($t -cne $r.Text) {
    if (Test-Running 'Wireshark') { Say 'deferred' $app "running: preferences wait$(if ($did) { '; written: ' + ($did -join ', ') })"; return }
    Save-Original $p
    Write-Raw $p $t $r.Bom
    $did += 'preferences'
  }
  Done $app $did $(if ($did) { 'read at start: restart it' })
}

# --- RuneLite: the overlays on the theme's paper ---------------------------------------------------
# Every profile in .runelite\profiles2 (RuneLite saves its profile on exit); the client's own look
# is fixed. A profile synced to a RuneLite account can bring the server's copy back at login.
function Set-RuneLite {
  $app = 'runelite'
  $files = @(Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE '.runelite\profiles2') -Filter '*.properties' -File -ErrorAction SilentlyContinue)
  if ($files.Count -eq 0) { Say 'skip' $app 'start it once (no profile yet)'; return }
  $want = Read-Json (Join-Path $Lp 'runelite.json')
  $todo = @()
  foreach ($f in $files) {
    $r = Read-Raw $f.FullName
    $t = $r.Text
    foreach ($kv in $want.PSObject.Properties) { $t = Set-PropertiesValue $t $kv.Name ([string]$kv.Value) }
    if ($t -cne $r.Text) { $todo += @{ Path = $f.FullName; Text = $t; Bom = $r.Bom; Name = $f.Name } }
  }
  if ($todo.Count -eq 0) { Done $app @() ''; return }
  if (Test-Running 'RuneLite') { Say 'deferred' $app 'running: the overlay colour waits (it saves its profile on exit)'; return }
  foreach ($e in $todo) { Save-Original $e.Path; Write-Raw $e.Path $e.Text $e.Bom }
  Done $app @($todo | ForEach-Object { "profiles2\$($_.Name)" }) 'the overlays; a synced profile can bring the server copy back'
}

# --- Zebar: the masthead's widget pack, and the settings that open it at start ------------------------
# Zebar reads %USERPROFILE%\.glzr\zebar: each <pack>\zpack.json, and settings.json's startupConfigs
# when it starts. Both are ours alone: the pack directory is replaced whole, and settings.json is put
# back when Zebar's tray menu changed it. Written before Zebar's first start, they also keep it from
# copying in its starter pack (which loads its scripts from the web).
function Set-Zebar {
  $app = 'zebar'
  if (-not (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'glzr.io\Zebar\zebar.exe'))) { Say 'skip' $app 'not installed (the desktop role installs it)'; return }
  $src = Join-Path $Lp 'zebar'
  $dst = Join-Path $env:USERPROFILE '.glzr\zebar'
  $did = @()
  $want = @(Get-ChildItem -LiteralPath (Join-Path $src 'letterpress') -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
  if ($want.Count -eq 0) { throw "$src\letterpress is empty (bin/gen-windows-look.py writes it)" }
  foreach ($n in $want) {
    if (Sync-File (Join-Path $src "letterpress\$n") (Join-Path $dst "letterpress\$n")) { $did += "letterpress\$n" }
  }
  $pack = Join-Path $dst 'letterpress'
  if (Test-Path -LiteralPath $pack) {
    foreach ($f in @(Get-ChildItem -LiteralPath $pack -File | Where-Object { $want -notcontains $_.Name })) {
      if (-not $DryRun) { Remove-Item -LiteralPath $f.FullName -Force }
      $did += "letterpress\$($f.Name) removed"
    }
  }
  $s = Join-Path $dst 'settings.json'
  $ss = Join-Path $src 'settings.json'
  if ((Test-Path -LiteralPath $s) -and ((Get-FileHash -LiteralPath $s).Hash -ne (Get-FileHash -LiteralPath $ss).Hash)) { Save-Original $s }
  if (Sync-File $ss $s) { $did += 'settings.json' }
  Done $app $did $(if ($did) { 'read at start: apply-live.ps1 restarts it on the desktop' })
}

# --- run ---------------------------------------------------------------------------------------------
Write-Host "== look for $env:USERNAME on $env:COMPUTERNAME$(if ($DryRun) { ' (dry run)' })"
if (-not (Test-Path -LiteralPath $Lp)) { Write-Host "[x] $Lp missing (install/windows/apply-windows.sh stages it)"; exit 1 }
foreach ($step in 'Set-Terminal', 'Set-PowerShell', 'Set-VSCodium', 'Set-LibreWolf', 'Set-Thunderbird', 'Set-Vesktop', 'Set-OBS',
  'Set-NotepadPlusPlus', 'Set-Mumble', 'Set-Halloy', 'Set-Calibre', 'Set-VLC', 'Set-LocalSend', 'Set-Vortex', 'Set-Mintty',
  'Set-PowerToys', 'Set-CommandPalette', 'Set-TeamSpeak', 'Set-Nomacs', 'Set-WinDirStat', 'Set-Wireshark', 'Set-RuneLite', 'Set-Zebar') {
  try { & $step } catch { Say '!' ($step -replace '^Set-', '').ToLower() $_.Exception.Message }
}
# the rest of the checklist (docs/design/themes/windows.md)
foreach ($a in 'proton pass', 'proton mail bridge', 'transmission') { Say 'follows' $a 'Windows dark mode' }
Say 'follows' 'windows shell' 'the desktop role: dark, the accent on title bars, the art, the Adwaita pointer, no sounds, a clear sign-in, a quiet Start and Explorer; apply-live.ps1: the taskbar auto-hidden'
foreach ($a in 'wireguard', 'openvpn gui') { Say 'cannot' $a 'no theming hook (it stays light)' }
foreach ($a in 'steam', 'spotify', 'battle.net', 'ea app', 'epic games', 'ubisoft connect', 'hytale', 'jagex launcher', 'nvidia app') {
  Say 'cannot' $a 'its own dark UI; no skins or patchers'
}
$c = $script:Count
Write-Host ("== look: {0} themed, {1} would change, {2} ok, {3} deferred, {4} skipped, {5} failed" -f $c['themed'], $c['would'], $c['ok'], $c['deferred'], $c['skip'], $c['!'])
if ($c['!'] -gt 0) { exit 1 }
exit 0

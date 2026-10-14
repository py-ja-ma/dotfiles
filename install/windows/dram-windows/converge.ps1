# install/windows/dram-windows/converge.ps1 - apply a rendered Windows build (decisions/0020,
# docs/platforms/windows/dram-ps1.md).
#
# The Windows side of install/windows/apply-windows.sh: run as administrator from
# C:\ProgramData\dram, where that script staged a build of windows/build/<host>/ - the render in
# build\ (manifest.json and the winget documents, where dram.ps1 keeps a release's render too)
# and every file the manifest lists. Each listed file is checked against its sha256 first; a
# missing or changed one stops the run before anything is applied (stage the build again).
# Then winget's extended features are enabled once (they come from the Store) and the build's
# phases run in order, 00 debloat, 10 system, 20 user, 30 apps, 40 autostart, 50 ask: each
# phase's documents through `winget configure` (machine, then user; both from this elevated
# session, so HKCU is this user's, pj's), every unit's result printed, then the phase's scripts
# - debloat.ps1 (only with -Debloat), account-picture.ps1, look.ps1 and icons.ps1 (the look
# inside the apps and on their shortcuts), autostart.ps1 (what may start by itself, apps the
# build just installed included). Last, apply-live.ps1 on pj's signed-in desktop (pointer, caret,
# keyboard toggle, colours, fonts, the taskbar's auto-hide and the masthead now rather than at
# the next sign-in), as dram.ps1 does it. The PC does not sleep while it runs (a sleep cut an
# SSH session mid-install on 2026-10-12). -DryRun: `winget configure test` (what would change)
# and every script's own dry run; nothing applied, nothing on the desktop.
#   powershell -ExecutionPolicy Bypass -File C:\ProgramData\dram\converge.ps1 [-Debloat] [-DryRun]
# Exit: 0 when every step converged (a dry run: when nothing would change), 1 when the staged
# files are not the build's, otherwise the first failing step's code. Logs: configure-<document>.log
# beside it.

param([switch]$Debloat, [switch]$DryRun)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Build = Join-Path $Here 'build'
Add-Type -Namespace Dram -Name Power -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags);'
[void][Dram.Power]::SetThreadExecutionState([uint32]2147483649)   # ES_CONTINUOUS | ES_SYSTEM_REQUIRED, until this process ends
$w = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
if (-not (Test-Path $w)) { Write-Output '[x] winget missing (App Installer)'; exit 1 }
$mf = Join-Path $Build 'manifest.json'
if (-not (Test-Path -LiteralPath $mf)) { Write-Output "[x] $mf missing (install/windows/apply-windows.sh stages a build)"; exit 1 }
$m = Get-Content -LiteralPath $mf -Raw -Encoding UTF8 | ConvertFrom-Json
if ($m.format -ne 1) { Write-Output "[x] manifest.json is format $($m.format); this converge.ps1 reads format 1"; exit 1 }

# every staged file as the render listed it, before anything is applied
$bad = @()
foreach ($f in @($m.files)) {
  $p = Join-Path $Here $f.path
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { $bad += "$($f.path) (missing)" }
  elseif ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne $f.sha256) { $bad += "$($f.path) (changed)" }
}
if ($bad.Count -gt 0) {
  Write-Output "[x] $($bad.Count) staged file(s) are not the build's: $(@($bad | Select-Object -First 8) -join ', ') - stage it again (install/windows/apply-windows.sh)"
  exit 1
}
Write-Output "[ok] $($m.host) $($m.release) ($($m.commit)): $(@($m.files).Count) staged files as rendered"
$script:Rc = 0
function Note([int]$code) { if ($code -ne 0 -and $script:Rc -eq 0) { $script:Rc = $code } }

# extended features (DSC) once; `configure --enable` takes no other flags
$first = Join-Path $Build (@($m.documents)[0].file)
& $w configure validate -f $first --disable-interactivity *> $null
if ($LASTEXITCODE -eq -1978335127) { & $w configure --enable *> $null; Write-Output "[ok] winget configure: extended features enabled (exit $LASTEXITCODE)" }

foreach ($phase in '00', '10', '20', '30', '40', '50') {
  foreach ($d in @($m.documents | Where-Object { $_.phase -eq $phase })) {
    $log = Join-Path $Here ('configure-' + [IO.Path]::GetFileNameWithoutExtension($d.file) + '.log')
    $cargs = @('configure') + @(if ($DryRun) { 'test' }) + @('-f', (Join-Path $Build $d.file), '--accept-configuration-agreements', '--disable-interactivity')
    & $w @cargs *> $log
    $code = $LASTEXITCODE
    Note $code
    Get-Content $log -Encoding UTF8 | Where-Object { $_ -match '^\S.*\[|^\s+(Unit |The |System\.)|successfully|not in the desired|is in the desired|was not' }
    Write-Output "== winget configure $(if ($DryRun) { 'test ' })$($d.file) (phase $phase, $($d.scope), $(@($d.units).Count) units): exit $code"
  }
  foreach ($s in @($m.scripts | Where-Object { $_.phase -eq $phase })) {
    if ($s.when -eq 'debloat' -and -not $Debloat) { continue }
    if ($DryRun -and -not $s.dryRun) { Write-Output "   $($s.file): has no dry run, skipped"; continue }
    $a = @($s.args) + @(if ($DryRun) { $s.dryRun })
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Here $s.file) @a
    Note $LASTEXITCODE
  }
}

# the look on the signed-in desktop now: a one-off task with that user's token, hidden (conhost
# --headless: Windows Terminal would otherwise host its console); apply-live.ps1 writes
# apply-live.log beside it
if ($DryRun) { Write-Output '   live: not in a dry run' }
elseif (-not (Test-Path -LiteralPath (Join-Path $Here 'apply-live.ps1'))) { Write-Output '   live: no apply-live.ps1 in this build; the look shows at the next sign-in' }
else {
  $user = (Get-CimInstance Win32_ComputerSystem).UserName
  if (-not $user) { Write-Output '   live: nobody is signed in at the PC; the look shows at the next sign-in' }
  elseif ($user -notmatch ('\\' + [regex]::Escape($env:USERNAME) + '$')) { Write-Output "   live: $user is signed in, not $env:USERNAME; the look shows at $env:USERNAME's next sign-in" }
  else {
    $t = 'dram-apply-live'
    $log = Join-Path $Here 'apply-live.log'
    $since = Get-Date
    $ps = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $act = New-ScheduledTaskAction -Execute (Join-Path $env:windir 'System32\conhost.exe') -Argument "--headless `"$ps`" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$(Join-Path $Here 'apply-live.ps1')`""
    Register-ScheduledTask -TaskName $t -Action $act -Principal (New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive) -Force | Out-Null
    Start-ScheduledTask -TaskName $t
    $deadline = $since.AddSeconds(60)
    while ((Get-Date) -lt $deadline -and -not ((Test-Path $log) -and (Get-Item $log).LastWriteTime -ge $since)) { Start-Sleep -Milliseconds 500 }
    Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
    if ((Test-Path $log) -and (Get-Item $log).LastWriteTime -ge $since) { Get-Content $log -Encoding UTF8 | ForEach-Object { $_ -replace '^\S+ \S+ ', '' } }
    else { Write-Output '[!] live: apply-live.ps1 did not report within 60 s; the look shows at the next sign-in' }
  }
}
Write-Output "== converge $($m.host)$(if ($DryRun) { ' (dry run)' }): exit $script:Rc"
exit $script:Rc

# install/windows/dram-windows/debloat.ps1 - cabin's Windows 11 (docs/platforms/windows/debloat.md).
#
# The apps cabin's Windows must not have, declared below, removed for every user and from
# the image new users get; safe to run again (it removes only what is still there). Run as
# administrator:
#   powershell -ExecutionPolicy Bypass -File debloat.ps1 [-DryRun]
#
# Two sources of bloat on cabin (2026-10-12): Windows' own consumer apps, and the bundle
# MSI's firmware pushes on a fresh install through WPBT ("MSI Driver Utility Installer":
# MSI Center, Norton, AiPPT, Dropbox, Chrome, Google Play Games, AIDA64, CPU-Z). The
# firmware switch is off in the BIOS by hand; DisableWpbtExecution (below) stops Windows
# running anything a firmware table hands it, whatever the BIOS says.
# Kept: the Store, winget, Terminal, Notepad, Paint, Photos, Snipping Tool, Calculator,
# Game Bar and the Xbox sign-in pieces games use,
# the codecs, Edge (a system part), the drivers and their consoles (AMD chipset, Realtek,
# NVIDIA). A Win32 uninstaller that only works with clicks (Norton's) is opened on the
# signed-in user's desktop and reported. What no uninstaller removes (MSI Center's
# services, its MsIo64 driver, Norton's remains after its restart) is declared under
# $Leftovers and removed directly. What starts at sign-in is autostart.ps1's job.
# Log: debloat.log beside this script.

param([switch]$DryRun)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- the declared state: none of these ---------------------------------------------------
$Appx = @(
  # Windows' own consumer apps
  'Clipchamp.Clipchamp', 'Microsoft.BingNews', 'Microsoft.BingSearch', 'Microsoft.BingWeather',
  'Microsoft.GamingApp', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.Copilot', 'Microsoft.StartExperiencesApp',
  'MicrosoftCorporationII.MicrosoftFamily', 'Microsoft.ZuneVideo', 'Microsoft.WindowsMaps',
  'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.MicrosoftStickyNotes',
  'Microsoft.OutlookForWindows', 'Microsoft.PowerAutomateDesktop', 'Microsoft.Todos',
  'Microsoft.Windows.DevHome', 'Microsoft.WindowsFeedbackHub', 'Microsoft.YourPhone',
  'MicrosoftCorporationII.QuickAssist', 'MicrosoftWindows.CrossDevice', 'MSTeams',
  'MicrosoftWindows.Client.WebExperience',
  # 2026-10-12: unused, and a Store app's icon cannot take the Letterpress tint.
  # Get Started lives in MicrosoftWindows.Client.CBS beside Windows Backup and Click to Do in
  # the CoreAI system package (switched off by policy: the unit windows-ai-off): both stay
  'Microsoft.WindowsAlarms', 'Microsoft.WindowsSoundRecorder', 'Microsoft.ZuneMusic', 'Microsoft.WindowsCamera',
  # MSI's bundle
  '9426MICRO-STARINTERNATION.MSICenter', '9426MICRO-STARINTERNATION.MSIGameBar'
)
# Win32 programs by their "Apps" name (winget uninstall --name, exact)
$Win32 = @(
  'Norton 360 for Gamers', 'AiPPT', 'Dropbox Redeem Launcher', 'Google Play Games', 'Google Chrome',
  'AIDA64 Extreme v8.35', 'CPUID CPU-Z MSI 2.20.2', 'LED Sync', 'MSI Center SDK', 'AMD Ryzen Master SDK',
  'Microsoft OneDrive', 'Microsoft .NET Core Runtime - 3.1.32 (x64)',
  # swapped out by the rulings of 2026-10-12: XSplit VCam (SplitmediaLabs, Hong Kong) for OBS's
  # virtual camera + obs-backgroundremoval, qBittorrent for Transmission, File Converter dropped;
  # GeForce NOW (the 3080 Ti plays locally), EVGA Precision X1 (a kernel driver at every boot),
  # Antec's iUnity (case-display.ps1 drives the case's panel instead), AutoHotkey (ARC Raiders'
  # anti-cheat counts a running AutoHotkey as a detection, and nothing here used it)
  'VCam', 'qBittorrent', 'File Converter', 'NVIDIA GeForce NOW*', 'EVGA Precision X1', '*iUnity*',
  'AutoHotkey*'
)
# a name may carry * and ? (-like): every installed program it matches is uninstalled
# What no uninstaller removes: services (stopped, deleted), kernel drivers (deleted; a loaded
# driver's file goes at the next restart), tasks, folders. A group waits while any service
# named in its Unless list still exists (an uninstaller that finishes at the next restart).
$Leftovers = @(
  @{ What     = "MSI Center's Mystic Light (its Store app is gone; its services stayed)"
    Services  = @('LightKeeperService', 'Mystic_Light_Service', 'MSI_Case_Service')
    # MICSYS MsIo64.sys: raw I/O-port and physical-memory access for any program, the kind of
    # driver attackers load; nothing needs it once MSI Center is gone
    Drivers   = @('MSIO')
    Tasks     = @('\MSI Task Host - LEDKeeper2_Host')
    Paths     = @('C:\Program Files (x86)\MSI', 'C:\Program Files\MSI', 'C:\ProgramData\MSI')
  },
  @{ What     = "EVGA Precision X1's kernel driver and folder (its uninstaller leaves them)"
    Drivers   = @('Driver|*\EVGA\Kernel\driver-x64.sys')   # the service is called just "Driver": removed only with EVGA's path
    Paths     = @('C:\Program Files (x86)\EVGA')
  },
  @{ What     = "Norton's remains, once its uninstaller has finished (after a restart)"
    Unless    = @('Norton*', 'nll*')
    Tasks     = @('\Norton\*')
    Paths     = @('C:\Program Files\Norton', 'C:\Program Files\Common Files\Norton', 'C:\ProgramData\Norton')
  }
)
# ---------------------------------------------------------------------------------------

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Log = Join-Path $Here 'debloat.log'
$script:Left = @()
function Say([string]$m) { $l = '{0:HH:mm:ss} {1}' -f (Get-Date), $m; Add-Content -Path $Log -Value $l -Encoding UTF8; Write-Output $l }
Say "== debloat on $env:COMPUTERNAME$(if ($DryRun) { ' (dry run)' })"

Say '-- apps (AppX): every user, and the image for new users'
foreach ($n in $Appx) {
  $inst = @(Get-AppxPackage -AllUsers -Name $n -ErrorAction SilentlyContinue)
  $prov = @(Get-AppxProvisionedPackage -Online | Where-Object DisplayName -EQ $n)
  if (-not $inst -and -not $prov) { continue }
  if ($DryRun) { Say "   would remove $n"; continue }
  foreach ($p in $prov) { try { Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null } catch { Say "[!] $n (image): $($_.Exception.Message)" } }
  foreach ($p in $inst) { try { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop } catch { Say "[!] $n : $($_.Exception.Message)" } }
  if (Get-AppxPackage -AllUsers -Name $n -ErrorAction SilentlyContinue) { $script:Left += $n; Say "[!] $n is still there" } else { Say "[ok] removed $n" }
}

Say '-- programs (Win32)'
$w = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
$keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
function Test-Installed([string]$name) { [bool](Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object DisplayName -EQ $name) }
function Find-Installed([string]$pattern) { @(Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $pattern } | ForEach-Object { $_.DisplayName } | Sort-Object -Unique) }
# a click-only uninstaller: its own command (the "Apps" entry's) on the signed-in user's
# desktop, through a one-off task with that user's interactive token
function Open-OnDesktop([string]$name) {
  $e = Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object DisplayName -EQ $name | Select-Object -First 1
  $user = (Get-CimInstance Win32_ComputerSystem).UserName
  if (-not $e.UninstallString -or -not $user) { return $false }
  if ($e.UninstallString -match '^\s*"([^"]+)"\s*(.*)$') { $exe = $matches[1]; $arg = $matches[2] } else { $exe, $arg = $e.UninstallString -split ' ', 2 }
  $act = if ($arg) { New-ScheduledTaskAction -Execute $exe -Argument $arg } else { New-ScheduledTaskAction -Execute $exe }
  $t = 'dram-uninstall-' + ($name -replace '[^A-Za-z0-9]', '')
  Register-ScheduledTask -TaskName $t -Action $act -Principal (New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest) -Force | Out-Null
  Start-ScheduledTask -TaskName $t
  return $true
}
# an NSIS uninstaller hands the job to a copy of itself in %TEMP% and returns at once, so winget
# can report success with the app still there (qBittorrent, 2026-10-12): run it in place, silent,
# for at most two minutes - one that still asks a question (EVGA's did, unseen, in session 0, and
# held the whole run) is stopped, with the copy winget left behind, and goes to the desktop instead
function Invoke-NsisInPlace([string]$name) {
  $e = Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object DisplayName -EQ $name | Select-Object -First 1
  if (-not $e.UninstallString) { return $false }
  $exe = if ($e.UninstallString -match '^\s*"([^"]+)"') { $matches[1] } else { ($e.UninstallString -split ' ')[0] }
  if (-not (Test-Path -LiteralPath $exe) -or -not ([Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($exe))).Contains('Nullsoft')) { return $false }
  $dir = Split-Path -Parent $exe
  Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(Un_A|Au_)\.exe$' -and $_.CommandLine -like "*$dir*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  $u = Start-Process -FilePath $exe -ArgumentList '/S', "_?=$dir" -PassThru -WindowStyle Hidden
  if (-not $u.WaitForExit(120000)) { $u | Stop-Process -Force -ErrorAction SilentlyContinue; return $false }
  Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue
  if ((Test-Path -LiteralPath $dir) -and -not (Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $dir -Recurse -Force }
  return -not (Test-Installed $name)
}
# what a click-only uninstaller left waiting, unseen, in session 0 (winget's attempt): matched by
# the app's own folder, or by the last word of its uninstall command (NVIDIA's "UninstallPackage <id>")
function Stop-HiddenUninstall([string]$name) {
  $e = Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object DisplayName -EQ $name | Select-Object -First 1
  if (-not $e.UninstallString) { return }
  if ($e.UninstallString -match '^\s*"([^"]+)"\s*(.*)$') { $exe = $matches[1]; $arg = $matches[2] } else { $exe, $arg = $e.UninstallString -split ' ', 2 }
  $tokens = @()
  $dir = Split-Path -Parent $exe
  if ($dir -and $dir -notlike "$env:windir*") { $tokens += $dir.TrimEnd('\') }
  if ($arg) { $last = (($arg.Trim() -split '\s+')[-1]).Trim('"'); if ($last.Length -ge 6) { $tokens += $last } }
  foreach ($pr in @(Get-CimInstance Win32_Process | Where-Object { $_.SessionId -eq 0 -and $_.CommandLine -and $_.ProcessId -ne $PID })) {
    foreach ($t in $tokens) { if ($pr.CommandLine -like "*$t*") { Stop-Process -Id $pr.ProcessId -Force -ErrorAction SilentlyContinue; break } }
  }
}
if (-not $DryRun) { Get-ScheduledTask -TaskName 'dram-uninstall-*' -ErrorAction SilentlyContinue | Where-Object State -NE 'Running' | Unregister-ScheduledTask -Confirm:$false }
foreach ($n in @($Win32 | ForEach-Object { Find-Installed $_ })) {
  if (-not (Test-Installed $n)) { continue }
  if ($DryRun) { Say "   would uninstall $n"; continue }
  # an uninstaller that waits for a click never ends over ssh: 5 minutes, then it goes to the desktop
  $p = Start-Process -FilePath $w -ArgumentList @('uninstall', '--name', "`"$n`"", '--exact', '--silent', '--force',
    '--accept-source-agreements', '--disable-interactivity') -PassThru -WindowStyle Hidden
  $timedOut = -not $p.WaitForExit(300000)
  if ($timedOut) { $p | Stop-Process -Force -ErrorAction SilentlyContinue }
  if ((Test-Installed $n) -and (Invoke-NsisInPlace $n)) { Say "[ok] uninstalled $n (its NSIS uninstaller, run in place)"; continue }
  if (Test-Installed $n) {
    Stop-HiddenUninstall $n
    if (Open-OnDesktop $n) { Say "[!] $n : its uninstaller wants clicks - opened on the desktop of $((Get-CimInstance Win32_ComputerSystem).UserName)" }
    else { Say "[!] $n : its uninstaller wants clicks (Settings > Apps; nobody is signed in to show it to)" }
  }
  if (Test-Installed $n) { $script:Left += $n; Say "[!] $n is still installed (exit $($p.ExitCode))" } else { Say "[ok] uninstalled $n" }
}

Say '-- leftovers no uninstaller removes'
Add-Type -Namespace Dram -Name Fs -MemberDefinition '[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] public static extern bool MoveFileEx(string from, string to, int flags);'
function Test-Service([string]$n) { & sc.exe query $n *> $null; $LASTEXITCODE -ne 1060 }
foreach ($g in $Leftovers) {
  if ($g.Unless -and (Get-Service -Name $g.Unless -ErrorAction SilentlyContinue)) { Say "   later: $($g.What) - its services are still there until a restart"; continue }
  $todo = @(@($g.Services) + @($g.Drivers | ForEach-Object { if ($_) { ($_ -split '\|')[0] } }) | Where-Object { $_ -and (Test-Service $_) } | ForEach-Object { "service $_" })
  foreach ($t in @($g.Tasks | Where-Object { $_ })) {
    $i = $t.LastIndexOf('\')
    $todo += @(Get-ScheduledTask -TaskPath $t.Substring(0, $i + 1) -TaskName $t.Substring($i + 1) -ErrorAction SilentlyContinue | ForEach-Object { "task $($_.TaskPath)$($_.TaskName)" })
  }
  $todo += @($g.Paths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | ForEach-Object { "folder $_" })
  if (-not $todo) { continue }
  Say "   $($g.What): $($todo -join '; ')"
  if ($DryRun) { continue }
  foreach ($n in @($g.Services | Where-Object { $_ -and (Test-Service $_) })) {
    Stop-Service -Name $n -Force -ErrorAction SilentlyContinue
    & sc.exe delete $n *> $null
    if ($LASTEXITCODE -eq 0) { Say "[ok] service $n deleted" } else { $script:Left += $n; Say "[!] service $n : sc delete exit $LASTEXITCODE" }
  }
  foreach ($spec in @($g.Drivers | Where-Object { $_ })) {
    $n, $want = $spec -split '\|', 2
    if (-not (Test-Service $n)) { continue }
    $file = ((Get-CimInstance Win32_SystemDriver -Filter "Name='$n'").PathName) -replace '^\\\?\?\\', ''
    if ($want -and $file -notlike $want) { Say "[!] driver $n is not the expected one ($file): left alone"; continue }
    & sc.exe stop $n *> $null
    & sc.exe delete $n *> $null
    if ($LASTEXITCODE -ne 0) { $script:Left += $n; Say "[!] driver $n : sc delete exit $LASTEXITCODE"; continue }
    if ($file -and (Test-Path -LiteralPath $file)) {
      Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
      if (Test-Path -LiteralPath $file) { [void][Dram.Fs]::MoveFileEx($file, $null, 4); Say "[ok] driver $n deleted; $file goes at the next restart (it is loaded)" }
      else { Say "[ok] driver $n and $file deleted" }
    } else { Say "[ok] driver $n deleted" }
  }
  foreach ($t in @($g.Tasks | Where-Object { $_ })) {
    $i = $t.LastIndexOf('\')
    Get-ScheduledTask -TaskPath $t.Substring(0, $i + 1) -TaskName $t.Substring($i + 1) -ErrorAction SilentlyContinue | ForEach-Object {
      Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -ErrorAction SilentlyContinue; Say "[ok] task $($_.TaskPath)$($_.TaskName) deleted" }
  }
  foreach ($p in @($g.Paths | Where-Object { $_ -and (Test-Path -LiteralPath $_) })) {
    Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith("$p\", [StringComparison]::OrdinalIgnoreCase) } | Stop-Process -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $p) { $script:Left += $p; Say "[!] $p : files in use; again after a restart" } else { Say "[ok] $p deleted" }
  }
}

Say '-- what brings bloat back'
if (-not $DryRun) {
  # Windows runs no executable a firmware table (WPBT) hands it: MSI's installer comes that way
  New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name DisableWpbtExecution -Value 1 -PropertyType DWord -Force | Out-Null
  # OneDrive's first-run installer for new accounts, Edge's start-at-sign-in
  foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run') {
    $props = (Get-ItemProperty $k -ErrorAction SilentlyContinue).PSObject.Properties | Where-Object { $_.Name -match '^(OneDriveSetup|OneDrive|MicrosoftEdgeAutoLaunch_)' }
    foreach ($pr in $props) { Remove-ItemProperty -Path $k -Name $pr.Name -ErrorAction SilentlyContinue; Say "[ok] start entry removed: $($pr.Name)" }
  }
  & reg.exe load 'HKU\DramDefault' 'C:\Users\Default\NTUSER.DAT' 2>$null | Out-Null
  & reg.exe delete 'HKU\DramDefault\Software\Microsoft\Windows\CurrentVersion\Run' /v OneDriveSetup /f 2>$null | Out-Null
  [gc]::Collect(); & reg.exe unload 'HKU\DramDefault' 2>$null | Out-Null
  Say '[ok] DisableWpbtExecution = 1; OneDrive kept off new accounts'
}
if ($script:Left) { Say "== done; still there: $($script:Left -join ', ')" } else { Say '== done: nothing on the list is left' }

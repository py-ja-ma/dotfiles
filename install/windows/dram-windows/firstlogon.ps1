# install/windows/dram-windows/firstlogon.ps1 - cabin's Windows 11 (docs/platforms/windows/README.md).
#
# Run once by autounattend.xml at the first sign-in (FirstLogonCommands), from
# C:\Windows\Setup\Scripts\dram-windows. Safe to run again by hand, as administrator:
#   powershell -ExecutionPolicy Bypass -File C:\Windows\Setup\Scripts\dram-windows\firstlogon.ps1
#
#   1. machine: Fast Startup and hibernation off, the hardware clock read as UTC (Arch keeps
#      it so), no automatic device encryption (BitLocker is turned on by hand), diagnostic
#      data at "required" only, no widgets board. The answer file set the first three
#      already; they are set again here and read back.
#   2. this user: no advertising ID, no tailored experiences, no web results or suggestions
#      in Start and Search, no silently installed "suggested" apps, file extensions shown.
#   3. apps through winget: Steam, Proton Pass. Without a network they are skipped; run the
#      script again later. The NVIDIA App is not in winget's catalogue (VM test, 2026-10-11):
#      Windows Update brings the driver; the App is a download from nvidia.com.
#   4. the account: automatic sign-in off; on the first run, the blank password the answer
#      file gave pj must be replaced at the next sign-in.
#
# Log: firstlogon.log beside this script. In the VM test (a file named vm-test beside it,
# put there by tests/windows-vm.sh) it also copies the log to the drive holding
# autounattend.xml and powers the VM off.

$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Log = Join-Path $Here 'firstlogon.log'
$VmTest = Test-Path (Join-Path $Here 'vm-test')
$FirstRun = -not (Test-Path (Join-Path $Here 'firstlogon.done'))
$script:Warnings = 0

function Say([string]$m) {
  $l = '{0:HH:mm:ss} {1}' -f (Get-Date), $m
  Add-Content -Path $Log -Value $l -Encoding UTF8
  Write-Host $l
}
function Step([string]$name, [scriptblock]$body) {
  try { & $body; Say "[ok] $name" }
  catch { $script:Warnings++; Say "[!] $name : $($_.Exception.Message)" }
}
function Set-Reg([string]$path, [string]$name, $value, [string]$type = 'DWord') {
  if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
  New-ItemProperty -Path $path -Name $name -Value $value -PropertyType $type -Force | Out-Null
}
function Get-Reg([string]$path, [string]$name) {
  try { (Get-ItemProperty -Path $path -Name $name -ErrorAction Stop).$name } catch { '<unset>' }
}

Say "== dram-windows first logon: $env:COMPUTERNAME, user $env:USERNAME, PowerShell $($PSVersionTable.PSVersion), first run: $FirstRun, VM test: $VmTest"
$os = Get-CimInstance Win32_OperatingSystem
Say "   $($os.Caption) $($os.Version) build $($os.BuildNumber)"

# --- 1. machine --------------------------------------------------------------------------
Step 'Fast Startup and hibernation off' {
  Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0
  powercfg.exe /hibernate off
  if ($LASTEXITCODE) { throw "powercfg exit $LASTEXITCODE" }
}
Step 'hardware clock read as UTC (RealTimeIsUniversal = 1)' {
  Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' 'RealTimeIsUniversal' 1
}
Step 'no automatic device encryption (PreventDeviceEncryption = 1)' {
  Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker' 'PreventDeviceEncryption' 1
}
Step 'diagnostic data: required only' {
  Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 1
}
Step 'no widgets board' {
  Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
}

# --- 2. this user ------------------------------------------------------------------------
Step 'no advertising ID, no tailored experiences' {
  Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
  Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
}
Step 'Start and Search: no web results, no suggestions, no suggested apps' {
  Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
  $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
  foreach ($n in 'SilentInstalledAppsEnabled', 'SystemPaneSuggestionsEnabled', 'SoftLandingEnabled',
    'SubscribedContent-310093Enabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled',
    'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled') { Set-Reg $cdm $n 0 }
  Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations' 0
}
Step 'Explorer shows file extensions' {
  Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt' 0
}

# --- 3. apps -----------------------------------------------------------------------------
function Get-Winget {
  $p = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
  # a new account's App Installer can take a while to register (first sign-in)
  for ($i = 0; $i -lt 60; $i++) {
    if (Test-Path $p) { return $p }
    if ($i -eq 0) {
      try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe } catch { }
    }
    Start-Sleep -Seconds 5
  }
  return $null
}
function Test-Online {
  for ($i = 0; $i -lt 24; $i++) {
    try {
      $r = Invoke-WebRequest -Uri 'https://cdn.winget.microsoft.com/cache/source.msix' -Method Head -UseBasicParsing -TimeoutSec 10
      if ($r.StatusCode -eq 200) { return $true }
    } catch { }
    Start-Sleep -Seconds 5
  }
  return $false
}
$winget = Get-Winget
if (-not $winget) {
  $script:Warnings++; Say '[!] winget did not appear (App Installer): apps skipped; run this script again later'
} elseif (-not (Test-Online)) {
  $script:Warnings++; Say '[!] no internet after 2 minutes: apps skipped; run this script again once online'
} else {
  # native commands with 2>&1 under 'Stop' throw on the first stderr line in PowerShell 5.1
  $ErrorActionPreference = 'Continue'
  Say "   winget $(& $winget --version)"
  $apps = @(
    @{ Name = 'Steam'; Args = @('--id', 'Valve.Steam') },
    @{ Name = 'Proton Pass'; Args = @('--id', 'Proton.ProtonPass') }
  )
  foreach ($a in $apps) {
    $out = & $winget install @($a.Args) --exact --source winget --silent --accept-package-agreements `
      --accept-source-agreements --disable-interactivity 2>&1 | Out-String
    $rc = $LASTEXITCODE
    Add-Content -Path $Log -Value ($out.Trim() -split "`r?`n" | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*[-\\|/]\s*$' -and $_ -notmatch '[\u2580-\u259F]' }) -Encoding UTF8
    # 0 installed; -1978335189 (0x8A15002B) already there, no newer version
    if ($rc -eq 0 -or $rc -eq -1978335189) { Say "[ok] $($a.Name) installed" }
    else { $script:Warnings++; Say "[!] $($a.Name): winget exit $rc (run this script again later)" }
  }
  $ErrorActionPreference = 'Stop'
}

# --- 4. the account ----------------------------------------------------------------------
Step 'automatic sign-in off' {
  $wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
  Set-ItemProperty -Path $wl -Name 'AutoAdminLogon' -Value '0'
  foreach ($n in 'DefaultPassword', 'AutoLogonCount') { Remove-ItemProperty -Path $wl -Name $n -ErrorAction SilentlyContinue }
}
if ($FirstRun) {
  Step "$env:USERNAME sets a password at the next sign-in" {
    net.exe user $env:USERNAME /logonpasswordchg:yes | Out-Null
    if ($LASTEXITCODE) { throw "net user exit $LASTEXITCODE" }
  }
}

# --- read back ---------------------------------------------------------------------------
Say '== read back'
Say ("   HiberbootEnabled={0} RealTimeIsUniversal={1} PreventDeviceEncryption={2} AllowTelemetry={3}" -f
  (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled'),
  (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' 'RealTimeIsUniversal'),
  (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker' 'PreventDeviceEncryption'),
  (Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry'))
Say ("   hibernation file: {0}; time zone: {1}" -f (Test-Path 'C:\hiberfil.sys'), (Get-TimeZone).Id)
try {
  $bl = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction Stop
  Say "   BitLocker on C: $($bl.VolumeStatus), protection $($bl.ProtectionStatus)"
} catch { Say '   BitLocker: no status (Home has no BitLocker)' }
try {
  $tpm = Get-Tpm
  Say "   TPM present $($tpm.TpmPresent), ready $($tpm.TpmReady); Secure Boot $(try { Confirm-SecureBootUEFI } catch { 'unknown' })"
} catch { Say '   TPM: no status' }

New-Item -Path (Join-Path $Here 'firstlogon.done') -ItemType File -Force | Out-Null
Say "== done: $script:Warnings warning(s)"

if ($VmTest) {
  # the test reads the log from the answer-file drive after the VM powers off
  $d = Get-PSDrive -PSProvider FileSystem | Where-Object { Test-Path (Join-Path $_.Root 'autounattend.xml') } | Select-Object -First 1
  if ($d) { Copy-Item -Path $Log -Destination (Join-Path $d.Root 'dram-windows\firstlogon.log') -Force }
  Stop-Computer -Force
} else {
  Write-Host ''
  Write-Host 'Next (docs/platforms/windows/README.md): sign out and in again to set your password; BitLocker by hand'
  Write-Host '(Pro), the recovery key into Proton Pass; the NVIDIA driver from Windows Update (or the'
  Write-Host 'NVIDIA App from nvidia.com); then back to Arch.'
  Read-Host 'Press Enter to close'
}

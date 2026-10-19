# install/windows/dram-windows/autostart.ps1 - what may start by itself on cabin's Windows.
#
# Most apps do not start by themselves (2026-10-12). Default off: every entry in
# the Run keys and the Startup folders, every packaged app's startup task and every
# third-party task started by sign-in, boot, unlock or connect is switched off unless
# declared below. Run keys and Startup folders use the switch Task Manager's Startup tab
# uses (StartupApproved): nothing is deleted, and an app that writes its entry back stays
# off (until it flips the switch itself: PowerToys and Proton Mail Bridge do, so they are
# set in their own settings; each run puts the rest back). Third-party services that start
# automatically and are not declared go to Manual; one without a readable signature is
# reported, not changed. Edge's preload and background mode are the base role's policies
# (edge-policies). RunOnce entries (installers finishing a job) are left alone. Safe to run
# again: prints what it found and what it changed, and writes autostart-report.csv
# (everything that can start by itself, and its state). Run as administrator, as the user
# whose sign-in it governs (apply-windows.sh logs in as pj):
#   powershell -ExecutionPolicy Bypass -File autostart.ps1 [-DryRun]
# Log: autostart.log beside this script.

param([switch]$DryRun)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- the declared state: only these start by themselves ----------------------------------
# entry names in the Run keys and Startup folders, startup-task ids, logon-task names (regex,
# matched whole)
$AllowStart = @(
  'SecurityHealth',   # Windows Security's tray icon
  'RtkAudUService',   # Realtek audio: jack detection and its console
  'Autorun for .*',   # PowerToys (its logon task): its shortcuts and FancyZones need it running
  'Zebar'             # the masthead across the top of each monitor (the desktop role's zebar-autostart)
)
# not Steam: switched off in Task Manager on 2026-10-12 (on Arch it starts silently for
# shader pre-caching; on Windows it starts when a game does).
# services other than Microsoft's that stay on Automatic (names, regex)
$AllowServices = @(
  'NVDisplay\.ContainerLocalSystem', 'NvContainerLocalSystem',   # the NVIDIA driver and its app
  'RtkAudioUniversalService',                                     # Realtek audio
  'AMD.*', 'amd.*',                                               # chipset drivers
  'sshd'                                                          # how the Mac converges this machine
)
# third-party tasks that keep their triggers: updaters, not apps
$AllowTasks = @('MicrosoftEdgeUpdateTask.*', 'NVIDIA App SelfUpdate.*', 'dram-.*')   # dram-*: this repo's own jobs (dram-case-display: the case's panel, resident)
# -------------------------------------------------------------------------------------------

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Log = Join-Path $Here 'autostart.log'
function Say([string]$m) { $l = '{0:HH:mm:ss} {1}' -f (Get-Date), $m; Add-Content -Path $Log -Value $l -Encoding UTF8; Write-Output $l }
function Allowed([string]$name, [string[]]$list) { foreach ($a in $list) { if ($name -match "^(?:$a)$") { return $true } }; return $false }
$Changed = 0
$Rows = New-Object System.Collections.ArrayList   # autostart-report.csv: what can start by itself, and its state
function Row([string]$kind, [string]$where, [string]$name, [string]$state) { [void]$Rows.Add([pscustomobject]@{ Kind = $kind; Where = $where; Name = $name; State = $state }) }
Say "== autostart on $env:COMPUTERNAME for $env:USERNAME$(if ($DryRun) { ' (dry run)' })"

# StartupApproved: 12 bytes, the first even = on (02 + zeros), odd = off (03 + the FILETIME it was turned off)
$On = [byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
function Off { [byte[]](@(3, 0, 0, 0) + [BitConverter]::GetBytes((Get-Date).ToFileTimeUtc())) }
function Set-Approved([string]$hive, [string]$sub, [string]$name, [bool]$want, [string]$where) {
  $k = "${hive}:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\$sub"
  $cur = $null
  try { $cur = (Get-ItemProperty -Path $k -Name $name -ErrorAction Stop).$name } catch { }
  $isOn = (-not $cur) -or ($cur[0] % 2 -eq 0)
  Row 'entry' $where $name $(if ($want) { 'on' } else { 'off' })
  if ($isOn -eq $want) { Say ("   [{0}] {1}: {2}" -f $(if ($want) { 'on' } else { 'off' }), $where, $name); return }
  if ($DryRun) { Say ("   would turn {0}: {1}: {2}" -f $(if ($want) { 'on' } else { 'off' }), $where, $name); return }
  if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
  $v = if ($want) { $On } else { Off }
  New-ItemProperty -Path $k -Name $name -PropertyType Binary -Value $v -Force | Out-Null
  $script:Changed++
  Say ("[ok] turned {0}: {1}: {2}" -f $(if ($want) { 'on' } else { 'off' }), $where, $name)
}

Say '-- Run keys'
foreach ($r in @(@('HKCU', 'Run', 'Run'), @('HKLM', 'Run', 'Run'), @('HKLM', 'WOW6432Node-Run', 'Run32'))) {
  $path = if ($r[1] -eq 'Run') { "$($r[0]):\Software\Microsoft\Windows\CurrentVersion\Run" } else { 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' }
  $item = Get-Item $path -ErrorAction SilentlyContinue
  if (-not $item) { continue }
  foreach ($n in $item.GetValueNames()) { if ($n) { Set-Approved $r[0] $r[2] $n (Allowed $n $AllowStart) "$($r[0]) $($r[2])" } }
}

Say '-- Startup folders'
foreach ($f in @(@('HKCU', [Environment]::GetFolderPath('Startup')), @('HKLM', [Environment]::GetFolderPath('CommonStartup')))) {
  Get-ChildItem $f[1] -Force -ErrorAction SilentlyContinue | Where-Object Name -NE 'desktop.ini' | ForEach-Object {
    Set-Approved $f[0] 'StartupFolder' $_.Name (Allowed ($_.BaseName) $AllowStart) "$($f[0]) Startup folder"
  }
}

Say '-- packaged apps (startup tasks)'
# State under the user's SystemAppData: 0 never on, 1 off by the user (the app cannot turn it back on), 2 on
$base = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData'
foreach ($p in Get-AppxPackage) {
  $m = Join-Path $p.InstallLocation 'AppxManifest.xml'
  if (-not (Test-Path $m) -or -not (Select-String -Path $m -Pattern 'windows.startupTask' -Quiet)) { continue }
  foreach ($t in ([xml](Get-Content $m -Raw)).GetElementsByTagName('*') | Where-Object { $_.LocalName -eq 'StartupTask' }) {
    $k = "$base\$($p.PackageFamilyName)\$($t.TaskId)"
    $st = (Get-ItemProperty $k -Name State -ErrorAction SilentlyContinue).State
    $want = Allowed $t.TaskId $AllowStart
    $isOn = ($st -eq 2 -or $st -eq 4)
    $label = "$($p.Name)/$($t.TaskId)"
    Row 'startup task' 'packaged app' $label $(if ($want) { 'on' } else { 'off' })
    if ($isOn -eq $want -and ($want -or $st -ne $null)) { Say ("   [{0}] {1}" -f $(if ($want) { 'on' } else { 'off' }), $label); continue }
    if ($DryRun) { Say "   would set $label to $(if ($want) { 'on' } else { 'off' })"; continue }
    if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
    New-ItemProperty -Path $k -Name State -PropertyType DWord -Value $(if ($want) { 2 } else { 1 }) -Force | Out-Null
    $script:Changed++
    Say "[ok] $label $(if ($want) { 'on' } else { 'off' })"
  }
}

Say '-- scheduled tasks (outside \Microsoft\, with a logon, boot, unlock or connect trigger)'
foreach ($t in Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and $_.State -ne 'Disabled' }) {
  $kinds = @($t.Triggers | ForEach-Object { $_.CimClass.CimClassName })
  if (-not ($kinds -match 'Logon|Boot|SessionStateChange')) { continue }
  $keep = (Allowed $t.TaskName $AllowStart) -or (Allowed $t.TaskName $AllowTasks) -or ($t.TaskPath -like '\dram\*')   # \dram\: this repo's own tasks (boot-guard)
  Row 'task' $t.TaskPath $t.TaskName $(if ($keep) { 'on' } else { 'off' })
  if ($keep) { Say "   [on] task $($t.TaskPath)$($t.TaskName)"; continue }
  if ($DryRun) { Say "   would disable task $($t.TaskPath)$($t.TaskName)"; continue }
  try { Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Stop | Out-Null; $script:Changed++; Say "[ok] disabled task $($t.TaskPath)$($t.TaskName)" }
  catch { Say "[!] task $($t.TaskPath)$($t.TaskName): $($_.Exception.Message)" }
}

Say '-- services on Automatic that are not Microsoft''s'
function ExePath([string]$cmd) { if ($cmd -match '^\s*"([^"]+)"') { $matches[1] } elseif ($cmd -match '^\s*(.+?\.exe)\b') { $matches[1] } else { $cmd } }
foreach ($s in Get-CimInstance Win32_Service | Where-Object { $_.StartMode -eq 'Auto' }) {
  $exe = ExePath $s.PathName
  $sig = Get-AuthenticodeSignature -LiteralPath $exe -ErrorAction SilentlyContinue
  if ($sig -and $sig.SignerCertificate -and $sig.SignerCertificate.Subject -match 'O=Microsoft Corporation') { continue }
  if (-not $sig -or -not $sig.SignerCertificate) { Row 'service' 'unsigned or unreadable' $s.Name 'auto (left alone)'; Say "   [?] $($s.Name): no readable signature ($exe) - left alone, check it"; continue }
  if (Allowed $s.Name $AllowServices) { Row 'service' $sig.SignerCertificate.Subject $s.Name 'auto'; Say "   [auto] $($s.Name)"; continue }
  Row 'service' $sig.SignerCertificate.Subject $s.Name 'manual'
  if ($DryRun) { Say "   would set $($s.Name) to Manual ($exe)"; continue }
  try { Set-Service -Name $s.Name -StartupType Manual -ErrorAction Stop; $script:Changed++; Say "[ok] $($s.Name) -> Manual ($exe)" }
  catch { Say "[!] $($s.Name): $($_.Exception.Message)" }
}

$Rows | Export-Csv -Path (Join-Path $Here 'autostart-report.csv') -NoTypeInformation -Encoding UTF8
Say "== done: $Changed change(s); report: autostart-report.csv"

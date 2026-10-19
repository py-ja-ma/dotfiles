# defender-hardening (windows/roles/base.nix): Defender's free protections beyond the shipped
# defaults (decisions/log.md#d152). Cloud protection at the High block level with the longer
# cloud check, Network Protection, no exclusions, scans that stay out of a game's way, and the
# attack surface reduction rules: twelve that a desktop never trips in Block, four heuristics in
# Warn until a month of their events stays clean, and the prevalence rule in Audit (it would stop
# fresh, rare binaries, such as this repo's own builds). Controlled Folder Access stays off:
# games save under Documents. Tamper Protection is on and is left to Windows Security (it has no
# switch here); the cloud and sample settings it guards are tested, not set.
# The Script unit runs this text as its script block, with -Mode Get, Test (exactly one bool)
# or Set. Windows PowerShell 5.1 and 7.
param([Parameter(Mandatory = $true)][ValidateSet('Get', 'Test', 'Set')][string]$Mode)

# rule guid -> action (1 Block, 2 Audit, 6 Warn)
$rules = [ordered]@{
  '56a863a9-875e-4185-98a7-b882c64b5ce5' = 1   # abuse of exploited vulnerable signed drivers
  'e6db77e5-3df2-4cf1-b95a-636979351e5b' = 1   # persistence through WMI event subscription
  'be9ba2d9-53ea-4cdc-84e5-9b1eeee46550' = 1   # executable content from email and webmail
  'd4f940ab-401b-4efc-aadc-ad5f3c50688a' = 1   # Office apps creating child processes
  '3b576869-a4ec-4529-8536-b80a7769e899' = 1   # Office apps creating executable content
  '75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84' = 1   # Office apps injecting code into other processes
  '92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b' = 1   # Win32 API calls from Office macros
  '26190899-1602-49e8-8b27-eb1d0a1ce869' = 1   # Outlook creating child processes
  '7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c' = 1   # Adobe Reader creating child processes
  'd3e037e1-3eb8-44c8-a917-57927947596d' = 1   # JavaScript and VBScript launching downloaded executables
  'b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4' = 1   # untrusted and unsigned processes from USB
  '33ddedf1-c6e0-47cb-833e-de6133960387' = 1   # rebooting into Safe Mode
  '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2' = 1   # credential stealing from LSASS (RunAsPPL covers it too)
  '5beb7efe-fd9a-4556-801d-275e5ffc04cc' = 6   # potentially obfuscated scripts
  'c1db55ab-c21a-4637-bb3f-a12568109d35' = 6   # advanced protection against ransomware
  'd1e49aac-8f56-4280-b9ba-993a6d77406c' = 6   # process creations from PsExec and WMI
  'c0033c00-d16d-4114-a5a0-dc9b3a7d2ceb' = 6   # copied or impersonated system tools
  '01443614-cd74-433a-b99e-2ecdc07bfc25' = 2   # executables that fail prevalence, age or trusted-list criteria
}

# an empty list comes back as one null element in Windows PowerShell 5.1
function Items($x) { @($x | Where-Object { $_ }) }
function Exclusions($p) { @((Items $p.ExclusionPath) + (Items $p.ExclusionProcess) + (Items $p.ExclusionExtension)) }

function Get-DramUnit {
  $p = Get-MpPreference
  @{ Result = ('cloud {0}/{1}s, network protection {2}, exclusions {3}, asr rules {4}' -f $p.CloudBlockLevel, $p.CloudExtendedTimeout, $p.EnableNetworkProtection, (Exclusions $p).Count, (Items $p.AttackSurfaceReductionRules_Ids).Count) }
}

function Test-DramUnit {
  $ErrorActionPreference = 'Continue'
  $p = Get-MpPreference
  if ($p.MAPSReporting -ne 2 -or $p.SubmitSamplesConsent -ne 1) { return $false }   # Advanced, SendSafeSamples
  if ($p.CloudBlockLevel -ne 2 -or $p.CloudExtendedTimeout -ne 50) { return $false }   # 2 = High
  if ($p.EnableNetworkProtection -ne 1) { return $false }
  if ((Exclusions $p).Count -gt 0) { return $false }
  if ($p.ScanAvgCPULoadFactor -ne 20 -or -not $p.ScanOnlyIfIdleEnabled) { return $false }
  if ($p.EnableControlledFolderAccess -ne 0) { return $false }
  $ids = Items $p.AttackSurfaceReductionRules_Ids; $acts = @($p.AttackSurfaceReductionRules_Actions)
  foreach ($g in $rules.Keys) {
    $i = [array]::IndexOf(($ids | ForEach-Object { $_.ToLower() }), $g)
    if ($i -lt 0 -or [int]$acts[$i] -ne $rules[$g]) { return $false }
  }
  return $true
}

function Set-DramUnit {
  $ErrorActionPreference = 'Continue'
  $p = Get-MpPreference
  Set-MpPreference -CloudBlockLevel High -CloudExtendedTimeout 50 -EnableNetworkProtection Enabled -ScanAvgCPULoadFactor 20 -ScanOnlyIfIdleEnabled $true -EnableControlledFolderAccess Disabled
  foreach ($x in Items $p.ExclusionPath) { Remove-MpPreference -ExclusionPath $x }
  foreach ($x in Items $p.ExclusionProcess) { Remove-MpPreference -ExclusionProcess $x }
  foreach ($x in Items $p.ExclusionExtension) { Remove-MpPreference -ExclusionExtension $x }
  foreach ($g in $rules.Keys) { Add-MpPreference -AttackSurfaceReductionRules_Ids $g -AttackSurfaceReductionRules_Actions $rules[$g] }
  # the two settings Tamper Protection guards: set only when they are not already there
  if ($p.MAPSReporting -ne 2) { Set-MpPreference -MAPSReporting Advanced }
  if ($p.SubmitSamplesConsent -ne 1) { Set-MpPreference -SubmitSamplesConsent SendSafeSamples }
}

switch ($Mode) {
  'Get' { Get-DramUnit }
  'Test' { Test-DramUnit }
  'Set' { Set-DramUnit }
}

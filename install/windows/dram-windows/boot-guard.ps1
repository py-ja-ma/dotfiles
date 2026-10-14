# install/windows/dram-windows/boot-guard.ps1 - rEFInd first, Windows Boot Manager last.
#
# The Windows twin of Arch's /usr/local/lib/dram/refind-first (system/apply-refind.sh): Windows'
# servicing (bcdboot during upgrades) moves "Windows Boot Manager" to the front of the
# firmware's boot order, and then Arch never boots to put rEFInd back (Arch owns the boot
# order: docs/platforms/windows/boot-guard.md). Run by a SYSTEM task at every Windows start (the unit
# boot-guard-task, windows/hosts/cabin-win.nix), and safe to run by hand. Changes the order
# only when it is wrong; logs before and after. Windows is still reachable: rEFInd's Windows
# tile and `dram boot-to windows` set BootNext to its entry.
#   powershell -ExecutionPolicy Bypass -File boot-guard.ps1 [-DryRun]
# Log: C:\ProgramData\dram\boot-guard.log

param([switch]$DryRun)
$ErrorActionPreference = 'Continue'
$log = 'C:\ProgramData\dram\boot-guard.log'
function Log([string]$m) { $l = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $m; Add-Content -Path $log -Value $l -Encoding Ascii; Write-Output $l }
function Order { ((bcdedit /enum '{fwbootmgr}' /v) -join "`n") -replace '(?s)^.*?displayorder\s+', '' -replace '(?s)\n\S.*$', '' -split '\s+' | Where-Object { $_ -match '^\{' } }

$blocks = ((bcdedit /enum firmware /v) -join "`n") -split "`n\s*`n"
$refind = $blocks | Where-Object { $_ -match '(?mi)^path\s+\\EFI\\refind\\refind_x64\.efi\s*$' } | Select-Object -First 1
$rid = if ($refind -match '(?m)^identifier\s+(\{[0-9a-fA-F-]+\})') { $Matches[1] } else { $null }
$wid = if ((((bcdedit /enum '{bootmgr}' /v) -join "`n") -match '(?m)^identifier\s+(\{[0-9a-fA-F-]+\})')) { $Matches[1] } else { $null }
if (-not $rid) { Log '[!] no firmware entry for \EFI\refind\refind_x64.efi: nothing to put first (Arch: system/apply-refind.sh)'; exit 1 }

$before = @(Order)
$ok = ($before.Count -gt 0) -and ($before[0] -eq $rid) -and (-not $wid -or $before[-1] -eq $wid)
if ($ok) { exit 0 }
Log ("order was: " + ($before -join ' '))
if ($DryRun) { Log "   would put $rid (rEFInd) first and $wid (Windows Boot Manager) last"; exit 0 }
bcdedit /set '{fwbootmgr}' displayorder $rid /addfirst | Out-Null
if ($wid) { bcdedit /set '{fwbootmgr}' displayorder $wid /addlast | Out-Null }
Log ("order now: " + (@(Order) -join ' '))

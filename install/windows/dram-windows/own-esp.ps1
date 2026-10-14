# install/windows/dram-windows/own-esp.ps1 - give Windows its own ESP on its own disk, in place.
#
# Windows Setup put its boot files on Arch's ESP (the 990 PRO), so Windows servicing writes into
# Arch's boot partition (decisions/log.md#d65; docs/platforms/windows/boot-guard.md). This
# makes the ESP Windows boots from live on Windows' disk, without a reinstall: WinRE off; its
# partition removed; C: shrunk by 1 GB; WinRE rebuilt right after C: (so it can still grow by
# shrinking C:, as Microsoft's layout expects); a FAT32 ESP after it, last on the disk;
# `bcdboot C:\Windows /s <ESP> /f UEFI`, then `bcdedit /set {bootmgr} device` to the new ESP
# (bcdboot with /s leaves the firmware entry alone and ignores /addlast; boot-guard.ps1 keeps it
# last); WinRE back on, registered in the new ESP's BCD. Nothing on Arch's ESP is touched: its
# old \EFI\Microsoft stays as the rollback until Windows has booted from its own ESP, then Arch
# removes it (system/windows-esp-retire.sh). Refuses unless Windows' disk has no ESP of its own and C: is on it.
# Run as administrator, once, in a window with no game running; then reboot into Windows with
# `bcdedit /set {fwbootmgr} bootsequence {bootmgr}` and check `bcdedit /enum {bootmgr}`.
#   powershell -ExecutionPolicy Bypass -File own-esp.ps1 [-DryRun]

param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
$EspGpt = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
$ReGpt = '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}'
function Say([string]$m) { Write-Output ('{0:HH:mm:ss} {1}' -f (Get-Date), $m) }
function Diskpart([string[]]$lines) {
  $f = Join-Path $env:TEMP 'dram-own-esp.txt'
  Set-Content -Path $f -Value $lines -Encoding Ascii
  $out = & diskpart.exe /s $f 2>&1
  $rc = $LASTEXITCODE
  Remove-Item $f -Force
  if ($rc -ne 0) { throw "diskpart failed ($rc): $($out -join ' | ')" }
}

$c = Get-Partition -DriveLetter C
$disk = Get-Disk -Number $c.DiskNumber
$parts = @(Get-Partition -DiskNumber $disk.Number)
Say "Windows' disk: $($disk.Number) $($disk.FriendlyName) ($([math]::Round($disk.Size / 1GB)) GB)"
$parts | ForEach-Object { Say ('   #{0} {1,-40} {2,8:N2} GB {3}' -f $_.PartitionNumber, $_.GptType, ($_.Size / 1GB), $_.DriveLetter) }
if ($parts | Where-Object GptType -EQ $EspGpt) { Say '[ok] this disk already has its own ESP: nothing to do'; exit 0 }
$re = @($parts | Where-Object GptType -EQ $ReGpt)
if ($re.Count -gt 1) { throw 'more than one recovery partition: do this by hand' }
if ($re -and $re[0].PartitionNumber -le $c.PartitionNumber) { throw 'the recovery partition is not after C:: do this by hand' }
function BootDevice { (bcdedit /enum '{bootmgr}' | Select-String '^device' | Select-Object -First 1).Line }
Say "boot manager today: $(BootDevice)"
$sz = Get-PartitionSupportedSize -DriveLetter C
$new = [long]$c.Size - 1GB
if ($new -lt $sz.SizeMin) { throw ("C: cannot shrink by 1 GB (its minimum is {0:N1} GB): stopping before any change" -f ($sz.SizeMin / 1GB)) }

if ($DryRun) {
  Say '   would: reagentc /disable; remove the recovery partition; shrink C: by 1 GB; recreate WinRE (1.2 GB) after C:;'
  Say '          create a FAT32 ESP after it (the rest, ~0.5 GB); bcdboot C:\Windows /s <ESP> /f UEFI /addlast; reagentc /enable'
  exit 0
}

Say 'WinRE off (winre.wim goes back to C:\Windows\System32\Recovery)'
& reagentc.exe /disable | Out-Null
if (-not (Test-Path 'C:\Windows\System32\Recovery\Winre.wim')) { throw 'Winre.wim is not in C:\Windows\System32\Recovery after reagentc /disable: stopping' }
if ($re) {
  Say "removing the old recovery partition #$($re[0].PartitionNumber)"
  Diskpart @("select disk $($disk.Number)", "select partition $($re[0].PartitionNumber)", 'delete partition override')
}
Say ("shrinking C: to {0:N2} GB" -f ($new / 1GB))
Resize-Partition -DriveLetter C -Size $new
Say 'creating WinRE (1.2 GB) after C: and the ESP after it'
Diskpart @(
  "select disk $($disk.Number)",
  'create partition primary size=1229', 'format quick fs=ntfs label="Recovery"', 'assign letter=R',
  'set id=de94bba4-06d1-4d40-a16a-bfd50179d6ac', 'gpt attributes=0x8000000000000001',
  'create partition efi', 'format quick fs=fat32 label="WIN-ESP"', 'assign letter=S')
New-Item -ItemType Directory -Path 'R:\Recovery\WindowsRE' -Force | Out-Null
Copy-Item 'C:\Windows\System32\Recovery\Winre.wim' 'R:\Recovery\WindowsRE\Winre.wim' -Force
& reagentc.exe /setreimage /path 'R:\Recovery\WindowsRE' /target 'C:\Windows' | Out-Null
Say 'boot files and their BCD to the new ESP'
# with /s, bcdboot ignores /addlast and leaves the firmware entry alone (cabin, 2026-10-12): the
# entry is re-pointed below, and boot-guard.ps1 keeps it last at every start
& bcdboot.exe 'C:\Windows' /s 'S:' /f UEFI
if ($LASTEXITCODE -ne 0) { throw "bcdboot failed ($LASTEXITCODE)" }
Say "the firmware's Windows Boot Manager entry to the new ESP"
& bcdedit.exe /set '{bootmgr}' device partition=S:
if ($LASTEXITCODE -ne 0) { throw "bcdedit could not re-point {bootmgr} ($LASTEXITCODE)" }
& reagentc.exe /disable | Out-Null   # WinRE re-registered in the new ESP's BCD, now the system store
& reagentc.exe /enable | Out-Null
& mountvol.exe 'R:' /D; & mountvol.exe 'S:' /D
Say "boot manager now: $(BootDevice)"
& reagentc.exe /info | Select-String 'Windows RE status|Windows RE location' | ForEach-Object { Say ('   ' + $_.ToString().Trim()) }
Say '[ok] done: reboot into Windows by BootNext to test (bcdedit /set {fwbootmgr} bootsequence {bootmgr}); Arch then retires /efi/EFI/Microsoft'

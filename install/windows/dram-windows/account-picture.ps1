# install/windows/dram-windows/account-picture.ps1 - the "pj" seal as the account picture.
#
# The account picture: a Letterpress seal reading "pj", distinct from the wallpaper
# (decisions/log.md#d91). bin/gen-avatar.sh renders it at every size Windows keeps
# (dotfiles/.local/share/dram/avatar/pj-<size>.png); apply-windows.sh copies them to
# C:\ProgramData\dram\avatar\. This puts them where Windows keeps an account's picture
# (C:\Users\Public\AccountPictures\<SID>\, one value per size under
# HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AccountPicture\Users\<SID>) for -User; the
# sign-in screen shows it from the next lock or sign-in. Safe to run again. Run as
# administrator:
#   powershell -ExecutionPolicy Bypass -File account-picture.ps1 [-User pj] [-DryRun]

param([string]$User = 'pj', [switch]$DryRun)
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Sizes = 32, 40, 48, 64, 96, 192, 208, 240, 424, 448, 1080
$sid = (New-Object System.Security.Principal.NTAccount("$env:COMPUTERNAME\$User")).Translate([System.Security.Principal.SecurityIdentifier]).Value
$dir = "C:\Users\Public\AccountPictures\$sid"
$key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AccountPicture\Users\$sid"
$changed = 0
foreach ($s in $Sizes) {
  $src = Join-Path $Here "avatar\pj-$s.png"
  if (-not (Test-Path $src)) { Write-Output "[x] $src missing (apply-windows.sh copies dotfiles/.local/share/dram/avatar)"; exit 1 }
  $dst = Join-Path $dir "pj-$s.png"
  $same = (Test-Path $dst) -and ((Get-FileHash $src).Hash -eq (Get-FileHash $dst).Hash)
  $cur = $null
  try { $cur = Get-ItemPropertyValue -Path $key -Name "Image$s" -ErrorAction Stop } catch { }
  if ($same -and $cur -eq $dst) { continue }
  if ($DryRun) { Write-Output "   would set Image$s -> $dst"; continue }
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  Copy-Item -LiteralPath $src -Destination $dst -Force
  if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
  New-ItemProperty -Path $key -Name "Image$s" -PropertyType String -Value $dst -Force | Out-Null
  $changed++
}
Write-Output "[ok] account picture for $User ($sid): $changed of $($Sizes.Count) sizes changed$(if ($DryRun) { ' (dry run)' })"

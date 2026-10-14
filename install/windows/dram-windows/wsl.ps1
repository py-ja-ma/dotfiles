# install/windows/dram-windows/wsl.ps1 - the WSL Arch clone on this PC (decisions/0021,
# docs/platforms/wsl/README.md). Run by hand, once per clone; running it again changes only
# what differs.
#
# From C:\ProgramData\dram, where bin/push-host.sh --wsl staged it with wslconfig, wsl.conf
# (the repo's system/wsl/wsl.conf) and dotfiles.bundle (the repo as a git bundle), in an
# elevated Windows PowerShell at the PC (Terminal (Admin)), signed in as the clone's user:
#   1) %UserProfile%\.wslconfig from wslconfig, filled from this PC's row (-Machine). It
#      caps the disk of a distro created AFTER it (defaultVhdSize), so it comes first;
#      when it changes, WSL is shut down so it is read again
#   2) WSL itself: `wsl --install --no-distribution` when it is missing (then restart
#      Windows and run this again: exit 3), else `wsl --update`; the OpenSSH Authentication
#      Agent service Automatic and running (the clone's ssh and git signing reach it)
#   3) the distro: `wsl --install archlinux --name <Machine>-wsl --location
#      C:\WSL\<Machine>-wsl --no-launch`, the official, signed Arch image, unless registered
#   4) the first root pass inside it: the pacman keyring the image leaves empty, a full
#      upgrade with git and sudo, the user (-User, in wheel; its password is typed here),
#      wheel in sudoers, linger, /etc/wsl.conf from wsl.conf (hostname <Machine>-wsl,
#      systemd, the default user, appendWindowsPath=false) and /etc/hostname; then
#      `wsl --terminate` so the distro starts again under its own name
#   5) as the user: ~/git/dotfiles cloned from dotfiles.bundle and checked out at the newest
#      release that knows this host (else master, channel main), then
#      install/bootstrap.sh --yes (in WSL its phases 1 and 3: dram apply, Nix, Home
#      Manager); sudo asks for the password typed in step 4
#   powershell -ExecutionPolicy Bypass -File C:\ProgramData\dram\wsl.ps1 [-Machine cabin] [-User pj] [-DryRun] [-NoBootstrap]
# -DryRun prints what would change and changes nothing; -NoBootstrap stops after step 4.
# Exit: 0 done; 3 restart Windows, then run it again; 1 a step failed (its line says which).
# Windows PowerShell 5.1 and PowerShell 7; ASCII only.

param([string]$Machine = 'cabin', [string]$User = 'pj', [switch]$DryRun, [switch]$NoBootstrap)
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Distro = "$Machine-wsl"
$Location = "C:\WSL\$Distro"
$Wsl = Join-Path $env:windir 'System32\wsl.exe'
$Bundle = Join-Path $Here 'dotfiles.bundle'
# the same folder as the clone sees it through WSL's automount (C:\ProgramData\dram -> /mnt/c/ProgramData/dram)
$HereWsl = '/mnt/' + $Here.Substring(0, 1).ToLower() + ($Here.Substring(2) -replace '\\', '/')
# wsl.exe writes UTF-16 to a pipe unless this is set (WSL 0.64+)
$env:WSL_UTF8 = '1'
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Say([string]$m) { Write-Output ('{0:HH:mm:ss} {1}' -f (Get-Date), $m) }
function Fail([string]$m) { Write-Output "[x] $m"; exit 1 }
function Invoke-WslQuiet([string[]]$a) {
  # wsl.exe's text, NULs dropped; Windows PowerShell 5.1 turns a native command's stderr
  # into a terminating error under Stop, so this runs with Continue
  $ErrorActionPreference = 'Continue'
  $out = & $Wsl @a 2>&1 | ForEach-Object { ($_.ToString() -replace "`0", '').TrimEnd() }
  return @{ Code = $LASTEXITCODE; Out = @($out | Where-Object { $_ }) }
}
function Invoke-WslConsole([string[]]$a) {
  # wsl.exe on this console (a password prompt, the bootstrap's sudo); its exit code. Not
  # `& $Wsl @a; return $LASTEXITCODE`: inside `$code = Invoke-WslConsole ...` that captures
  # wsl.exe's output too, so $code became @(<its lines>, 0) and `$code -ne 0` held - a root
  # pass that worked read as failed and the password step never ran (cabin, 2026-10-12).
  # Start-Process leaves the console to wsl.exe and hands back only the exit code.
  $line = ($a | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
  $p = Start-Process -FilePath $Wsl -ArgumentList $line -NoNewWindow -PassThru
  $null = $p.Handle   # without the handle, PowerShell 5.1 can lose the exit code
  $p.WaitForExit()
  return [int]$p.ExitCode
}
function Write-LfFile([string]$path, [string]$text) {
  # a script for bash: LF line ends, no BOM
  [IO.File]::WriteAllText($path, ($text -replace "`r`n", "`n"), $Utf8)
}

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Fail 'run it elevated (Terminal (Admin)): enabling WSL and the agent service need it' }
foreach ($f in 'wslconfig', 'wsl.conf') {
  if (-not (Test-Path -LiteralPath (Join-Path $Here $f))) { Fail "$Here\$f missing (bin/push-host.sh --wsl stages it)" }
}
if (-not $NoBootstrap -and -not (Test-Path -LiteralPath $Bundle)) { Fail "$Bundle missing: from the Mac, bin/push-host.sh --wsl $Distro <user>@<this PC>" }
Say "the WSL clone $Distro for $User on $env:COMPUTERNAME$(if ($DryRun) { ' (dry run)' })"

# --- 1) .wslconfig -------------------------------------------------------------------
$tpl = [IO.File]::ReadAllText((Join-Path $Here 'wslconfig')) -replace "`r", ''
$row = @($tpl -split "`n" | Where-Object { $_ -match ('^#:\s+' + [regex]::Escape($Machine) + '\s') })
if ($row.Count -ne 1) { Fail "wslconfig has no row for $Machine (a '#: $Machine <memory> <swap> <vhd>' line)" }
$v = $row[0].Trim() -split '\s+'
$want = $tpl.Replace('@MEMORY@', $v[2]).Replace('@SWAP@', $v[3]).Replace('@VHD@', $v[4])
$cfg = Join-Path $env:USERPROFILE '.wslconfig'
$have = $null
if (Test-Path -LiteralPath $cfg) { $have = [IO.File]::ReadAllText($cfg) -replace "`r", '' }
$cfgChanged = $false
if ($have -ceq $want) { Say "[ok] $cfg current (memory $($v[2]), swap $($v[3]), defaultVhdSize $($v[4]))" }
elseif ($DryRun) { Say "[would] write $cfg (memory $($v[2]), swap $($v[3]), defaultVhdSize $($v[4]), mirrored, sparse)" }
else {
  if ($null -ne $have -and -not (Test-Path -LiteralPath "$cfg.before-dram")) { Copy-Item -LiteralPath $cfg -Destination "$cfg.before-dram" }
  [IO.File]::WriteAllText($cfg, $want, $Utf8)
  $cfgChanged = $true
  Say "[ok] wrote $cfg (memory $($v[2]), swap $($v[3]), defaultVhdSize $($v[4]))"
}

# --- 2) WSL and the agent ----------------------------------------------------------------
$ver = Invoke-WslQuiet @('--version')
if ($ver.Code -ne 0 -or -not $ver.Out) {
  if ($DryRun) { Say '[would] wsl --install --no-distribution (then a restart)'; exit 0 }
  Say 'WSL is not installed: wsl --install --no-distribution'
  $code = Invoke-WslConsole @('--install', '--no-distribution')
  if ($code -ne 0) { Fail "wsl --install --no-distribution failed ($code)" }
  Say '[!] restart Windows, then run wsl.ps1 again'
  exit 3
}
$num = if ($ver.Out[0] -match '(\d+\.\d+\.\d+)') { [version]$Matches[1] } else { [version]'0.0.0' }
if (-not $DryRun) {
  $u = Invoke-WslQuiet @('--update')
  if ($u.Code -ne 0) { Say "[!] wsl --update failed ($($u.Code)): $($u.Out -join ' ')" }
  $ver = Invoke-WslQuiet @('--version')
  if ($ver.Out -and $ver.Out[0] -match '(\d+\.\d+\.\d+)') { $num = [version]$Matches[1] }
}
if ($num -lt [version]'2.4.4') { Fail "WSL ${num}: wsl --install <distro> --name/--location needs 2.4.4 or newer (wsl --update)" }
Say "[ok] WSL $num"
$svc = Get-Service -Name ssh-agent -ErrorAction SilentlyContinue
if (-not $svc) { Say "[!] no OpenSSH Authentication Agent service (the OpenSSH Client capability): the clone's ssh has no agent" }
elseif ($svc.StartType -eq 'Automatic' -and $svc.Status -eq 'Running') { Say '[ok] ssh-agent Automatic and running' }
elseif ($DryRun) { Say '[would] ssh-agent: Automatic, started' }
else {
  Set-Service -Name ssh-agent -StartupType Automatic
  Start-Service -Name ssh-agent
  Say '[ok] ssh-agent Automatic and running (the YubiKey: ssh-add -K here, docs/platforms/wsl/README.md)'
}
if ($cfgChanged) {
  # .wslconfig is read when WSL starts; a running WSL would create the disk uncapped
  $null = Invoke-WslQuiet @('--shutdown')
  Say '[ok] wsl --shutdown (WSL reads the new .wslconfig at its next start)'
}

# --- 3) the distro ---------------------------------------------------------------------
$list = Invoke-WslQuiet @('--list', '--quiet')
$registered = @($list.Out | ForEach-Object { $_.Trim() }) -contains $Distro
if ($registered) { Say "[ok] $Distro is registered" }
elseif ($DryRun) { Say "[would] wsl --install archlinux --name $Distro --location $Location --no-launch"; Say '[would] then the root pass, and the bootstrap as the user'; exit 0 }
else {
  Say "wsl --install archlinux --name $Distro --location $Location --no-launch"
  $code = Invoke-WslConsole @('--install', 'archlinux', '--name', $Distro, '--location', $Location, '--no-launch')
  if ($code -ne 0) { Fail "wsl --install archlinux failed ($code)" }
  Say "[ok] $Distro registered at $Location"
}

# --- 4) the first root pass --------------------------------------------------------------
$rootScript = @'
set -euo pipefail
U="$1" H="$2" D="$3" T="$4"
# the keyring the image leaves empty for reproducibility (its first-setup would make it)
if [ ! -s /etc/pacman.d/gnupg/pubring.kbx ] && [ ! -s /etc/pacman.d/gnupg/pubring.gpg ]; then
  pacman-key --init
  pacman-key --populate archlinux
fi
pacman -Syu --noconfirm --needed git sudo
id "$U" >/dev/null 2>&1 || useradd -m -u 1000 -G wheel -s /bin/bash "$U"
id -nG "$U" | tr ' ' '\n' | grep -cx wheel >/dev/null || usermod -aG wheel "$U"
printf '%%wheel ALL=(ALL:ALL) ALL\n' >/etc/sudoers.d/.10-wheel
visudo -cf /etc/sudoers.d/.10-wheel >/dev/null
chmod 0440 /etc/sudoers.d/.10-wheel
mv /etc/sudoers.d/.10-wheel /etc/sudoers.d/10-wheel
loginctl enable-linger "$U" || echo "linger: dram apply's system/wsl-setup.sh turns it on later"
sed -e "s/@HOST@/$H/g" -e "s/@USER@/$U/g" -e "s/@DISTRO@/$D/g" "$T" >/etc/wsl.conf
printf '%s\n' "$H" >/etc/hostname
echo "root pass done: $U in wheel, /etc/wsl.conf names the distro $H"
'@
$rootSh = Join-Path $Here 'wsl-root.sh'
if ($DryRun) { Say "[would] the root pass in $Distro (keyring, pacman -Syu git sudo, $User in wheel, /etc/wsl.conf, /etc/hostname)" }
else {
  Write-LfFile $rootSh $rootScript
  Say "root pass in $Distro"
  $code = Invoke-WslConsole @('-d', $Distro, '-u', 'root', '--', 'bash', "$HereWsl/wsl-root.sh", $User, $Distro, $Distro, "$HereWsl/wsl.conf")
  Remove-Item -LiteralPath $rootSh -Force -ErrorAction SilentlyContinue
  if ($code -ne 0) { Fail "the root pass failed ($code): its output is above" }
  $st = Invoke-WslQuiet @('-d', $Distro, '-u', 'root', '--', 'passwd', '-S', $User)
  $state = if ($st.Out) { ($st.Out[0] -split '\s+')[1] } else { '' }
  if ($state -ne 'P') {
    Say "the password for $User in $Distro (sudo asks for it):"
    $code = Invoke-WslConsole @('-d', $Distro, '-u', 'root', '--', 'passwd', $User)
    if ($code -ne 0) { Fail "passwd $User failed ($code)" }
  } else { Say "[ok] $User has a password" }
  $null = Invoke-WslQuiet @('--terminate', $Distro)
  # WSL reads wsl.conf only once the distro has stopped (the "8-second rule")
  for ($i = 0; $i -lt 30; $i++) {
    $run = Invoke-WslQuiet @('--list', '--running', '--quiet')
    if (-not (@($run.Out | ForEach-Object { $_.Trim() }) -contains $Distro)) { break }
    Start-Sleep -Seconds 1
  }
  Say "[ok] $Distro stopped: it starts again as $Distro, user $User"
}
if ($NoBootstrap) { Say 'stopped before the bootstrap (-NoBootstrap)'; exit 0 }

# --- 5) the repo and the bootstrap, as the user ------------------------------------------------
$userScript = @'
set -euo pipefail
H="$1" B="$2" R="$HOME/git/dotfiles"
if [ ! -d "$R/.git" ]; then
  br="$(git bundle list-heads "$B" | sed -n 's|^[0-9a-f]* refs/heads/||p' | grep -x master || true)"
  [ -n "$br" ] || br="$(git bundle list-heads "$B" | sed -n 's|^[0-9a-f]* refs/heads/||p' | head -1)"
  mkdir -p "$HOME/git"
  git clone -q -b "$br" "$B" "$R"
  git -C "$R" remote remove origin
  echo "cloned $br from the bundle into $R"
fi
t="$(git -C "$R" tag -l 'v*' --sort=-v:refname | head -1)"
if [ -n "$t" ] && git -C "$R" cat-file -e "$t:modules/hosts/$H.nix" 2>/dev/null; then
  git -C "$R" checkout -q --detach "$t"
  echo "at release $t (channel stable)"
else
  mkdir -p "$HOME/.config/dram"
  echo main >"$HOME/.config/dram/channel"
  echo "no release knows $H yet: following master (channel main; dram channel stable later)"
fi
bash "$R/install/bootstrap.sh" --yes
'@
$userSh = Join-Path $Here 'wsl-user.sh'
if ($DryRun) { Say "[would] as ${User}: clone $Bundle into ~/git/dotfiles, then install/bootstrap.sh --yes"; exit 0 }
Write-LfFile $userSh $userScript
Say "as $User in ${Distro}: the repo, then install/bootstrap.sh --yes (sudo asks for the password)"
$code = Invoke-WslConsole @('-d', $Distro, '-u', $User, '--cd', '~', '--', 'bash', '-l', "$HereWsl/wsl-user.sh", $Distro, "$HereWsl/dotfiles.bundle")
Remove-Item -LiteralPath $userSh -Force -ErrorAction SilentlyContinue
if ($code -ne 0) { Fail "the bootstrap failed ($code): its output is above; fix it, then run wsl.ps1 again (or bash ~/git/dotfiles/install/bootstrap.sh in $Distro)" }
$null = Invoke-WslQuiet @('--terminate', $Distro)
Say "[ok] $Distro is converged. Next (docs/platforms/wsl/README.md): open it (wsl -d $Distro), dram doctor; ssh-add -K here with the YubiKey plugged in; VSCodium's Open Remote - SSH to 127.0.0.1:2222"
exit 0

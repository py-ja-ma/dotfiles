#!/usr/bin/env bash
# usage: arch-install.sh --preset NAME --disk PATH --hostname NAME [options]
#
# Puts Arch on one disk (plus, for the bench preset, a second "work" disk) from the Arch ISO (decisions/0010): GPT with an ESP at
# /efi, btrfs with the subvolume layout of decisions/0011 (a data pool on
# desktops, LUKS2 on laptops), a minimal base from the pinned mirrors
# (install/mirrorlist — nothing here talks to archlinux.org), a UKI booted by
# systemd-boot, networking, the user, a copy of this repo at
# ~/git/dotfiles and the host file with its roles. First boot continues with
# install/bootstrap.sh, which runs `dram apply`; Secure Boot, snapshots and
# the per-snapshot boot entries come with `dram apply`'s hooks. Run as root from the ISO,
# out of a checkout of this repo (USB stick, or git clone from the Mac).
#
# Safety: every disk is listed first and only --disk is touched; a disk that
# holds NTFS, BitLocker or a Windows boot manager is refused; you type the
# disk's serial number to confirm (or pass it with --yes-wipe).
#
#   --preset NAME         install/presets/NAME.env: desktop | laptop | admin | vm-test
#   --disk PATH           the target, ideally /dev/disk/by-id/...
#   --hostname NAME       the new host's name (modules/hosts/NAME.nix)
#   --roles "A B"         roles for a new host file (asked when missing and the
#                         repo has no modules/hosts/NAME.nix)
#   --user NAME           the login user (default pj)
#   --timezone ZONE       default America/New_York
#   --sys-gib N           override the preset's system-pool size (desktop presets)
#   --work-disk PATH      a second disk for the work pool (VMs, ML, containers, scratch;
#                         the bench preset requires it, decisions/0017); wiped the same way
#   --yes-wipe SERIAL     confirm the wipe without the prompt (VM tests)
#   --yes-wipe-work SERIAL  the same for --work-disk
#   --password-file FILE  the user's password, first line (VM tests); otherwise asked
#   --luks-keyfile FILE   LUKS passphrase file (VM tests); otherwise asked
#   --sshd                enable sshd on first boot (vm-test does by default)
#   --poweroff            power off at the end (VM tests)
#   --dry-run             print every command, change nothing
#   -h, --help            this text
#
# Every option may also come from the kernel command line as dram.<option>=value
# (roles comma-separated), which is how the unattended VM test drives it.
#
# exit: 0 ok · 1 refused or a step failed · 2 bad usage
# see: decisions/0010-install-path.md, decisions/0011-disk-boot-secure-boot-snapshots.md

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

PRESET="" DISK="" HOST="" ROLES="" USERNAME=pj TZONE="America/New_York" SYS_GIB_OVERRIDE=""
YES_WIPE="" WORK_DISK="" YES_WIPE_WORK="" PASSWORD_FILE="" LUKS_KEYFILE="" SSHD=0 POWEROFF=0 DRY=0

usage_line() { sed -n '2s/^# \{0,1\}//p' "$0" >&2; }
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --preset | --disk | --hostname | --roles | --user | --timezone | --sys-gib | --yes-wipe | --password-file | --luks-keyfile | --work-disk | --yes-wipe-work)
      [ $# -ge 2 ] || {
        usage_line
        exit 2
      }
      case "$1" in
        --preset) PRESET="$2" ;;
        --disk) DISK="$2" ;;
        --hostname) HOST="$2" ;;
        --roles) ROLES="$2" ;;
        --user) USERNAME="$2" ;;
        --timezone) TZONE="$2" ;;
        --sys-gib) SYS_GIB_OVERRIDE="$2" ;;
        --yes-wipe) YES_WIPE="$2" ;;
        --password-file) PASSWORD_FILE="$2" ;;
        --luks-keyfile) LUKS_KEYFILE="$2" ;;
        --work-disk) WORK_DISK="$2" ;;
        --yes-wipe-work) YES_WIPE_WORK="$2" ;;
      esac
      shift 2
      continue
      ;;
    --sshd) SSHD=1 ;;
    --poweroff) POWEROFF=1 ;;
    --dry-run) DRY=1 ;;
    *)
      usage_line
      exit 2
      ;;
  esac
  shift
done

say() { printf '\n\033[1;35m######\033[0m \033[1m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
warn() { printf '\033[1;33m  !! %s\033[0m\n' "$*"; }
die() {
  printf '\033[1;31m  ** %s\033[0m\n' "$*" >&2
  exit 1
}
# run "cmd": eval so --dry-run prints the exact command string
# shellcheck disable=SC2294
run() { if [ "$DRY" = 1 ]; then printf '  \033[2m[dry-run] %s\033[0m\n' "$*"; else eval "$@" || die "failed: $*"; fi; }

# kernel command line fallback: dram.preset=, dram.disk=, dram.host=, dram.roles=a,b ...
cmdline() { tr ' ' '\n' </proc/cmdline 2>/dev/null | sed -n "s/^dram\.$1=//p" | tail -1; }
[ -n "$PRESET" ] || PRESET="$(cmdline preset)"
[ -n "$DISK" ] || DISK="$(cmdline disk)"
[ -n "$HOST" ] || HOST="$(cmdline host)"
[ -n "$ROLES" ] || ROLES="$(cmdline roles | tr ',' ' ')"
[ -n "$YES_WIPE" ] || YES_WIPE="$(cmdline wipe)"
[ -n "$WORK_DISK" ] || WORK_DISK="$(cmdline work-disk)"
[ -n "$YES_WIPE_WORK" ] || YES_WIPE_WORK="$(cmdline wipe-work)"
[ -n "$PASSWORD_FILE" ] || PASSWORD_FILE="$(cmdline password-file)"
[ "$(cmdline poweroff)" = 1 ] && POWEROFF=1
[ -n "$SYS_GIB_OVERRIDE" ] || SYS_GIB_OVERRIDE="$(cmdline sys-gib)"
SERIAL_OVERRIDE="$(cmdline serial-console)" # VM tests of the desktop-class presets

[ -n "$PRESET" ] && [ -n "$DISK" ] && [ -n "$HOST" ] || {
  usage_line
  echo "  (--preset, --disk and --hostname are required)" >&2
  exit 2
}
[ -f "$HERE/presets/$PRESET.env" ] || die "no preset install/presets/$PRESET.env ($(cd "$HERE/presets" && ls -- *.env | sed 's/\.env$//' | paste -sd' '))"
# shellcheck source=/dev/null
. "$HERE/presets/$PRESET.env"
[ -n "$SYS_GIB_OVERRIDE" ] && SYS_GIB="$SYS_GIB_OVERRIDE"
[ -n "$SERIAL_OVERRIDE" ] && SERIAL_CONSOLE="$SERIAL_OVERRIDE"
[ "${SERIAL_CONSOLE:-0}" = 1 ] && SSHD=1
echo "$HOST" | grep -qE '^[a-z][a-z0-9-]{0,62}$' || die "hostname '$HOST': lowercase letters, digits and dashes"
[ "${WORK_REQUIRED:-0}" = 1 ] && [ -z "$WORK_DISK" ] && die "preset $PRESET needs --work-disk (the second NVMe, decisions/0017)"
[ -n "$WORK_DISK" ] && [ -z "${WORK_SUBVOLS:-}" ] && die "preset $PRESET has no WORK_SUBVOLS — --work-disk is for the bench preset"

# ---------------------------------------------------------------- 0 preflight ----
say "0) Preflight — preset $PRESET: $PRESET_DESC"
[ "$DRY" = 1 ] || [ "$(id -u)" -eq 0 ] || die "run as root from the Arch ISO"
[ -d /sys/firmware/efi ] || [ "$DRY" = 1 ] || die "not booted in UEFI mode"
for t in sgdisk mkfs.btrfs mkfs.fat pacstrap genfstab arch-chroot blkid lsblk; do
  command -v "$t" >/dev/null 2>&1 || [ "$DRY" = 1 ] || die "$t missing — run this from the Arch ISO"
done
DEV="$(readlink -f "$DISK" 2>/dev/null)"
[ -n "$DEV" ] || DEV="$DISK"
[ -b "$DEV" ] || [ "$DRY" = 1 ] || die "no block device behind $DISK"
WDEV=""
if [ -n "$WORK_DISK" ]; then
  WDEV="$(readlink -f "$WORK_DISK" 2>/dev/null)"
  [ -n "$WDEV" ] || WDEV="$WORK_DISK"
  [ -b "$WDEV" ] || [ "$DRY" = 1 ] || die "no block device behind $WORK_DISK"
  [ "$WDEV" != "$DEV" ] || die "--work-disk is the same disk as --disk"
fi

info "Disks on this machine:"
lsblk -dno PATH,SIZE,MODEL,SERIAL,TRAN -e7,11 2>/dev/null | sed 's/^/    /'
for d in $(lsblk -dnpo NAME -e7,11 2>/dev/null); do
  if [ "$d" = "$DEV" ]; then
    info "WILL BE WIPED:  $d (system + data)"
  elif [ -n "$WDEV" ] && [ "$d" = "$WDEV" ]; then
    info "WILL BE WIPED:  $d (work pool)"
  else info "not touched:    $d"; fi
done

# confirm_disk <dev> <--yes value> <label>: refuse Windows (NTFS, BitLocker, an ESP
# holding EFI/Microsoft), then the typed serial; prints the serial
confirm_disk() {
  local dev="$1" yes="$2" label="$3" win="" part fstype m serial typed
  while read -r part fstype; do
    case "${fstype,,}" in ntfs | bitlocker) win="$win $part($fstype)" ;; esac
    if [ "${fstype,,}" = vfat ] && [ "$DRY" = 0 ]; then
      m="$(mktemp -d)"
      if mount -o ro "$part" "$m" 2>/dev/null; then
        [ -d "$m/EFI/Microsoft" ] && win="$win $part(EFI/Microsoft)"
        umount "$m"
      fi
      rmdir "$m"
    fi
  done < <(lsblk -lnpo NAME,FSTYPE "$dev" 2>/dev/null | awk 'NF==2')
  [ -z "$win" ] || die "$dev ($label) holds Windows:$win — refusing (decisions/0010). Pick the other disk."
  serial="$(lsblk -dno SERIAL "$dev" 2>/dev/null | tr -d ' ')"
  [ -n "$serial" ] || serial="$(basename "$dev")"
  if [ "$yes" != "$serial" ]; then
    [ -t 0 ] || die "type the serial of the $label disk to confirm, or pass its --yes-wipe option ($serial)"
    read -rp "  Type the serial of $dev ($serial, $label) to wipe it: " typed </dev/tty
    [ "$typed" = "$serial" ] || die "serial not typed — nothing was changed"
  fi
  printf '%s\n' "$serial"
}
SERIAL="$(confirm_disk "$DEV" "$YES_WIPE" "system")" || exit 1
WSERIAL=""
[ -n "$WDEV" ] && { WSERIAL="$(confirm_disk "$WDEV" "$YES_WIPE_WORK" "work")" || exit 1; }

# the ISO's own mirrorlist comes from reflector (archlinux.org); use ours
run "install -m644 '$HERE/mirrorlist' /etc/pacman.d/mirrorlist"
if [ "$DRY" = 0 ]; then
  timedatectl set-ntp true 2>/dev/null || true
  for _ in $(seq 60); do systemctl is-active --quiet pacman-init.service && break || sleep 2; done
  curl -sfI -m 10 https://geo.mirror.pkgbuild.com/ >/dev/null || die "the mirrors are unreachable — check the network (iwctl for Wi-Fi)"
fi

UCODE=""
grep -q GenuineIntel /proc/cpuinfo 2>/dev/null && UCODE=intel-ucode
grep -q AuthenticAMD /proc/cpuinfo 2>/dev/null && UCODE=amd-ucode

# ---------------------------------------------------------------- 1 partitions ---
say "1) Partitions on $DEV"
P_SYS_TYPE=8304 # Linux x86-64 root
[ "$ENCRYPT" = luks2 ] && P_SYS_TYPE=8309
if [ "${SYS_GIB:-0}" -gt 0 ]; then
  run "sgdisk --zap-all '$DEV'"
  run "sgdisk -n1:1MiB:+${ESP_MIB}MiB -t1:ef00 -c1:ESP -n2:0:+${SYS_GIB}GiB -t2:$P_SYS_TYPE -c2:dram-sys -n3:0:0 -t3:8300 -c3:dram-data '$DEV'"
else
  run "sgdisk --zap-all '$DEV'"
  run "sgdisk -n1:1MiB:+${ESP_MIB}MiB -t1:ef00 -c1:ESP -n2:0:0 -t2:$P_SYS_TYPE -c2:dram-sys '$DEV'"
fi
run "udevadm settle"
part() { lsblk -lnpo NAME,PARTLABEL "$DEV" 2>/dev/null | awk -v l="$1" '$2==l {print $1}'; }
P_ESP="$(part ESP)" P_SYS="$(part dram-sys)" P_DATA="$(part dram-data)"
[ "$DRY" = 1 ] && P_ESP="${DEV}p1" P_SYS="${DEV}p2" P_DATA="${DEV}p3"
[ -n "$P_ESP" ] && [ -n "$P_SYS" ] || die "partitions not found after sgdisk"

# ---------------------------------------------------------------- 2 LUKS2 --------
SYS_DEV="$P_SYS" LUKS_UUID=""
if [ "$ENCRYPT" = luks2 ]; then
  say "2) LUKS2 on $P_SYS (TPM2 + PIN are enrolled after first boot, by dram apply)"
  kf=""
  [ -n "$LUKS_KEYFILE" ] && kf="--key-file '$LUKS_KEYFILE'"
  run "cryptsetup luksFormat --type luks2 --pbkdf argon2id --label dram-sys --batch-mode $kf '$P_SYS'"
  run "cryptsetup open --allow-discards $kf '$P_SYS' dram-sys"
  SYS_DEV=/dev/mapper/dram-sys
  [ "$DRY" = 0 ] && LUKS_UUID="$(blkid -s UUID -o value "$P_SYS")"
fi

# ---------------------------------------------------------------- 3 filesystems ---
say "3) Filesystems and subvolumes (decisions/0011)"
OPTS="noatime,compress=zstd:1,discard=async"
run "mkfs.fat -F32 -n ESP '$P_ESP'"
run "mkfs.btrfs -f -L dram-sys '$SYS_DEV'"
[ -n "$P_DATA" ] && [ "${SYS_GIB:-0}" -gt 0 ] && run "mkfs.btrfs -f -L dram-data '$P_DATA'"

SYS_SUBVOLS="@:/ @home:/home @snapshots:/.snapshots @home_snapshots:/home/.snapshots @var_log:/var/log @var_cache_pacman:/var/cache/pacman/pkg @flatpak:/var/lib/flatpak @sbctl:/var/lib/sbctl"
[ "$SWAP" = hibernate ] && SYS_SUBVOLS="$SYS_SUBVOLS @swap:/swap:nocow"
# single-pool presets keep their data subvolumes in the system pool
[ "${SYS_GIB:-0}" -gt 0 ] || SYS_SUBVOLS="$SYS_SUBVOLS $DATA_SUBVOLS"

mk_subvols() { # mk_subvols <dev> "<name:mount[:nocow]> ..."
  run "mount '$1' /mnt"
  for sv in $2; do run "btrfs subvolume create '/mnt/${sv%%:*}'"; done
  run "umount /mnt"
}
mount_subvols() { # mount_subvols <dev> "<list>" — @ must already be mounted for the system pool
  local sv name rest mp flag
  for sv in $2; do
    name="${sv%%:*}" rest="${sv#*:}" mp="${rest%%:*}" flag=""
    [ "$rest" != "$mp" ] && flag="${rest#*:}"
    [ "$mp" = / ] && continue
    run "mount --mkdir -o '$OPTS,subvol=$name' '$1' '/mnt$mp'"
    [ "$flag" = nocow ] && run "chattr +C '/mnt$mp'"
  done
}
mk_subvols "$SYS_DEV" "$SYS_SUBVOLS"
run "mount -o '$OPTS,subvol=@' '$SYS_DEV' /mnt"
# /home first, then /home/.snapshots inside it: mount in list order
mount_subvols "$SYS_DEV" "$SYS_SUBVOLS"
if [ "${SYS_GIB:-0}" -gt 0 ] && [ -n "$P_DATA" ]; then
  mk_subvols "$P_DATA" "$DATA_SUBVOLS"
  mount_subvols "$P_DATA" "$DATA_SUBVOLS"
fi
# the bench's second NVMe: one btrfs work pool (VMs, ML, containers, scratch)
P_WORK=""
if [ -n "$WDEV" ]; then
  say "3b) Work pool on $WDEV"
  run "sgdisk --zap-all '$WDEV'"
  run "sgdisk -n1:1MiB:0 -t1:8300 -c1:dram-work '$WDEV'"
  run "udevadm settle"
  P_WORK="$(lsblk -lnpo NAME,PARTLABEL "$WDEV" 2>/dev/null | awk '$2=="dram-work" {print $1}')"
  [ "$DRY" = 1 ] && P_WORK="${WDEV}p1"
  [ -n "$P_WORK" ] || die "work partition not found after sgdisk"
  run "mkfs.btrfs -f -L dram-work '$P_WORK'"
  mk_subvols "$P_WORK" "$WORK_SUBVOLS"
  mount_subvols "$P_WORK" "$WORK_SUBVOLS"
fi
run "mount --mkdir -o fmask=0077,dmask=0077 '$P_ESP' /mnt/efi"
if [ "$SWAP" = hibernate ]; then
  ram_gib=$((($(awk '/MemTotal/ {print $2}' /proc/meminfo) + 1048575) / 1048576))
  run "btrfs filesystem mkswapfile --size ${ram_gib}g /mnt/swap/swapfile"
fi

# ---------------------------------------------------------------- 4 base system ---
say "4) Base system (pacstrap; the roles come later through dram apply)"
PKGS="base linux linux-firmware $UCODE btrfs-progs sudo git openssh iwd python efibootmgr man-db"
[ "$ENCRYPT" = luks2 ] && PKGS="$PKGS cryptsetup"
run "pacstrap -K /mnt $PKGS"
run "genfstab -U /mnt >> /mnt/etc/fstab"
# subvolid= pins a subvolume id that a rollback replaces; subvol= is enough
run "sed -i 's/,subvolid=[0-9]*//' /mnt/etc/fstab"
[ "$SWAP" = hibernate ] && run "echo '/swap/swapfile none swap defaults 0 0' >> /mnt/etc/fstab"
run "install -m644 '$HERE/mirrorlist' /mnt/etc/pacman.d/mirrorlist"

# ---------------------------------------------------------------- 5 configure -----
say "5) Configure the new system"
SYS_UUID=""
[ "$DRY" = 0 ] && SYS_UUID="$(blkid -s UUID -o value "$SYS_DEV")"
CMDLINE="root=UUID=$SYS_UUID rootflags=subvol=@ rw"
HOOKS="base systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck"
if [ "$ENCRYPT" = luks2 ]; then
  CMDLINE="rd.luks.name=$LUKS_UUID=dram-sys rd.luks.options=discard root=/dev/mapper/dram-sys rootflags=subvol=@ rw"
  HOOKS="base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck"
fi
[ "${SERIAL_CONSOLE:-0}" = 1 ] && CMDLINE="$CMDLINE console=tty0 console=ttyS0,115200"

CHROOT_SCRIPT="/mnt/root/dram-chroot.sh"
if [ "$DRY" = 0 ]; then
  cat >"$CHROOT_SCRIPT" <<EOF
set -euo pipefail
ln -sf /usr/share/zoneinfo/$TZONE /etc/localtime
hwclock --systohc || true
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo 'KEYMAP=us' > /etc/vconsole.conf
echo '$HOST' > /etc/hostname
printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 $HOST\n' > /etc/hosts
# initramfs: systemd-based; a UKI on the ESP that systemd-boot finds by itself
mkdir -p /etc/mkinitcpio.conf.d /etc/kernel /efi/EFI/Linux
echo 'HOOKS=($HOOKS)' > /etc/mkinitcpio.conf.d/dram.conf
echo '$CMDLINE' > /etc/kernel/cmdline
# hibernation (laptop preset): resume from the swapfile; the offset is where btrfs put it
if [ "$SWAP" = hibernate ] && [ -f /swap/swapfile ]; then
  off="\$(btrfs inspect-internal map-swapfile -r /swap/swapfile)"
  printf '%s resume=%s resume_offset=%s\n' "\$(cat /etc/kernel/cmdline)" '$([ "$ENCRYPT" = luks2 ] && echo /dev/mapper/dram-sys || echo "UUID=$SYS_UUID")' "\$off" >/etc/kernel/cmdline.new
  mv /etc/kernel/cmdline.new /etc/kernel/cmdline
fi
cat > /etc/mkinitcpio.d/linux.preset <<'P'
ALL_kver="/boot/vmlinuz-linux"
PRESETS=('default' 'fallback')
default_uki="/efi/EFI/Linux/arch-linux.efi"
fallback_uki="/efi/EFI/Linux/arch-linux-fallback.efi"
fallback_options="-S autodetect"
P
rm -f /boot/initramfs-linux*.img
mkinitcpio -P
bootctl install --esp-path=/efi
printf 'default arch-linux.efi\ntimeout 3\nconsole-mode keep\neditor no\n' > /efi/loader/loader.conf
# networking: systemd-networkd + resolved, iwd for Wi-Fi
mkdir -p /etc/systemd/network
printf '[Match]\nName=en*\n\n[Network]\nDHCP=yes\n' > /etc/systemd/network/20-wired.network
printf '[Match]\nName=wl*\n\n[Network]\nDHCP=yes\nIgnoreCarrierLoss=3s\n' > /etc/systemd/network/25-wireless.network
systemctl enable systemd-networkd systemd-resolved systemd-timesyncd iwd fstrim.timer
[ "$SSHD" = 1 ] && systemctl enable sshd
# the user: wheel + sudo; root stays locked
useradd -m -G wheel -s /bin/bash '$USERNAME'
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
passwd -l root
EOF
fi
run "arch-chroot /mnt bash /root/dram-chroot.sh"
run "rm -f '$CHROOT_SCRIPT'"
# arch-chroot bind-mounts the ISO's resolv.conf over the target's, so the stub link is
# made from outside, once the chroot has gone
run "ln -sf ../run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf"
# bootctl in the chroot cannot write EFI variables; the ISO can. The removable-path copy
# (EFI/BOOT/BOOTX64.EFI) boots either way; the named entry puts it first in BootOrder.
if [ "$DRY" = 1 ] || [ -d /sys/firmware/efi/efivars ]; then
  run "efibootmgr --quiet --create --disk '$DEV' --part 1 --loader '\\EFI\\systemd\\systemd-bootx64.efi' --label 'Linux Boot Manager' --unicode"
fi
if [ -n "$PASSWORD_FILE" ]; then
  run "printf '%s:%s\n' '$USERNAME' \"\$(head -1 '$PASSWORD_FILE')\" | arch-chroot /mnt chpasswd"
else
  info "Password for $USERNAME:"
  run "arch-chroot /mnt passwd '$USERNAME'"
fi
# Wi-Fi the ISO already knows (iwctl) comes along
if [ -d /var/lib/iwd ] && ls /var/lib/iwd/*.psk >/dev/null 2>&1; then
  run "install -d -m700 /mnt/var/lib/iwd && cp /var/lib/iwd/*.psk /mnt/var/lib/iwd/"
fi

# ---------------------------------------------------------------- 6 repo + host ---
say "6) This repo and the host file"
HOMEDIR="/mnt/home/$USERNAME"
run "install -d '$HOMEDIR/git' && cp -a '$REPO' '$HOMEDIR/git/dotfiles'"
HOSTFILE="$HOMEDIR/git/dotfiles/modules/hosts/$HOST.nix"
if [ -f "$REPO/modules/hosts/$HOST.nix" ]; then
  info "modules/hosts/$HOST.nix exists — its roles: $(sed -nE 's/^[[:space:]]*roles[[:space:]]*=[[:space:]]*\[([^]]*)\].*/\1/p' "$REPO/modules/hosts/$HOST.nix" | tr -d '"')"
else
  # shellcheck source=install/lib/detect.sh
  . "$HERE/lib/detect.sh"
  # shellcheck source=install/lib/roles.sh
  . "$HERE/lib/roles.sh"
  if [ -z "$ROLES" ]; then
    info "Roles available: $(known_roles "$REPO" | paste -sd' ')"
    [ -t 0 ] || die "no --roles and no terminal to ask"
    read -rp "  Roles for $HOST (space separated; base is implicit): " ROLES
  fi
  for r in $ROLES; do known_roles "$REPO" | grep -qx "$r" || die "unknown role '$r'"; done
  gpu="$(detect_gpus | awk '{print $1}')"
  [ -n "$gpu" ] || gpu=intel
  laptop=false
  [ "$(detect_form_factor)" = laptop ] && laptop=true
  rl=""
  for r in $ROLES; do rl="$rl \"$r\""; done
  if [ "$DRY" = 0 ]; then
    cat >"$HOSTFILE" <<EOF
{ ... }:

# $HOST — written by install/arch-install.sh on $(date +%F) (preset $PRESET).
# Detected: CPU $(detect_cpu), GPU $(detect_gpus), $(detect_form_factor). Commit it after
# the first \`dram harvest\` (decisions/0009).
{
  dram = {
    hostName = "$HOST";
    roles = [$rl ];   # one line: install/lib/roles.sh reads it with grep (decisions/0009)
    isLaptop = $laptop;
    gpu = "$gpu";
  };
}
EOF
  fi
  info "wrote modules/hosts/$HOST.nix: roles$rl, gpu $gpu, laptop $laptop"
fi
run "arch-chroot /mnt chown -R '$USERNAME:$USERNAME' '/home/$USERNAME/git'"

# facts the first boot reads instead of guessing (no secrets in here)
run "install -d /mnt/etc/dram"
if [ "$DRY" = 0 ]; then
  {
    echo "INSTALL_DATE=$(date -Is)"
    echo "PRESET=$PRESET"
    echo "BOOTLOADER=systemd-boot"
    echo "ESP=/efi"
    echo "ENCRYPT=$ENCRYPT"
    echo "LUKS_UUID=$LUKS_UUID"
    echo "SYS_UUID=$SYS_UUID"
    echo "DATA_UUID=$([ -n "$P_DATA" ] && [ "${SYS_GIB:-0}" -gt 0 ] && blkid -s UUID -o value "$P_DATA")"
    echo "SWAP=$SWAP"
    echo "DISK_SERIAL=$SERIAL"
    echo "WORK_UUID=$([ -n "$P_WORK" ] && blkid -s UUID -o value "$P_WORK")"
    echo "WORK_SERIAL=$WSERIAL"
    echo "ISO=$(cat /version 2>/dev/null || echo unknown)"
  } >/mnt/etc/dram/install-facts.env
fi

say "Done — $HOST is installed on $DEV"
info "Next: reboot, log in as $USERNAME, then:"
info "  cd ~/git/dotfiles && bash install/bootstrap.sh"
info "(bootstrap upgrades once, then runs dram apply for the roles; docs/records/handbook/01-install.md)"
if [ "$POWEROFF" = 1 ] && [ "$DRY" = 0 ]; then
  sync
  umount -R /mnt || true
  [ "$ENCRYPT" = luks2 ] && cryptsetup close dram-sys
  systemctl poweroff
fi

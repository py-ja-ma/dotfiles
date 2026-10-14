#!/usr/bin/env bash
# usage: snapshots-setup.sh [--dry-run]
#
# Turns on SteamOS-style snapshots for this host (decisions/0011): snapper
# configs `root` (/) and `home` (/home) on the @snapshots / @home_snapshots
# subvolumes install/arch-install.sh made, the dram-snapshot helper in
# /usr/local/lib/dram/, the pacman hooks that snapshot before and after every
# transaction and build a boot entry per snapshot, and the snapper timers.
# Idempotent; a `dram apply` role hook (system/apply-hooks.tsv). Skips with a
# note on a host without btrfs or without the @snapshots layout (the older
# ext4 hosts). Root, unless --dry-run.
#
#   -n, --dry-run   print what would change
#   -h, --help      this text
#
# exit: 0 ok (or skipped) · 1 not root or a step failed · 2 bad usage
# see: decisions/0011-disk-boot-secure-boot-snapshots.md

DRY=0
case "${1:-}" in
  "") ;;
  -n | --dry-run) DRY=1 ;;
  -h | --help)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    sed -n '2s/^# \{0,1\}//p' "$0" >&2
    exit 2
    ;;
esac

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RC=0
say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
failed() {
  warn "$*"
  RC=1
}
run() { if [ "$DRY" -eq 1 ]; then printf '  \033[2m[dry-run] %s\033[0m\n' "$*"; else "$@"; fi; }
[ "$(id -u)" -eq 0 ] || [ "$DRY" -eq 1 ] || {
  echo "Run with sudo: sudo bash $0 [--dry-run]"
  exit 1
}

if [ "$(findmnt -no FSTYPE / 2>/dev/null)" != btrfs ] || ! findmnt -no OPTIONS / 2>/dev/null | grep -qE 'subvol=/@(,|$)'; then
  warn "/ is not the btrfs @ subvolume (an older ext4/LVM host?) — snapshots skipped (decisions/0011)"
  exit 0
fi
command -v snapper >/dev/null 2>&1 || [ "$DRY" -eq 1 ] || {
  failed "snapper is not installed — dram apply installs it (packages/metal.txt)"
  exit 1
}

# create-config wants to make the .snapshots subvolume itself; ours already exists
# (@snapshots, mounted by fstab), so: unmount, let snapper create its config, drop
# the nested subvolume it made, remount ours.
config() { # config <name> <mountpoint>
  local name="$1" mp="$2" snap="$2/.snapshots"
  [ "$mp" = / ] && snap=/.snapshots
  say "snapper config $name ($mp)"
  if [ ! -f "/etc/snapper/configs/$name" ]; then
    findmnt -no SOURCE "$snap" >/dev/null 2>&1 || {
      failed "$snap is not mounted — the @snapshots layout from install/arch-install.sh is missing"
      return
    }
    run umount "$snap" && run rmdir "$snap" \
      && run snapper --no-dbus -c "$name" create-config "$mp" \
      && run btrfs subvolume delete "$snap" \
      && run mkdir "$snap" && run mount "$snap" || {
      failed "create-config $name failed"
      return
    }
  fi
  run install -m640 "$REPO/system/snapper/$name" "/etc/snapper/configs/$name" && ok "/etc/snapper/configs/$name"
  run chmod 750 "$snap"
}
config root /
config home /home
if [ "$DRY" -eq 0 ] && ! grep -q '^SNAPPER_CONFIGS="root home"' /etc/conf.d/snapper 2>/dev/null; then
  sed -i 's/^SNAPPER_CONFIGS=.*/SNAPPER_CONFIGS="root home"/' /etc/conf.d/snapper 2>/dev/null || echo 'SNAPPER_CONFIGS="root home"' >/etc/conf.d/snapper
fi

say "dram-snapshot helper + pacman hooks"
run install -Dm755 "$REPO/system/dram-snapshot.sh" /usr/local/lib/dram/dram-snapshot && ok "/usr/local/lib/dram/dram-snapshot"
for h in 00-dram-snap-pre.hook zz-dram-snap-post.hook; do
  run install -Dm644 "$REPO/system/hooks/$h" "/etc/pacman.d/hooks/$h" && ok "/etc/pacman.d/hooks/$h"
done
# what systemd.volatile=overlay needs in the snapshot entries' initramfs (dram-snapshot -A)
run install -Dm644 "$REPO/system/initcpio/dram-volatile" /etc/initcpio/install/dram-volatile && ok "/etc/initcpio/install/dram-volatile"
if pacman -Q snap-pac >/dev/null 2>&1; then
  warn "snap-pac is installed too — two snapshots per transaction; sudo pacman -Rns snap-pac (decisions/0011)"
fi

say "timers"
for t in snapper-cleanup.timer snapper-timeline.timer; do
  if systemctl is-enabled --quiet "$t" 2>/dev/null; then ok "$t enabled"; else run systemctl enable --now "$t" && ok "$t enabled" || failed "could not enable $t"; fi
done

# the live system is the menu's default, whatever the snapshot entries sort as
LOADER=/efi/loader/loader.conf
if [ -f "$LOADER" ]; then
  if grep -qx 'default arch-linux.efi' "$LOADER"; then ok "$LOADER: default arch-linux.efi"; else
    say "systemd-boot default: the live system"
    if [ "$DRY" -eq 1 ]; then echo "  [dry-run] default arch-linux.efi -> $LOADER"; else
      {
        grep -v '^default ' "$LOADER"
        echo 'default arch-linux.efi'
      } >"$LOADER.new" && mv "$LOADER.new" "$LOADER" && ok "$LOADER: default arch-linux.efi" || failed "could not write $LOADER"
    fi
  fi
fi

if [ "$DRY" -eq 0 ] && [ -d /efi/EFI/Linux ]; then
  say "boot entries for the existing snapshots"
  /usr/local/lib/dram/dram-snapshot ukis || failed "dram-snapshot ukis failed"
fi
exit "$RC"

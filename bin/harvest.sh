#!/usr/bin/env bash
# usage: harvest.sh <host-name> <ssh-target>
#
# Captures a host's current state into hosts/<name>/ over ssh: package lists
# (explicit, AUR, versions.lock), enabled systemd units, copies of the
# key /etc files and a hardware.txt (cpu, gpu, form, boot). The same files
# `dram harvest` writes from the host itself. Runs on the Mac.
#
#   -h, --help    this text
#
# needs:  ssh to the host; pacman, systemctl, tar and base64 on it
# alone:  yes: it writes hosts/<name>/ under the repo it sits in
# here:   by hand on the Mac; bin/check.sh §2 and §3 read what it writes
# exit:   0 ok · 1 ssh failed · 2 bad usage
# see:    docs/operations/releases/README.md, docs/records/handbook/02-first-login.md

# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT

case "${1:-}" in
  -h | --help)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac
set -euo pipefail

[ $# -eq 2 ] || {
  sed -n '2s/^# \{0,1\}//p' "$0" >&2
  exit 2
}
NAME="$1"
TARGET="$2"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$REPO/hosts/$NAME"

echo "==> harvesting $NAME from $TARGET"
mkdir -p "$DEST"/{packages,etc,systemd}

ssh "$TARGET" 'bash -s' <<'REMOTE' >/tmp/harvest-$$.tar.b64
set -e
H=$(mktemp -d)
mkdir -p "$H"/{packages,etc,systemd}

pacman -Qqe > "$H/packages/explicit.txt"
# -Qqm exits 1 when the set is empty (zero foreign packages since [dram]); that is a
# result, not a failure. No deps.txt: nothing reads it, and it is versions.lock minus
# explicit.txt anyway
pacman -Qqm > "$H/packages/aur.txt" || true
pacman -Q   > "$H/packages/versions.lock"

# list-unit-files --state=enabled omits template INSTANCES (ly@tty2, wg-quick@home
# show as `indirect`); their enablement symlinks in *.wants/ are the record.
# a plain ssh session has no user bus; point systemctl --user at the running
# user manager (a desktop host's user is logged in)
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
{
  systemctl list-unit-files --state=enabled --no-legend --no-pager 2>/dev/null | awk '{print $1}'
  find /etc/systemd/system \( -path '*.wants/*@*' -o -path '*.requires/*@*' \) -print 2>/dev/null | sed 's|.*/||'
} | sort -u > "$H/systemd/enabled-system.txt"
{
  systemctl --user list-unit-files --state=enabled --no-legend --no-pager 2>/dev/null | awk '{print $1}'
  find "$HOME/.config/systemd/user" \( -path '*.wants/*@*' -o -path '*.requires/*@*' \) -print 2>/dev/null | sed 's|.*/||'
} | sort -u > "$H/systemd/enabled-user.txt"
systemctl get-default > "$H/systemd/default-target.txt"

for f in /etc/fstab /etc/mkinitcpio.conf /etc/default/grub /etc/locale.gen \
         /etc/locale.conf /etc/vconsole.conf /etc/hostname /etc/pacman.conf; do
  [ -f "$f" ] && cp "$f" "$H/etc/$(basename "$f" | sed 's|^grub$|default-grub|')"
done
ls /etc/pacman.d/hooks/ > "$H/etc/pacman-hooks.txt" 2>/dev/null || true

{
  echo "hostname:   $(cat /etc/hostname)"
  echo "cpu:        $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | xargs)"
  echo "gpu:        $(lspci 2>/dev/null | grep -iE 'vga|3d' | cut -d: -f3- | xargs)"
  echo "kernel:     $(uname -r)"
  echo "boot mode:  $([ -d /sys/firmware/efi ] && echo UEFI || echo BIOS)"
  if grep -qs '^BOOTLOADER=systemd-boot' /etc/dram/install-facts.env; then
    BL="systemd-boot $(pacman -Q systemd 2>/dev/null | awk '{print $2}')"
  else
    BL=$(pacman -Q refind grub 2>/dev/null | paste -sd' ')
  fi
  echo "bootloader: ${BL:-unknown}"
  echo "esp:        $(findmnt -no SOURCE,TARGET,FSTYPE /efi 2>/dev/null || findmnt -no SOURCE,TARGET,FSTYPE /boot 2>/dev/null)"
  echo "session:    ${XDG_SESSION_TYPE:-unknown}"
  NIXBIN=$(command -v nix 2>/dev/null || ls /nix/var/nix/profiles/default/bin/nix "$HOME/.nix-profile/bin/nix" 2>/dev/null | head -1)
  echo "nix:        $([ -n "$NIXBIN" ] && "$NIXBIN" --version || echo 'not installed')"
  FORM=desktop; for b in /sys/class/power_supply/BAT*; do [ -e "$b" ] && FORM=laptop && break; done
  echo "form:       $FORM"
  echo
  lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,UUID
} > "$H/hardware.txt"

tar cz -C "$H" . | base64
REMOTE

# files the host no longer produces (a removed /etc/default/grub, a unit list)
# must not linger from an earlier harvest: replace the three subtrees
rm -rf "${DEST:?}"/{packages,etc,systemd}
mkdir -p "$DEST"/{packages,etc,systemd}
base64 -d </tmp/harvest-$$.tar.b64 | tar xz -C "$DEST"
rm -f /tmp/harvest-$$.tar.b64

echo "==> wrote:"
find "$DEST" -type f | sed "s|$REPO/||" | sort
echo "==> explicit=$(wc -l <"$DEST/packages/explicit.txt" | tr -d ' ')" \
  "aur=$(wc -l <"$DEST/packages/aur.txt" | tr -d ' ')"

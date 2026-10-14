#!/usr/bin/env bash
# usage: secureboot-test.sh --arm | --check | --dry-run
#
# Proves that the firmware enforces Secure Boot for the internal disk, not only that it
# reports "enabled": some firmware runs unsigned images anyway (MSI boards until the
# "Secure Boot Preset" is set to "Maximum Security": handbook 01 §2; sbctl's quirk
# FQ0001, which sbctl infers from the board model and cannot verify).
#   --arm     copies systemd's stock, unsigned systemd-bootx64.efi to
#             /efi/EFI/dramtest/test.efi, adds a firmware boot entry for it without
#             touching BootOrder (efibootmgr --create-only) and sets BootNext to it.
#             Then reboot: an enforcing firmware refuses the image (often with a
#             message: press Enter) and boots the normal entry instead.
#   --check   after that reboot: says which entry booted (BootCurrent), then removes
#             the test entry and the file. Exit 0 = refused (enforcing), 1 = the
#             unsigned image ran (not enforcing), 2 = not armed.
# The removable-media half needs no script: boot an unsigned ISO (the Arch ISO) from
# the firmware's boot menu; it must be refused. Run again after a BIOS update, a CMOS
# clear or "Load Defaults", which can reset the preset. Root, unless --dry-run.
#
#   --dry-run    print what --arm would do; change nothing
#   -h, --help   this text
#
# needs:  efibootmgr, systemd-boot's unsigned stub, an ESP at /efi; root unless --dry-run
# alone:  yes on any UEFI host with Secure Boot on
# here:   by hand, after secureboot-setup.sh and after any firmware change
# exit:   0 ok (--check: enforcing) · 1 a step failed (--check: not enforcing) · 2 bad usage or not armed
# see:    docs/security/boot-trust/secure-boot.md, docs/records/handbook/01-install.md §8,
#         docs/records/handbook/11-troubleshooting.md

# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT

MODE=""
for a in "$@"; do
  case "$a" in
    --arm) MODE=arm ;;
    --check) MODE=check ;;
    --dry-run) MODE=dry ;;
    -h | --help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      sed -n '2s/^# \{0,1\}//p' "$0" >&2
      exit 2
      ;;
  esac
done
[ -n "$MODE" ] || {
  sed -n '2s/^# \{0,1\}//p' "$0" >&2
  exit 2
}

set -uo pipefail
ESP=/efi
SRC=/usr/lib/systemd/boot/efi/systemd-bootx64.efi
DIR="$ESP/EFI/dramtest"
LABEL="dram Secure Boot test (unsigned)"
say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}
entry() { efibootmgr 2>/dev/null | sed -n "s/^Boot\([0-9A-F]\{4\}\)\*\{0,1\} $LABEL.*/\1/p" | head -1; }

if [ "$MODE" = dry ]; then
  echo "  [dry-run] install -D $SRC $DIR/test.efi   (unsigned: sbctl verify must say 'not signed')"
  echo "  [dry-run] efibootmgr --create-only --disk <the ESP's disk> --part <its number> --loader '\\EFI\\dramtest\\test.efi' --label '$LABEL'"
  echo "  [dry-run] efibootmgr --bootnext <that entry>; then reboot, then: sudo bash $0 --check"
  exit 0
fi
[ "$(id -u)" -eq 0 ] || die "run as root (sudo bash $0 $MODE)"
command -v efibootmgr >/dev/null || die "efibootmgr missing"

if [ "$MODE" = arm ]; then
  [ -f "$SRC" ] || die "$SRC missing (systemd)"
  part="$(findmnt -no SOURCE "$ESP")" || die "$ESP is not mounted"
  disk="/dev/$(lsblk -no PKNAME "$part")"
  num="$(cat "/sys/class/block/$(basename "$part")/partition")"
  [ -b "$disk" ] && [ -n "$num" ] || die "cannot tell the ESP's disk and partition number ($part)"
  install -D -m 0644 "$SRC" "$DIR/test.efi" || die "could not copy the test image"
  if command -v sbctl >/dev/null && ! sbctl verify "$DIR/test.efi" 2>&1 | grep -c 'not signed' >/dev/null; then
    rm -rf "$DIR"
    die "the test image is signed — the test would prove nothing"
  fi
  [ -z "$(entry)" ] || efibootmgr -q -b "$(entry)" -B
  efibootmgr -q --create-only --disk "$disk" --part "$num" --loader '\EFI\dramtest\test.efi' --label "$LABEL" --unicode \
    || die "efibootmgr could not add the test entry"
  e="$(entry)"
  [ -n "$e" ] || die "the test entry did not appear"
  efibootmgr -q --bootnext "$e" || die "could not set BootNext"
  ok "armed: Boot$e runs once at the next boot ($(efibootmgr | sed -n 's/^BootOrder: //p') unchanged)"
  echo "    reboot now (press Enter if the firmware reports an unsigned image), then: sudo bash $0 --check"
  exit 0
fi

# --check
e="$(entry)"
[ -n "$e" ] || {
  echo "not armed (no '$LABEL' entry): sudo bash $0 --arm, reboot, then --check" >&2
  exit 2
}
cur="$(efibootmgr | sed -n 's/^BootCurrent: //p')"
efibootmgr -q -b "$e" -B && rm -rf "$DIR" && say "test entry Boot$e and $DIR removed"
if [ "$cur" = "$e" ]; then
  printf '\033[1;31m[x]\033[0m the UNSIGNED test image booted (BootCurrent %s): the firmware does NOT enforce Secure Boot — handbook 01 §2 (MSI: Secure Boot Preset -> Maximum Security)\n' "$cur"
  exit 1
fi
ok "the firmware refused the unsigned image and booted Boot$cur instead: Secure Boot is enforced for the internal disk"

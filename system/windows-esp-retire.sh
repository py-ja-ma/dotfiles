#!/usr/bin/env bash
# usage: windows-esp-retire.sh [--dry-run]
#
# Takes Windows' boot files off Arch's ESP once Windows boots from its own
# (decisions/log.md#d65; install/windows/dram-windows/own-esp.ps1): Windows Setup
# had put \EFI\Microsoft on Arch's ESP, so Windows servicing wrote into Arch's boot partition.
# Only when Windows' own ESP (FAT label WIN-ESP) holds \EFI\Microsoft\Boot\bootmgfw.efi and a
# "Windows Boot Manager" NVRAM entry points at it: archives <ESP>/EFI/Microsoft to
# /var/lib/dram/backup/efi-microsoft-<stamp>.tar, removes it, and deletes every other
# "Windows Boot Manager" NVRAM entry (the one MSI's firmware re-adds for any ESP holding
# bootmgfw.efi, and the old drives'); then runs apply-refind.sh so the Windows tile starts
# Windows' own entry. Without WIN-ESP it changes nothing. Idempotent; an `ask` hook of
# `dram apply`. Root, unless --dry-run.
#
#   -n, --dry-run   print what would change
#   -h, --help      this text
#
# exit: 0 done or nothing to do · 1 not root, a check or a step failed · 2 bad usage
# rollback: tar -xf the archive into <ESP>/EFI/, then efibootmgr -c for its entry
# see: docs/platforms/windows/boot-guard.md, docs/platforms/arch/boot-chain.md

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
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}
[ "$(id -u)" -eq 0 ] || [ "$DRY" -eq 1 ] || die "run with sudo (or --dry-run)"
command -v efibootmgr >/dev/null || die "efibootmgr missing"

ESP="$(bootctl --print-esp-path 2>/dev/null || echo /efi)"
ARCH_PU="$(findmnt -no PARTUUID "$ESP" 2>/dev/null)"
# lsblk reads udev's database, so this works without root too (blkid would not, in a --dry-run)
WIN_DEV="$(readlink -f /dev/disk/by-label/WIN-ESP 2>/dev/null)"
WIN_PU=""
[ -b "$WIN_DEV" ] && WIN_PU="$(lsblk -dno PARTUUID "$WIN_DEV" 2>/dev/null)"
[ -n "$WIN_PU" ] || {
  ok "no WIN-ESP partition: Windows still boots from this ESP (own-esp.ps1 first); nothing changed"
  exit 0
}
[ -n "$ARCH_PU" ] && [ "${ARCH_PU,,}" != "${WIN_PU,,}" ] || die "WIN-ESP is this ESP ($ESP): refusing"

# Windows' own ESP must hold the boot manager, and an NVRAM entry must point at it
if [ "$(id -u)" -eq 0 ]; then
  mnt="$(mktemp -d)"
  trap 'mountpoint -q "$mnt" && umount "$mnt"; rmdir "$mnt" 2>/dev/null' EXIT
  mount -o ro "$WIN_DEV" "$mnt" 2>/dev/null || die "cannot mount WIN-ESP ($WIN_DEV) read-only"
  [ -f "$mnt/EFI/Microsoft/Boot/bootmgfw.efi" ] || die "WIN-ESP has no \\EFI\\Microsoft\\Boot\\bootmgfw.efi: refusing"
  umount "$mnt"
else
  echo "  [dry-run] not root: WIN-ESP's \\EFI\\Microsoft\\Boot\\bootmgfw.efi is checked on the real run"
fi
entries="$(efibootmgr -v 2>/dev/null | grep -i 'bootmgfw\.efi')"
keep="$(printf '%s\n' "$entries" | awk -v pu="$WIN_PU" 'tolower($0) ~ tolower(pu) { print substr($1, 5, 4); exit }')"
[ -n "$keep" ] || die "no NVRAM entry starts WIN-ESP's boot manager: boot Windows once, or create one, first"
ok "Windows boots from its own ESP (PARTUUID $WIN_PU, Boot$keep)"

# the copy on Arch's ESP: archived, then removed
if [ -d "$ESP/EFI/Microsoft" ]; then
  stamp="$(date +%Y%m%d-%H%M%S)"
  arc="/var/lib/dram/backup/efi-microsoft-$stamp.tar"
  if [ "$DRY" -eq 1 ]; then
    echo "  [dry-run] tar $ESP/EFI/Microsoft -> $arc; rm -r $ESP/EFI/Microsoft"
  else
    install -d -m 700 /var/lib/dram/backup || die "cannot create /var/lib/dram/backup"
    tar -C "$ESP/EFI" -cf "$arc" Microsoft || die "could not archive $ESP/EFI/Microsoft"
    # grep -c reads the whole listing: grep -q quits at the match, and tar's SIGPIPE then
    # fails the pipe under pipefail (it did on cabin, 2026-10-12)
    tar -tf "$arc" | grep -ci '^Microsoft/Boot/bootmgfw\.efi$' >/dev/null || die "the archive lacks bootmgfw.efi: kept $ESP/EFI/Microsoft"
    rm -r "$ESP/EFI/Microsoft" || die "could not remove $ESP/EFI/Microsoft"
    ok "$ESP/EFI/Microsoft archived to $arc and removed"
  fi
else
  ok "no EFI/Microsoft on $ESP"
fi

# every other Windows Boot Manager entry (Arch's ESP, the old drives): deleted
printf '%s\n' "$entries" | while read -r line; do
  [ -n "$line" ] || continue
  n="$(printf '%s' "$line" | awk '{ print substr($1, 5, 4) }')"
  [ "$n" = "$keep" ] && continue
  case "$n" in [0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) ;; *) continue ;; esac
  if [ "$DRY" -eq 1 ]; then
    echo "  [dry-run] efibootmgr -b $n -B   ($(printf '%s' "$line" | cut -c1-110))"
  else
    efibootmgr -q -b "$n" -B && ok "NVRAM entry Boot$n deleted (a Windows boot manager not on WIN-ESP)"
  fi
done

# the rEFInd tile follows Windows' own entry
if [ "$DRY" -eq 1 ]; then
  bash "$REPO/system/apply-refind.sh" --dry-run | grep -iE 'windows|refind.conf' || true
else
  bash "$REPO/system/apply-refind.sh" || die "apply-refind.sh failed"
fi

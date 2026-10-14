#!/usr/bin/env bash
# usage: bench-disk.sh --disk PATH [--dry-run] [--yes-wipe SERIAL]
#
# Lays out cabin's test-bench disk (the 2 TB SATA SSD, decisions/0017) from Arch, before
# Debian, Fedora and NixOS are installed onto it: GPT with a 2 GiB FAT32 boot partition the
# three share (label BENCH-ESP) and one empty partition per OS (GPT names bench-debian,
# bench-fedora, bench-nixos, ~500 GiB each) plus bench-spare (the rest, for the next one).
# Each installer then only picks its partition and mounts BENCH-ESP without formatting it
# (docs/platforms/bench/README.md). Wipes the disk: it is listed, a disk holding Windows or Arch's own ESP
# (/efi) is refused, and you type its serial. Root, unless --dry-run.
#
#   --disk PATH        the 2 TB SATA SSD, ideally /dev/disk/by-id/ata-...
#   --slot-gib N       size of each OS partition (default 500)
#   --yes-wipe SERIAL  confirm without the prompt (tests)
#   -n, --dry-run      print the commands
#   -h, --help         this text
#
# exit: 0 ok · 1 refused or a step failed · 2 bad usage
# see: decisions/0017-cabin-bench-layout.md, docs/platforms/bench/README.md

DISK="" YES="" DRY=0 SLOT=500
while [ $# -gt 0 ]; do
  case "$1" in
    --disk | --yes-wipe | --slot-gib)
      [ $# -ge 2 ] || {
        sed -n '2s/^# \{0,1\}//p' "$0" >&2
        exit 2
      }
      case "$1" in
        --disk) DISK="$2" ;;
        --yes-wipe) YES="$2" ;;
        --slot-gib) SLOT="$2" ;;
      esac
      shift 2
      continue
      ;;
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
  shift
done

set -uo pipefail
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
run() { if [ "$DRY" -eq 1 ]; then printf '  \033[2m[dry-run] %s\033[0m\n' "$*"; else "$@" || die "failed: $*"; fi; }
[ -n "$DISK" ] || {
  sed -n '2s/^# \{0,1\}//p' "$0" >&2
  exit 2
}
[[ "$SLOT" =~ ^[0-9]+$ ]] || die "--slot-gib wants a number"
[ "$(id -u)" -eq 0 ] || [ "$DRY" -eq 1 ] || die "run with sudo"
DEV="$(readlink -f "$DISK" 2>/dev/null)"
[ -n "$DEV" ] || DEV="$DISK"
[ -b "$DEV" ] || [ "$DRY" -eq 1 ] || die "no block device behind $DISK"

lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS "$DEV" 2>/dev/null
# never the disk Arch boots from, never Windows
own="$(findmnt -no SOURCE /efi 2>/dev/null)"
if [ -n "$own" ] && lsblk -lnpo NAME "$DEV" 2>/dev/null | grep -cx "$own" >/dev/null; then die "$DEV holds Arch's own /efi — wrong disk"; fi
if lsblk -lnpo FSTYPE "$DEV" 2>/dev/null | grep -ciE '^(ntfs|bitlocker)$' >/dev/null; then die "$DEV holds Windows — wrong disk"; fi
if lsblk -lnpo MOUNTPOINTS "$DEV" 2>/dev/null | grep -c . >/dev/null; then die "something on $DEV is mounted — unmount it first"; fi
serial="$(lsblk -dno SERIAL "$DEV" 2>/dev/null | tr -d ' ')"
[ -n "$serial" ] || serial="$(basename "$DEV")"
if [ "$YES" != "$serial" ] && [ "$DRY" -eq 0 ]; then
  read -rp "Type the serial of $DEV ($serial) to wipe it: " typed
  [ "$typed" = "$serial" ] || die "serial not typed — nothing changed"
fi

run sgdisk --zap-all "$DEV"
run sgdisk -n1:1MiB:+2GiB -t1:ef00 -c1:bench-esp \
  -n2:0:+"${SLOT}"GiB -t2:8304 -c2:bench-debian \
  -n3:0:+"${SLOT}"GiB -t3:8304 -c3:bench-fedora \
  -n4:0:+"${SLOT}"GiB -t4:8304 -c4:bench-nixos \
  -n5:0:0 -t5:8300 -c5:bench-spare "$DEV"
run udevadm settle
esp="$(lsblk -lnpo NAME,PARTLABEL "$DEV" 2>/dev/null | awk '$2=="bench-esp" {print $1}')"
[ "$DRY" -eq 1 ] && esp="${DEV}1"
[ -n "$esp" ] || die "bench-esp not found after sgdisk"
run mkfs.fat -F32 -n BENCH-ESP "$esp"
ok "bench disk ready: install Debian, Fedora, NixOS onto their partitions (docs/platforms/bench/README.md)"
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL "$DEV" 2>/dev/null

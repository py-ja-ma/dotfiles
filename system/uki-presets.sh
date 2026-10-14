#!/usr/bin/env bash
# usage: uki-presets.sh [--check | --dry-run]
#
# One UKI per installed kernel on a systemd-boot host (decisions/0011). The installer
# writes linux's preset; a kernel installed later — cabin's linux-lts, from
# packages/host-cabin.txt — gets mkinitcpio's template instead, which builds an
# initramfs in /boot that systemd-boot never shows. For every kernel in
# /usr/lib/modules/*/pkgbase whose preset has no default_uki, this writes the UKI
# preset (the shape install/arch-install.sh writes for linux), removes that kernel's
# /boot initramfs images, runs `mkinitcpio -p <kernel>` and, once the Secure Boot keys
# exist, signs the new UKIs and registers them with sbctl (re-signed on every update
# from then on). Idempotent: a `dram apply` hook (before secureboot-setup.sh) and
# bootstrap phase 5 run it; `dram doctor --boot` names it when a kernel has no UKI. A
# host without /efi/EFI/Linux (rEFInd) is left alone. Root, except --check.
#
#   --check      list the kernels without a UKI preset; change nothing (exit 1 if any)
#   --dry-run    print what would change
#   -h, --help   this text
#
# exit: 0 ok · 1 a step failed, not root, or (--check) a kernel has no UKI preset · 2 bad usage
# see: docs/records/handbook/11-troubleshooting.md, docs/platforms/arch/boot-chain.md, install/arch-install.sh

CHECK=0 DRY=0
for a in "$@"; do
  case "$a" in
    --check) CHECK=1 ;;
    --dry-run) DRY=1 ;;
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

set -uo pipefail
# overridable for a test in a temp dir
ESP="${DRAM_ESP:-/efi}"
PRESET_DIR="${DRAM_PRESET_DIR:-/etc/mkinitcpio.d}"
MODULES_DIR="${DRAM_MODULES_DIR:-/usr/lib/modules}"
BOOT="${DRAM_BOOT:-/boot}"
MKINITCPIO="${DRAM_MKINITCPIO:-mkinitcpio}"
SBCTL_KEY="${DRAM_SBCTL_KEY:-/var/lib/sbctl/keys/db/db.key}"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}

if [ ! -d "$ESP/EFI/Linux" ]; then
  say "no $ESP/EFI/Linux: not a UKI host, nothing to do"
  exit 0
fi

kernels="$(cat "$MODULES_DIR"/*/pkgbase 2>/dev/null | sort -u)"
[ -n "$kernels" ] || die "no kernel found ($MODULES_DIR/*/pkgbase)"
missing=""
for k in $kernels; do
  if grep -qE '^[[:space:]]*default_uki=' "$PRESET_DIR/$k.preset" 2>/dev/null; then
    say "$k: UKI preset in place"
  else
    missing="${missing:+$missing }$k"
  fi
done
[ -n "$missing" ] || exit 0

if [ "$CHECK" = 1 ]; then
  for k in $missing; do echo "$k: no UKI preset ($PRESET_DIR/$k.preset) — sudo bash $0"; done
  exit 1
fi
[ "$DRY" = 1 ] || [ "$(id -u)" -eq 0 ] || [ -n "${DRAM_PRESET_DIR:-}" ] || die "run as root (sudo bash $0)"

for k in $missing; do
  if [ "$DRY" = 1 ]; then
    echo "  [dry-run] $PRESET_DIR/$k.preset -> $ESP/EFI/Linux/arch-$k.efi (+ -fallback); rm $BOOT/initramfs-$k*.img; $MKINITCPIO -p $k$([ -f "$SBCTL_KEY" ] && echo '; sbctl sign -s both')"
    continue
  fi
  say "$k: UKI preset, then $MKINITCPIO -p $k"
  printf '%s\n' \
    "# written by system/uki-presets.sh: a UKI that systemd-boot finds by itself (decisions/0011)" \
    "ALL_kver=\"/boot/vmlinuz-$k\"" \
    "PRESETS=('default' 'fallback')" \
    "default_uki=\"/efi/EFI/Linux/arch-$k.efi\"" \
    "fallback_uki=\"/efi/EFI/Linux/arch-$k-fallback.efi\"" \
    "fallback_options=\"-S autodetect\"" >"$PRESET_DIR/$k.preset" || die "cannot write $PRESET_DIR/$k.preset"
  rm -f "$BOOT/initramfs-$k.img" "$BOOT/initramfs-$k-fallback.img"
  "$MKINITCPIO" -p "$k" || die "$MKINITCPIO -p $k failed — the preset is written; fix the error and run it again"
  if [ -f "$SBCTL_KEY" ]; then
    for f in "$ESP/EFI/Linux/arch-$k.efi" "$ESP/EFI/Linux/arch-$k-fallback.efi"; do
      [ -f "$f" ] && { sbctl sign -s "$f" >/dev/null || die "sbctl sign -s $f failed"; }
    done
  fi
done

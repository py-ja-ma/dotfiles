#!/usr/bin/env bash
# usage: secureboot-setup.sh [--dry-run] [--yes]
#
# Secure Boot with my own keys and Microsoft's (decisions/0011): sbctl keys, a
# signed systemd-boot (signed at the source, so `bootctl update` stays signed),
# signed UKIs registered for re-signing on every update (sbctl's own pacman and
# mkinitcpio hooks), and, only when the firmware is in Setup Mode,
# `sbctl enroll-keys --microsoft`. Never without Microsoft's keys: a GPU's option
# ROM and Windows' boot manager are signed by Microsoft, and cabin has no
# integrated GPU to fall back to (no picture at all). Out of Setup Mode it prints
# the firmware steps instead. Root, unless --dry-run.
#
#   -n, --dry-run   print what would change
#   -y, --yes       enroll without the confirmation prompt (VM tests)
#   -h, --help      this text
#
# needs:  sbctl, systemd-boot and UKIs at /efi (install/arch-install.sh's layout), python3;
#         root unless --dry-run
# alone:  yes on any systemd-boot + UKI host; put the firmware in Setup Mode to enroll
# here:   an `ask` hook of `dram apply` on metal hosts (system/apply-hooks.tsv), after
#         uki-presets.sh; `dram doctor --boot` checks the result
# exit:   0 ok (or nothing to do) · 1 not root or a step failed · 2 bad usage
# see:    docs/security/boot-trust/secure-boot.md, docs/records/handbook/01-install.md §2 and §8,
#         decisions/0011-disk-boot-secure-boot-snapshots.md

# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT

DRY=0 YES=0
for a in "$@"; do
  case "$a" in
    -n | --dry-run) DRY=1 ;;
    -y | --yes) YES=1 ;;
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
ESP=/efi
STUB=/usr/lib/systemd/boot/efi/systemd-bootx64.efi
say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}
run() { if [ "$DRY" -eq 1 ]; then printf '  \033[2m[dry-run] %s\033[0m\n' "$*"; else "$@"; fi; }
[ "$(id -u)" -eq 0 ] || [ "$DRY" -eq 1 ] || die "run with sudo"
[ -d "$ESP/loader" ] && [ -d "$ESP/EFI/Linux" ] || {
  warn "no systemd-boot + UKI layout at $ESP (an older rEFInd host?) — nothing to do (decisions/0011)"
  exit 0
}
command -v sbctl >/dev/null 2>&1 || [ "$DRY" -eq 1 ] || die "sbctl is not installed — dram apply installs it (packages/metal.txt)"

field() { sbctl status --json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('$1'))" 2>/dev/null; }
say "state: setup mode $(field setup_mode), secure boot $(field secure_boot), keys $([ -d /var/lib/sbctl/keys ] && echo yes || echo no)"

if [ ! -f /var/lib/sbctl/keys/db/db.key ]; then
  say "creating the keys (/var/lib/sbctl, its own subvolume; export it offline: docs/security/boot-trust/secure-boot.md)"
  run sbctl create-keys || die "sbctl create-keys failed"
fi

say "signing systemd-boot at the source and on the ESP"
run sbctl sign -s -o "$STUB.signed" "$STUB" || die "could not sign $STUB"
run bootctl install --esp-path="$ESP" --graceful >/dev/null 2>&1 || run bootctl update --esp-path="$ESP" --graceful
for f in "$ESP/EFI/systemd/systemd-bootx64.efi" "$ESP/EFI/BOOT/BOOTX64.EFI"; do
  [ -f "$f" ] && { run sbctl sign -s "$f" >/dev/null || die "could not sign $f"; }
done

say "signing the UKIs"
for f in "$ESP"/EFI/Linux/*.efi; do
  [ -e "$f" ] || continue
  case "$(basename "$f")" in
    arch-snap-*) run sbctl sign "$f" >/dev/null || warn "could not sign $f" ;; # rotate; not registered
    *) run sbctl sign -s "$f" >/dev/null || die "could not sign $f" ;;
  esac
done
[ "$DRY" -eq 1 ] || sbctl verify 2>&1 | sed 's/^/    /'

if [ "$(field setup_mode)" = True ]; then
  say "firmware is in Setup Mode: enroll our keys + Microsoft's (+ the firmware vendor's when it has a default db)"
  if [ "$YES" -ne 1 ]; then
    [ -t 0 ] || die "no terminal to confirm — re-run with --yes, or by hand"
    read -rp "    Enroll now? Type 'microsoft' to confirm Microsoft's keys go in too: " a
    [ "$a" = microsoft ] || die "not confirmed — nothing enrolled"
  fi
  # the firmware's own default db (vendor keys) exists only when the board exports
  # dbDefault; OVMF and some boards do not, and sbctl then refuses -f outright
  builtin=()
  if ls /sys/firmware/efi/efivars/dbDefault-* >/dev/null 2>&1; then
    builtin=(--firmware-builtin)
  else
    warn "the firmware exports no default db (dbDefault): enrolling ours + Microsoft's only"
  fi
  run sbctl enroll-keys --microsoft "${builtin[@]}" || die "enroll-keys failed — the firmware still has no PK; nothing is enforced"
  ok "enrolled. Reboot; the firmware enforces Secure Boot from now on (turn it on in setup if it does not)"
elif [ "$(field secure_boot)" = True ]; then
  ok "Secure Boot is on and everything here is signed"
else
  warn "Secure Boot is off and the firmware is not in Setup Mode. In firmware setup:"
  echo "    CSM off, Fast Boot off, TPM on; Secure Boot -> mode Custom -> clear the Platform Key"
  echo "    (Setup Mode; the item's name varies by board, docs/records/handbook/01-install.md §2),"
  echo "    save, boot here, run this again."
fi

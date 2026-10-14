#!/usr/bin/env bash
# usage: tpm2-enroll.sh [--dry-run | --reenroll]
#
# Laptop disk unlock (decisions/0011): enrolls the TPM2 into the LUKS2 volume
# install/arch-install.sh made, bound to PCR 7 (the Secure Boot state) and a
# PIN, adds a recovery key (printed once: put it in Proton Pass before
# anything else), tells the initramfs to try the TPM, and rebuilds the UKIs.
# The TPM2 keyslot gets priority `prefer`, so the boot asks the TPM before a
# plugged-in YubiKey (decisions/0019; install/lib/luks.sh), and rd.luks.options
# follows the volume's tokens (tries=0: the recovery prompt never runs out).
# The passphrase slot stays: remove it yourself only after the PIN and the
# recovery key have both unlocked a reboot. Needs Secure Boot on first (PCR 7
# is only meaningful then). Does nothing on a host without LUKS. Root, unless
# --dry-run.
#
#   -n, --dry-run   print what would change
#   --reenroll      after the TPM refused (PCR 7 changed: firmware, Secure Boot keys)
#                   and a YubiKey or the recovery key opened the disk: a new TPM2 slot
#                   for the new PCR 7, the old one wiped; unlocks with the one YubiKey
#                   plugged in, else asks for the passphrase or recovery key
#   -h, --help      this text
#
# needs:  cryptsetup with systemd-cryptenroll, a TPM2, mkinitcpio and UKIs,
#         install/lib/luks.sh; root unless --dry-run
# alone:  yes on a LUKS2 volume, with luks.sh beside it in install/lib/
# here:   an `ask` hook of `dram apply` on metal hosts (system/apply-hooks.tsv), after
#         secureboot-setup.sh and before fido2-enroll.sh
# exit:   0 ok (or nothing to do) · 1 not root or a step failed · 2 bad usage
# see:    docs/security/boot-trust/README.md, docs/security/identity/yubikeys.md,
#         decisions/0011-disk-boot-secure-boot-snapshots.md

# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT

DRY=0 REENROLL=0
case "${1:-}" in
  "") ;;
  -n | --dry-run) DRY=1 ;;
  --reenroll) REENROLL=1 ;;
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
FACTS=/etc/dram/install-facts.env
say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}
run() { if [ "$DRY" -eq 1 ]; then printf '  \033[2m[dry-run] %s\033[0m\n' "$*"; else "$@"; fi; }
# shellcheck source=../install/lib/luks.sh
. "$REPO/install/lib/luks.sh" || die "cannot read install/lib/luks.sh"
[ "$(id -u)" -eq 0 ] || [ "$DRY" -eq 1 ] || die "run with sudo"

luks_uuid="$(sed -n 's/^LUKS_UUID=//p' "$FACTS" 2>/dev/null)"
[ -n "$luks_uuid" ] || {
  ok "no LUKS volume recorded in $FACTS — nothing to enroll"
  exit 0
}
dev="/dev/disk/by-uuid/$luks_uuid"
[ -b "$dev" ] || [ "$DRY" -eq 1 ] || die "$dev not found"
command -v systemd-cryptenroll >/dev/null || die "systemd-cryptenroll missing"
[ -e /dev/tpmrm0 ] || [ "$DRY" -eq 1 ] || die "no TPM2 (/dev/tpmrm0) — turn the TPM on in firmware"
sb="$(od -An -t u1 /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c 2>/dev/null | awk '{print $NF}')"
[ "$sb" = 1 ] || [ "$DRY" -eq 1 ] || die "Secure Boot is off — run system/secureboot-setup.sh and enable it first (PCR 7 binds to it)"

if [ "$REENROLL" -eq 1 ]; then
  say "a new TPM2 slot for today's PCR 7 (the old one is wiped after it)"
  unlock=()
  if [ "$(fido2-token -L 2>/dev/null | grep -c .)" -eq 1 ]; then
    unlock=(--unlock-fido2-device=auto)
    echo "  unlocking with the YubiKey plugged in (its PIN, a touch); then the new TPM PIN twice"
  else echo "  unlocking with the passphrase or recovery key; then the new TPM PIN twice"; fi
  systemd-cryptenroll "$dev" ${unlock[@]+"${unlock[@]}"} --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes \
    || die "TPM2 re-enrolment failed (the old slot is still there)"
elif systemd-cryptenroll "$dev" 2>/dev/null | grep -q tpm2; then
  ok "a TPM2 slot already exists on $dev"
else
  say "recovery key (shown once — store it in Proton Pass NOW)"
  run systemd-cryptenroll --recovery-key "$dev" || die "recovery key enrolment failed"
  say "TPM2 + PIN, bound to PCR 7"
  run systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes "$dev" || die "TPM2 enrolment failed"
fi
pacman -Q tpm2-tss >/dev/null 2>&1 || warn "tpm2-tss is not installed — the initramfs cannot reach the TPM (packages/laptop.txt)"
if [ "$DRY" -eq 1 ]; then
  run cryptsetup config "$dev" --key-slot "<the TPM2 slot>" --priority prefer
  run "rd.luks.options= from the volume's tokens (install/lib/luks.sh), then mkinitcpio -P"
  exit 0
fi
# the TPM2 slot ahead of any YubiKey in the boot's generic token pass, after EVERY enrolment
luks_prefer_tpm2 "$dev" || die "cryptsetup config --priority prefer failed"
ok "TPM2 keyslot at priority prefer"
opts="$(luks_rd_options "$dev")" || die "cannot read the LUKS2 header"
luks_set_cmdline "$opts"
[ $? -le 1 ] || die "no rd.luks.options= in /etc/kernel/cmdline — not a volume install/arch-install.sh made?"
ok "rd.luks.options=$opts"
run mkinitcpio -P || die "mkinitcpio -P failed"
ok "done. Reboot: the PIN unlocks; test the recovery key once from the boot prompt too."
echo "    Only then, if you want no passphrase at all: sudo systemd-cryptenroll --wipe-slot=password $dev"

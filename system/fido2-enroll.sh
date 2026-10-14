#!/usr/bin/env bash
# usage: fido2-enroll.sh [--dry-run] [--label LABEL | --wipe LABEL]
#
# lantern's disk (decisions/0019): enrols the one YubiKey plugged in as a
# FIDO2 token of the LUKS2 volume install/arch-install.sh made (its FIDO2 PIN + a touch),
# beside TPM2 + PIN and the recovery key, so a TPM that refuses (a firmware or Secure Boot
# change) is answered by a YubiKey instead of the 48-character recovery key. Run it once
# per key, that key alone plugged in. It also keeps the volume in the shape the boot needs
# on every run: the TPM2 keyslot at priority `prefer`, libfido2 inside the UKI, and
# rd.luks.options=tpm2-device=auto,fido2-device=auto,tries=0,discard. Records which slot
# holds which key in /etc/dram/luks-fido2 (a lost key is wiped by its slot number). Does
# nothing on a host without LUKS. Root, unless --dry-run.
#
#   -n, --dry-run     print what would change
#   --label LABEL     the key's label in keys/ (primary, spare); asked when omitted
#   --wipe LABEL      a lost key: wipe its slot (from /etc/dram/luks-fido2; needs no
#                     key and no unlock) and forget it
#   -h, --help        this text
#
# needs:  cryptsetup with systemd-cryptenroll, libfido2, mkinitcpio and UKIs,
#         install/lib/luks.sh; one YubiKey with a FIDO2 PIN; root unless --dry-run
# alone:  yes on a LUKS2 volume with a TPM2 slot, with luks.sh beside it in install/lib/
# here:   an `ask` hook of `dram apply` on metal hosts (system/apply-hooks.tsv), after
#         tpm2-enroll.sh
# exit:   0 ok (or nothing to do) · 1 not root, no single key with a FIDO2 PIN, or a step
#         failed · 2 bad usage
# see:    docs/security/identity/yubikeys.md, decisions/0019-yubikeys.md

# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT

DRY=0 LABEL="" WIPE=0
while [ $# -gt 0 ]; do
  case "$1" in
    -n | --dry-run) DRY=1 ;;
    --label | --wipe)
      [ "$1" = --wipe ] && WIPE=1
      LABEL="${2:-}"
      [ -n "$LABEL" ] || {
        sed -n '2s/^# \{0,1\}//p' "$0" >&2
        exit 2
      }
      shift
      ;;
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
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FACTS="${DRAM_FACTS:-/etc/dram/install-facts.env}"
RECORD="${DRAM_LUKS_FIDO2:-/etc/dram/luks-fido2}"
UKI="${DRAM_UKI:-/efi/EFI/Linux/arch-linux.efi}"
say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}
dry() { printf '  \033[2m[dry-run] %s\033[0m\n' "$*"; }
# shellcheck source=../install/lib/luks.sh
. "$REPO/install/lib/luks.sh" || die "cannot read install/lib/luks.sh"
[ "$(id -u)" -eq 0 ] || [ "$DRY" -eq 1 ] || die "run with sudo"

luks_uuid="$(sed -n 's/^LUKS_UUID=//p' "$FACTS" 2>/dev/null)"
[ -n "$luks_uuid" ] || {
  ok "no LUKS volume recorded in $FACTS — nothing to enrol"
  exit 0
}
dev="/dev/disk/by-uuid/$luks_uuid"
[ -b "$dev" ] || [ -n "${DRAM_LUKS_JSON:-}" ] || [ "$DRY" -eq 1 ] || die "$dev not found"
# the LUKS header is root-only: a dry run as the user (dram apply --dry-run) stops before it
header_ok() { [ "$(id -u)" -eq 0 ] || [ -n "${DRAM_LUKS_JSON:-}" ]; }
if [ "$WIPE" -eq 1 ]; then
  slot="$(awk -F'\t' -v l="$LABEL" '$1 == l {print $2}' "$RECORD" 2>/dev/null | tail -1)"
  [ -n "$slot" ] || die "no slot recorded for '$LABEL' in $RECORD (sudo systemd-cryptenroll $dev lists the slots)"
  say "wiping '$LABEL' (slot $slot) from the disk"
  if [ "$DRY" -eq 1 ]; then
    dry "systemd-cryptenroll $dev --wipe-slot=$slot; drop '$LABEL' from $RECORD"
    exit 0
  fi
  luks_query "$dev" slots:systemd-fido2 | grep -qx "$slot" || die "slot $slot is not a FIDO2 slot any more — check: sudo systemd-cryptenroll $dev"
  systemd-cryptenroll "$dev" --wipe-slot="$slot" || die "systemd-cryptenroll --wipe-slot=$slot failed"
  tmp="$(mktemp)"
  awk -F'\t' -v l="$LABEL" '$1 != l' "$RECORD" >"$tmp" && cat "$tmp" >"$RECORD"
  rm -f "$tmp"
  ok "slot $slot wiped; '$LABEL' forgotten"
  # with the last key gone, fido2-device= leaves the command line again
  opts="$(luks_rd_options "$dev")" || die "cannot read the LUKS2 header"
  luks_set_cmdline "$opts" && { mkinitcpio -P >/dev/null || die "mkinitcpio -P failed"; }
  ok "rd.luks.options=$opts"
  exit 0
fi
pacman -Q libfido2 >/dev/null 2>&1 || die "libfido2 is not installed (packages/base.txt): dram apply first"
command -v fido2-token >/dev/null || die "fido2-token missing (libfido2)"

# rebuild the UKIs when libfido2 is missing from the live one (installing libfido2 does
# not trigger mkinitcpio's pacman hook; sd-encrypt copies it only when present)
uki_has_fido2() { lsinitcpio "$UKI" 2>/dev/null | grep -q 'usr/lib/libfido2\.so\.1'; }

# converge: the TPM2 slot first in the generic token pass, the kernel command line, the image
converge() {
  local opts changed=0
  header_ok || {
    dry "as root: TPM2 slot priority prefer, rd.luks.options from the header's tokens, libfido2 in the UKI"
    return 0
  }
  luks_prefer_tpm2 "$dev" "$DRY" || die "cryptsetup config --priority prefer failed"
  [ -n "$(luks_query "$dev" slots:systemd-tpm2)" ] && ok "TPM2 keyslot(s) at priority prefer"
  opts="$(luks_rd_options "$dev")" || die "cannot read the LUKS2 header"
  if [ "$DRY" -eq 1 ]; then
    dry "rd.luks.options=$opts in /etc/kernel/cmdline, then mkinitcpio -P if it changed"
    return 0
  fi
  luks_set_cmdline "$opts"
  case $? in
    0)
      ok "kernel command line: rd.luks.options=$opts"
      changed=1
      ;;
    1) ok "kernel command line already has rd.luks.options=$opts" ;;
    *) die "no rd.luks.options= in /etc/kernel/cmdline — not a volume install/arch-install.sh made?" ;;
  esac
  if [ "$changed" -eq 1 ] || ! uki_has_fido2; then
    say "rebuilding the UKIs (mkinitcpio -P)"
    mkinitcpio -P >/dev/null || die "mkinitcpio -P failed"
  fi
  if uki_has_fido2; then ok "libfido2 is inside $UKI"; else die "libfido2 is still missing from $UKI (lsinitcpio)"; fi
}

say "the YubiKey plugged in"
n="$(fido2-token -L 2>/dev/null | grep -c .)"
if [ "$n" -eq 0 ]; then
  if header_ok && [ -n "$(luks_query "$dev" slots:systemd-fido2)" ]; then
    ok "no key plugged in; the volume has $(luks_query "$dev" slots:systemd-fido2 | grep -c .) YubiKey slot(s) — checking the rest"
  else warn "no YubiKey plugged in: nothing enrolled (plug ONE in and run this again)"; fi
  converge
  exit 0
fi
[ "$n" -eq 1 ] || die "plug in exactly ONE YubiKey (fido2-token -L sees $n) — two at once make systemd-cryptenroll refuse"
hid="$(fido2-token -L | head -1 | cut -d: -f1)"
# a key with no FIDO2 PIN is enrolled without one, silently (systemd-cryptenroll drops the
# flag): refuse instead
if fido2-token -I "$hid" 2>/dev/null | grep -E '^options:' | grep -qE '(^|[ ,])clientPin(,|$)'; then
  ok "$hid has a FIDO2 PIN"
else
  die "this key has no FIDO2 PIN: ykman fido access change-pin (or dram yubikey enroll), then again"
fi
serial="$(ykman list --serials 2>/dev/null | head -1)"

labels="$(grep -vE '^[[:space:]]*(#|$)' "$REPO/keys/pam-u2f.txt" 2>/dev/null | cut -d: -f1)"
if [ -z "$LABEL" ] && [ "$DRY" -eq 1 ]; then
  LABEL=primary # a dry run only shows the steps
elif [ -z "$LABEL" ]; then
  [ -t 0 ] || die "--label <primary|spare> (no terminal to ask)"
  read -rp "    which key is this (${labels:+$(paste -sd/ - <<<"$labels")}, as in keys/)? " LABEL
fi
[[ $LABEL =~ ^[a-z][a-z0-9-]{0,15}$ ]] || die "label '$LABEL': lowercase letters, digits and dashes"
grep -qx "$LABEL" <<<"$labels" || warn "'$LABEL' is not in keys/pam-u2f.txt (yet?)"

fido2_slots() { luks_query "$dev" slots:systemd-fido2 | sort -n; }
old="$(awk -F'\t' -v l="$LABEL" '$1 == l {print $2}' "$RECORD" 2>/dev/null | tail -1)"
if [ -n "$old" ] && header_ok && fido2_slots | grep -qx "$old"; then
  ok "'$LABEL' is already slot $old ($RECORD); to re-enrol it: sudo systemd-cryptenroll $dev --wipe-slot=$old"
  converge
  exit 0
fi

say "enrolling '$LABEL'${serial:+ (serial $serial)}: the TPM2 PIN (or the recovery key), then this key's PIN and two touches"
if [ "$DRY" -eq 1 ]; then
  dry "systemd-cryptenroll $dev --fido2-device=auto --fido2-with-client-pin=yes --fido2-with-user-presence=yes --fido2-with-user-verification=no"
  converge
  exit 0
fi
before="$(fido2_slots)"
enrol() { systemd-cryptenroll "$dev" "$@" --fido2-device=auto --fido2-with-client-pin=yes --fido2-with-user-presence=yes --fido2-with-user-verification=no; }
if [ -n "$(luks_query "$dev" slots:systemd-tpm2)" ]; then
  enrol --unlock-tpm2-device=auto || {
    warn "the TPM did not unlock it — the passphrase or recovery key instead"
    enrol || die "systemd-cryptenroll failed"
  }
else
  enrol || die "systemd-cryptenroll failed"
fi
slot="$(comm -13 <(printf '%s\n' "$before") <(fido2_slots) | head -1)"
[ -n "$slot" ] || die "no new FIDO2 slot appeared (systemd-cryptenroll $dev)"
tok="$(luks_query "$dev" "token:$slot")"
if ! grep -q '"fido2-clientPin-required": true' <<<"$tok" || ! grep -q '"fido2-up-required": true' <<<"$tok"; then
  systemd-cryptenroll "$dev" --wipe-slot="$slot" >/dev/null 2>&1
  die "slot $slot came out without PIN or touch (wiped again): $tok"
fi
install -d -m 0755 "$(dirname "$RECORD")"
printf '%s\t%s\t%s\t%s\n' "$LABEL" "$slot" "${serial:--}" "$(date +%F)" >>"$RECORD"
ok "'$LABEL' is LUKS slot $slot (PIN + touch), recorded in $RECORD"
converge

cat <<'RUNBOOK'

How lantern's disk asks from now on (docs/security/identity/yubikeys.md, "lantern's disk"):
  normal boot   keys unplugged; type the TPM PIN at "Please enter LUKS2 token PIN"
  TPM refuses   (after a firmware or Secure Boot change) plug in ONE key before power-on
                and type that key's FIDO2 PIN at the first prompt, then touch it; or type
                the TPM PIN, then the key's PIN at "security token PIN", then touch
  no key        at "security token PIN" type anything, wait 30 s: the recovery key prompt
  never         type the recovery key at a PIN prompt
  afterwards    sudo bash ~/git/dotfiles/system/tpm2-enroll.sh --reenroll
RUNBOOK

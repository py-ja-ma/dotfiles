# shellcheck shell=bash
# LUKS2 helpers for system/tpm2-enroll.sh and system/fido2-enroll.sh (decisions/0011,
# decisions/0019): the systemd tokens a volume holds, the rd.luks.options= they call for,
# the kernel command line edit, and the TPM2 keyslot's `prefer` priority. Sourced, never
# run. tests/yubikey-t0.sh points DRAM_LUKS_JSON at a saved header dump and DRAM_CMDLINE
# at a copy of /etc/kernel/cmdline.

# luks_meta <dev>: the volume's LUKS2 metadata as JSON
luks_meta() {
  if [ -n "${DRAM_LUKS_JSON:-}" ]; then cat "$DRAM_LUKS_JSON"; else cryptsetup luksDump --dump-json-metadata "$1"; fi
}

# luks_query <dev> <what>:
#   types          the token types, one per line (systemd-tpm2, systemd-fido2, systemd-recovery)
#   slots:<type>   the keyslots bound to tokens of that type
#   token:<slot>   the JSON of the token bound to that keyslot
#   priority:<slot> 0 ignore, 1 normal, 2 prefer
luks_query() {
  luks_meta "$1" | python3 -I -c '
import json, sys
d = json.load(sys.stdin)
what = sys.argv[1]
toks = d.get("tokens", {}).values()
if what == "types":
    for t in sorted({v.get("type", "") for v in toks}):
        print(t)
elif what.startswith("slots:"):
    for v in toks:
        if v.get("type") == what[6:]:
            print("\n".join(v.get("keyslots", [])))
elif what.startswith("token:"):
    for v in toks:
        if what[6:] in v.get("keyslots", []):
            print(json.dumps(v))
            break
elif what.startswith("priority:"):
    print(d.get("keyslots", {}).get(what[9:], {}).get("priority", 1))
' "$2"
}

# luks_rd_options <dev>: the rd.luks.options= value the volume's tokens call for: the TPM2
# stage, then the YubiKey stage, the recovery prompt without a limit
# (tries=0; the token stages count against tries=), and discard
luks_rd_options() {
  local types opts=""
  types="$(luks_query "$1" types)" || return 1
  grep -qx systemd-tpm2 <<<"$types" && opts="tpm2-device=auto,"
  grep -qx systemd-fido2 <<<"$types" && opts="${opts}fido2-device=auto,"
  [ -n "$opts" ] && opts="${opts}tries=0,"
  printf '%sdiscard\n' "$opts"
}

# luks_set_cmdline <options>: write rd.luks.options=<options> into the kernel command line
# file. Exit 0 = changed (rebuild the UKIs), 1 = already so, 2 = no rd.luks.options= there
luks_set_cmdline() {
  local f="${DRAM_CMDLINE:-/etc/kernel/cmdline}" cur
  grep -q 'rd\.luks\.options=' "$f" 2>/dev/null || return 2
  cur="$(tr ' ' '\n' <"$f" | sed -n 's/^rd\.luks\.options=//p' | head -1)"
  [ "$cur" = "$1" ] && return 1
  sed -i.dram-tmp "s#rd\.luks\.options=[^ ]*#rd.luks.options=$1#" "$f" && rm -f "$f.dram-tmp"
}

# luks_prefer_tpm2 <dev> [dry]: the `prefer` priority on every TPM2 keyslot, so the generic
# token pass asks the TPM before a plugged-in YubiKey: a TPM PIN sent to the key would spend
# one of its 8 FIDO2 PIN tries, and a TPM unlock never refills them. Re-enrolling the TPM
# appends its token after the YubiKeys', so this runs after every TPM enrolment
luks_prefer_tpm2() {
  local s
  for s in $(luks_query "$1" slots:systemd-tpm2); do
    [ "$(luks_query "$1" "priority:$s")" = 2 ] && continue
    if [ "${2:-0}" = 1 ]; then
      printf '  [dry-run] cryptsetup config %s --key-slot %s --priority prefer\n' "$1" "$s"
    else
      cryptsetup config "$1" --key-slot "$s" --priority prefer || return 1
    fi
  done
}

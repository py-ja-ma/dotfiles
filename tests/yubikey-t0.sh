#!/usr/bin/env bash
# usage: yubikey-t0.sh
#
# Test tier T0 for the YubiKeys (decisions/0019), any machine with bash, no key needed:
# system/yubikey-setup.sh against throwaway copies of Arch's PAM files (the pam_u2f
# line right after each password line, once; an older line replaced; polkit's copied
# from the vendor dir; a file without the anchor left alone; the key map off with
# nothing listed, ON only when the self-test passes, following keys/pam-u2f.txt once
# on without a touch, emptied by --off; a malformed credential or a missing module
# stops it before any write), then secrets-bootstrap.sh --register-yubikey on a copy
# of .sops.yaml, and bin/yubikey.sh's refusals. Changes nothing outside a temp dir.
# bin/check.sh runs it.
#
#   -h, --help    this text
#
# exit: 0 every check passed · 1 a check failed · 2 bad usage
# see: docs/security/identity/yubikeys.md

case "${1:-}" in
  "") ;;
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
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAILS=0
ok() { echo "ok   $1"; }
bad() {
  echo "FAIL $1${2:+ — $2}"
  FAILS=$((FAILS + 1))
}
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want '$3', got '$2'"; fi; }
me="$(id -un)"
LINE="$(grep -E '^auth[[:space:]].*pam_u2f\.so' "$REPO/system/pam-u2f.conf" | head -1)"
C1='AAAAbbbbCCCCdddd+/==,BBBBccccDDDD==,es256,+presence'
C2='EEEEffffGGGG==,HHHHiiii==,eddsa,+presence'

# a throwaway repo (the hook reads keys/ next to itself) and Arch's three PAM files
mkdir -p "$T/repo/system" "$T/repo/keys" "$T/pamd" "$T/vendor" "$T/etc"
cp "$REPO/system/yubikey-setup.sh" "$REPO/system/pam-u2f.conf" "$T/repo/system/"
: >"$T/repo/keys/pam-u2f.txt"
: >"$T/pam_u2f.so"
printf '#%%PAM-1.0\nauth\t\tinclude\t\tsystem-auth\naccount\t\tinclude\t\tsystem-auth\nsession\t\tinclude\t\tsystem-auth\nsession\t\toptional\tpam_systemd.so class=none\n' >"$T/pamd/sudo"
printf '#%%PAM-1.0\n\nauth       requisite    pam_nologin.so\nauth       include      system-local-login\naccount    include      system-local-login\nsession    include      system-local-login\npassword   include      system-local-login\n' >"$T/pamd/login"
printf '#%%PAM-1.0\n\nauth       include      system-auth\naccount    include      system-auth\npassword   include      system-auth\nsession    include      system-auth\n' >"$T/vendor/polkit-1"
setup() { # setup <selftest-command> [args...]
  local st="$1"
  shift
  DRAM_USER="$me" DRAM_PAMD="$T/pamd" DRAM_VENDOR_PAMD="$T/vendor" DRAM_ETC="$T/etc" \
    DRAM_PAM_U2F_SO="$T/pam_u2f.so" DRAM_U2F_SELFTEST="$st" bash "$T/repo/system/yubikey-setup.sh" "$@" >"$T/out" 2>&1
}
after() { awk -v a="$2" 'found { print; exit } $1 == "auth" && $2 == "include" && $3 == a { found = 1 }' "$T/pamd/$1"; }
u2f_lines() { grep -c 'pam_u2f\.so' "$T/pamd/$1"; }
mapline() { grep "^$me:" "$T/etc/u2f_mappings" 2>/dev/null; }

# --- the PAM lines -------------------------------------------------------------------
setup false
expect_eq "nothing listed: exit 0" "$?" 0
expect_eq "sudo: the pam_u2f line right after 'auth include system-auth'" "$(after sudo system-auth)" "$LINE"
expect_eq "login: right after 'auth include system-local-login'" "$(after login system-local-login)" "$LINE"
expect_eq "polkit-1: copied from the vendor dir, line after the password" "$(after polkit-1 system-auth)" "$LINE"
expect_eq "sudo: one pam_u2f line" "$(u2f_lines sudo)" 1
expect_eq "nothing listed: the map has no line for $me" "$(mapline)" ""
cp -R "$T/pamd" "$T/pamd.1"
setup false
if diff -r "$T/pamd" "$T/pamd.1" >/dev/null; then ok "a re-run changes no PAM file"; else bad "a re-run changes no PAM file"; fi
sed -i.x 's/ nouserok cue / nouserok /' "$T/pamd/sudo" && rm -f "$T/pamd/sudo.x"
setup false
expect_eq "an older pam_u2f line is replaced, not doubled" "$(u2f_lines sudo):$(after sudo system-auth)" "1:$LINE"
printf '#%%PAM-1.0\nauth include system-login\n' >"$T/pamd/sudo"
setup false
expect_eq "no anchor: exit 1" "$?" 1
expect_eq "no anchor: the file is left alone" "$(u2f_lines sudo)" 0
grep -q "no 'auth include system-auth' line" "$T/out" && ok "no anchor: says so" || bad "no anchor: says so"
cp "$T/pamd.1/sudo" "$T/pamd/sudo"

# --- the key map ---------------------------------------------------------------------
printf '# test\nprimary:%s\nspare:%s\n' "$C1" "$C2" >"$T/repo/keys/pam-u2f.txt"
setup false
expect_eq "listed, self-test fails: exit 0" "$?" 0
expect_eq "listed, self-test fails: still off" "$(mapline)" ""
grep -q 'NOT switched on' "$T/out" && ok "listed, self-test fails: says so" || bad "listed, self-test fails: says so"
setup true
expect_eq "self-test passes: ON with both credentials" "$(mapline)" "$me:$C1:$C2"
printf 'spare:%s\n' "$C2" >"$T/repo/keys/pam-u2f.txt"
setup false
expect_eq "once on, a revoked key leaves the map without a touch" "$(mapline)" "$me:$C2"
setup false --off
expect_eq "--off: no line for $me" "$(mapline)" ""
printf 'spare:%s\nbroken line\n' "$C2" >"$T/repo/keys/pam-u2f.txt"
cp "$T/etc/u2f_mappings" "$T/map.before"
setup true
expect_eq "a malformed credential: exit 1" "$?" 1
if cmp -s "$T/map.before" "$T/etc/u2f_mappings"; then ok "a malformed credential: nothing written"; else bad "a malformed credential: nothing written"; fi
printf 'spare:%s\n' "${C2%+presence}+presence+pin" >"$T/repo/keys/pam-u2f.txt"
setup true
expect_eq "a +pin credential (ly would type the password as the PIN): exit 1" "$?" 1
if cmp -s "$T/map.before" "$T/etc/u2f_mappings"; then ok "a +pin credential: nothing written"; else bad "a +pin credential: nothing written"; fi
printf 'spare:%s\n' "$C2" >"$T/repo/keys/pam-u2f.txt"
rm -f "$T/pam_u2f.so"
cp -R "$T/pamd" "$T/pamd.2"
setup true
expect_eq "pam_u2f.so missing: exit 1" "$?" 1
if diff -r "$T/pamd" "$T/pamd.2" >/dev/null; then ok "pam_u2f.so missing: no PAM file touched"; else bad "pam_u2f.so missing: no PAM file touched"; fi

# --- the pam_u2f line itself -----------------------------------------------------------
for w in 'module_unknown=ignore' 'nouserok' 'authfile=/etc/dram/u2f_mappings' 'origin=pam://dram' 'appid=pam://dram'; do
  case "$LINE" in *"$w"*) ok "the line has $w" ;; *) bad "the line has $w" ;; esac
done
# ly answers EVERY hidden prompt with the password: a PIN prompt would spend FIDO2 PIN tries
case "$LINE" in *pinverification=1* | *userverification=1* | *interactive* | *manual*) bad "the line asks for no PIN, ENTER or manual step" ;; *) ok "the line asks for no PIN, ENTER or manual step" ;; esac
expect_eq "bin/yubikey.sh enrols with the line's origin" "$(sed -n 's/^ORIGIN=//p' "$REPO/bin/yubikey.sh")" "$(printf '%s\n' "$LINE" | grep -oE 'origin=[^ ]+' | cut -d= -f2)"

# --- secrets-bootstrap.sh --register-yubikey ---------------------------------------------
mkdir -p "$T/s/system"
cp "$REPO/system/secrets-bootstrap.sh" "$T/s/system/"
printf 'keys:\n  # host: cabin\n  - &cabin age1REPLACE\ncreation_rules:\n  - path_regex: ^secrets/.*\\.yaml$\n    key_groups:\n      - age:\n          - *cabin\n' >"$T/s/.sops.yaml"
K1="age1yubikey1$(printf 'q%.0s' $(seq 1 59))"
K2="age1yubikey1$(printf 'p%.0s' $(seq 1 59))"
reg() { bash "$T/s/system/secrets-bootstrap.sh" --register-yubikey "$@" >/dev/null 2>&1; }
reg primary "$K1"
expect_eq "register: exit 0" "$?" 0
reg spare "$K2"
expect_eq "register: the anchors, in order" "$(grep -E '^  - &yk_' "$T/s/.sops.yaml" | awk '{print $2}' | paste -sd' ' -)" "&yk_primary &yk_spare"
expect_eq "register: the age list" "$(grep -E '^          - \*' "$T/s/.sops.yaml" | awk '{print $2}' | paste -sd' ' -)" "*cabin *yk_primary *yk_spare"
expect_eq "register: markers sit above creation_rules" "$(awk '/^creation_rules:/ {print prev} {prev = $0}' "$T/s/.sops.yaml")" "  - &yk_spare $K2"
cp "$T/s/.sops.yaml" "$T/s/before"
reg primary "$K1"
expect_eq "register again: exit 0" "$?" 0
if cmp -s "$T/s/before" "$T/s/.sops.yaml"; then ok "register again: no change"; else bad "register again: no change"; fi
reg primary "$K2"
expect_eq "a label with a different recipient: refused" "$?" 1
reg Primary "$K1"
expect_eq "a bad label: refused" "$?" 1
reg nano age1yubikey1short
expect_eq "a malformed recipient: refused" "$?" 1
cp "$T/s/.sops.yaml" "$T/s/before.tag"
reg tagged "age1tag1$(printf 'z%.0s' $(seq 1 59))"
expect_eq "the next plugin's age1tag1 recipient: accepted" "$?" 0
cp "$T/s/before.tag" "$T/s/.sops.yaml"
if cmp -s "$T/s/before" "$T/s/.sops.yaml"; then ok "refusals change nothing"; else bad "refusals change nothing"; fi

# --- lantern's disk: install/lib/luks.sh and system/fido2-enroll.sh's refusals ------------
# a LUKS2 header dump the way cryptsetup luksDump --dump-json-metadata prints the parts read
# here (keyslot priority 2 = prefer, absent = normal; checked against cryptsetup 2.8.8)
meta() { # meta <tokens-json> [<keyslot-1-priority>]
  printf '{"keyslots":{"0":{"type":"luks2"},"1":{"type":"luks2"%s},"2":{"type":"luks2"}},"tokens":{%s}}\n' "${2:+,\"priority\":$2}" "$1" >"$T/meta.json"
}
TPM='"0":{"type":"systemd-tpm2","keyslots":["1"]}'
FIDO='"1":{"type":"systemd-fido2","keyslots":["2"],"fido2-clientPin-required":true,"fido2-up-required":true}'
lib() { DRAM_LUKS_JSON="$T/meta.json" DRAM_CMDLINE="$T/cmdline" bash -c '. "$1"; shift; "$@"' _ "$REPO/install/lib/luks.sh" "$@"; }
meta ""
expect_eq "luks: no tokens -> discard" "$(lib luks_rd_options x)" "discard"
meta "$TPM"
expect_eq "luks: TPM2 -> tpm2, tries=0" "$(lib luks_rd_options x)" "tpm2-device=auto,tries=0,discard"
meta "$TPM,$FIDO" 2
expect_eq "luks: TPM2 + YubiKey -> both stages, tries=0" "$(lib luks_rd_options x)" "tpm2-device=auto,fido2-device=auto,tries=0,discard"
expect_eq "luks: the TPM2 keyslot" "$(lib luks_query x slots:systemd-tpm2)" 1
expect_eq "luks: priority prefer read as 2" "$(lib luks_query x priority:1)" 2
expect_eq "luks: an already preferred slot is left alone" "$(lib luks_prefer_tpm2 x 1)" ""
meta "$TPM,$FIDO"
expect_eq "luks: a normal TPM2 slot gets prefer" "$(lib luks_prefer_tpm2 x 1 | grep -c 'key-slot 1 --priority prefer')" 1
printf 'rd.luks.name=U=dram-sys rd.luks.options=tpm2-device=auto,discard root=/dev/mapper/dram-sys rw resume=/dev/mapper/dram-sys\n' >"$T/cmdline"
lib luks_set_cmdline "tpm2-device=auto,fido2-device=auto,tries=0,discard"
expect_eq "luks: cmdline changed (exit 0)" "$?" 0
expect_eq "luks: only rd.luks.options= changed" "$(cat "$T/cmdline")" "rd.luks.name=U=dram-sys rd.luks.options=tpm2-device=auto,fido2-device=auto,tries=0,discard root=/dev/mapper/dram-sys rw resume=/dev/mapper/dram-sys"
lib luks_set_cmdline "tpm2-device=auto,fido2-device=auto,tries=0,discard"
expect_eq "luks: cmdline already so (exit 1)" "$?" 1
printf 'root=UUID=x rw\n' >"$T/cmdline"
lib luks_set_cmdline discard
expect_eq "luks: no rd.luks.options= (exit 2)" "$?" 2

mkdir -p "$T/stub"
printf '#!/bin/sh\n[ "${STUB_FIDO2_PKG:-1}" = 1 ]\n' >"$T/stub/pacman"
cat >"$T/stub/fido2-token" <<'STUB'
#!/bin/sh
case "$1" in
  -L) i=0; while [ "$i" -lt "${STUB_KEYS:-1}" ]; do echo "/dev/hidraw$i: vendor=0x1050, product=0x0407 (Yubico YubiKey OTP+FIDO+CCID)"; i=$((i + 1)); done ;;
  -I) if [ "${STUB_PIN:-1}" = 1 ]; then echo "options: rk, up, noplat, credMgmt, clientPin, largeBlobs"; else echo "options: rk, up, noplat, credMgmt, noclientPin"; fi ;;
esac
STUB
chmod +x "$T/stub/pacman" "$T/stub/fido2-token"
printf 'LUKS_UUID=11111111-2222-3333-4444-555555555555\n' >"$T/facts"
fe() { env PATH="$T/stub:$PATH" DRAM_FACTS="$T/facts" DRAM_LUKS_JSON="$T/meta.json" DRAM_LUKS_FIDO2="$T/luks-fido2" \
  DRAM_UKI="$T/none.efi" "$@" bash "$REPO/system/fido2-enroll.sh" --dry-run --label primary >"$T/out" 2>&1; }
meta "$TPM"
: >"$T/facts.none"
env PATH="$T/stub:$PATH" DRAM_FACTS="$T/facts.none" bash "$REPO/system/fido2-enroll.sh" --dry-run >"$T/out" 2>&1
expect_eq "fido2-enroll: no LUKS recorded -> exit 0" "$?" 0
fe STUB_FIDO2_PKG=0
expect_eq "fido2-enroll: libfido2 missing -> exit 1" "$?" 1
fe STUB_KEYS=2
expect_eq "fido2-enroll: two keys plugged in -> exit 1" "$?" 1
grep -q 'exactly ONE' "$T/out" && ok "fido2-enroll: two keys: says so" || bad "fido2-enroll: two keys: says so"
fe STUB_PIN=0
expect_eq "fido2-enroll: a key without a FIDO2 PIN -> exit 1 (systemd would enrol it PIN-less)" "$?" 1
fe STUB_KEYS=0
expect_eq "fido2-enroll: no key plugged in -> exit 0 with a warning" "$?:$(grep -c 'no YubiKey plugged in' "$T/out")" "0:1"
fe
expect_eq "fido2-enroll: one key with a PIN -> the dry-run enrolment" "$?:$(grep -c 'fido2-with-client-pin=yes --fido2-with-user-presence=yes --fido2-with-user-verification=no' "$T/out")" "0:1"
printf 'primary\t2\t12345678\t2026-10-11\n' >"$T/luks-fido2"
env PATH="$T/stub:$PATH" DRAM_FACTS="$T/facts" DRAM_LUKS_JSON="$T/meta.json" DRAM_LUKS_FIDO2="$T/luks-fido2" \
  bash "$REPO/system/fido2-enroll.sh" --dry-run --wipe primary >"$T/out" 2>&1
expect_eq "fido2-enroll --wipe: the recorded slot" "$?:$(grep -c 'wipe-slot=2' "$T/out")" "0:1"
env PATH="$T/stub:$PATH" DRAM_FACTS="$T/facts" DRAM_LUKS_JSON="$T/meta.json" DRAM_LUKS_FIDO2="$T/luks-fido2" \
  bash "$REPO/system/fido2-enroll.sh" --dry-run --wipe spare >"$T/out" 2>&1
expect_eq "fido2-enroll --wipe: an unrecorded label -> exit 1" "$?" 1

# --- bin/yubikey.sh ------------------------------------------------------------------------
HOME="$T/home" bash "$REPO/bin/yubikey.sh" enroll >/dev/null 2>&1
expect_eq "yubikey enroll without a label: exit 2" "$?" 2
HOME="$T/home" bash "$REPO/bin/yubikey.sh" enroll Primary >/dev/null 2>&1
expect_eq "yubikey enroll with a bad label: exit 1" "$?" 1
HOME="$T/home" bash "$REPO/bin/yubikey.sh" use spare >/dev/null 2>&1
expect_eq "yubikey use without a handle here: exit 1" "$?" 1
mkdir -p "$T/home/.ssh"
printf 'h\n' >"$T/home/.ssh/id_ed25519_sk_rk_dram-spare"
printf 'sk-ssh-ed25519@openssh.com AAAAtest\n' >"$T/home/.ssh/id_ed25519_sk_rk_dram-spare.pub"
HOME="$T/home" bash "$REPO/bin/yubikey.sh" use spare >/dev/null 2>&1
expect_eq "yubikey use spare: the signing link" "$(readlink "$T/home/.ssh/id_ed25519_sk"):$(readlink "$T/home/.ssh/id_ed25519_sk.pub")" "id_ed25519_sk_rk_dram-spare:id_ed25519_sk_rk_dram-spare.pub"

[ "$FAILS" -eq 0 ] || {
  echo "yubikey-t0: $FAILS check(s) failed" >&2
  exit 1
}
echo "yubikey-t0: all checks passed"

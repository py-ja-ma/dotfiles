#!/usr/bin/env bash
# usage: yubikey.sh <status | enroll <label> [--no-age] | ssh [<label>] | use <label>>
#
# The YubiKeys (decisions/0019); `dram yubikey` runs this. The public
# halves live in keys/ssh.pub, keys/pam-u2f.txt and .sops.yaml, committed on the Mac;
# nothing here writes the repo. Runs as the login user on an Arch host, never root.
#
#   status               what keys/ lists, the YubiKeys plugged in, and this host: the
#                        SSH handles, the signing link, sshd's keys file, the second
#                        factor (the full check is `dram doctor`)
#   enroll <label>       once per YubiKey, on an Arch host with the desktop role, that
#                        key plugged in alone: sets its FIDO2 PIN if unset, creates the
#                        resident SSH key (application ssh:dram-<label>), the pam-u2f
#                        credential (origin pam://dram) and, unless --no-age, an age
#                        identity in a PIV slot; prints the lines to commit on the Mac.
#                        Labels: primary, spare (lowercase, digits, dashes)
#   ssh [<label>]        once per host: copy the resident SSH handles off the plugged-in
#                        key (ssh-keygen -K, asks for its FIDO2 PIN) into ~/.ssh and link
#                        ~/.ssh/id_ed25519_sk to <label>'s (default: the first in
#                        keys/ssh.pub whose handle is here)
#   use <label>          point ~/.ssh/id_ed25519_sk (ssh's default security-key identity
#                        and git's signing key, modules/dev.nix) at another key's handle
#   -h, --help           this text
#
# needs:  ykman (yubikey-manager), OpenSSH with libfido2, fido2-token (libfido2), pamu2fcfg
#         (pam-u2f), age-plugin-yubikey for the age identity; the login user, not root
# alone:  yes, as a recipe: it writes nothing into the repo and prints the lines to commit
# here:   `dram yubikey` runs it; the lines it prints go into keys/ and .sops.yaml, which
#         harden.sh, yubikey-setup.sh and modules/dev.nix read
# exit:   0 ok · 1 a step failed or a tool is missing · 2 bad usage
# see:    docs/security/identity/yubikeys.md

# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSHD="$HOME/.ssh"
LINK="$SSHD/id_ed25519_sk"
LABEL_RE='^[a-z][a-z0-9-]{0,15}$'
ORIGIN=pam://dram

say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }
usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }
bad_usage() {
  sed -n '2s/^# \{0,1\}//p' "$0" >&2
  exit 2
}
need() {
  local t
  for t in "$@"; do have "$t" || die "$t is missing (packages/roles/desktop.txt: dram apply)"; done
}
ask_yes() { # ask_yes "question" -> 0 unless the answer starts with n; no terminal = no
  [ -t 0 ] || return 1
  local a
  read -rp "    $1 [Y/n] " a
  case "$a" in [nN]*) return 1 ;; *) return 0 ;; esac
}
handle_of() { printf '%s/id_ed25519_sk_rk_dram-%s' "$SSHD" "$1"; }
# labels <file>: the labels a keys/ file lists, in file order
ssh_labels() { grep -oE ' yubikey:[a-z][a-z0-9-]*$' "$REPO/keys/ssh.pub" 2>/dev/null | cut -d: -f2; }
u2f_labels() { grep -vE '^[[:space:]]*(#|$)' "$REPO/keys/pam-u2f.txt" 2>/dev/null | cut -d: -f1; }
sops_labels() { awk '$1 == "#" && $2 == "yubikey:" { print $3 }' "$REPO/.sops.yaml" 2>/dev/null; }
# key_of <label>: the "type base64" part of that label's line in keys/ssh.pub
key_of() { grep -E " yubikey:$1\$" "$REPO/keys/ssh.pub" 2>/dev/null | awk '{print $1, $2}'; }
plugged() { # one line per FIDO device; ykman adds the serial when it can see it
  if have ykman && ykman list 2>/dev/null | grep -c . >/dev/null; then ykman list 2>/dev/null; elif have fido2-token; then fido2-token -L 2>/dev/null; fi
}

cmd_status() {
  [ $# -eq 0 ] || bad_usage
  say "listed in the repo"
  printf '  keys/ssh.pub       %s\n' "$(ssh_labels | paste -sd' ' -)"
  printf '  keys/pam-u2f.txt   %s\n' "$(u2f_labels | paste -sd' ' -)"
  printf '  .sops.yaml         %s\n' "$(sops_labels | paste -sd' ' -)"
  say "plugged in here"
  local p
  p="$(plugged)"
  if [ -n "$p" ]; then printf '%s\n' "$p" | sed 's/^/  /'; else echo "  none (or no access: ykman/fido2-token see only keys at the local seat)"; fi
  # a wrong PIN spends one of 8 tries and only a right FIDO2 PIN gives them back: a stray
  # TPM PIN at lantern's disk prompt with a key plugged in is the usual culprit
  if [ -n "$p" ] && have ykman && [ "$(fido2-token -L 2>/dev/null | grep -c .)" -eq 1 ]; then
    local tries
    tries="$(ykman fido info 2>/dev/null | sed -n 's/^PIN:[[:space:]]*\([0-9][0-9]*\) attempt.*/\1/p')"
    if [ -n "$tries" ] && [ "$tries" -lt 8 ]; then warn "FIDO2 PIN: $tries of 8 tries left — type the PIN once to refill them: ykman fido access verify-pin"; elif [ -n "$tries" ]; then ok "FIDO2 PIN: 8 of 8 tries left"; fi
  fi
  say "this host ($(cat /etc/hostname 2>/dev/null || hostname), $(id -un))"
  local l h
  for l in $(ssh_labels); do
    h="$(handle_of "$l")"
    if [ -f "$h" ]; then ok "SSH handle for $l: $h"; else warn "no SSH handle for $l here (dram yubikey ssh, with that key plugged in)"; fi
  done
  if [ -L "$LINK" ]; then ok "$LINK -> $(readlink "$LINK") (ssh's default security key; git signs with it)"; elif [ -e "$LINK" ]; then warn "$LINK is a file, not a link to a dram handle"; else warn "no $LINK (dram yubikey ssh)"; fi
  if [ -f "/etc/ssh/authorized_keys.d/$(id -un)" ]; then ok "sshd: $(grep -c '^sk-' "/etc/ssh/authorized_keys.d/$(id -un)") YubiKey key(s) in /etc/ssh/authorized_keys.d/$(id -un)"; else warn "sshd: no /etc/ssh/authorized_keys.d/$(id -un) (sudo bash $REPO/system/harden.sh)"; fi
  if grep -q "^$(id -un):" /etc/dram/u2f_mappings 2>/dev/null; then ok "second factor ON for $(id -un)"; else warn "second factor off for $(id -un) (sudo bash $REPO/system/yubikey-setup.sh, at the machine)"; fi
}

cmd_enroll() {
  local label="" age=1 a
  for a in "$@"; do
    case "$a" in
      --no-age) age=0 ;;
      -*) bad_usage ;;
      *)
        [ -z "$label" ] || bad_usage
        label="$a"
        ;;
    esac
  done
  [ -n "$label" ] || bad_usage
  [[ $label =~ $LABEL_RE ]] || die "label '$label': lowercase letters, digits and dashes (primary, spare)"
  [ "$(id -u)" -ne 0 ] || die "run as your login user, not root"
  ssh_labels | grep -qx "$label" && die "keys/ssh.pub already lists '$label' — a new key gets a new label (or revoke the old one first: docs/security/identity/yubikeys.md)"
  need ssh-keygen pamu2fcfg fido2-token ykman
  [ "$age" -eq 0 ] || need age-plugin-yubikey
  local n
  n="$(fido2-token -L 2>/dev/null | grep -c .)"
  [ "$n" -eq 1 ] || die "plug in exactly ONE YubiKey (fido2-token -L sees $n FIDO device(s))"
  local info fw serial ktype=ed25519-sk
  info="$(ykman info 2>/dev/null)" || die "ykman info failed (is the key at this machine, not over ssh?)"
  fw="$(sed -n 's/^Firmware version:[[:space:]]*//p' <<<"$info")"
  serial="$(sed -n 's/^Serial number:[[:space:]]*//p' <<<"$info")"
  # ed25519-sk needs firmware 5.2.3; older FIDO2 keys get ecdsa-sk
  [ "$(printf '%s\n5.2.3\n' "${fw:-0}" | sort -V | head -1)" = 5.2.3 ] || ktype=ecdsa-sk
  ok "YubiKey ${serial:-?}, firmware ${fw:-?}: $ktype"

  say "1/5 the OTP application over USB"
  # a touch while nothing waits for one types a one-time password + Enter into whatever
  # has focus — at ly, hyprlock or a sudo prompt that is a wrong password (faillock)
  if grep -qE '^Yubico OTP[[:space:]]+Enabled' <<<"$info"; then
    if ask_yes "Switch OTP off on this key (a stray touch then types nothing)?"; then
      ykman config usb --disable OTP --force || die "ykman config usb --disable OTP failed"
      sleep 3 # the key re-enumerates
      ok "OTP off"
    else warn "OTP stays on: a touch with no request pending types a code + Enter"; fi
  else ok "OTP is off"; fi

  say "2/5 the FIDO2 PIN (resident SSH keys and the LUKS unlock need one; 8 wrong PINs lock FIDO2)"
  if ykman fido info 2>/dev/null | grep -ciE 'PIN:[[:space:]]*not set' >/dev/null; then
    ykman fido access change-pin || die "the FIDO2 PIN was not set"
  else ok "the FIDO2 PIN is set ($(ykman fido info 2>/dev/null | sed -n 's/^PIN:[[:space:]]*//p'))"; fi

  say "3/5 the SSH key on the YubiKey (PIN, then touch)"
  local h
  h="$(handle_of "$label")"
  mkdir -p "$SSHD" && chmod 700 "$SSHD"
  [ -e "$h" ] && die "$h exists already — move it away first"
  ssh-keygen -t "$ktype" -O resident -O "application=ssh:dram-$label" -C "yubikey:$label" -N "" -f "$h" || die "ssh-keygen -t $ktype failed"
  [ -e "$LINK" ] || cmd_use "$label"

  say "4/5 the pam-u2f credential (touch)"
  local cred
  cred="$(pamu2fcfg -n -o "$ORIGIN" -i "$ORIGIN")" || die "pamu2fcfg failed"
  cred="${cred#:}"
  [[ $cred == *",+presence" ]] || die "pamu2fcfg made '${cred##*,}' credentials; dram's needs exactly +presence (ly would type the password as a PIN)"

  local recipient=""
  if [ "$age" -eq 1 ]; then
    say "5/5 the age identity in a PIV slot (sops; PIV PIN once, a touch per decryption)"
    local piv
    piv="$(ykman piv info 2>/dev/null)" || die "ykman piv info failed: is pcscd running? (sudo systemctl enable --now pcscd.socket)"
    if grep -qi 'default PIN' <<<"$piv"; then
      echo "  the PIV PIN is the factory 123456: set your own (6-8 characters; Proton Pass)"
      ykman piv access change-pin || die "PIV PIN not changed"
    fi
    if grep -qi 'default PUK' <<<"$piv"; then
      echo "  the PIV PUK is the factory 12345678: set your own (Proton Pass)"
      ykman piv access change-puk || die "PIV PUK not changed"
    fi
    # age-plugin-yubikey 0.5.1 handles only a PIN-protected TDES management key; 5.7+
    # firmware ships an AES-192 default
    if grep -qi 'default Management key' <<<"$piv" || ! grep -qiE '^Management key algorithm:[[:space:]]*TDES' <<<"$piv"; then
      echo "  the PIV management key becomes a random TDES key the PIN protects"
      ykman piv access change-management-key -a TDES --protect || die "management key not changed"
    fi
    local idf="$HOME/.config/sops/age/yubikey-$label.txt" out
    mkdir -p "$(dirname "$idf")" && chmod 700 "$(dirname "$idf")"
    out="$(age-plugin-yubikey --generate --name "dram-$label" --pin-policy once --touch-policy always)" \
      || die "age-plugin-yubikey --generate failed (an RSA or Ed25519 key in another PIV slot breaks it: ykman piv info)"
    (umask 077 && printf '%s\n' "$out" >"$idf")
    # 0.5.x prints age1yubikey1…; the next release prints age1tag1…
    recipient="$(printf '%s\n' "$out" | grep -oE 'age1(yubikey|tag)1[02-9ac-hj-np-z]+' | head -1)"
    [ -n "$recipient" ] || die "no age recipient in age-plugin-yubikey's output (saved to $idf)"
    ok "identity stub: $idf (not secret; sops uses it with SOPS_AGE_KEY_FILE)"
  else say "5/5 skipped: no age identity (--no-age)"; fi

  say "enrolled '$label'${serial:+ (serial $serial)} — now in ~/git/dotfiles, here or on the Mac (lodge):"
  printf "  printf '%%s\\\\n' '%s yubikey:%s' >>keys/ssh.pub\n" "$(awk '{print $1, $2}' "$h.pub")" "$label"
  printf "  printf '%%s\\\\n' '%s:%s' >>keys/pam-u2f.txt\n" "$label" "$cred"
  [ -n "$recipient" ] && printf '  bash system/secrets-bootstrap.sh --register-yubikey %s %s\n' "$label" "$recipient"
  printf '  git add keys .sops.yaml && git commit -m "keys: enrol the %s YubiKey%s"\n' "$label" "${serial:+ ($serial)}"
  echo "  committed here: on the Mac git pull <user>@<this host>:git/dotfiles master. Then release (bin/release.sh),"
  echo "  and on each host: dram update; dram apply; dram yubikey ssh"
  echo "  lantern: sudo bash ~/git/dotfiles/system/fido2-enroll.sh (this key alone plugged in)"
  echo "  Proton Pass: this key's FIDO2 PIN, PIV PIN and PUK, its serial and label"
}

cmd_ssh() {
  [ $# -le 1 ] || bad_usage
  local want="${1:-}"
  [ -z "$want" ] || [[ $want =~ $LABEL_RE ]] || bad_usage
  [ "$(id -u)" -ne 0 ] || die "run as your login user, not root"
  need ssh-keygen
  local tmp f got=""
  tmp="$(mktemp -d)"
  say "downloading the resident SSH handles (FIDO2 PIN)"
  (cd "$tmp" && ssh-keygen -K -N '') || {
    rm -rf "$tmp"
    die "ssh-keygen -K failed (is a YubiKey plugged in at this machine?)"
  }
  mkdir -p "$SSHD" && chmod 700 "$SSHD"
  for f in "$tmp"/id_*_sk_rk_dram-*; do
    [ -e "$f" ] || continue
    case "$f" in *.pub) continue ;; esac
    local base l
    base="$(basename "$f")" l="${base#id_*_sk_rk_dram-}"
    install -m 0600 "$f" "$SSHD/$base" && install -m 0644 "$f.pub" "$SSHD/$base.pub"
    if [ "$(awk '{print $1, $2}' "$f.pub")" = "$(key_of "$l")" ]; then ok "$l: ~/.ssh/$base (matches keys/ssh.pub)"; else warn "$l: ~/.ssh/$base — not (yet) in keys/ssh.pub"; fi
    got="$got $l"
  done
  rm -rf "$tmp"
  [ -n "$got" ] || die "this YubiKey holds no dram SSH key (application ssh:dram-*) — dram yubikey enroll <label>"
  if [ -z "$want" ]; then
    for l in $(ssh_labels); do [ -f "$(handle_of "$l")" ] && want="$l" && break; done
    # shellcheck disable=SC2086 # $got is a space-separated label list
    [ -n "$want" ] || want="$(printf '%s\n' $got | head -1)"
  fi
  cmd_use "$want"
}

cmd_use() {
  [ $# -eq 1 ] || bad_usage
  [[ $1 =~ $LABEL_RE ]] || bad_usage
  local h
  h="$(handle_of "$1")"
  [ -f "$h" ] && [ -f "$h.pub" ] || die "no handle for '$1' here ($h) — dram yubikey ssh, with that key plugged in"
  if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then die "$LINK is a real file — move it away first"; fi
  if ! ln -sfn "$(basename "$h")" "$LINK" || ! ln -sfn "$(basename "$h").pub" "$LINK.pub"; then die "could not link $LINK"; fi
  ok "$LINK -> $(basename "$h"): ssh offers it by default, git signs with it"
  key_of "$1" | grep -q . || warn "'$1' is not in keys/ssh.pub: hosts' sshd and git's allowed_signers do not know it yet"
}

case "${1:-}" in
  -h | --help | help)
    usage
    exit 0
    ;;
  status)
    shift
    cmd_status "$@"
    ;;
  enroll)
    shift
    cmd_enroll "$@"
    ;;
  ssh)
    shift
    cmd_ssh "$@"
    ;;
  use)
    shift
    cmd_use "$@"
    ;;
  *) bad_usage ;;
esac

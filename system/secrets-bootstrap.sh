#!/usr/bin/env bash
# usage: secrets-bootstrap.sh [--register <host> <age1...> | --register-yubikey <label> <age1yubikey1...> | --init-borg | --verify] [--dry-run]
#
# The by-hand steps of the sops-nix runbook, made idempotent. Runs as the login user
# (never root), on the Arch hosts and on the Mac (bash 3.2). sops / age / age-keygen
# come from PATH (~/.nix-profile/bin, modules/dev.nix).
#
#   (no mode)                  host: create ~/.config/sops/age/keys.txt if missing
#                              (dir 0700, file 0600) and print the PUBLIC key
#   --register <host> <age1…>  Mac: write that host's public key into .sops.yaml
#                              (the `# host: <host>` marker + `&<host>` anchor);
#                              refuses a malformed key or a different real key
#   --register-yubikey <label> <age1yubikey1…|age1tag1…>
#                              Mac: add a YubiKey's age recipient (age-plugin-yubikey,
#                              decisions/0019) to .sops.yaml as `# yubikey: <label>` +
#                              `&yk_<label>`, and to the creation rule; refuses a
#                              malformed recipient or a label that has a different one
#   --init-borg                host, once both recipients are real: encrypt the
#                              current ~/.config/borgmatic/passphrase into
#                              secrets/pj.yaml as `borg_passphrase` (sops --encrypt
#                              from a 0600 temp file; the value is never printed)
#   --verify                   host: decrypt borg_passphrase from secrets/pj.yaml
#                              and compare its sha256 with the plaintext file;
#                              prints `==> match: secrets/pj.yaml#borg_passphrase == <path>` or MISMATCH
#   --dry-run                  with any mode: say what would change, change nothing
#   -h, --help                 this text
#
# needs:  sops, age and age-keygen on PATH; awk, sed, git; sha256sum or shasum
# alone:  yes, with your own .sops.yaml (a `# host:` marker and an anchor per recipient)
#         and your own secrets file in place of secrets/pj.yaml
# here:   by hand on a host and on the Mac (the handbook's chapter 8); `dram doctor`
#         checks the key's mode and the decrypted secret
# exit:   0 ok · 1 root, missing tool, mismatch, or refused key · 2 bad usage
# see:    docs/security/identity/secrets.md

# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYDIR="$HOME/.config/sops/age"
KEYFILE="$KEYDIR/keys.txt"
PLAIN="$HOME/.config/borgmatic/passphrase"
SOPS_CFG="$REPO/.sops.yaml"
SECRETS="$REPO/secrets/pj.yaml"
PLACEHOLDER="age1REPLACE"
AGE_RE='^age1[02-9ac-hj-np-z]{58}$'
# age-plugin-yubikey's recipient: a compressed P-256 point (33 bytes) in bech32;
# 0.5.x prints age1yubikey1…, its next release age1tag1…
YK_AGE_RE='^age1(yubikey|tag)1[02-9ac-hj-np-z]{59}$'
YK_LABEL_RE='^[a-z][a-z0-9-]{0,15}$'
# scratch dir for --init-borg (holds the plaintext for a moment); global so the
# EXIT trap still sees it after the function returns, on success or `die`.
TMPD=""
trap '[ -n "$TMPD" ] && rm -rf "$TMPD"' EXIT

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() {
  printf '\033[1;31m[!]\033[0m %s\n' "$*" >&2
  exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }
is_age_key() { [[ $1 =~ $AGE_RE ]]; }
mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
sha256_of() { # sha256 of a string, never of a file (so no path leaks either)
  if have sha256sum; then printf '%s' "$1" | sha256sum | cut -c1-64; else printf '%s' "$1" | shasum -a 256 | cut -c1-64; fi
}
# recipient_of <host>: the key on the `- &<host> …` line of .sops.yaml
recipient_of() { awk -v h="$1" '$1 == "-" && $2 == "&" h { print $3 }' "$SOPS_CFG"; }
# hosts: every `# host: <name>` marker in .sops.yaml
hosts() { awk '$1 == "#" && $2 == "host:" { print $3 }' "$SOPS_CFG"; }
# yubikeys: every `# yubikey: <label>` marker; yk_recipient_of <label>: its `&yk_<label>` key
yubikeys() { awk '$1 == "#" && $2 == "yubikey:" { print $3 }' "$SOPS_CFG"; }
yk_recipient_of() { awk -v h="yk_$1" '$1 == "-" && $2 == "&" h { print $3 }' "$SOPS_CFG"; }

[ "$(id -u)" != 0 ] || die "run as pj, not root (the key belongs to the user that runs dram switch)"
[ -f "$SOPS_CFG" ] || die "no $SOPS_CFG"

MODE=keygen DRY=0 REG_HOST="" REG_KEY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --register)
      MODE=register
      REG_HOST="${2:-}" REG_KEY="${3:-}"
      [ -n "$REG_HOST" ] && [ -n "$REG_KEY" ] || die "usage: --register <host> <age1...>"
      shift 2
      ;;
    --register-yubikey)
      MODE=register-yubikey
      REG_HOST="${2:-}" REG_KEY="${3:-}"
      [ -n "$REG_HOST" ] && [ -n "$REG_KEY" ] || die "usage: --register-yubikey <label> <age1yubikey1...>"
      shift 2
      ;;
    --init-borg) MODE=init-borg ;;
    --verify) MODE=verify ;;
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

# --- recipients ---------------------------------------------------------------
# all_recipients_real: every marked host has a real key; prints the comma list
all_recipients_real() {
  local h k list=""
  for h in $(hosts); do
    k="$(recipient_of "$h")"
    [ -n "$k" ] || die ".sops.yaml: marker '# host: $h' has no '&$h' anchor line under it"
    if [ "$k" = "$PLACEHOLDER" ] || ! is_age_key "$k"; then
      die "recipient for $h in .sops.yaml is still '$k' — run this script on $h, then on the Mac: --register $h <age1...>"
    fi
    list="${list:+$list,}$k"
  done
  [ -n "$list" ] || die ".sops.yaml has no '# host:' markers"
  # the YubiKeys (decisions/0019) are recipients too: either key can edit and re-key
  # the secrets on any machine with age-plugin-yubikey, no surviving host needed
  for h in $(yubikeys); do
    k="$(yk_recipient_of "$h")"
    [[ $k =~ $YK_AGE_RE ]] || die ".sops.yaml: '# yubikey: $h' has no valid '&yk_$h' recipient under it"
    list="$list,$k"
  done
  printf '%s\n' "$list"
}

# --- modes ----------------------------------------------------------------------
do_keygen() {
  have age-keygen || die "age-keygen not in PATH (age is in home.packages — dram switch, or pacman -S age)"
  local host
  host="$(cat /etc/hostname 2>/dev/null || hostname)" # the hosts ship no hostname binary
  if [ -f "$KEYFILE" ]; then
    say "age key already exists: $KEYFILE"
    [ "$(mode_of "$KEYDIR")" = 700 ] || { [ "$DRY" = 1 ] && say "would chmod 700 $KEYDIR" || chmod 700 "$KEYDIR"; }
    [ "$(mode_of "$KEYFILE")" = 600 ] || { [ "$DRY" = 1 ] && say "would chmod 600 $KEYFILE" || chmod 600 "$KEYFILE"; }
  else
    if [ "$DRY" = 1 ]; then
      say "would: mkdir -p $KEYDIR (0700); age-keygen -o $KEYFILE (0600)"
      return 0
    fi
    say "generating the age key for $host -> $KEYFILE"
    (umask 077 && mkdir -p "$KEYDIR")
    chmod 700 "$KEYDIR"
    (umask 077 && age-keygen -o "$KEYFILE" 2>/dev/null)
    chmod 600 "$KEYFILE"
  fi
  local pub
  pub="$(age-keygen -y "$KEYFILE")"
  printf '\npublic key for %s:\n  %s\n\n' "$host" "$pub"
  printf 'next, on the Mac:\n  bash system/secrets-bootstrap.sh --register %s %s\n' "$host" "$pub"
}

do_register() {
  local cur
  is_age_key "$REG_KEY" || die "not an age public key (age1 + 58 bech32 chars): '$REG_KEY'"
  grep -q "^  # host: $REG_HOST\$" "$SOPS_CFG" || die "no '# host: $REG_HOST' marker in .sops.yaml (hosts: $(hosts | paste -sd' ' -))"
  cur="$(recipient_of "$REG_HOST")"
  [ -n "$cur" ] || die "no '- &$REG_HOST …' line in .sops.yaml"
  if [ "$cur" = "$REG_KEY" ]; then
    say "$REG_HOST already registered with that key — nothing to do"
    return 0
  fi
  if [ "$cur" != "$PLACEHOLDER" ]; then
    die "$REG_HOST already has a different real key ($cur). Re-keying a host: edit .sops.yaml by hand, then 'sops updatekeys secrets/pj.yaml' from a host that still decrypts."
  fi
  if [ "$DRY" = 1 ]; then
    say "would set '&$REG_HOST' in .sops.yaml to $REG_KEY"
    return 0
  fi
  local tmp
  tmp="$(mktemp "$SOPS_CFG.XXXXXX")"
  awk -v h="$REG_HOST" -v k="$REG_KEY" '$1 == "-" && $2 == "&" h { $0 = "  - &" h " " k } { print }' "$SOPS_CFG" >"$tmp"
  cat "$tmp" >"$SOPS_CFG" # in place: keeps .sops.yaml's own mode (mktemp made $tmp 0600)
  rm -f "$tmp"
  say "registered $REG_HOST in .sops.yaml"
  printf '  git -C %s add .sops.yaml && git -C %s commit -m "sops: register %s"\n' "$REPO" "$REPO" "$REG_HOST"
  [ -f "$SECRETS" ] && say "secrets/pj.yaml exists: run 'sops updatekeys secrets/pj.yaml' on a host that decrypts, then commit"
  return 0
}

# A YubiKey's recipient goes in twice: a `# yubikey:` marker + `&yk_<label>` anchor at
# the end of `keys:`, and `*yk_<label>` at the end of the creation rule's age list.
do_register_yubikey() {
  local label="$REG_HOST" key="$REG_KEY" cur
  [[ $label =~ $YK_LABEL_RE ]] || die "label '$label': lowercase letters, digits and dashes (primary, spare)"
  [[ $key =~ $YK_AGE_RE ]] || die "not an age-plugin-yubikey recipient (age1yubikey1 or age1tag1 + 59 bech32 chars): '$key'"
  cur="$(yk_recipient_of "$label")"
  if [ "$cur" = "$key" ]; then
    say "yubikey $label already registered with that recipient — nothing to do"
    return 0
  fi
  [ -z "$cur" ] || die "yubikey $label already has a different recipient ($cur). Re-keying: edit .sops.yaml by hand, then 'sops updatekeys secrets/pj.yaml'."
  grep -q '^creation_rules:' "$SOPS_CFG" || die ".sops.yaml has no creation_rules: line"
  grep -qE '^          - \*' "$SOPS_CFG" || die ".sops.yaml: no '          - *<name>' line under the age list"
  if [ "$DRY" = 1 ]; then
    say "would add '# yubikey: $label' / '&yk_$label' $key to keys: and '*yk_$label' to the age list"
    return 0
  fi
  local tmp n
  tmp="$(mktemp "$SOPS_CFG.XXXXXX")"
  n="$(grep -cE '^          - \*' "$SOPS_CFG")"
  awk -v l="$label" -v k="$key" -v n="$n" '
    /^creation_rules:/ { printf "  # yubikey: %s\n  - &yk_%s %s\n", l, l, k }
    { print }
    /^          - \*/ && ++seen == n { printf "          - *yk_%s\n", l }' "$SOPS_CFG" >"$tmp"
  cat "$tmp" >"$SOPS_CFG" # in place: keeps .sops.yaml's own mode
  rm -f "$tmp"
  say "registered yubikey $label in .sops.yaml"
  printf '  git -C %s add .sops.yaml && git -C %s commit -m "sops: register the %s YubiKey"\n' "$REPO" "$REPO" "$label"
  [ -f "$SECRETS" ] && say "secrets/pj.yaml exists: run 'sops updatekeys secrets/pj.yaml' on a machine that decrypts, then commit"
  return 0
}

# decrypted_sha: sha256 of the borg_passphrase value inside secrets/pj.yaml
decrypted_sha() {
  local dec
  dec="$(SOPS_AGE_KEY_FILE="$KEYFILE" sops --decrypt --extract '["borg_passphrase"]' "$SECRETS")" \
    || die "sops could not decrypt $SECRETS with $KEYFILE (is this host a recipient? journalctl --user -u sops-nix)"
  sha256_of "$dec"
}

do_verify() {
  have sops || die "sops not in PATH"
  [ -f "$SECRETS" ] || die "$SECRETS does not exist yet (--init-borg)"
  [ -f "$KEYFILE" ] || die "$KEYFILE missing (run without flags first)"
  [ -f "$PLAIN" ] || die "$PLAIN missing — nothing to compare against (docs/operations/backups/README.md)"
  local a b
  a="$(decrypted_sha)"
  b="$(sha256_of "$(cat "$PLAIN")")"
  if [ "$a" = "$b" ]; then
    say "match: secrets/pj.yaml#borg_passphrase == $PLAIN"
  else
    die "MISMATCH: secrets/pj.yaml#borg_passphrase != $PLAIN"
  fi
}

do_init_borg() {
  have sops || die "sops not in PATH (it is in home.packages — dram switch)"
  [ -f "$KEYFILE" ] || die "$KEYFILE missing (run without flags first, then --register on the Mac)"
  if [ -f "$SECRETS" ]; then
    say "$SECRETS already exists — edit it with: sops secrets/pj.yaml ; check it with --verify"
    return 0
  fi
  [ -f "$PLAIN" ] || die "$PLAIN missing (docs/operations/backups/README.md custody)"
  [ "$(mode_of "$PLAIN")" = 600 ] || die "$PLAIN is $(mode_of "$PLAIN"), not 0600 — fix that first"
  local recips val tmp enc
  recips="$(all_recipients_real)"
  val="$(cat "$PLAIN")" # $(…) drops trailing newlines, exactly what borg does with a passcommand
  [ -n "$val" ] || die "$PLAIN is empty"
  case "$val" in *$'\n'*) die "$PLAIN has more than one line; borg only reads the first — fix the file first" ;; esac
  if [ "$DRY" = 1 ]; then
    say "would encrypt $PLAIN -> $SECRETS as borg_passphrase for: $recips"
    return 0
  fi
  TMPD="$(mktemp -d)"
  chmod 700 "$TMPD"
  tmp="$TMPD/pj.yaml" enc="$TMPD/pj.enc.yaml"
  (umask 077 && : >"$tmp")
  chmod 600 "$tmp"
  # YAML single-quoted scalar: only ' needs escaping (doubled); nothing else is
  # interpreted. Pattern/replacement via variables: bash 3.2 (the Mac) keeps
  # literal quotes inside ${var//"x"/"y"}, bash 5 does not.
  local q="'" qq="''"
  printf "borg_passphrase: '%s'\n" "${val//$q/$qq}" >"$tmp"
  unset val q qq
  # the temp file lives outside secrets/, so tell sops which .sops.yaml rule it
  # would match (sops >= 3.9: --filename-override); recipients are explicit anyway
  sops --encrypt --input-type yaml --output-type yaml --age "$recips" \
    --filename-override "$REPO/secrets/pj.yaml" "$tmp" >"$enc" \
    || die "sops --encrypt failed (nothing written to secrets/)"
  install -m 0644 "$enc" "$SECRETS"
  say "wrote $SECRETS (ciphertext, recipients: $(hosts | paste -sd' ' -))"
  do_verify
  if git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$REPO" add secrets/pj.yaml
    say "staged secrets/pj.yaml — the flake only sees tracked files; commit it:"
  else
    say "not a git checkout: git add secrets/pj.yaml by hand (the flake only sees tracked files), then:"
  fi
  printf '  git -C %s commit -m "secrets: borg_passphrase"\n' "$REPO"
}

case "$MODE" in
  keygen) do_keygen ;;
  register) do_register ;;
  register-yubikey) do_register_yubikey ;;
  init-borg) do_init_borg ;;
  verify) do_verify ;;
esac

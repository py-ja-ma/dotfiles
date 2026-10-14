#!/usr/bin/env bash
# usage: yubikey-setup.sh [--dry-run | --off]
#
# The YubiKey as the second factor on a desktop host (decisions/0019): writes the
# pam_u2f line of system/pam-u2f.conf right after the password line of
# /etc/pam.d/sudo, polkit-1 and login (ly, hyprlock and the console include login), and
# /etc/dram/u2f_mappings for this host's login from keys/pam-u2f.txt. The second factor
# switches on only after a listed key answers a test touch at this machine
# (system/u2f-selftest.py), so a host never asks for a key that cannot answer here;
# once on, a re-run follows keys/pam-u2f.txt (a revoked key's credential disappears)
# without a touch. A mistake here costs sudo, and root is locked. Root, unless --dry-run.
#
#   -n, --dry-run   print what would change
#   --off           switch the second factor off on this host (the map loses every
#                   line; the PAM lines stay and ask for nothing). Needs no key;
#                   without sudo, docs/security/identity/yubikeys.md has the
#                   break-glass from the ISO
#   -h, --help      this text
#
# env:    DRAM_USER (default: the sudo caller, else pj); tests/yubikey-t0.sh points
#         DRAM_PAMD, DRAM_VENDOR_PAMD, DRAM_ETC, DRAM_PAM_U2F_SO and DRAM_U2F_SELFTEST at a
#         temp dir (sudo's env_reset never passes them through)
# needs:  pam-u2f, libfido2, python3 (for u2f-selftest.py), keys/pam-u2f.txt; root
#         unless --dry-run
# alone:  yes, with your own credentials in keys/pam-u2f.txt and your own origin in
#         system/pam-u2f.conf; keep a root shell open while you test
# here:   an `ask` hook of `dram apply` for the desktop role (system/apply-hooks.tsv);
#         `dram doctor` ("yubikeys") says when the second factor is off
# exit:   0 ok (second factor on, or not yet: nothing listed / no key here) · 1 not root
#         or a step failed · 2 bad usage
# see:    docs/security/identity/yubikeys.md

# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT

DRY=0 OFF=0
case "${1:-}" in
  "") ;;
  -n | --dry-run) DRY=1 ;;
  --off) OFF=1 ;;
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
USERNAME="${DRAM_USER:-${SUDO_USER:-pj}}"
CREDS_SRC="$REPO/keys/pam-u2f.txt"
PAMD="${DRAM_PAMD:-/etc/pam.d}"
VENDOR_PAMD="${DRAM_VENDOR_PAMD:-/usr/lib/pam.d}"
ETC="${DRAM_ETC:-/etc/dram}"
MAP="$ETC/u2f_mappings"
MODULE="${DRAM_PAM_U2F_SO:-/usr/lib/security/pam_u2f.so}"
SELFTEST="${DRAM_U2F_SELFTEST:-python3 -I $REPO/system/u2f-selftest.py}"
# service -> the password line ours goes after
SERVICES="sudo:system-auth login:system-local-login polkit-1:system-auth"
RC=0
say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
dry() { printf '  \033[2m[dry-run] %s\033[0m\n' "$*"; }
[ "$(id -u)" -eq 0 ] || [ "$DRY" -eq 1 ] || [ -n "${DRAM_PAMD:-}" ] || {
  echo "Run with sudo: sudo bash $0 [--dry-run | --off]"
  exit 1
}

LINE="$(grep -E '^auth[[:space:]].*[[:space:]]pam_u2f\.so[[:space:]]' "$REPO/system/pam-u2f.conf" | head -1)"
[ -n "$LINE" ] || {
  warn "no pam_u2f.so line in system/pam-u2f.conf"
  exit 1
}
# creds: the credentials of keys/pam-u2f.txt (`<label>:<cred>` lines), one per line;
# a malformed line stops the hook before anything is written. Options are exactly
# +presence: a +pin or +verification credential makes pam_u2f ask for the FIDO2 PIN,
# which ly answers with the login password
CRED_RE='^[a-z][a-z0-9-]{0,15}:[A-Za-z0-9+/=_-]+,[A-Za-z0-9+/=_-]+,(es256|eddsa|rs256),\+presence$'
creds() { grep -vE '^[[:space:]]*(#|$)' "$CREDS_SRC" 2>/dev/null | cut -d: -f2-; }
bad="$(grep -vE '^[[:space:]]*(#|$)' "$CREDS_SRC" 2>/dev/null | grep -vE "$CRED_RE" || true)"
[ -z "$bad" ] || {
  warn "keys/pam-u2f.txt has a malformed line (want <label>:<KeyHandle>,<UserKey>,<CoseType>,+presence):"
  printf '      %s\n' "${bad:0:80}…"
  exit 1
}
# write_map <file> <with-line: 0|1>: the header, then this login's line when asked
write_map() {
  {
    echo "# written by dotfiles/system/yubikey-setup.sh from keys/pam-u2f.txt — do not hand-edit"
    echo "# (docs/security/identity/yubikeys.md). No line for a login = pam_u2f does not ask it (nouserok)."
    if [ "$2" -eq 1 ]; then printf '%s:%s\n' "$USERNAME" "$(creds | paste -sd: -)"; fi
  } >"$1"
}
active() { grep -q "^$USERNAME:" "$MAP" 2>/dev/null; }

if [ "$OFF" -eq 1 ]; then
  say "second factor OFF for $USERNAME on this host"
  tmp="$(mktemp)"
  write_map "$tmp" 0
  if install -d -m 0755 "$ETC" && install -m 0644 "$tmp" "$MAP"; then
    ok "$MAP has no line for $USERNAME: pam_u2f asks nothing (re-run without --off to switch it on)"
  else RC=1; fi
  rm -f "$tmp"
  exit "$RC"
fi

id "$USERNAME" >/dev/null 2>&1 || {
  warn "no user $USERNAME (DRAM_USER)"
  exit 1
}
# a pam_u2f line in a service whose module is missing would be ignored (module_unknown
# =ignore), but there is no reason to write one before the package is here
[ -f "$MODULE" ] || [ "$DRY" -eq 1 ] || {
  warn "pam_u2f.so is missing (pam-u2f, packages/roles/desktop.txt) — dram apply installs it first"
  exit 1
}

say "the pam_u2f line after the password line of sudo, login and polkit-1"
for pair in $SERVICES; do
  svc="${pair%%:*}" anchor="${pair#*:}" f="$PAMD/${pair%%:*}"
  # polkit ships its file in /usr/lib/pam.d; an /etc copy takes precedence
  src="$f"
  [ -f "$f" ] || src="$VENDOR_PAMD/$svc"
  if [ ! -f "$src" ]; then
    warn "$f missing — $svc gets no second factor"
    RC=1
    continue
  fi
  if ! grep -qE "^auth[[:space:]]+include[[:space:]]+$anchor([[:space:]]|\$)" "$src"; then
    warn "$src has no 'auth include $anchor' line to follow — left unchanged; $svc gets no second factor"
    RC=1
    continue
  fi
  tmp="$(mktemp)"
  # drop any older pam_u2f line, then put the current one right after the anchor
  awk -v a="$anchor" -v line="$LINE" '
    $0 ~ /[[:space:]]pam_u2f\.so([[:space:]]|$)/ && $1 !~ /^#/ { next }
    { print }
    !done && $1 == "auth" && $2 == "include" && $3 == a { print line; done = 1 }' "$src" >"$tmp"
  if cmp -s "$tmp" "$f" 2>/dev/null; then
    ok "$f has the pam_u2f line"
  elif [ "$DRY" -eq 1 ]; then
    dry "$f: the pam_u2f line after 'auth include $anchor'$([ "$src" = "$f" ] || echo " (copied from $src)")"
  else
    install -d -m 0755 "$ETC"
    [ -f "$f" ] && cp -a "$f" "$ETC/pam.d-$svc.bak-$(date +%Y%m%d-%H%M%S)"
    if install -m 0644 "$tmp" "$f"; then ok "$f: the pam_u2f line is in"; else
      warn "could not write $f"
      RC=1
    fi
  fi
  rm -f "$tmp"
done

say "the key map: $MAP"
n="$(creds | grep -c . || true)"
tmp="$(mktemp)"
if [ "$n" -eq 0 ]; then
  write_map "$tmp" 0
  if cmp -s "$tmp" "$MAP" 2>/dev/null; then
    ok "no YubiKey in keys/pam-u2f.txt yet — second factor off"
  elif [ "$DRY" -eq 1 ]; then dry "write $MAP without a line (no YubiKey listed yet)"; else
    if install -d -m 0755 "$ETC" && install -m 0644 "$tmp" "$MAP"; then
      ok "no YubiKey in keys/pam-u2f.txt — second factor off (docs/security/identity/yubikeys.md: enrol)"
    else RC=1; fi
  fi
elif active; then
  write_map "$tmp" 1
  if cmp -s "$tmp" "$MAP"; then
    ok "second factor on for $USERNAME ($n key(s))"
  elif [ "$DRY" -eq 1 ]; then dry "rewrite $MAP for $USERNAME ($n key(s), follows keys/pam-u2f.txt)"; else
    if install -m 0644 "$tmp" "$MAP"; then
      ok "second factor on for $USERNAME — the map follows keys/pam-u2f.txt again ($n key(s))"
    else RC=1; fi
  fi
elif [ "$DRY" -eq 1 ]; then
  dry "ask for a touch of a listed key, then write $MAP for $USERNAME ($n key(s))"
else
  # switching ON: prove a listed key answers here first, through pam_u2f itself
  write_map "$tmp" 1
  chmod 0644 "$tmp"
  # shellcheck disable=SC2086 # SELFTEST is a command line
  if $SELFTEST --authfile "$tmp" --user "$USERNAME"; then
    if install -d -m 0755 "$ETC" && install -m 0644 "$tmp" "$MAP"; then
      ok "second factor ON for $USERNAME: sudo, polkit, ly, hyprlock and the console ask for a touch after the password"
    else RC=1; fi
  else
    warn "second factor NOT switched on: no listed YubiKey answered at this machine."
    warn "plug one in here (not over ssh) and re-run: sudo bash $0"
  fi
fi
rm -f "$tmp"
exit "$RC"

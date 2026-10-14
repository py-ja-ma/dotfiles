#!/usr/bin/env bash
# usage: re-lab-setup.sh [--dry-run]
#
# The system half of the re-lab role (docs/toolchain/profiles/re-lab.md): the main user
# joins `uucp` (Arch's group for /dev/ttyUSB* and /dev/ttyACM*: UART consoles, the Pico
# serprog, a Bus Pirate), and system/udev/70-dram-re-lab.rules gives the user at the
# machine the USB flash programmers through `uaccess`. Idempotent; a `dram apply` role
# hook (system/apply-hooks.tsv). A group change takes effect at the next login.
# Root, unless --dry-run.
#
#   -n, --dry-run   print what would change
#   -h, --help      this text
#
# env: DRAM_USER (default: the sudo caller, else pj)
# exit: 0 ok · 1 not root or a step failed · 2 bad usage
# see: docs/toolchain/profiles/re-lab.md

DRY=0
case "${1:-}" in
  "") ;;
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

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USERNAME="${DRAM_USER:-${SUDO_USER:-pj}}"
RULES=/etc/udev/rules.d/70-dram-re-lab.rules
RC=0
say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
run() { if [ "$DRY" -eq 1 ]; then printf '  \033[2m[dry-run] %s\033[0m\n' "$*"; else "$@"; fi; }
[ "$(id -u)" -eq 0 ] || [ "$DRY" -eq 1 ] || {
  echo "Run with sudo: sudo bash $0 [--dry-run]"
  exit 1
}

say "serial ports: $USERNAME in uucp"
if ! id "$USERNAME" >/dev/null 2>&1; then
  warn "no user $USERNAME (DRAM_USER)"
  RC=1
elif id -nG "$USERNAME" | tr ' ' '\n' | grep -qx uucp; then
  ok "$USERNAME is in uucp"
else
  if run gpasswd -a "$USERNAME" uucp >/dev/null; then ok "$USERNAME added to uucp (next login)"; else
    warn "could not add $USERNAME to uucp"
    RC=1
  fi
fi

say "USB flash programmers: $RULES"
if [ -f "$RULES" ] && cmp -s "$REPO/system/udev/70-dram-re-lab.rules" "$RULES"; then
  ok "$RULES unchanged"
elif run install -Dm644 "$REPO/system/udev/70-dram-re-lab.rules" "$RULES"; then
  ok "$RULES installed"
  [ "$DRY" -eq 1 ] || udevadm control --reload 2>/dev/null || true
else
  warn "could not install $RULES"
  RC=1
fi
exit "$RC"

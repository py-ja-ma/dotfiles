#!/usr/bin/env bash
# usage: printing-setup.sh [--dry-run]
#
# Printing for the college role (docs/toolchain/profiles/college.md): CUPS answers through its socket
# (cups.socket enabled: it starts with the first print job or settings window), network
# printers that speak IPP Everywhere need no driver, and the settings window is
# system-config-printer (changes go through polkit, cups-pk-helper). Idempotent; a
# `dram apply` role hook (system/apply-hooks.tsv). Root, unless --dry-run.
#
#   -n, --dry-run   print what would change
#   -h, --help      this text
#
# exit: 0 ok · 1 not root, CUPS missing, or a step failed · 2 bad usage
# see: docs/toolchain/profiles/college.md

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
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}
# shellcheck source=install/lib/detect.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install/lib/detect.sh"
# a WSL clone prints from Windows: CUPS is left out there (packages/wsl-skip.tsv,
# decisions/0021), and the hook row is college,metal
if [ "$(detect_platform)" = wsl ]; then
  ok "WSL: no CUPS in the clone (Windows prints) — nothing to do"
  exit 0
fi
[ "$(id -u)" -eq 0 ] || [ "$DRY" -eq 1 ] || die "run with sudo (or --dry-run)"
command -v cupsd >/dev/null || [ "$DRY" -eq 1 ] || die "CUPS is not installed (packages/roles/college.txt: dram apply)"

if systemctl is-enabled -q cups.socket 2>/dev/null; then
  ok "cups.socket enabled"
elif [ "$DRY" -eq 1 ]; then
  echo "  [dry-run] systemctl enable --now cups.socket"
else
  systemctl enable --now cups.socket || die "could not enable cups.socket"
  ok "cups.socket enabled: printers in system-config-printer, or http://localhost:631"
fi

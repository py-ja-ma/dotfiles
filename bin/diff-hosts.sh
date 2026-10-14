#!/usr/bin/env bash
# usage: diff-hosts.sh <host-a> <host-b>
#
# Compares the documented package sets of two hosts from hosts/<h>/packages/:
# explicit packages only on one side, and version differences. Reads the repo
# only; runs on the Mac.
#
#   -h, --help    this text
#
# needs:  the harvests in hosts/<host>/packages/ (bin/harvest.sh or dram harvest)
# alone:  yes, beside a hosts/ directory of the same layout
# here:   by hand on the Mac
# exit:   0 ok · 1 a host has no harvest yet · 2 bad usage
# see:    docs/operations/releases/README.md

# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT

case "${1:-}" in
  -h | --help)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac
set -euo pipefail

[ $# -eq 2 ] || {
  sed -n '2s/^# \{0,1\}//p' "$0" >&2
  exit 2
}
A="$1"
B="$2"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for h in "$A" "$B"; do
  [ -f "$REPO/hosts/$h/packages/explicit.txt" ] \
    || {
      echo "error: hosts/$h/packages/explicit.txt not found - run harvest.sh first" >&2
      exit 1
    }
done

section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

section "only on $A (explicit)"
comm -23 <(sort "$REPO/hosts/$A/packages/explicit.txt") \
  <(sort "$REPO/hosts/$B/packages/explicit.txt") | sed 's/^/  /'

section "only on $B (explicit)"
comm -13 <(sort "$REPO/hosts/$A/packages/explicit.txt") \
  <(sort "$REPO/hosts/$B/packages/explicit.txt") | sed 's/^/  /'

section "version drift (same package, different version)"
if [ -f "$REPO/hosts/$A/packages/versions.lock" ] && [ -f "$REPO/hosts/$B/packages/versions.lock" ]; then
  join <(sort "$REPO/hosts/$A/packages/versions.lock") \
    <(sort "$REPO/hosts/$B/packages/versions.lock") \
    | awk 'NF==3 && $2!=$3 {printf "  %-40s %s  ->  %s\n", $1, $2, $3}' | head -40
else
  echo "  (skipped: versions.lock missing for one host - run harvest.sh to get one)"
fi

section "enabled units only on $A"
comm -23 <(sort "$REPO/hosts/$A/systemd/enabled-system.txt" 2>/dev/null) \
  <(sort "$REPO/hosts/$B/systemd/enabled-system.txt" 2>/dev/null) | sed 's/^/  /'

section "enabled units only on $B"
comm -13 <(sort "$REPO/hosts/$A/systemd/enabled-system.txt" 2>/dev/null) \
  <(sort "$REPO/hosts/$B/systemd/enabled-system.txt" 2>/dev/null) | sed 's/^/  /'

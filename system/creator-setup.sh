#!/usr/bin/env bash
# usage: creator-setup.sh [--dry-run]
#
# The recordings folder of the creator role (docs/toolchain/profiles/creator.md): /data/recordings, where
# OBS's profiles record (dotfiles/obs/*/basic.ini RecFilePath), owned by the main user, and
# ~/videos/recordings -> /data/recordings, so SUPER+SHIFT+R's clips (record-toggle.sh) land
# beside OBS's. /data/recordings is the @recordings subvolume on the data pool
# (decisions/0011): it is root's when the subvolume is new, and OBS cannot record into it
# until this runs. Elsewhere it is created as a plain directory. An empty
# ~/videos/recordings folder gives way to the link; one holding files is left alone.
# Deletes nothing else. Idempotent; a `dram apply` role hook (system/apply-hooks.tsv). Root,
# unless --dry-run.
#
#   -n, --dry-run   print what would change
#   -h, --help      this text
#
# env: DRAM_USER (default: the sudo caller, else pj), DRAM_RECORDINGS (default /data/recordings)
# exit: 0 ok · 1 not root or a step failed · 2 bad usage
# see: docs/toolchain/profiles/creator.md, docs/records/handbook/02-first-login.md

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
USERNAME="${DRAM_USER:-${SUDO_USER:-pj}}"
ROOT="${DRAM_RECORDINGS:-/data/recordings}"
say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
run() { if [ "$DRY" -eq 1 ]; then printf '  \033[2m[dry-run] %s\033[0m\n' "$*"; else "$@"; fi; }
[ "$(id -u)" -eq 0 ] || [ "$DRY" -eq 1 ] || {
  echo "Run with sudo: sudo bash $0 [--dry-run]"
  exit 1
}
id "$USERNAME" >/dev/null 2>&1 || [ "$DRY" -eq 1 ] || {
  warn "no user $USERNAME (DRAM_USER)"
  exit 1
}
GROUP="$(id -gn "$USERNAME" 2>/dev/null || echo "$USERNAME")"
HOMEDIR="$(getent passwd "$USERNAME" 2>/dev/null | cut -d: -f6)"
HOMEDIR="${HOMEDIR:-/home/$USERNAME}"

say "recordings folder $ROOT"
if findmnt -n "$ROOT" >/dev/null 2>&1; then ok "$ROOT is its own mount (the @recordings subvolume)"; else
  warn "$ROOT is not a mount — a plain directory on this disk (older host or one pool; decisions/0011)"
fi
if [ -d "$ROOT" ] && [ "$(stat -c %U "$ROOT")" = "$USERNAME" ]; then
  ok "$ROOT belongs to $USERNAME"
elif [ -d "$ROOT" ]; then
  # the top level only: recordings already there keep their owners
  run chown "$USERNAME:$GROUP" "$ROOT" || {
    warn "could not hand $ROOT to $USERNAME"
    exit 1
  }
  ok "$ROOT handed to $USERNAME"
else
  run install -d -m 755 -o "$USERNAME" -g "$GROUP" "$ROOT" || {
    warn "could not create $ROOT"
    exit 1
  }
  ok "$ROOT created"
fi

say "recordings folder in the home directory"
videos="$HOMEDIR/videos"
link="$videos/recordings"
[ -d "$videos" ] || run install -d -m 755 -o "$USERNAME" -g "$GROUP" "$videos" || {
  warn "could not create $videos"
  exit 1
}
if [ -L "$link" ] && [ "$(readlink "$link")" = "$ROOT" ]; then
  ok "$link -> $ROOT"
elif [ -d "$link" ] && [ ! -L "$link" ] && [ -z "$(ls -A "$link")" ]; then
  run rmdir "$link" && run ln -s "$ROOT" "$link" && { [ "$DRY" -eq 1 ] || chown -h "$USERNAME:$GROUP" "$link"; } \
    && ok "$link -> $ROOT (the empty folder gave way)"
elif [ -e "$link" ] || [ -L "$link" ]; then
  warn "$link holds files or is another link — left alone; move them to $ROOT, rmdir it, run again"
else
  run ln -s "$ROOT" "$link" && { [ "$DRY" -eq 1 ] || chown -h "$USERNAME:$GROUP" "$link"; } && ok "$link -> $ROOT"
fi

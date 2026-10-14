#!/usr/bin/env bash
# usage: emulation-setup.sh [--dry-run]
#
# The ROM/BIOS tree of the emulation role (decisions/0016, docs/toolchain/profiles/emulation.md), EmuDeck's
# layout on the data pool so a reinstall keeps it: /data/emulation/{roms/<system>, bios,
# saves, storage, tools}, owned by the main user, and ~/roms -> /data/emulation/roms (the
# home folder's short lowercase names, handbook 02 §2). /data/emulation is the @emulation
# subvolume on desktops installed by install/arch-install.sh; elsewhere it is created as a
# plain directory. Deletes nothing but its own older ~/ROMs link. Idempotent; a
# `dram apply` role hook (system/apply-hooks.tsv). Root, unless --dry-run.
#
#   -n, --dry-run   print what would change
#   -h, --help      this text
#
# env: DRAM_USER (default: the sudo caller, else pj), DRAM_EMU_ROOT (default /data/emulation)
# exit: 0 ok · 1 not root or a step failed · 2 bad usage
# see: docs/toolchain/profiles/emulation.md

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
ROOT="${DRAM_EMU_ROOT:-/data/emulation}"
# ES-DE's system names (its folder per system); one per console or arcade family we emulate
SYSTEMS="nes snes gb gbc gba n64 gc wii wiiu nds n3ds psx ps2 ps3 ps4 psp psvita xbox xbox360
  mastersystem gamegear sg-1000 megadrive segacd sega32x saturn dreamcast naomi atomiswave
  model2 model3 arcade neogeo pcengine pcenginecd supergrafx scummvm"
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

say "tree under $ROOT"
if findmnt -n "$ROOT" >/dev/null 2>&1; then ok "$ROOT is its own mount (the @emulation subvolume)"; else
  warn "$ROOT is not a mount — a plain directory on this disk (older host or one pool; decisions/0011)"
fi
new=0
for d in roms bios saves storage tools $(for s in $SYSTEMS; do echo "roms/$s"; done); do
  [ -d "$ROOT/$d" ] && continue
  run install -d -m 755 -o "$USERNAME" -g "$GROUP" "$ROOT/$d" || {
    warn "could not create $ROOT/$d"
    exit 1
  }
  new=$((new + 1))
done
# the top level belongs to the user too (it is root's when the subvolume is new)
[ "$DRY" -eq 1 ] || chown "$USERNAME:$GROUP" "$ROOT"
ok "$new folder(s) created; $(echo "$SYSTEMS" | wc -w | tr -d ' ') systems under roms/"

say "roms folder in the home directory"
link="$HOMEDIR/roms"
if [ -L "$link" ] && [ "$(readlink "$link")" = "$ROOT/roms" ]; then ok "$link -> $ROOT/roms"; elif [ -e "$link" ] || [ -L "$link" ]; then
  warn "$link exists and is not our link — left alone (the ROMs are in $ROOT/roms)"
else
  run ln -s "$ROOT/roms" "$link" && { [ "$DRY" -eq 1 ] || chown -h "$USERNAME:$GROUP" "$link"; } && ok "$link -> $ROOT/roms"
fi
# the link this script made before the lowercase names: only ever our own symlink goes
old="$HOMEDIR/ROMs"
if [ -L "$old" ] && [ "$(readlink "$old")" = "$ROOT/roms" ]; then
  run rm "$old" && ok "the old $old link removed (now $link)"
fi

#!/usr/bin/env bash
# usage: wallpaper-hotplug.sh
#
# Repaints the quote wallpaper when a monitor is hotplugged (autostarted by
# hyprland.lua). awww-daemon restores an output it has painted before from its
# cache, but a never-painted one stays black (first dock, cache reset), so this
# follows Hyprland's socket2 event stream and runs `quote-wallpaper.sh --show`
# whenever an output is added; without that script the English quote is
# painted on the new output. The read blocks on the socket: zero CPU while idle.
#
#   -h, --help    this text
#
# env: WALLPAPER_HOTPLUG_LOG=path   append a debug log there
#
# exit: 0 ok · 1 no Hyprland session · 2 bad usage
# see: docs/design/themes/wallpaper.md

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

WALL="$HOME/pictures/wallpapers/quote-wall.png"
QW="$HOME/.local/bin/quote-wallpaper.sh"

# Optional debug log (set WALLPAPER_HOTPLUG_LOG=/path to enable).
LOG="${WALLPAPER_HOTPLUG_LOG:-}"
log() {
  [ -n "$LOG" ] && printf '%s %s\n' "$(date +%T)" "$1" >>"$LOG"
  return 0
}

# --- locate the Hyprland event socket ----------------------------------------
sig="${HYPRLAND_INSTANCE_SIGNATURE:-}"
runtime="${XDG_RUNTIME_DIR:-}"
if [ -z "$sig" ] || [ -z "$runtime" ]; then
  echo "wallpaper-hotplug: HYPRLAND_INSTANCE_SIGNATURE or XDG_RUNTIME_DIR unset; exiting." >&2
  exit 1
fi
SOCKET="$runtime/hypr/$sig/.socket2.sock"
if [ ! -S "$SOCKET" ]; then
  echo "wallpaper-hotplug: event socket $SOCKET not found; exiting." >&2
  exit 1
fi

# --- pick a UNIX-socket reader that streams event lines to stdout ------------
# socat is the standard tool; nc -U works too; python3 is a last-resort fallback
# so the fix works even before `socat` is installed.
if command -v socat >/dev/null 2>&1; then
  reader() { socat -U - UNIX-CONNECT:"$SOCKET"; }
elif command -v nc >/dev/null 2>&1 && nc -h 2>&1 | grep -q -- '-U'; then
  reader() { nc -U "$SOCKET"; }
elif command -v python3 >/dev/null 2>&1; then
  reader() {
    python3 - "$SOCKET" <<'PY'
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sys.argv[1])
with s.makefile("r") as f:
    for line in f:
        sys.stdout.write(line)
        sys.stdout.flush()
PY
  }
else
  echo "wallpaper-hotplug: need socat (preferred), nc -U, or python3 to read the event socket; exiting." >&2
  exit 1
fi

# --- repaint the wallpaper on a new output -----------------------------------
# Preferred: `quote-wallpaper.sh --show` re-displays the cached renders with the
# per-output mapping (and re-evaluates it: a dock can change which output is
# "second"). Fallback: `awww img -o NAME` paints the English quote on just the
# new output (then on everything if that fails).
repaint() {
  local out="${1:-}"
  sleep 1 # let the freshly-added output fully register before painting
  if [ -x "$QW" ] && "$QW" --show >/dev/null 2>&1; then
    log "repaint via quote-wallpaper --show (added=$out)"
    return 0
  fi
  command -v awww >/dev/null 2>&1 || {
    log "awww missing, skip"
    return 0
  }
  [ -f "$WALL" ] || {
    log "no wallpaper file, skip"
    return 0
  }
  pgrep -x awww-daemon >/dev/null 2>&1 || {
    setsid -f awww-daemon >/dev/null 2>&1
    sleep 0.4
  }
  if [ -n "$out" ]; then
    log "repaint output=$out (fallback)"
    awww img "$WALL" -o "$out" --transition-type none >/dev/null 2>&1 \
      || awww img "$WALL" --transition-type none >/dev/null 2>&1
  else
    log "repaint all outputs (fallback)"
    awww img "$WALL" --transition-type none >/dev/null 2>&1
  fi
}

log "listener started, socket=$SOCKET"

# --- event loop --------------------------------------------------------------
# Hyprland sends BOTH `monitoradded` and `monitoraddedv2` for each new output;
# we react to only one of them so we don't repaint twice. The blocking read
# means zero CPU while idle. If the stream ends (Hyprland exited/restarted) we
# simply exit — the exec-once in hyprland.lua respawns us at next login.
reader | while read -r line; do
  case "$line" in
    monitoradded\>\>*)
      # format: monitoradded>>NAME  (e.g. monitoradded>>DP-4)
      name="${line#monitoradded>>}"
      log "event: $line"
      repaint "$name"
      ;;
  esac
done
log "event stream closed; exiting"

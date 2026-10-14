#!/usr/bin/env bash
# usage: waybar-fullscreen.sh
#
# Hides waybar while the active window is fullscreen (either Hyprland
# fullscreen mode) and brings it back when it is not; autostarted by
# hyprland.lua. Follows Hyprland's event socket and toggles waybar with
# SIGUSR1 only when the wanted state differs from the last one set; the
# tracked state resets when waybar's pid changes (dram-theme and gamemode
# restart it). waybar-toggle.sh's flag file pauses it.
#
#   -h, --help    this text
#
# exit: 0 ok · 1 no Hyprland session or socket · 2 bad usage
# see: dotfiles/.config/waybar/README.md

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

sig="${HYPRLAND_INSTANCE_SIGNATURE:-}"
runtime="${XDG_RUNTIME_DIR:-}"
[ -n "$sig" ] && [ -n "$runtime" ] || {
  echo "waybar-fullscreen: no Hyprland session env; exiting." >&2
  exit 1
}
SOCKET="$runtime/hypr/$sig/.socket2.sock"
[ -S "$SOCKET" ] || {
  echo "waybar-fullscreen: $SOCKET not found; exiting." >&2
  exit 1
}

# same reader fallback chain as wallpaper-hotplug.sh
if command -v socat >/dev/null 2>&1; then
  reader() { socat -U - UNIX-CONNECT:"$SOCKET"; }
elif command -v nc >/dev/null 2>&1 && nc -h 2>&1 | grep -q -- '-U'; then
  reader() { nc -U "$SOCKET"; }
elif command -v python3 >/dev/null 2>&1; then
  reader() {
    python3 - "$SOCKET" <<'PY'
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.connect(sys.argv[1])
with s.makefile("r") as f:
    for line in f: sys.stdout.write(line); sys.stdout.flush()
PY
  }
else
  echo "waybar-fullscreen: need socat, nc -U, or python3; exiting." >&2
  exit 1
fi

# waybar-toggle.sh (SUPER+SHIFT+B) drops this flag while the user has flipped
# the bar by hand; we stay out of the way until it is removed (the toggle
# restores the bar to the state we last set, so `hidden` stays truthful).
MANUAL="${XDG_RUNTIME_DIR:-/tmp}/waybar-manual"

hidden=0
last_pid=""
sync_bar() {
  [ -e "$MANUAL" ] && return 0
  pid=$(pgrep -x -o waybar 2>/dev/null || true)
  [ -n "$pid" ] || return 0 # no bar, nothing to do
  [ "$pid" = "$last_pid" ] || {
    hidden=0
    last_pid=$pid
  } # bar restarted -> it is visible again
  fs=$(hyprctl activewindow -j 2>/dev/null | jq -r '.fullscreen // 0' 2>/dev/null || echo 0)
  want=0
  [ "$fs" != "0" ] && [ "$fs" != "null" ] && want=1
  if [ "$want" != "$hidden" ]; then pkill -SIGUSR1 -x waybar && hidden=$want; fi
}

sync_bar
reader | while IFS= read -r line; do
  case "$line" in
    fullscreen\>\>* | activewindow\>\>* | workspace\>\>* | focusedmon\>\>* | closewindow\>\>* | openlayer\>\>*) sync_bar ;;
  esac
done

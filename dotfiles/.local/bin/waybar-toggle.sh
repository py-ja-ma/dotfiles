#!/usr/bin/env bash
# usage: waybar-toggle.sh
#
# Hides or shows the bar by hand (SUPER+SHIFT+B) with SIGUSR1, without
# desyncing waybar-fullscreen.sh: the first press drops a flag file (the
# auto-hider pauses while it exists) and flips the bar; the second removes the
# flag and flips it back. The flag records waybar's pid, so a bar restarted in
# between (it comes back visible) just drops the flag.
#
#   -h, --help    this text
#
# exit: 0 ok · 1 waybar not running · 2 bad usage
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

FLAG="${XDG_RUNTIME_DIR:-/tmp}/waybar-manual"

pid=$(pgrep -x -o waybar 2>/dev/null || true)
[ -n "$pid" ] || {
  notify-send -a waybar "waybar is not running" "dram-theme restarts it, or run: waybar &"
  exit 1
}

if [ -f "$FLAG" ]; then
  flagged_pid=$(cat "$FLAG" 2>/dev/null || true)
  rm -f "$FLAG"
  if [ "$flagged_pid" = "$pid" ]; then
    pkill -SIGUSR1 -x waybar # same bar: undo our flip
  fi                         # restarted bar: already visible, nothing to undo
else
  printf '%s\n' "$pid" >"$FLAG"
  pkill -SIGUSR1 -x waybar
fi

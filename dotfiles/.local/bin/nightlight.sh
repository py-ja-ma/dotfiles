#!/usr/bin/env bash
# usage: nightlight.sh
#
# Blue-light filter toggle (SUPER+ALT+N) via hyprsunset. If a hyprsunset is
# already running (hyprland.lua autostarts one; dram-theme-auto drives it by
# the sun) the filter is forced to 4000 K over IPC and the next press hands
# control back to the sun; if none runs, one is spawned and the next press
# kills it. A state file under $XDG_RUNTIME_DIR remembers which, so "off"
# undoes exactly that and leaves a scheduled instance alive.
#
#   -h, --help    this text
#
# exit: 0 ok · 1 hyprsunset missing · 2 bad usage
# see: docs/design/themes/switcher.md

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

TEMP=4000
# same default as dram-theme-auto (XDG_RUNTIME_DIR or /run/user/<uid>), so the
# manual override is seen from either side even when the variable is unset
STATE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/nightlight.state" # "ipc" | "spawned"

command -v hyprsunset >/dev/null 2>&1 || {
  notify-send -a nightlight "Night light unavailable" "Install hyprsunset."
  exit 1
}
say() { notify-send -a nightlight "$@" 2>/dev/null || true; }

if pgrep -x hyprsunset >/dev/null 2>&1; then
  case "$(cat "$STATE" 2>/dev/null || true)" in
    ipc)
      # back to whatever the sun says now (dram-theme-auto owns the schedule)
      rm -f "$STATE"
      "$HOME/.local/bin/dram-theme-auto" --nightlight >/dev/null 2>&1 \
        || hyprctl hyprsunset identity >/dev/null 2>&1 || true
      say "Night light: back to the sun"
      ;;
    spawned)
      pkill -x hyprsunset
      rm -f "$STATE"
      say "Night light OFF"
      ;;
    *)
      # someone else's instance (the scheduled one): override over IPC
      if hyprctl hyprsunset temperature "$TEMP" >/dev/null 2>&1; then
        echo ipc >"$STATE"
        say "Night light ON" "${TEMP}K until the next press (then back to the sun)"
      else
        say "Night light: IPC failed" "a hyprsunset is running but hyprctl hyprsunset did not answer"
        exit 1
      fi
      ;;
  esac
else
  setsid -f hyprsunset --temperature "$TEMP" >/dev/null 2>&1
  echo spawned >"$STATE"
  say "Night light ON" "${TEMP}K"
fi

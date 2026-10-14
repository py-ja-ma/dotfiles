#!/usr/bin/env bash
# usage: layout-toggle.sh
#
# Flips the global layout dwindle <-> scrolling (SUPER+ALT+L) through the Lua
# API over hyprctl (`repl` reads, `eval` writes). The change lasts until the
# next config reload, when hyprland.lua's `general.layout = "dwindle"` wins
# again: dwindle is the default, scrolling is a mode you opt into for a session.
#
#   -h, --help    this text
#
# exit: 0 ok · 1 hyprctl eval failed · 2 bad usage
# see: docs/design/shell-and-bars/keybinds.md

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

cur=$(hyprctl repl 'hl.get_config("general.layout")' 2>/dev/null | tr -d '[:space:]')
case "$cur" in
  scrolling) new=dwindle ;;
  *) new=scrolling ;;
esac

if hyprctl eval "hl.config({ [\"general.layout\"] = \"$new\" })" >/dev/null 2>&1; then
  if [ "$new" = scrolling ]; then
    hint="SUPER+CTRL+←/→ scroll a column, +SHIFT swaps, SUPER+CTRL+F fit, SUPER+CTRL+P promote. SUPER+ALT+L to go back."
  else
    hint="SUPER+J toggles the split, SUPER+P pseudo-tiles."
  fi
  notify-send -a layout "Layout: $new" "$hint" 2>/dev/null || true
else
  notify-send -u critical -a layout "Layout switch failed" "hyprctl eval returned an error (is Hyprland running?)" 2>/dev/null || true
  exit 1
fi

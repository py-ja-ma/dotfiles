#!/usr/bin/env bash
# usage: gamemode.sh
#
# Game-mode toggle (SUPER+SHIFT+G): turns animations, blur, shadows, rounding,
# gaps and the paper-grain screen shader off for maximum performance; the
# second press runs a plain `hyprctl reload`, which restores hyprland.lua
# exactly. State is a flag file under $XDG_RUNTIME_DIR; a notification reports
# each flip.
#
#   -h, --help    this text
#
# exit: 0 ok · 1 hyprctl failed · 2 bad usage
# see: docs/toolchain/profiles/gaming.md

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
STATE="${XDG_RUNTIME_DIR:-/tmp}/hypr-gamemode"
# Paper-grain screen shader (hyprland.lua decoration.screen_shader): an extra
# full-screen pass per frame, so it goes off with the rest of the eye candy.
SHADER="$HOME/.config/hypr/shaders/grain.frag"

if [ -e "$STATE" ]; then
  rm -f "$STATE"
  hyprctl reload >/dev/null
  # reload already re-applies hyprland.lua (shader included); set it explicitly
  # too so the grain comes back even if the reload had nothing to re-run.
  hyprctl eval "hl.config({ decoration = { screen_shader = \"$SHADER\" } })" >/dev/null 2>&1 || true
  notify-send -a "performance mode" "Performance mode OFF" "Animations, blur, gaps and grain restored."
else
  touch "$STATE"
  hyprctl eval 'hl.config({
    animations = { enabled = false },
    decoration = {
      rounding = 0,
      blur   = { enabled = false },
      shadow = { enabled = false },
      screen_shader = "",            -- grain.frag off: no extra full-screen pass
    },
    general = { gaps_in = 0, gaps_out = 0, border_size = 1 },
  })' >/dev/null
  notify-send -a "performance mode" "Performance mode ON" "Eye candy off for max FPS."
fi

#!/usr/bin/env bash
# usage: lid.sh open|close
#
# Enables or disables the internal laptop panel on lid open/close while docked
# (the two `switch:*:Lid Switch` binds in hyprland.lua). Monitor changes go
# through `hyprctl eval 'hl.monitor{...}'` because this Hyprland build uses the
# Lua config (`hyprctl keyword monitor` is rejected). The panel connector is the
# first eDP*; re-enable uses the preferred mode and auto position so it comes
# back in any dock layout. Does not lock the session (hypridle does).
#
#   close         disable the panel
#   open          enable the panel (preferred mode, auto position, scale 1.5)
#   -h, --help    this text
#
# exit: 0 ok · 1 hyprctl failed · 2 bad usage
# see: dotfiles/.config/hypr/README.md

case "${1:-}" in
  -h | --help)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

set -uo pipefail

panel="$(hyprctl monitors all -j 2>/dev/null | grep -oE '"name": *"eDP[^"]*"' | head -1 | grep -oE 'eDP[^"]*')"
[ -n "$panel" ] || panel="eDP-1"

case "${1:-}" in
  close) hyprctl eval "hl.monitor({ output = \"$panel\", disabled = true })" ;;
  open) hyprctl eval "hl.monitor({ output = \"$panel\", mode = \"preferred\", position = \"auto\", scale = 1.5 })" ;;
  *)
    echo "usage: ${0##*/} {open|close}" >&2
    exit 2
    ;;
esac

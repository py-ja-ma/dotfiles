#!/usr/bin/env bash
# usage: power-menu.sh
#
# Power menu (SUPER+X, SUPER+M). A rofi list in the theme's Letterpress rofi
# style with the five actions wlogout used to show: lock, logout, suspend,
# reboot, shutdown. Type the first letter or pick with the arrows; ESC cancels.
# Replaced wlogout + wlogout-menu.sh 2026-10-10 (decisions/0013: wlogout failed
# the Community rule).
#
#   -h, --help    this text
#
# exit: 0 ok (or cancelled) · 1 the action failed · 2 bad usage
# see: dotfiles/.config/rofi/README.md

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

choice=$(printf '%s\n' lock logout suspend reboot shutdown \
  | rofi -dmenu -i -p "power" -no-custom -theme-str 'listview { lines: 5; }') || exit 0

case "$choice" in
  lock) pidof hyprlock >/dev/null || exec hyprlock ;;
  logout) exec hyprctl dispatch 'hl.dsp.exit()' ;;
  suspend) exec systemctl suspend ;;
  reboot) exec systemctl reboot ;;
  shutdown) exec systemctl poweroff ;;
  *) exit 0 ;;
esac

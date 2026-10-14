#!/usr/bin/env bash
# usage: wallpaper-menu.sh
#
# Wallpaper picker (SUPER+SHIFT+W): lists the images in ~/pictures/wallpapers
# in rofi and fades the chosen one in on the focused monitor through awww. A
# manual override for one output only: quote-wallpaper.sh still owns the
# generated quote wall and repaints every output on theme switch and hotplug.
#
#   -h, --help    this text
#
# exit: 0 ok (or cancelled) · 1 awww missing or no wallpaper dir · 2 bad usage
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

DIR="$HOME/pictures/wallpapers"
[ -d "$DIR" ] || {
  notify-send -a wallpaper "No wallpapers" "$DIR does not exist"
  exit 1
}
command -v awww >/dev/null 2>&1 || {
  notify-send -u critical -a wallpaper "awww not installed" "packages/roles/desktop.txt: awww"
  exit 1
}

# quote-wall*.png (quote-wall.png, quote-wall-ru.png) are the generated quote
# wallpapers (quote-wallpaper.sh), not pictures to pick.
pick=$(find -L "$DIR" -maxdepth 1 -type f \
  \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) \
  ! -name 'quote-wall*.png' -printf '%f\n' | sort | rofi -dmenu -i -p "wallpaper") || exit 0
[ -n "$pick" ] || exit 0

pgrep -x awww-daemon >/dev/null 2>&1 || {
  setsid -f awww-daemon >/dev/null 2>&1
  sleep 0.4
}

mon=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | .name' 2>/dev/null)
# `awww img` paints every output by default; -o NAME limits it to one.
if [ -n "$mon" ]; then
  awww img "$DIR/$pick" -o "$mon" --transition-type fade --transition-duration 0.9
else
  awww img "$DIR/$pick" --transition-type fade --transition-duration 0.9
fi

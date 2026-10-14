#!/usr/bin/env bash
# usage: screenshot.sh [region|window|output|all]
#
# Every screenshot bind goes through here so there is one naming scheme,
# ~/pictures/screenshots/screenshot-YYYYMMDD-HHMMSS.png (the same strftime pattern as
# satty's output-filename, so annotated and raw shots sort together). grim +
# slurp only; satty is optional, without it a region/window shot lands on the
# clipboard instead. Default: region.
#
#   region        Print               slurp a region -> satty (Ctrl+C copy, Ctrl+S save)
#   window        SUPER+SHIFT+Print   active window geometry (hyprctl) -> grim -g -> satty
#   output        SUPER+CTRL+Print    focused monitor -> file + clipboard, path notified
#   all           SUPER+Print         every monitor -> file + clipboard, path notified
#   -h, --help    this text
#
# exit: 0 ok (or cancelled) · 1 grim/jq/slurp missing or no window · 2 bad usage
# see: docs/design/shell-and-bars/keybinds.md

case "${1:-}" in
  "" | region | window | output | all) ;;
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

mode="${1:-region}"
dir="$HOME/pictures/screenshots"
mkdir -p "$dir"
out="$dir/screenshot-$(date +%Y%m%d-%H%M%S).png"

for tool in grim jq; do
  command -v "$tool" >/dev/null 2>&1 || {
    notify-send -u critical -a screenshot "screenshot: $tool missing"
    exit 1
  }
done

annotate() { # png on stdin
  if command -v satty >/dev/null 2>&1; then
    satty --filename - --output-filename "$out"
  else
    wl-copy && notify-send -a screenshot "Screenshot copied" "satty is not installed, so the shot went to the clipboard only"
  fi
}

saved() { # $1 = file
  wl-copy <"$1" 2>/dev/null || true
  notify-send -a screenshot -i "$1" "Screenshot saved" "$1 (also on the clipboard)"
}

case "$mode" in
  region)
    command -v slurp >/dev/null 2>&1 || {
      notify-send -u critical -a screenshot "screenshot: slurp missing"
      exit 1
    }
    geom=$(slurp) || exit 0 # ESC = cancel, silently
    grim -g "$geom" - | annotate
    ;;
  window)
    # `at`/`size` are logical layout coordinates, exactly what grim -g wants.
    geom=$(hyprctl activewindow -j 2>/dev/null | jq -r 'select(.at and .size) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
    [ -n "$geom" ] || {
      notify-send -a screenshot "No active window" "Focus a window first"
      exit 1
    }
    grim -g "$geom" - | annotate
    ;;
  output)
    mon=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | .name')
    [ -n "$mon" ] || {
      notify-send -u critical -a screenshot "No focused monitor"
      exit 1
    }
    grim -o "$mon" "$out" && saved "$out"
    ;;
  all)
    grim "$out" && saved "$out"
    ;;
  *)
    echo "usage: screenshot.sh region|window|output|all" >&2
    exit 2
    ;;
esac

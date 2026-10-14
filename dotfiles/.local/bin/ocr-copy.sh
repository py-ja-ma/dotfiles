#!/usr/bin/env bash
# usage: ocr-copy.sh
#
# OCRs a screen region to the clipboard (SUPER+SHIFT+X): slurp selects the
# region, grim grabs it, tesseract (eng) reads it, wl-copy takes the text; a
# notification shows the first 120 characters.
#
#   -h, --help    this text
#
# exit: 0 ok · 1 tesseract missing · 2 bad usage
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

if ! command -v tesseract >/dev/null 2>&1; then
  notify-send -a ocr "OCR unavailable" "Install tesseract + tesseract-data-eng."
  exit 1
fi

text="$(grim -g "$(slurp)" - | tesseract stdin stdout -l eng 2>/dev/null | sed -e 's/[[:space:]]*$//' -e '/^$/d')"
if [ -n "$text" ]; then
  printf '%s' "$text" | wl-copy
  notify-send -a ocr "OCR copied" "$(printf '%s' "$text" | head -c 120)"
else
  notify-send -a ocr "OCR" "No text recognized in that region."
fi

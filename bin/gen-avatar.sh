#!/usr/bin/env bash
# usage: gen-avatar.sh [--out DIR]
#
# The "pj" account picture, distinct from the wallpaper: a Letterpress seal - "pj" in EB
# Garamond italic, paper on a vermilion disc (washi's accent #c0442b) ringed in paper, on the
# dark base #1c140f - at the sizes Windows keeps for an account picture
# (install/windows/dram-windows/account-picture.ps1) and 512 px meant for ~/.face on the Linux
# hosts (nothing installs it yet). Needs ImageMagick 7 (`magick`) and EB Garamond Italic
# (AVATAR_FONT=path, else fontconfig's match): on Arch, imagemagick, with the italic from
# dotfiles/.local/share/fonts/ that the desktop role links; on the Mac, the throwaway nixos/nix
# container (decisions/log.md#d26) with the flake's own nixpkgs:
#   docker run --rm -v "$PWD:/repo" -w /repo nixos/nix sh -c 'nix --extra-experimental-features
#     "nix-command flakes" shell --inputs-from . nixpkgs#imagemagick nixpkgs#eb-garamond
#     nixpkgs#bash nixpkgs#findutils -c bash bin/gen-avatar.sh'
#
#   --out DIR   default: dotfiles/.local/share/dram/avatar
#   -h, --help  this text
#
# exit: 0 written · 1 no magick or no font · 2 bad usage
# see: dotfiles/.local/share/dram/README.md

OUT=""
case "${1:-}" in
  "") ;;
  --out) OUT="${2:-}" ;;
  -h | --help)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    sed -n '2s/^# \{0,1\}//p' "$0" >&2
    exit 2
    ;;
esac

set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${OUT:-$REPO/dotfiles/.local/share/dram/avatar}"
command -v magick >/dev/null || {
  echo "gen-avatar: needs ImageMagick 7 (magick)" >&2
  exit 1
}
FONT="${AVATAR_FONT:-}"
if [ -z "$FONT" ]; then
  FONT="$(fc-match -f '%{file}' 'EB Garamond:italic' 2>/dev/null || true)"
  case "$FONT" in *[Gg]aramond*[Ii]talic*) ;; *) FONT="" ;; esac
fi
if [ -z "$FONT" ]; then
  # a Nix shell: the font is in the store, not in fontconfig
  FONT="$(find /nix/store -maxdepth 6 \( -iname 'EBGaramond-Italic.otf' -o -iname 'EBGaramond12-Italic.otf' \) 2>/dev/null | head -n 1 || true)"
fi
[ -n "$FONT" ] && [ -f "$FONT" ] || {
  echo "gen-avatar: EB Garamond Italic not found (set AVATAR_FONT)" >&2
  exit 1
}

BASE='#1c140f' ACCENT='#c0442b' PAPER='#f3e9df'
mkdir -p "$OUT"
master="$OUT/pj-1080.png"
magick -size 1080x1080 "xc:$BASE" \
  -fill "$ACCENT" -draw 'circle 540,540 540,46' \
  -fill none -stroke "$PAPER" -strokewidth 9 -draw 'circle 540,540 540,92' \
  -stroke none -fill "$PAPER" -font "$FONT" -pointsize 600 -gravity center -annotate +6-58 'pj' \
  -strip "$master"
for s in 32 40 48 64 96 192 208 240 424 448 512; do
  magick "$master" -filter Lanczos -resize "${s}x${s}" -strip "$OUT/pj-$s.png"
done
echo "gen-avatar: $(find "$OUT" -name 'pj-*.png' | wc -l | tr -d ' ') sizes in $OUT (font: $FONT)"

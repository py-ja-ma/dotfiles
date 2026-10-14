#!/usr/bin/env bash
# usage: monitors-pin.sh [--print]
#
# Writes ~/.config/dram/monitors.lua: this host's external panels by their description
# (`desc:`, which ends in the panel's serial number), left to right as Hyprland places
# them: main is the leftmost, mid the next. hyprland.lua and gaming.lua read the file, so
# their monitor and workspace rules follow a panel from port to port (a dock renumbers its
# DP-* ports). Without the file the rules name cabin's ports, DP-1 and HDMI-A-1. The file
# stays on the host: serial numbers are kept out of the repo. Run it once the panels stand
# where they belong, then `hyprctl reload`.
#
#   --print     print the file instead of writing it
#   -h, --help  this text
#
# exit: 0 written or printed · 1 no Hyprland, or no external panel · 2 bad usage
# see: dotfiles/.config/hypr/README.md

PRINT=0
case "${1:-}" in
  "") ;;
  --print) PRINT=1 ;;
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
command -v hyprctl >/dev/null 2>&1 || {
  echo "monitors-pin.sh: no hyprctl (run it inside the Hyprland session)" >&2
  exit 1
}
json="$(hyprctl -j monitors 2>/dev/null)" || {
  echo "monitors-pin.sh: Hyprland does not answer (run it inside the session)" >&2
  exit 1
}
# external panels only (a laptop's own panel is eDP-*), left to right
mapfile -t descs < <(jq -r '[.[] | select(.name | startswith("eDP") | not)] | sort_by(.x) | .[].description' <<<"$json")
[ "${#descs[@]}" -gt 0 ] || {
  echo "monitors-pin.sh: no external panel connected" >&2
  exit 1
}
lua_str() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }
out="-- written by monitors-pin.sh: this host's panels by description, left to right
-- (hyprland.lua and gaming.lua read it; kept out of the repo)
return {
  main = $(lua_str "desc:${descs[0]}"),"
[ "${#descs[@]}" -gt 1 ] && out="$out
  mid  = $(lua_str "desc:${descs[1]}"),"
out="$out
}"
if [ "$PRINT" -eq 1 ]; then
  printf '%s\n' "$out"
  exit 0
fi
dest="${XDG_CONFIG_HOME:-$HOME/.config}/dram/monitors.lua"
mkdir -p "$(dirname "$dest")"
printf '%s\n' "$out" >"$dest"
echo "wrote $dest (main: ${descs[0]}${descs[1]:+; mid: ${descs[1]}}); hyprctl reload to apply"

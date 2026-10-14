#!/usr/bin/env bash
# usage: kb-layout.sh [toggle|en|ru|status]
#
# Keeps every keyboard on the same layout. Hyprland lists the lid switch, power
# button and video bus as "keyboards" and toggles layouts per device, so they
# drift apart; this sets all of them to one explicit index with
# `hyprctl switchxkblayout all N`. Default action: toggle (SUPER+ALT+SPACE,
# Alt+Shift, the bar's layout click).
#
#   toggle        next layout on every keyboard (default)
#   en, ru        that layout on every keyboard
#   status        print the main keyboard's layout (us / ru); needs the
#                 desktop's Hyprland socket (a terminal on the host, not ssh)
#   -h, --help    this text
#
# exit: 0 ok · 1 hyprctl failed · 2 bad usage
# see: docs/design/shell-and-bars/keybinds.md

case "${1:-}" in
  -h | --help)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

set -euo pipefail
layouts="$(hyprctl getoption input:kb_layout -j 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["str"])' 2>/dev/null || echo "us,ru")"
IFS=, read -r -a L <<<"$layouts"
current_idx() { # index of the main keyboard's active layout, 0 if unknown
  local devices
  devices="$(hyprctl devices -j 2>/dev/null || true)"
  [ -n "$devices" ] || {
    echo "kb-layout.sh: hyprctl failed (no Hyprland session)" >&2
    return 1
  }
  printf '%s' "$devices" | python3 -c '
import sys, json
d = json.load(sys.stdin)["keyboards"]
main = next((k for k in d if k.get("main")), d[0] if d else None)
name = (main or {}).get("active_keymap", "")
layouts = sys.argv[1].split(",")
names = {"us": "English", "ru": "Russian"}
for i, l in enumerate(layouts):
    if names.get(l, l).lower() in name.lower(): print(i); break
else: print(0)' "$layouts"
}
case "${1:-toggle}" in
  status)
    i="$(current_idx)"
    printf '%s\n' "${L[$i]}"
    ;;
  toggle)
    i="$(current_idx)"
    n=$(((i + 1) % ${#L[@]}))
    hyprctl switchxkblayout all "$n" >/dev/null
    ;;
  en) hyprctl switchxkblayout all 0 >/dev/null ;;
  ru)
    n=0
    for k in "${!L[@]}"; do [ "${L[$k]}" = ru ] && n=$k; done
    hyprctl switchxkblayout all "$n" >/dev/null
    ;;
  *)
    echo "usage: kb-layout.sh toggle|en|ru|status" >&2
    exit 2
    ;;
esac

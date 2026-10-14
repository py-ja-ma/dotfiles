#!/usr/bin/env bash
# usage: waybar-updates.sh [--force]
#
# Pending-updates badge for waybar's custom/updates module: one JSON line
# {text, tooltip, class}; empty text hides the module, so the badge only shows
# when something is pending. checkupdates uses its own temp DB (never -Sy on
# the real one) and covers [dram] too (an ordinary sync repo); it hits the
# network, so its list is cached for 30 minutes (~/.cache/dram/updates.pkgs).
# (paru -Qua left 2026-10-10 with paru; the cache keeps its empty "aur" section.) A pending dram
# build (dram channel --target: the channel's newest tag or master is not the
# checkout) counts as one more and names its target in the tooltip; it is
# local git, read every time. `dram update` / `dram channel` delete the cache
# and send SIGRTMIN+8 to refresh.
#
#   --force       recompute now, ignoring the cache
#   -h, --help    this text
#
# exit: 0 ok · 2 bad usage
# see: docs/platforms/arch/hooks.md

case "${1:-}" in
  "" | --force) ;;
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
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/dram/updates.pkgs" # "repo\n<lines>\naur\n<lines>"
TTL=1800

repo="" aur=""
fresh=0
if [ "${1:-}" != "--force" ] && [ -f "$CACHE" ]; then
  age=$(($(date +%s) - $(stat -c %Y "$CACHE")))
  [ "$age" -lt "$TTL" ] && fresh=1
fi
if [ "$fresh" -eq 1 ]; then
  repo="$(sed -n '/^repo$/,/^aur$/{/^repo$/d;/^aur$/d;p}' "$CACHE")"
  aur="$(sed -n '/^aur$/,${/^aur$/d;p}' "$CACHE")"
else
  if command -v checkupdates >/dev/null 2>&1; then
    repo="$(timeout 60 checkupdates 2>/dev/null)" # exit 2 = nothing pending
  fi
  mkdir -p "$(dirname "$CACHE")"
  printf 'repo\n%s\naur\n%s\n' "$repo" "$aur" | sed '/^$/d' >"$CACHE"
fi
nr=0 na=0
[ -n "$repo" ] && nr="$(printf '%s\n' "$repo" | sed '/^$/d' | wc -l)"
[ -n "$aur" ] && na="$(printf '%s\n' "$aur" | sed '/^$/d' | wc -l)"

# the dram itself: local refs only, never cached (docs/operations/releases/README.md)
dram_line="" ndram=0
if command -v dram >/dev/null 2>&1; then
  read -r channel target n < <(timeout 5 dram channel --target 2>/dev/null) || true
  if [ -n "${target:-}" ] && [ "$target" != - ] && [ "${n:-0}" != 0 ]; then
    ndram=1
    dram_line="dram: $target available ($channel, $n commits) — dram changelog"
  fi
fi
total=$((nr + na + ndram))

# Russian plural of "пакет" for the badge text: 1 пакет, 2–4 пакета, 5+ пакетов
# (11–14 are always пакетов). The bar is the dram's one Russian-language surface.
plural() {
  local n=$1 r10=$(($1 % 10)) r100=$(($1 % 100))
  if [ "$r10" -eq 1 ] && [ "$r100" -ne 11 ]; then
    echo "$n пакет"
  elif [ "$r10" -ge 2 ] && [ "$r10" -le 4 ] && { [ "$r100" -lt 12 ] || [ "$r100" -gt 14 ]; }; then
    echo "$n пакета"
  else
    echo "$n пакетов"
  fi
}

if [ "$total" -eq 0 ]; then
  out='{"text":"","tooltip":"up to date","class":"none"}'
else
  # first 12 lines of the list in the tooltip, JSON-escaped by python
  tip="$(printf '%s repo + %s AUR%s pending — click to run dram update\n%s%s' "$nr" "$na" \
    "$([ "$ndram" -eq 1 ] && echo ' + the dram')" "${dram_line:+$dram_line
}" "$(printf '%s\n%s\n' "$repo" "$aur" | sed '/^$/d' | head -12)")"
  out="$(python3 -c 'import json,sys; print(json.dumps({"text": sys.argv[1], "tooltip": sys.argv[2], "class": "pending"}))' "$(plural "$total")" "$tip")"
fi
printf '%s\n' "$out"

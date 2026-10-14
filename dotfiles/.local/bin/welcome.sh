#!/usr/bin/env bash
# usage: welcome.sh
#
# The "Welcome back, PJ" login toast, fired once by hyprland.lua's autostart.
# Waits up to 10 s for swaync so the toast lands themed, then sends one line:
# the date (Russian when ru_RU.UTF-8 is generated, English otherwise), the
# battery percentage if there is one, "up since HH:MM", the pending update
# count when checkupdates answers within 2 s, "dram vX available (stable)"
# when the channel target is not the checkout (dram channel --target), and
# "update applied — reboot to finish" while ~/.local/state/dram/reboot-required
# is newer than this boot. Comment its line out in hyprland.lua to disable it.
#
#   -h, --help    this text
#
# exit: 0 ok · 2 bad usage
# see: dotfiles/.config/hypr/README.md

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

# Wait for swaync to claim the notification bus (bounded: 20 x 0.5s = 10s).
for _ in $(seq 1 20); do
  pgrep -x swaync >/dev/null 2>&1 && break
  sleep 0.5
done

sep=$' · ' # " · " middle-dot separator

# today's date — Russian when the locale is generated, English otherwise
# (docs/design/typography/README.md "Russian", the same test hyprlock runs):
# "Вторник, 6 октября" / "Tuesday, 6 October"
if locale -a 2>/dev/null | grep -qi '^ru_RU\.utf-\?8$'; then
  body="$(LC_TIME=ru_RU.UTF-8 date +'%A, %-d %B')"
else
  body="$(date +'%A, %-d %B')"
fi

# battery percentage, if a battery is present
for bat in /sys/class/power_supply/BAT*/capacity; do
  if [[ -r "$bat" ]]; then
    cap="$(cat "$bat" 2>/dev/null)"
    [[ -n "${cap:-}" ]] && body="${body}${sep}Battery ${cap}%"
    break
  fi
done

# boot time, e.g. "up since 08:12"
since="$(date -d "$(uptime -s 2>/dev/null)" +%H:%M 2>/dev/null)" \
  && body="${body}${sep}up since ${since}"

# pending updates — checkupdates hits the network, so hard 2s timeout;
# skip silently on timeout / no tool / zero updates
if command -v checkupdates >/dev/null 2>&1; then
  updates="$(timeout 2 checkupdates --nocolor 2>/dev/null | grep -c .)"
  [[ "${updates:-0}" -gt 0 ]] && body="${body}${sep}${updates} updates"
fi

# a newer build on this host's channel — local git refs only, no network
# (docs/operations/releases/README.md): "dram v2026.10.2 available (stable)"
if command -v dram >/dev/null 2>&1; then
  read -r channel target n < <(timeout 5 dram channel --target 2>/dev/null) || true
  [[ -n "${target:-}" && "$target" != - && "${n:-0}" != 0 ]] \
    && body="${body}${sep}dram ${target} available (${channel})"
fi

# `dram update` leaves reboot-required when the kernel, Hyprland or the NVIDIA
# driver changed; it counts until the next boot (same rule as dram doctor)
rr="${XDG_STATE_HOME:-$HOME/.local/state}/dram/reboot-required"
if [[ -f "$rr" ]]; then
  boot="$(date -d "$(uptime -s 2>/dev/null)" +%s 2>/dev/null || echo 0)"
  [[ "$(stat -c %Y "$rr" 2>/dev/null || echo 0)" -gt "$boot" ]] \
    && body="${body}${sep}update applied — reboot to finish"
fi

notify-send -a system -u normal "Welcome back, PJ" "$body"

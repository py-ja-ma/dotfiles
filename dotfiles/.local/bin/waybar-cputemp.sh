#!/usr/bin/env bash
# usage: waybar-cputemp.sh
#
# CPU package temperature for the bar's custom/cputemp module, as one waybar
# JSON line. The sensor is picked by name (k10temp/zenpower on AMD, coretemp
# on Intel) because hwmon numbers change between boots and differ per host;
# the class "critical" turns the figure red above 82 °C. Hidden when no sensor
# is found.
#
#   -h, --help    this text
#
# exit: 0 ok · 2 bad usage
# see: dotfiles/.config/waybar/README.md

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
crit=82
f=""
for d in /sys/class/hwmon/hwmon*; do
  case "$(cat "$d/name" 2>/dev/null)" in
    k10temp | zenpower | coretemp)
      f="$d/temp1_input"
      break
      ;;
  esac
done
[ -r "$f" ] || {
  printf '{"text":"","class":"hidden"}\n'
  exit 0
}
t=$(($(cat "$f") / 1000))
cls=""
[ "$t" -ge "$crit" ] && cls="critical"
printf '{"text":"<span font_features=\\"smcp, lnum, tnum\\">%s °</span>","class":"%s","tooltip":false}\n' "$t" "$cls"

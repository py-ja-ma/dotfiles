#!/usr/bin/env bash
# usage: waybar-date.sh [--short]
#
# The dateline under the masthead clock (waybar custom/date): "вторник, 6
# октября" when the ru_RU locale is generated on the host
# (system/locale-setup.sh), "Tuesday, 6 October" otherwise; never a C-locale
# fallback. The day is unpadded (%-d), which waybar's own clock formatter
# cannot do.
#
#   (no flag)     %A, %-d %B   the external bar
#   --short       %a, %-d %b   the laptop bar
#   -h, --help    this text
#
# exit: 0 ok · 2 bad usage
# see: dotfiles/.config/waybar/README.md

set -u
fmt='%A, %-d %B'
case "${1:-}" in
  "") ;;
  --short) fmt='%a, %-d %b' ;;
  -h | --help)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    sed -n '2s/^# \{0,1\}//p' "$0" >&2
    exit 2
    ;;
esac
if locale -a 2>/dev/null | grep -qiE '^ru_RU\.utf-?8$'; then
  LC_TIME=ru_RU.UTF-8 date +"$fmt"
else
  date +"$fmt"
fi

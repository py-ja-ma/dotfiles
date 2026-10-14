#!/usr/bin/env bash
# usage: record-toggle.sh
#
# Starts or stops a screen recording (SUPER+SHIFT+R) with gpu-screen-recorder,
# which picks the encoder itself (NVENC on cabin, VA-API on lantern). The
# first press records the focused monitor with desktop audio to
# ~/videos/recordings/rec-YYYYMMDD-HHMMSS.mp4 (with the creator role a link to
# /data/recordings, OBS's folder); the second sends SIGINT (flush + save) and
# notifies the path. State is a pid file, so a gsr-ui replay buffer
# (SUPER+ALT+R) is never touched.
#
#   -h, --help    this text
#
# exit: 0 ok · 1 gpu-screen-recorder missing or failed to start · 2 bad usage
# see: docs/design/shell-and-bars/keybinds.md, docs/toolchain/profiles/creator.md

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

STATE="${XDG_RUNTIME_DIR:-/tmp}/record-toggle.state" # "<pid> <file>"

command -v gpu-screen-recorder >/dev/null 2>&1 || {
  notify-send -u critical -a record "gpu-screen-recorder not installed" "packages/roles/desktop.txt: gpu-screen-recorder"
  exit 1
}

# --- stop ---------------------------------------------------------------------
if [ -f "$STATE" ]; then
  read -r pid file <"$STATE" || true
  if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
    kill -INT "$pid"
    rm -f "$STATE"
    notify-send -a record "Recording saved" "${file:-?} (finalising…)"
    exit 0
  fi
  rm -f "$STATE" # stale: the recorder died or was stopped elsewhere; fall through and start a new one
fi

# --- start --------------------------------------------------------------------
mkdir -p "$HOME/videos/recordings"
out="$HOME/videos/recordings/rec-$(date +%Y%m%d-%H%M%S).mp4"
mon=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | .name' 2>/dev/null)
[ -n "$mon" ] || mon=screen

if command -v nvidia-smi >/dev/null 2>&1 || lspci -n 2>/dev/null | grep -q ' 10de:'; then
  enc="NVENC (NVIDIA)"
else
  enc="VA-API"
fi

# In a script (no job control) the background child is not a group leader, so
# setsid execs in place and $! IS the recorder's pid. -w <monitor> -f 60 -a
# default_output = focused output, 60 fps, desktop audio (README's example).
setsid gpu-screen-recorder -w "$mon" -f 60 -a default_output -o "$out" >/dev/null 2>&1 &
pid=$!
sleep 0.7
if kill -0 "$pid" 2>/dev/null; then
  printf '%s %s\n' "$pid" "$out" >"$STATE"
  # $'\n' is a real newline; inside "..." the two characters \n were literal
  notify-send -a record "Recording $mon" "$enc, 60 fps, desktop audio"$'\n'"SUPER+SHIFT+R again to stop"
else
  notify-send -u critical -a record "Recording failed to start" "run 'gpu-screen-recorder -w $mon -f 60 -a default_output -o /tmp/t.mp4' in a terminal to see why"
  exit 1
fi

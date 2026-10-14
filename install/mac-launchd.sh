#!/usr/bin/env bash
# usage: mac-launchd.sh [--uninstall | --status]
#
# Installs (or refreshes) the Mac launchd job dev.pj.pull-backups that runs
# bin/pull-backups.sh daily at 06:00 and once whenever the job is loaded
# (RunAtLoad: at every login, and at this install itself, so running this
# script triggers one pull right away). launchd replays a missed
# StartCalendarInterval only after sleep, never after a power-off
# (launchd.plist(5)), so a Mac that was off at 06:00 pulls at the next login
# instead; pull-backups.sh skips a host pulled less than 20 h ago, so the
# extra runs cost one ssh probe. Writes
# ~/Library/LaunchAgents/dev.pj.pull-backups.plist, boots the old job out and
# the new one in. Logs land in ~/backups/borg/launchd.{out,err}. Run by hand
# on the Mac. --uninstall boots the job out and removes the plist; the pulled
# copies under ~/backups/borg/ and the logs stay (docs/records/handbook/10-teardown.md).
# --status prints the job's state, run count and last exit code from
# `launchctl print` and changes nothing.
#
#   --uninstall   launchctl bootout + rm the plist
#   --status      state / runs / last exit code; exit 1 when the job is not loaded
#   -h, --help    this text
#
# exit: 0 ok · 1 launchctl failed or (--status) job not loaded · 2 bad usage
# see: docs/operations/backups/README.md, docs/platforms/macos/README.md

MODE=install
case "${1:-}" in
  "") ;;
  --uninstall) MODE=uninstall ;;
  --status) MODE=status ;;
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
LABEL=dev.pj.pull-backups
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
TARGET="gui/$(id -u)/$LABEL"

case "$MODE" in
  status)
    if out="$(launchctl print "$TARGET" 2>/dev/null)"; then
      printf '%s\n' "$out" | grep -E -m4 '^\s*(state|runs|last exit code|path) =' | sed 's/^[[:space:]]*//'
      exit 0
    fi
    echo "$LABEL is not loaded (plist: $([ -f "$PLIST" ] && echo present || echo absent))"
    exit 1
    ;;
  uninstall)
    launchctl bootout "$TARGET" 2>/dev/null && echo "booted out $LABEL" || echo "$LABEL was not loaded"
    rm -f "$PLIST"
    echo "removed $PLIST; ~/backups/borg/ (the pulled copies, pull.log, launchd.{out,err}) is untouched"
    exit 0
    ;;
esac

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/backups/borg"
cat >"$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$REPO/bin/pull-backups.sh</string></array>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>6</integer><key>Minute</key><integer>0</integer></dict>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$HOME/backups/borg/launchd.out</string>
  <key>StandardErrorPath</key><string>$HOME/backups/borg/launchd.err</string>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>10</integer>
</dict></plist>
PL
launchctl bootout "$TARGET" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "installed $LABEL -> $(launchctl print "$TARGET" | grep -m1 state)"

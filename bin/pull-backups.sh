#!/usr/bin/env bash
# usage: pull-backups.sh [--check]
#
# The Mac's side of the backups: pulls each host's Borg repository (which lives
# on the other host, backups/borg/<peer>) into ~/backups/borg/on-<host>/, so
# the Mac holds a copy of both. Per host, over one multiplexed ssh connection
# (ControlMaster: the 2026-10-06 06:05 pull died in rsync's second handshake
# right after a successful probe): a probe; then a staging step on the host,
# where `borg with-lock` copies each repo under ~/backups/borg/ to
# ~/backups/borg-stage/<name>/ while holding the Borg lock (no passphrase
# needed; lock.exclusive/lock.roster are left out), so the copy is never
# mid-transaction; then an rsync --delete of backups/borg-stage/ into
# on-<host>/ (one retry after 30 s). Layout on the Mac is unchanged:
# on-<host>/<peer-repo>/. A host that is off is skipped; a host whose
# on-<host>/.pulled marker is younger than 20 h is skipped too (the launchd
# job also runs at every login, RunAtLoad). At the end, a WARN line per host
# whose copy is older than 2 days or has no marker yet. Scheduled by
# install/mac-launchd.sh (daily 06:00 and at login, after the 03:00 host
# backups); run by hand any time. Log: ~/backups/borg/pull.log. Runs on the
# Mac (bash 3.2, openrsync); the hosts need borg + rsync (packages/base.txt).
#
#   --check       read-only: print the age of each host's copy; exit 1 when one
#                 is older than 2 days or was never pulled. Touches nothing.
#   -h, --help    this text
#
# needs:  ssh, rsync or openrsync; borg and rsync on the hosts; install/lib/roles.sh and
#         each host file's address and backupPeer
# alone:  yes, after replacing the host lookup with a list of your own hosts
# here:   paused with the backups until the NAS (decisions/0014): it pulls only hosts whose
#         file names a backupPeer; install/mac-launchd.sh schedules it
# exit:   0 ok · 1 a staging or rsync step failed, or (--check) a copy is stale or missing · 2 bad usage
# see:    docs/operations/backups/README.md

# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT

MODE=pull
case "${1:-}" in
  "") ;;
  --check) MODE=check ;;
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
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HOME/backups/borg"
LOG="$DEST/pull.log"
FRESH_MIN=1200 # once-a-day guard: skip a host whose .pulled is younger than 20 h (find -mmin)
STALE_H=48     # WARN / --check threshold: a copy older than 2 days is stale

# One ssh connection per host: the probe opens the master (ControlPersist keeps
# it 120 s idle), the staging command and rsync ride it, `ssh -O exit` closes
# it. The same options go to rsync as one -e string, so ControlPath must not
# contain spaces (/Users/<you>/.ssh/cm-<hash>).
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=4
  -o ControlMaster=auto -o "ControlPath=$HOME/.ssh/cm-%C" -o ControlPersist=120)

# Runs ON the host, one quoted command: a consistent copy of every repo it
# stores, taken under the Borg lock (`with-lock` needs no passphrase;
# --lock-wait 600 waits out a running backup instead of failing). Lock files
# stay out of the copy, so the Mac copy opens without `borg break-lock`. A
# stage dir whose repo is gone is dropped, so the Mac mirror keeps following
# what the host stores.
REMOTE_STAGE='set -e
mkdir -p ~/backups/borg-stage
for r in ~/backups/borg/*/; do
  [ -f "$r/config" ] || continue
  n=$(basename "$r")
  borg --lock-wait 600 with-lock "$r" rsync -a --delete --exclude lock.exclusive --exclude lock.roster "$r" ~/backups/borg-stage/"$n"/
done
for s in ~/backups/borg-stage/*/; do
  if [ -d "$s" ] && [ ! -f ~/backups/borg/"$(basename "$s")"/config ]; then rm -rf "$s"; fi
done'

log() { echo "$(date '+%F %T') $*" | tee -a "$LOG"; }
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; } # GNU, then BSD
# age_h <host>: age of on-<host>/.pulled in whole hours; exit 1 when there is no marker
age_h() {
  local m
  m=$(mtime "$DEST/on-$1/.pulled") && [ -n "$m" ] || return 1
  echo $((($(date +%s) - m) / 3600))
}

HOSTS=""
rc=0
# every host whose modules/hosts/<name>.nix sets dram.address (install/lib/roles.sh) AND
# still names a backupPeer: backups are paused until the NAS (decisions/0014), and a
# rebuilt host's file has no peer, so this pull winds down by itself host by host
# shellcheck source=install/lib/roles.sh
. "$REPO/install/lib/roles.sh"
for entry in $(host_addresses "$REPO"); do
  h=${entry%%=*}
  grep -qE '^[[:space:]]*(dram\.)?backupPeer[[:space:]]*=[[:space:]]*"[^"]+"' "$REPO/modules/hosts/$h.nix" || continue
  ip=${entry#*=}
  u=$(host_user "$REPO" "$h")
  HOSTS="$HOSTS $h"
  [ "$MODE" = pull ] || continue
  mkdir -p "$DEST"
  # once a day: launchd fires this at login as well as at 06:00
  if [ -n "$(find "$DEST/on-$h/.pulled" -mmin -"$FRESH_MIN" 2>/dev/null)" ]; then
    log "$h pulled $(age_h "$h") h ago, skipped (once a day)"
    continue
  fi
  if ! ssh "${SSH_OPTS[@]}" "$u@$ip" true 2>/dev/null; then
    log "$h unreachable, skipped"
    continue
  fi
  if ! ssh "${SSH_OPTS[@]}" "$u@$ip" "$REMOTE_STAGE" 2>>"$LOG"; then
    log "staging on $h FAILED (nothing pulled; the Mac copy is the previous one)"
    rc=1
    ssh "${SSH_OPTS[@]}" -O exit "$u@$ip" 2>/dev/null
    continue
  fi
  # the stage is a complete, lock-free copy of backups/borg/ as of a moment ago;
  # /.pulled is the Mac's own marker and must survive --delete.
  # one retry: a transient ssh/rsync failure gets a second chance after 30 s.
  pull() { rsync -a --delete --timeout=120 --exclude /.pulled \
    -e "ssh ${SSH_OPTS[*]}" \
    "$u@$ip:backups/borg-stage/" "$DEST/on-$h/" 2>>"$LOG"; }
  if pull || {
    sleep 30
    pull
  }; then
    touch "$DEST/on-$h/.pulled"
    log "pulled from $h: $(du -sh "$DEST/on-$h" | cut -f1)"
  else
    log "rsync from $h FAILED"
    rc=1
  fi
  ssh "${SSH_OPTS[@]}" -O exit "$u@$ip" 2>/dev/null
done

# Age of each copy. A pull run prints (and logs) only the WARN lines; --check
# prints one line per host and exits 1 when any copy is stale or missing.
stale=0
for h in $HOSTS; do
  if a=$(age_h "$h"); then
    if [ "$a" -ge "$STALE_H" ]; then
      msg="WARN $h: the Mac copy is $((a / 24)) days old (on-$h/.pulled); run: bash bin/pull-backups.sh"
      stale=1
    else
      msg="$h: the Mac copy is $a h old"
    fi
  else
    msg="WARN $h: no pull recorded yet (no $DEST/on-$h/.pulled); run: bash bin/pull-backups.sh"
    stale=1
  fi
  if [ "$MODE" = check ]; then
    echo "$msg"
  elif [ "${msg#WARN}" != "$msg" ]; then
    log "$msg"
  fi
done
[ "$MODE" = check ] && exit $stale
exit $rc

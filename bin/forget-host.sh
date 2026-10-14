#!/usr/bin/env bash
# usage: forget-host.sh <host> [--plan | --execute [--delete-backups] [--dry-run]]
#
# Mac side of retiring a host (the host side is system/decommission.sh).
# --plan (the default) prints what --execute would do and changes nothing.
# --execute, after the host name typed back: git rm modules/hosts/<host>.nix
# and hosts/<host>/ (flake.nix needs no edit: it reads the directory), drops
# the host from .sops.yaml (the `# host:` marker, the `&<host>` anchor and
# the `*<host>` reference) and runs `sops updatekeys -y secrets/pj.yaml` when
# sops is on PATH — it is not on the Mac, so it prints the command to run with
# a YubiKey (or on the backup peer, when the host had one) — removes the
# host's `<host>=<ip>` entry from the hardcoded list in bin/pull-backups.sh
# when it has one, prints the bin/sync-dram-repo.sh lines that name it (which
# host is builder and which consumer is a decision, not a sed), then runs
# bin/check.sh. The host's address comes from its own file (`address`).
# While backups are paused (decisions/0014) there is no peer and no Borg
# copy; with one, the Mac's copy of the host's OWN Borg repo,
# ~/backups/borg/on-<peer>/<host>/, goes only with --delete-backups and a
# second typed confirmation, and ~/backups/borg/on-<host>/ (the PEER's repo
# as that host stored it) is never deleted here. Peer-side steps and the
# UniFi / GitHub steps are printed for you. Nothing is committed. Runs on the
# Mac (bash 3.2).
#
#   --plan              print the plan (default)
#   --execute           do it, after the typed host name
#   --delete-backups    with --execute: also rm -rf ~/backups/borg/on-<peer>/<host>
#   --dry-run           with --execute: print the commands, change nothing, no prompt
#   -h, --help          this text
#
# needs:  git, awk, sed; sops for the recipient update (it prints the command without);
#         install/lib/roles.sh, .sops.yaml, bin/pull-backups.sh, bin/check.sh
# alone:  no: it edits this repo's host files, .sops.yaml and the pull list
# here:   by hand on the Mac, after system/decommission.sh --plan on the host
# exit:   0 ok · 1 refused (unknown host, name mismatch, no terminal) or check.sh failed · 2 bad usage
# see:    docs/records/handbook/10-teardown.md, docs/operations/releases/README.md

# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT

set -uo pipefail

HOST="" MODE=plan DRY=0 DEL_BACKUPS=0
for a in "$@"; do
  case "$a" in
    -h | --help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
  esac
done
while [ $# -gt 0 ]; do
  case "$1" in
    --plan) MODE=plan ;;
    --execute) MODE=execute ;;
    --dry-run) DRY=1 ;;
    --delete-backups) DEL_BACKUPS=1 ;;
    -*)
      sed -n '2s/^# \{0,1\}//p' "$0" >&2
      exit 2
      ;;
    *)
      [ -z "$HOST" ] || {
        sed -n '2s/^# \{0,1\}//p' "$0" >&2
        exit 2
      }
      HOST="$1"
      ;;
  esac
  shift
done
[ -n "$HOST" ] || {
  sed -n '2s/^# \{0,1\}//p' "$0" >&2
  exit 2
}

die() {
  printf '\033[1;31m[!]\033[0m %s\n' "$*" >&2
  exit 1
}
say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# --- facts --------------------------------------------------------------------
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1
MOD="modules/hosts/$HOST.nix"
[ -f "$MOD" ] || die "unknown host '$HOST' (hosts: $(for f in modules/hosts/*.nix; do basename "$f" .nix; done | paste -sd' ' -))"
nixval() { sed -n "s/^[[:space:]]*\(dram\.\)\{0,1\}$1[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\2/p" "$2" | head -1; }
PEER="$(nixval backupPeer "$MOD")"
# shellcheck source=install/lib/roles.sh
. "$REPO/install/lib/roles.sh"
PEER_USER="$(host_user "$REPO" "${PEER:-none}")" # logins: dram.user, default pj
HOST_USER="$(host_user "$REPO" "$HOST")"
PEER_ADDR="$(nixval backupPeerAddr "$MOD")"
# the host's own address: its host file's `address` first, then how the hosts that back
# up to it name it, then the pull-backups.sh list
ADDR="$(nixval address "$MOD")" DEPENDANTS=""
for f in modules/hosts/*.nix; do
  h="$(basename "$f" .nix)"
  [ "$h" != "$HOST" ] || continue
  if [ "$(nixval backupPeer "$f")" = "$HOST" ]; then
    DEPENDANTS="${DEPENDANTS:+$DEPENDANTS }$h"
    [ -n "$ADDR" ] || ADDR="$(nixval backupPeerAddr "$f")"
  fi
done
[ -n "$ADDR" ] || ADDR="$(sed -n "s/^for entry in .* $HOST=\([0-9.]*\).*/\1/p" bin/pull-backups.sh 2>/dev/null | head -1)"
BORG="$HOME/backups/borg"
OWN_REPO_COPY="$BORG/on-$PEER/$HOST"
STORED_COPY="$BORG/on-$HOST"
SOPS_HAS="$(grep -c "^  # host: $HOST\$" .sops.yaml)"
PULL_HAS="$(grep -c "^for entry in .*[ ]$HOST=" bin/pull-backups.sh)"
SYNC_HITS="$(grep -n -E "$HOST|${ADDR:-NOADDR}" bin/sync-dram-repo.sh | grep -v -E '^[0-9]+:[[:space:]]*#' || true)"
DOCS_HITS="$(git grep -l "hosts/$HOST/" -- docs README.md 2>/dev/null | grep -v '^docs/commands.md$' | paste -sd' ' - || true)"

present() { if [ -e "$1" ]; then echo "present"; else echo "absent"; fi; }
sz() { du -sh "$1" 2>/dev/null | cut -f1; }

# --- the plan (also the checklist --execute walks) ----------------------------
N=0
item() {
  N=$((N + 1))
  printf '\n\033[1m%2d. %s\033[0m  \033[2m[%s]\033[0m\n' "$N" "$1" "$2"
}
cmd() { printf '      $ %s\n' "$*"; }
note() { printf '      %s\n' "$*"; }

do_plan() {
  printf '\033[1mforget %s\033[0m  (its peer: %s @ %s; its address: %s; hosts backing up to it: %s)\n' \
    "$HOST" "${PEER:-none}" "${PEER_ADDR:-?}" "${ADDR:-unknown}" "${DEPENDANTS:-none}"
  echo "--plan changes nothing. Items marked [--execute] are what --execute does; the rest is yours, by hand."

  item "the host's module and harvest" "--execute"
  cmd "git rm -r -q $MOD hosts/$HOST"
  note "flake.nix needs no edit (modules/hosts/ is read at evaluation); bin/check.sh §2 then agrees."
  [ -n "$DOCS_HITS" ] && note "docs that reference hosts/$HOST/… (check.sh §6 fails on them after the rm): $DOCS_HITS"

  item "sops recipient" "--execute, then a surviving host"
  if [ "$SOPS_HAS" -gt 0 ]; then
    note ".sops.yaml: $(grep -A1 "^  # host: $HOST\$" .sops.yaml | tail -1 | sed 's/^ *//') + the '- *$HOST' reference under key_groups"
    cmd "awk … .sops.yaml     # drops the marker line, the anchor line and the reference"
    if have sops; then
      cmd "sops updatekeys -y secrets/pj.yaml"
    elif [ -n "$PEER" ] && [ -n "$PEER_ADDR" ]; then
      note "sops is not on this Mac: after pushing the commit, on $PEER:"
      cmd "ssh $PEER_USER@$PEER_ADDR 'cd ~/git/dotfiles && ~/.nix-profile/bin/sops updatekeys -y secrets/pj.yaml && git commit -am \"sops: forget $HOST\"'"
    else
      note "sops is not on this Mac: after pushing the commit, on any host with a YubiKey's identity stub (docs/security/identity/yubikeys.md):"
      cmd "SOPS_AGE_KEY_FILE=~/.config/sops/age/yubikey-primary.txt sops updatekeys -y secrets/pj.yaml && git commit -am 'sops: forget $HOST'"
    fi
    note "older commits of secrets/pj.yaml stay readable by $HOST's age key; that key is the host's to destroy (decommission.sh)."
  else
    note ".sops.yaml has no '# host: $HOST' marker — nothing to drop."
  fi

  item "bin/pull-backups.sh host list" "--execute"
  if [ "$PULL_HAS" -gt 0 ]; then
    note "$(grep -n '^for entry in ' bin/pull-backups.sh)"
    cmd "sed '/^for entry in /s/ $HOST=[0-9.]*//' bin/pull-backups.sh     # drops the $HOST=… token"
  else
    note "no '$HOST=…' token on the 'for entry in' line."
  fi

  item "bin/sync-dram-repo.sh" "by hand"
  if [ -n "$SYNC_HITS" ]; then
    printf '%s\n' "$SYNC_HITS" | sed 's/^/      /'
    note "builder (SRC) -> consumer (DST) is one pipe; with $HOST gone decide the new pair and edit the two lines, or git rm the script."
  else
    note "does not name $HOST."
  fi

  item "the Mac's Borg copies" "--delete-backups"
  note "$OWN_REPO_COPY: $(present "$OWN_REPO_COPY") ($(sz "$OWN_REPO_COPY" || echo -)) — $HOST's OWN archives, as $PEER stored them. The last copy once the peer's dir is gone."
  cmd "rm -rf $OWN_REPO_COPY     # only with --delete-backups, after a second typed confirmation"
  note "$STORED_COPY: $(present "$STORED_COPY") ($(sz "$STORED_COPY" || echo -)) — the repos $HOST STORED for others (${DEPENDANTS:-nobody}). Never deleted here."
  [ -n "$DEPENDANTS" ] && note "keep it until ${DEPENDANTS} has archives on a new target; then: rm -rf $STORED_COPY"
  note "Time Machine keeps what it already has of ~/backups/borg either way."

  item "bin/check.sh" "--execute"
  cmd "bash bin/check.sh     # docs/commands.md and docs that name hosts/$HOST/ may need a follow-up"

  if [ -n "$PEER" ] && [ -n "$PEER_ADDR" ]; then
    item "on $PEER (from this Mac, unrestricted key)" "by hand"
    cmd "ssh $PEER_USER@$PEER_ADDR \"grep -n ' $HOST_USER@$HOST\\$' ~/.ssh/authorized_keys\"      # the pinned borg-serve line"
    cmd "ssh $PEER_USER@$PEER_ADDR \"sed -i '/ $HOST_USER@$HOST\\$/d' ~/.ssh/authorized_keys\""
    cmd "ssh $PEER_USER@$PEER_ADDR 'du -sh backups/borg/$HOST && rm -rf backups/borg/$HOST'     # irreversible; item 5 is then the only copy"
  else
    item "the other hosts (from this Mac)" "by hand"
    note "no backup peer (backups are paused, decisions/0014): nothing of $HOST's lives on another host."
    note "its own key, if another host's ~/.ssh/authorized_keys lists it: ssh <user>@<host> \"sed -i '/ $HOST_USER@$HOST\\$/d' ~/.ssh/authorized_keys\""
  fi
  if [ -n "$DEPENDANTS" ]; then
    for d in $DEPENDANTS; do
      note "modules/hosts/$d.nix points its backups at $HOST — set backupPeer/backupPeerAddr to a surviving host, push, then on $d:"
      cmd "dram switch && borgmatic repo-create --encryption repokey-blake2 && dram backup"
    done
  fi
  cmd "ssh-keygen -R ${ADDR:-<ip>}     # this Mac's known_hosts"

  item "UniFi + GitHub" "by hand"
  note "UniFi: Settings -> VPN -> VPN Server -> WireGuard: delete client '$HOST'; release the DHCP reservation for ${ADDR:-its address} (docs/security/network/README.md)."
  note "GitHub -> Settings -> SSH and GPG keys: remove the authentication key AND the signing key '$HOST_USER@$HOST' (decommission.sh --plan prints the fingerprint)."

  item "commit" "by hand"
  cmd "git commit -m 'forget $HOST'"
  cmd "bin/release.sh -m 'forget $HOST'     # or bin/push-host.sh <user>@<address> to each remaining host"
}

# --- execute ------------------------------------------------------------------
run() {
  if [ "$DRY" = 1 ]; then
    printf '  \033[2m[dry-run] %s\033[0m\n' "$*"
  else
    printf '  $ %s\n' "$*"
    "$@"
  fi
}
# in-place edit that keeps the file's mode and works on bash 3.2 / BSD sed
rewrite() { # rewrite <file> <cmd...>   (cmd reads the file on stdin, writes stdout)
  local f="$1" tmp
  shift
  tmp="$(mktemp "$f.XXXXXX")"
  "$@" <"$f" >"$tmp" && cat "$tmp" >"$f"
  rm -f "$tmp"
}
sops_drop() { awk -v h="$HOST" '
  $1 == "#" && $2 == "host:" && $3 == h { skip = 1; next }
  skip == 1 && $1 == "-" && $2 == ("&" h) { skip = 0; next }
  $1 == "-" && $2 == ("*" h) { next }
  { print }'; }
pull_drop() { sed "/^for entry in /s/ $HOST=[0-9.]*//"; }

do_execute() {
  cat <<EOF

  ##########################################################################
  #  FORGET $HOST on this Mac
  #
  #  git rm $MOD + hosts/$HOST/, drop the sops recipient,
  #  edit bin/pull-backups.sh, run bin/check.sh. Nothing is committed.
$(if [ "$DEL_BACKUPS" = 1 ]; then printf '  #\n  #  --delete-backups: rm -rf %s\n  #  (%s'"'"'s own archives; asks again)' "$OWN_REPO_COPY" "$HOST"; else printf '  #'; fi)
  #  Not touched: $STORED_COPY (the peer's data), the peer, UniFi, GitHub.
  ##########################################################################

EOF
  if [ "$DRY" = 1 ]; then
    say "dry run: the commands, nothing changes"
  else
    [ -t 0 ] && [ -t 1 ] || die "refusing: --execute needs a terminal (no TTY). --dry-run shows the steps."
    printf 'type the host name (%s) to continue, anything else to stop: ' "$HOST"
    read -r answer
    [ "$answer" = "$HOST" ] || die "that is not '$HOST' — nothing done"
  fi

  say "module + harvest"
  run git rm -r -q "$MOD" "hosts/$HOST"

  say "sops recipient"
  if [ "$SOPS_HAS" -gt 0 ]; then
    run rewrite .sops.yaml sops_drop
    if have sops; then
      run sops updatekeys -y secrets/pj.yaml
    else
      echo "  sops not on this Mac — after pushing, on $PEER:"
      echo "    ssh $PEER_USER@$PEER_ADDR 'cd ~/git/dotfiles && ~/.nix-profile/bin/sops updatekeys -y secrets/pj.yaml && git commit -am \"sops: forget $HOST\"'"
    fi
  else
    echo "  nothing to drop"
  fi

  say "bin/pull-backups.sh"
  if [ "$PULL_HAS" -gt 0 ]; then run rewrite bin/pull-backups.sh pull_drop; else echo "  no entry"; fi

  say "bin/sync-dram-repo.sh (by hand)"
  if [ -n "$SYNC_HITS" ]; then printf '%s\n' "$SYNC_HITS" | sed 's/^/  /'; else echo "  does not name $HOST"; fi

  if [ "$DEL_BACKUPS" = 1 ]; then
    say "the Mac's copy of $HOST's own Borg repo: $OWN_REPO_COPY ($(sz "$OWN_REPO_COPY" || echo absent))"
    if [ -d "$OWN_REPO_COPY" ]; then
      if [ "$DRY" = 1 ]; then
        run rm -rf "$OWN_REPO_COPY"
      else
        printf 'this is irreversible. type "delete %s backups" to continue: ' "$HOST"
        read -r answer
        if [ "$answer" = "delete $HOST backups" ]; then run rm -rf "$OWN_REPO_COPY"; else echo "  kept"; fi
      fi
    else
      echo "  absent — nothing to delete"
    fi
  else
    say "Borg copies kept: $OWN_REPO_COPY (--delete-backups), $STORED_COPY (never here)"
  fi

  say "bin/check.sh"
  rc=0
  if [ "$DRY" = 1 ]; then run bash bin/check.sh; else bash bin/check.sh || rc=1; fi

  echo
  say "next: the peer-side, UniFi and GitHub items of --plan; then: git commit -m 'forget $HOST' && bin/push-host.sh $PEER_USER@$PEER_ADDR"
  return $rc
}

case "$MODE" in
  plan) do_plan ;;
  execute) do_execute ;;
esac

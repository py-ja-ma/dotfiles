#!/usr/bin/env bash
# usage: push-host.sh <ssh-target> [branch] [--force] | --wsl <host> <windows-ssh-target> [branch]
#
# Pushes this repo's committed state to a host's ~/git/dotfiles without
# touching gitignored runtime state there (themes/current, cava/config, the
# files dram-theme writes): git bundle (the branch + every tag) -> ssh pipe ->
# `git fetch` on the host. The hosts have no remote, so this is how release
# tags (bin/release.sh) and master reach them. What happens to the checkout
# depends on the host's channel (dram channel, docs/operations/releases/README.md):
#   on a branch (channel main)        `git reset --hard` to the pushed tip, as before
#   detached at a release (stable)    refs updated, checkout untouched; `dram update`
#                                     there moves it to the newest tag
# Tracked files update in place; untracked and ignored files are left alone.
# On a branch the host side refuses to reset over uncommitted edits to tracked
# files and names them: commit or stash them there, or pass --force to discard.
# A detached (stable) host is never reset, so its edits are left as they are.
# Needs a clean working tree here. Runs on the Mac.
#
# --wsl <host>: a WSL clone (form = "wsl" in modules/hosts/<host>.nix, decisions/0021)
# has no ssh of its own. The bundle goes to its Windows PC's OpenSSH instead
# (HostKeyAlias <wsl.windowsHost>-win, as install/windows/apply-windows.sh connects) and
# is staged as C:\ProgramData\dram\dotfiles.bundle, beside what
# dram-windows/wsl.ps1 builds the clone with (wsl.ps1, wslconfig, wsl.conf). In the
# clone `dram update` receives it first (dram receive). Nothing runs in the clone from
# here; a failed connection (Windows off, or cabin booted into Arch) changes nothing.
#
#   branch        the branch to push (default: the current one)
#   --force       discard uncommitted edits to tracked files on the host
#   -h, --help    this text
#
# needs:  git, ssh, scp; install/lib/roles.sh for --wsl; ~/git/dotfiles cloned on the host
# alone:  yes, for hosts without a git remote: change the ~/git/dotfiles path in the
#         host-side block
# here:   bin/release.sh runs it for each host with dram.address; by hand on the Mac
# env:    DRAM_WIN_SSH   extra ssh/scp options for --wsl (as for apply-windows.sh)
# exit:   0 ok · 1 dirty tree here, uncommitted edits there, or ssh failed · 2 bad usage
# see:    docs/operations/releases/pushes.md, docs/platforms/wsl/README.md

# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT

usage_line() { sed -n '2s/^# \{0,1\}//p' "$0" >&2; }
case "${1:-}" in
  -h | --help)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac
set -euo pipefail
WSLHOST=""
if [ "${1:-}" = --wsl ]; then
  WSLHOST="${2:-}"
  [ $# -ge 3 ] && [ -n "$WSLHOST" ] || {
    usage_line
    exit 2
  }
  shift 2
fi
case "${1:-}" in
  "" | -*)
    usage_line
    exit 2
    ;;
esac
TARGET="$1"
shift
BRANCH="" FORCE=0
for a in "$@"; do
  case "$a" in
    --force) FORCE=1 ;;
    -*)
      usage_line
      exit 2
      ;;
    *) BRANCH="$a" ;;
  esac
done
[ -n "$BRANCH" ] || BRANCH="$(git rev-parse --abbrev-ref HEAD)"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"
[ -z "$(git status --porcelain)" ] || {
  echo "error: uncommitted changes; commit first" >&2
  exit 1
}
B=$(mktemp -t dotfiles.XXXXXX.bundle)
# the trap also fires when the ssh copy below fails under set -e
trap 'rm -f "$B"' EXIT
git bundle create -q "$B" "$BRANCH" --tags # tags ride along: releases are tags (bin/release.sh)

if [ -n "$WSLHOST" ]; then
  # shellcheck source=install/lib/roles.sh
  . "$REPO/install/lib/roles.sh"
  [ "$(host_form "$REPO" "$WSLHOST")" = wsl ] || {
    echo "error: modules/hosts/$WSLHOST.nix is not a WSL clone (form = \"wsl\"); push a metal host without --wsl" >&2
    exit 1
  }
  WIN="$(host_wsl "$REPO" "$WSLHOST" windowsHost)"
  [ -n "$WIN" ] || {
    echo "error: modules/hosts/$WSLHOST.nix sets no wsl.windowsHost" >&2
    exit 1
  }
  # Windows' host key under its own alias, never Arch's at the same address: when cabin runs
  # Arch the key differs and ssh refuses, so nothing is copied to the wrong system
  # shellcheck disable=SC2206 # DRAM_WIN_SSH is a list of options, split into words
  O=(-o "HostKeyAlias=$WIN-win" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o LogLevel=ERROR ${DRAM_WIN_SSH:-})
  D='C:\ProgramData\dram'
  ssh "${O[@]}" "$TARGET" "if not exist $D mkdir $D" >/dev/null || {
    echo "error: ssh to $TARGET as $WIN-win failed (Windows on, its OpenSSH up? cabin may be booted into Arch)" >&2
    exit 1
  }
  # the bundle under a temporary name, then renamed: a clone never reads half a file
  scp -q "${O[@]}" "$B" "$TARGET:C:/ProgramData/dram/dotfiles.bundle.part"
  ssh "${O[@]}" "$TARGET" "move /y $D\\dotfiles.bundle.part $D\\dotfiles.bundle" >/dev/null
  # what dram-windows/wsl.ps1 builds the clone with, from this same commit
  scp -q "${O[@]}" "$REPO/install/windows/dram-windows/wsl.ps1" "$TARGET:C:/ProgramData/dram/wsl.ps1"
  scp -q "${O[@]}" "$REPO/install/windows/wslconfig" "$TARGET:C:/ProgramData/dram/wslconfig"
  scp -q "${O[@]}" "$REPO/system/wsl/wsl.conf" "$TARGET:C:/ProgramData/dram/wsl.conf"
  echo "staged for $WSLHOST on $WIN-win: $D\\dotfiles.bundle ($BRANCH $(git log -1 --format=%h "$BRANCH"), $(git tag -l 'v*' --sort=-v:refname | head -1)), wsl.ps1, wslconfig, wsl.conf"
  echo "in the clone: dram update (it receives the bundle first), or dram receive; a new clone: wsl.ps1 (docs/platforms/wsl/README.md)"
  exit 0
fi
# ssh pipe rather than scp: the sftp subsystem dropped the connection on cabin under load (2026-10-05)
ssh "$TARGET" 'cat > /tmp/dotfiles.bundle' <"$B"
ssh "$TARGET" bash -s "$BRANCH" "$FORCE" <<'REMOTE'
set -euo pipefail
BR="$1" FORCE="$2"
cd ~/git/dotfiles 2>/dev/null || { echo "error: ~/git/dotfiles missing on host; clone it first" >&2; exit 1; }
ON_BRANCH=0
git symbolic-ref -q HEAD >/dev/null && ON_BRANCH=1
if [ "$ON_BRANCH" -eq 1 ]; then
  # only the branch arm resets the checkout, so only there can edits be lost
  DIRTY="$(git status --porcelain --untracked-files=no)"
  if [ -n "$DIRTY" ] && [ "$FORCE" != 1 ]; then
    echo "error: uncommitted changes to tracked files on $(hostname) — reset --hard would discard them:" >&2
    echo "$DIRTY" | sed 's/^/    /' >&2
    echo "commit or stash them on the host, or re-run with --force to discard." >&2
    rm -f /tmp/dotfiles.bundle
    exit 1
  fi
  [ -n "$DIRTY" ] && echo "--force: discarding host edits to: $(echo "$DIRTY" | awk '{print $2}' | tr '\n' ' ')"
fi
git fetch -q /tmp/dotfiles.bundle "$BR"
if [ "$ON_BRANCH" -eq 1 ]; then
  # on a branch (channel main): the checkout follows the push, as it always has
  git reset -q --hard FETCH_HEAD
else
  # detached at a release (channel stable): move the branch ref only; the
  # checkout (edits included) stays on its release until `dram update` applies
  # the newest tag
  git update-ref "refs/heads/$BR" FETCH_HEAD
fi
# the tags: `git fetch <bundle> <branch>` does not carry them; + = a re-cut tag wins
git fetch -q /tmp/dotfiles.bundle '+refs/tags/*:refs/tags/*' 2>/dev/null || true
rm -f /tmp/dotfiles.bundle
if git symbolic-ref -q HEAD >/dev/null; then
  echo "host now at $(git log -1 --format='%h %s' | cut -c1-70)"
else
  echo "host checkout stays at $(git describe --tags --exact-match 2>/dev/null || git rev-parse --short HEAD) (detached: channel stable); $BR -> $(git log -1 --format=%h "$BR")$(t="$(git tag -l 'v*' --sort=-v:refname | head -1)"; [ -n "$t" ] && echo ", newest tag $t — dram update there applies it")"
fi
echo "runtime state intact: themes/current -> $(readlink dotfiles/.config/themes/current 2>/dev/null || echo '(not set - run dram-theme or dram-switch)')"
REMOTE

#!/usr/bin/env bash
# usage: release.sh -m "<summary>" [--dry-run] [--checkpoint] [--no-push]
#
# Cuts a release on the Mac. A build is a commit; a release is an annotated
# tag vYYYY.MM.N on one (calendar, like SteamOS build ids). In order:
#   1. the tree is clean, on master, and `bash bin/check.sh` is green
#   2. the next tag for today: vYYYY.MM.N, N = 1 + the highest N this month
#   3. CHANGELOG.md gets a section at the top: the tag and the date, the summary,
#      then the commits since the previous tag grouped Removed, Added, Changed,
#      Fixed, Security by each commit's `Changelog:` trailer (no trailer: Changed;
#      `Changelog: skip` leaves the commit out; docs/records/changelog.md)
#   4. commit "release vX: <summary>", then `git tag -a vX -m "<summary>"`
#   5. bin/push-host.sh <user>@<address> for every modules/hosts/*.nix that sets
#      dram.address (tags ride in the bundle). A host on channel stable moves
#      to the tag with `dram update` there; one on main is reset to it now.
#      A WSL clone (form = "wsl") gets `push-host.sh --wsl`: the bundle is staged
#      on its Windows PC, and a failure there (Windows off, or cabin in Arch) is
#      a warning, not a failed release: the clone catches up at the next push.
#
#   -m <summary>   one line for the tag annotation and the CHANGELOG section (required unless --dry-run)
#   --checkpoint   a build every host must pass through: the word "checkpoint"
#                  goes into the annotation and `dram update` stops at it
#   --dry-run      print the tag, the CHANGELOG section and the push targets; change nothing
#   --no-push      commit and tag, skip the pushes (bin/push-host.sh later)
#   -h, --help     this text
#
# needs:  git, ssh; bin/check.sh, bin/push-host.sh, install/lib/roles.sh; runs on the Mac
# alone:  yes, with a push script and a check script of your own; releases are cut
#         from master and the hosts' addresses come from modules/hosts/*.nix
# here:   by hand on the Mac; CHANGELOG.md is its output, and dram changelog reads it
# exit:   0 ok · 1 dirty tree, not on master, check.sh failed, nothing new, or a push failed · 2 bad usage
# see:    docs/operations/releases/README.md

# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT

case "${1:-}" in
  -h | --help)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac
set -euo pipefail

SUMMARY="" DRY=0 CHECKPOINT=0 PUSH=1
while [ $# -gt 0 ]; do
  case "$1" in
    -m)
      SUMMARY="${2:-}"
      shift
      ;;
    -m*) SUMMARY="${1#-m}" ;;
    --dry-run) DRY=1 ;;
    --checkpoint) CHECKPOINT=1 ;;
    --no-push) PUSH=0 ;;
    *)
      sed -n '2s/^# \{0,1\}//p' "$0" >&2
      exit 2
      ;;
  esac
  shift
done
if [ -z "$SUMMARY" ] && [ "$DRY" -eq 0 ]; then
  echo "error: -m \"<summary>\" is required (one line: what this release is)" >&2
  sed -n '2s/^# \{0,1\}//p' "$0" >&2
  exit 2
fi
[ -n "$SUMMARY" ] || SUMMARY="(dry run: no summary given)"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"
say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}

# --- 1) preconditions ------------------------------------------------------------------
say "Preconditions"
[ -z "$(git status --porcelain)" ] || die "uncommitted changes — commit first (a release is a commit)"
[ "$(git rev-parse --abbrev-ref HEAD)" = master ] || die "not on master (releases are cut from master; the hosts' main channel is master)"
ok "tree clean, on master at $(git log -1 --format='%h %s' | cut -c1-70)"
CHECKLOG="$(mktemp "${TMPDIR:-/tmp}/release-check.XXXXXX")"
if bash bin/check.sh >"$CHECKLOG" 2>&1; then
  ok "bin/check.sh: $(tail -1 "$CHECKLOG" | sed 's/\x1b\[[0-9;]*m//g')"
  rm -f "$CHECKLOG"
else
  tail -15 "$CHECKLOG"
  die "bin/check.sh failed — fix it first (log: $CHECKLOG)"
fi

# --- 2) the next tag -------------------------------------------------------------------
PREV="$(git tag -l 'v*' --sort=-v:refname | head -1)"
MONTH="v$(date +%Y.%m)"
N=0
for t in $(git tag -l "$MONTH.*"); do
  n="${t##*.}"
  case "$n" in *[!0-9]*) continue ;; esac
  [ "$n" -gt "$N" ] && N="$n"
done
TAG="$MONTH.$((N + 1))"
if [ -n "$PREV" ]; then
  [ "$(git rev-parse "$PREV^{commit}")" != "$(git rev-parse HEAD)" ] || die "HEAD is already released as $PREV — nothing new to tag"
  RANGE="$PREV..HEAD"
else
  RANGE="HEAD"
fi
COUNT="$(git rev-list --count $RANGE)"
[ "$COUNT" -gt 0 ] || die "no commits since $PREV"
say "Release $TAG (previous: ${PREV:-none}; $COUNT commit(s))"

# --- 3) the CHANGELOG section ----------------------------------------------------------
# Keep a Changelog's groups (docs/records/changelog.md): a commit's `Changelog:` trailer
# (added, changed, fixed, removed, security) picks its group, `Changelog: skip` leaves it
# out, and a commit without the trailer is Changed. Removed comes first, so what went is
# read before what came. The entry is the commit's subject. The first release (no
# previous tag) lists the last 40 commits and says how many came before.
LIMIT=""
NOTE=""
if [ -z "$PREV" ] && [ "$COUNT" -gt 40 ]; then
  LIMIT="-n 40"
  NOTE="(first release: the $((COUNT - 40)) commits before these are in \`git log\`)"
fi
# one line per commit: <group><TAB><subject>
# shellcheck disable=SC2086
ENTRIES="$(git log $RANGE $LIMIT --no-merges --format='%(trailers:key=Changelog,valueonly,separator=%x20)%x09%s' \
  | awk -F'\t' '{ g = tolower($1); sub(/ .*/, "", g)
      if (g == "skip") next
      if (g !~ /^(added|changed|fixed|removed|security)$/) g = "changed"
      print g "\t" $2 }')"
SECTION="## $TAG ($(date +%Y-%m-%d))

$SUMMARY$(if [ "$CHECKPOINT" -eq 1 ]; then printf ' Checkpoint: every host passes through this build (`dram update` twice).'; fi)
"
for g in removed added changed fixed security; do
  lines="$(printf '%s\n' "$ENTRIES" | awk -F'\t' -v g="$g" '$1 == g { print "- " $2 }')"
  [ -n "$lines" ] && SECTION="$SECTION
### $(printf '%s' "${g:0:1}" | tr '[:lower:]' '[:upper:]')${g:1}
$lines
"
done
[ -n "$NOTE" ] && SECTION="$SECTION
$NOTE
"
# The intro above the first `## v` is written once (HEADER) and then kept as it is
# in the file, so hand edits to it survive a release.
HEADER="# Changelog

Release notes, newest first: one section per release tag, written by \`bin/release.sh\`
from the commits since the previous tag. On a host \`dram changelog\` prints the latest
section, \`dram changelog vX\` one release, \`dram changelog --since vX\` everything newer
(\`docs/operations/releases/README.md\`). How a section is written: \`docs/records/changelog.md\`."
if [ -f CHANGELOG.md ]; then
  INTRO="$(awk '/^## v/ { exit } { print }' CHANGELOG.md)"
  [ -n "$(printf '%s' "$INTRO" | tr -d '[:space:]')" ] || INTRO="$HEADER"
  BODY="$(awk 'f { print } /^## v/ && !f { f = 1; print }' CHANGELOG.md)"
  NEW="$INTRO

$SECTION
$BODY"
else
  NEW="$HEADER

$SECTION"
fi

say "CHANGELOG.md section"
printf '%s\n' "$SECTION"
say "Tag annotation"
ANNOT="$SUMMARY"
[ "$CHECKPOINT" -eq 1 ] && ANNOT="$SUMMARY

checkpoint: every host must pass through this build before a later one."
printf '%s\n' "$ANNOT" | sed 's/^/    /'

# --- 4) push targets (listed before the commit so --dry-run shows them) ----------------
TARGETS=""
# shellcheck source=install/lib/roles.sh
. "$REPO/install/lib/roles.sh"
for h in modules/hosts/*.nix; do
  name="$(basename "$h" .nix)"
  # both spellings: `address = "..."` inside `dram = { ... }` and `dram.address = "..."`
  addr="$(sed -nE 's/^[[:space:]]*(dram\.)?address[[:space:]]*=[[:space:]]*"([^"]+)".*/\2/p' "$h" | head -1)"
  if [ -n "$addr" ]; then TARGETS="$TARGETS $name=$(host_user "$REPO" "$name")@$addr"; else warn "$h sets no dram.address — not pushed"; fi
done
say "Push targets (bin/push-host.sh)"
for t in $TARGETS; do
  if [ "$(host_form "$REPO" "${t%%=*}")" = wsl ]; then
    echo "    ${t%%=*}  ${t#*=}  (WSL clone: staged through Windows' OpenSSH, HostKeyAlias $(host_wsl "$REPO" "${t%%=*}" windowsHost)-win)"
  else echo "    ${t%%=*}  ${t#*=}"; fi
done
[ -n "$TARGETS" ] || warn "no host has dram.address — nothing will be pushed"

if [ "$DRY" -eq 1 ]; then
  say "Dry run: nothing written, tagged or pushed. Next: bin/release.sh -m \"<summary>\""
  exit 0
fi

# --- 5) commit + tag -------------------------------------------------------------------
say "Committing CHANGELOG.md and tagging $TAG"
printf '%s\n' "$NEW" >CHANGELOG.md # final newline: .editorconfig insert_final_newline
git add CHANGELOG.md
git commit -q -m "release $TAG: $SUMMARY"
git tag -a "$TAG" -m "$ANNOT"
ok "$TAG -> $(git log -1 --format='%h %s' | cut -c1-70)"

# --- 6) push ---------------------------------------------------------------------------
[ "$PUSH" -eq 1 ] || {
  say "Not pushed (--no-push). Later: bin/push-host.sh <user>@<address> for each host."
  exit 0
}
rc=0
for t in $TARGETS; do
  say "Push -> ${t%%=*} (${t#*=})"
  if [ "$(host_form "$REPO" "${t%%=*}")" = wsl ]; then
    # the clone's Windows PC may be off, or cabin booted into Arch: not a failed release
    if bin/push-host.sh --wsl "${t%%=*}" "${t#*=}" master; then ok "${t%%=*}: $TAG staged on its Windows PC (dram update in the clone)"; else
      warn "${t%%=*}: not staged (its Windows PC is off or in another OS) — later: bin/push-host.sh --wsl ${t%%=*} ${t#*=}"
    fi
    continue
  fi
  if bin/push-host.sh "${t#*=}" master; then ok "${t%%=*} has $TAG"; else
    warn "push to ${t%%=*} failed — retry: bin/push-host.sh ${t#*=}"
    rc=1
  fi
done
say "Released $TAG. On a host: dram update --check, dram changelog, dram update."
exit "$rc"

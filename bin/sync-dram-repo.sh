#!/usr/bin/env bash
# usage: sync-dram-repo.sh
#
# Carries the [dram] package repo from the builder (the host with the builder role,
# /srv/dram) to every other host with a dram.address (/var/lib/dram-repo) through the
# Mac: the hosts' keys for each other are pinned to `borg serve`, so cabin cannot rsync
# to lantern directly, and the Mac holds unrestricted keys to both. The mirror stays at
# ~/backups/dram/. Signatures travel with the files (a tampered copy fails
# `SigLevel = Required DatabaseRequired`). Runs on the Mac.
#
#   -h, --help    this text
#
# needs:  rsync (openrsync on macOS 26 takes the flags), ssh; install/lib/roles.sh and
#         the host files' roles and addresses
# alone:  yes, with the two paths and the host list made your own
# here:   by hand on the Mac after each `dram pkgs publish` on the builder
# exit:   0 ok · 1 an rsync failed · 2 bad usage
# see:    docs/operations/releases/pushes.md, docs/toolchain/packaging/README.md

# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT

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

set -euo pipefail
# Who is who comes from the host files (decisions/0009): the one host with the builder
# role is the source; every other host with a dram.address receives the repo.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=install/lib/roles.sh
. "$REPO/install/lib/roles.sh"
BUILDER=$(hosts_with_role "$REPO" builder)
[ "$(printf '%s\n' "$BUILDER" | grep -c .)" -eq 1 ] || {
  echo "error: want exactly one host with the builder role, found: ${BUILDER:-none}" >&2
  exit 1
}
ADDRS=$(host_addresses "$REPO")
SRC_ADDR=$(printf '%s\n' "$ADDRS" | sed -n "s/^$BUILDER=//p")
[ -n "$SRC_ADDR" ] || {
  echo "error: modules/hosts/$BUILDER.nix sets no dram.address" >&2
  exit 1
}
SRC=$(host_user "$REPO" "$BUILDER")@$SRC_ADDR:/srv/dram/
MIRROR="$HOME/backups/dram/"
mkdir -p "$MIRROR"
# --delay-updates --delete-delay: files land as temporaries and are renamed, and
# deletions run, only after the whole transfer — pacman on lantern never sees a
# new dram.db.sig next to an old dram.db.tar.zst or a db that names a missing file
# (openrsync on macOS 26 and rsync 3.5 on Arch both take the flags).
rsync -a --delete --delay-updates --delete-delay -e "ssh -o BatchMode=yes" "$SRC" "$MIRROR"
# an emptied or half-built /srv/dram on the builder must not --delete the others' repos
[ -s "$MIRROR/dram.db.tar.zst" ] || {
  echo "error: $MIRROR has no dram.db.tar.zst after the pull from $BUILDER — not pushing" >&2
  exit 1
}
n=$(find "$MIRROR" -name '*.pkg.tar.zst' | wc -l | tr -d ' ')
for entry in $ADDRS; do
  [ "${entry%%=*}" = "$BUILDER" ] && continue
  rsync -a --delete --delay-updates --delete-delay -e "ssh -o BatchMode=yes" "$MIRROR" "$(host_user "$REPO" "${entry%%=*}")@${entry#*=}:/var/lib/dram-repo/"
  echo "synced $n package(s) + db to ${entry%%=*}"
done
echo "Mac mirror at $MIRROR"

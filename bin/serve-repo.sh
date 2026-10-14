#!/usr/bin/env bash
# usage: serve-repo.sh [--port N | --out FILE]
#
# Hands this repo to a machine booted from the Arch ISO (handbook 01 §4): a clone of the
# checked-out branch with every release tag (the installed host's `dram update` follows
# the tags), packed as a tar — the ISO has curl and tar but no git — with its sha256 and
# the commands to type in the ISO, served over HTTP on this machine's LAN address until
# Ctrl-C. Only committed work travels (a clean tree is required, and the clone is made
# from a bundle of the branch); the sha256 typed in the ISO is what proves the download
# is the tar made here. No macOS ._* metadata files. Runs on the Mac (or any machine
# with git, tar and python3).
#
#   --port N      the HTTP port (default 8000)
#   --out FILE    write the tar to FILE (a USB stick, no network between the machines) and stop
#   -h, --help    this text
#
# exit: 0 stopped with Ctrl-C · 1 dirty tree, no LAN address, or the clone or tar failed · 2 bad usage
# see: docs/records/handbook/01-install.md, docs/platforms/arch/install.md

PORT=8000 OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --port)
      PORT="${2:-}"
      [[ $PORT =~ ^[0-9]{2,5}$ ]] || {
        sed -n '2s/^# \{0,1\}//p' "$0" >&2
        exit 2
      }
      shift
      ;;
    --out)
      OUT="${2:-}"
      [ -n "$OUT" ] || {
        sed -n '2s/^# \{0,1\}//p' "$0" >&2
        exit 2
      }
      shift
      ;;
    -h | --help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      sed -n '2s/^# \{0,1\}//p' "$0" >&2
      exit 2
      ;;
  esac
  shift
done

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}
[ -z "$(git -C "$REPO" status --porcelain)" ] || die "uncommitted changes in $REPO — commit them first (only committed work travels)"
BRANCH="$(git -C "$REPO" symbolic-ref --short HEAD 2>/dev/null)" || die "detached HEAD — check out the branch to install"

# this machine's LAN address: macOS names its interfaces en0, en1 …; Linux asks the route
IP=""
if [ -z "$OUT" ]; then
  if command -v ipconfig >/dev/null 2>&1; then
    for i in en0 en1 en2 en3 en4 en5 en6 en7 en8; do
      IP="$(ipconfig getifaddr "$i" 2>/dev/null)" && [ -n "$IP" ] && break
    done
  fi
  [ -n "$IP" ] || IP="$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p')"
  [ -n "$IP" ] || die "no LAN address found (is this machine on the network?)"
fi

DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
# the branch and the tags only, through a bundle, so nothing else of this clone travels
git -C "$REPO" bundle create "$DIR/dotfiles.bundle" "$BRANCH" --tags 2>/dev/null || die "git bundle create failed"
git clone -q -b "$BRANCH" "$DIR/dotfiles.bundle" "$DIR/dotfiles" || die "git clone of the bundle failed"
git -C "$DIR/dotfiles" remote remove origin
mkdir "$DIR/www"
# macOS tar writes ._* AppleDouble files for extended attributes unless told not to
TARFLAGS=(--no-xattrs)
[ "$(uname -s)" = Darwin ] && TARFLAGS+=(--no-mac-metadata)
COPYFILE_DISABLE=1 tar "${TARFLAGS[@]}" -C "$DIR/dotfiles" -cf "$DIR/www/dotfiles.tar" . || die "tar failed"
if command -v sha256sum >/dev/null 2>&1; then SUM="$(sha256sum "$DIR/www/dotfiles.tar" | cut -c1-64)"; else SUM="$(shasum -a 256 "$DIR/www/dotfiles.tar" | cut -c1-64)"; fi
if [ -n "$OUT" ]; then
  cp "$DIR/www/dotfiles.tar" "$OUT" || die "could not write $OUT"
  cat <<EOF
Wrote $BRANCH at $(git -C "$REPO" rev-parse --short HEAD) with $(git -C "$REPO" tag -l | grep -c .) tag(s) to $OUT
  sha256 $SUM
In the Arch ISO (as root), the stick mounted at /media:
  sha256sum /media/$(basename "$OUT")   # must print $SUM
  mkdir /root/dotfiles && tar -xf /media/$(basename "$OUT") -C /root/dotfiles
EOF
  exit 0
fi

cat <<EOF
Serving $BRANCH at $(git -C "$REPO" rev-parse --short HEAD) with $(git -C "$REPO" tag -l | grep -c .) tag(s)
  sha256 $SUM
In the Arch ISO (as root):
  curl -fO http://$IP:$PORT/dotfiles.tar
  sha256sum dotfiles.tar             # must print $SUM
  mkdir /root/dotfiles && tar -xf dotfiles.tar -C /root/dotfiles
Ctrl-C here when the download is done.
EOF
cd "$DIR/www" && python3 -m http.server "$PORT" --bind "$IP"

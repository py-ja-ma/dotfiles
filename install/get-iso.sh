#!/usr/bin/env bash
# usage: get-iso.sh [DIR]
#
# Downloads the pinned Arch ISO (install/iso.pin) and its signature into DIR
# (default ~/vm-bench/iso), then verifies the sha256 AND the release signature
# against the pinned key fingerprint, in a throwaway GnuPG home. Prints the
# path of the verified ISO. Runs on the Mac or any Linux with curl + gpg; write
# it to a USB stick yourself (dd / Disk Utility) after it says OK.
#
#   -h, --help    this text
#
# exit: 0 verified · 1 download, checksum or signature failed · 2 bad usage
# see: decisions/0010-install-path.md

case "${1:-}" in
  -h | --help)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  -*)
    sed -n '2s/^# \{0,1\}//p' "$0" >&2
    exit 2
    ;;
esac

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install/iso.pin
. "$HERE/iso.pin"
DIR="${1:-$HOME/vm-bench/iso}"
ISO="archlinux-$VERSION-x86_64.iso"
die() {
  echo "error: $*" >&2
  exit 1
}
mkdir -p "$DIR" || die "cannot create $DIR"
for f in "$ISO" "$ISO.sig"; do
  [ -s "$DIR/$f" ] && continue
  curl -fL --retry 3 -o "$DIR/$f.part" "$MIRROR/$VERSION/$f" && mv "$DIR/$f.part" "$DIR/$f" || die "download of $f failed"
done
got="$(shasum -a 256 "$DIR/$ISO" 2>/dev/null || sha256sum "$DIR/$ISO")"
[ "${got%% *}" = "$SHA256" ] || die "sha256 mismatch for $ISO (got ${got%% *})"
G="$(mktemp -d)"
trap 'rm -rf "$G"' EXIT
GNUPGHOME="$G" gpg --batch --quiet --auto-key-locate clear,wkd --locate-external-keys "$RELEASE_KEY_UID" >/dev/null 2>&1 \
  || die "could not fetch $RELEASE_KEY_UID by WKD"
GNUPGHOME="$G" gpg --batch --status-fd 1 --verify "$DIR/$ISO.sig" "$DIR/$ISO" 2>/dev/null \
  | grep -q "^\[GNUPG:\] VALIDSIG $RELEASE_KEY_FPR " || die "signature does not verify against $RELEASE_KEY_FPR"
echo "OK $DIR/$ISO (sha256 + signature by $RELEASE_KEY_FPR)"

#!/usr/bin/env bash
# usage: apply-windows.sh [--host USER@ADDR] [--build NAME] [--debloat] [--dry-run] [--stage DIR]
#
# Converges a Windows PC to its rendered build over SSH, from the Mac or from Arch
# (decisions/0020, docs/platforms/windows/dram-ps1.md): the way in before bin/push-windows.sh
# and dram.ps1, and beside them. The build is windows/build/NAME/ (default cabin-win),
# rendered from windows/ by bin/render-windows.sh and committed; a stale one is refused.
# Everything its manifest.json lists is staged through install/lib/windows-stage.sh, as
# bin/push-windows.sh stages it: the render (build\: the winget documents and manifest.json, its
# release (git describe) and commit filled in), the units' PowerShell (windows/units/), the
# converge's scripts (dram-windows/*.ps1), the Letterpress files and the masthead's Zebar pack
# (install/windows/letterpress/, bin/gen-windows-look.py), the art, the "pj" seal, the files
# Arch shares with Windows, and the house fonts and the Adwaita pointer of
# install/windows/fonts.pin and cursors.pin (each download cached in ~/.cache/dram/fonts or
# ~/.cache/dram/cursors and refused unless its sha256 matches; only the pinned members are
# taken out of it, bsdtar). Every staged file is checked against the manifest's sha256 here,
# and again on Windows before anything is applied. A directory the build stages into is the
# build's and is replaced whole (fonts\ and cursors\ only when they changed; build\ is copied
# over, since dram.ps1 keeps its own records there); build\manifest.json goes last. Then
# converge.ps1 runs there: the build's phases in order, debloat.ps1 first with --debloat, the
# look on the signed-in desktop last. Running it again changes only what drifted. Needs
# Windows' OpenSSH on and an administrator login (docs/platforms/windows/README.md); extra
# ssh/scp options come
# from DRAM_WIN_SSH (e.g. a ControlPath or -i KEY), HostKeyAlias=NAME always, so Windows' host
# key never clashes with Arch's for the same address.
#
#   --host USER@ADDR   default: user and address of windows/hosts/NAME.nix (pj@cabin)
#   --build NAME       the build in windows/build/ to apply (default cabin-win)
#   --debloat          also run debloat.ps1 (phase 00)
#   --dry-run          `winget configure test` and every script's dry run; the files are
#                      still staged, nothing is applied
#   --stage DIR        assemble the build in DIR, as it would land in C:\ProgramData\dram
#                      (checked, the release filled in), and stop: no ssh
#   -h, --help         this text
#
# exit: 0 converged (or already) · 1 a stale build, or a download, check, copy or unit failed · 2 bad usage
# see: docs/platforms/windows/dram-ps1.md, install/windows/fonts.pin, install/windows/cursors.pin

HOST="" BUILD=cabin-win DEBLOAT=0 DRY=0 ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --host)
      HOST="${2:-}"
      [ -n "$HOST" ] || {
        sed -n '2s/^# \{0,1\}//p' "$0" >&2
        exit 2
      }
      shift
      ;;
    --build)
      BUILD="${2:-}"
      shift
      ;;
    --stage)
      ONLY="${2:-}"
      [ -n "$ONLY" ] || {
        sed -n '2s/^# \{0,1\}//p' "$0" >&2
        exit 2
      }
      shift
      ;;
    --debloat) DEBLOAT=1 ;;
    --dry-run) DRY=1 ;;
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
case "$BUILD" in "" | *[!a-z0-9-]*)
  sed -n '2s/^# \{0,1\}//p' "$0" >&2
  exit 2
  ;;
esac

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}
# shellcheck source=install/lib/windows-stage.sh
. "$REPO/install/lib/windows-stage.sh"
M="$REPO/windows/build/$BUILD/manifest.json"
[ -f "$M" ] || die "no windows/build/$BUILD (bin/render-windows.sh $BUILD)"
if [ -z "$HOST" ]; then
  f="$REPO/windows/hosts/$BUILD.nix"
  addr="$(sed -nE 's/^[[:space:]]*address[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$f" 2>/dev/null | head -1)"
  user="$(sed -nE 's/^[[:space:]]*user[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$f" 2>/dev/null | head -1)"
  [ -n "$addr" ] || die "windows/hosts/$BUILD.nix names no address: --host USER@ADDR"
  HOST="${user:-pj}@$addr"
fi
# shellcheck disable=SC2206 # DRAM_WIN_SSH is a list of options, split by the shell
O=(-o "HostKeyAlias=$BUILD" -o LogLevel=ERROR ${DRAM_WIN_SSH:-})
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
R="$STAGE/root"

say "build windows/build/$BUILD"
if [ -f "$REPO/bin/render-windows.sh" ]; then
  bash "$REPO/bin/render-windows.sh" --check "$BUILD" \
    || die "windows/build/$BUILD is stale: bin/render-windows.sh $BUILD, commit windows/build, then apply"
else
  printf '\033[1;33m[!]\033[0m bin/render-windows.sh is not in this tree: the render'"'"'s freshness is not checked (each file'"'"'s sha256 still is)\n'
fi
win_stage_build "$REPO" "$M" "$R"
# the render itself (the documents are files[] entries already) and its release, filled in
mkdir -p "$R/build" && cp "$M" "$R/build/manifest.json" || die "could not stage manifest.json"
win_fill_release "$R/build/manifest.json" "$(git -C "$REPO" describe --tags --always --dirty 2>/dev/null || echo unknown)" \
  "$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
if [ -n "$ONLY" ]; then
  mkdir -p "$ONLY" && cp -R "$R/." "$ONLY/" || die "could not copy the build to $ONLY"
  echo "   staged in $ONLY (nothing copied to Windows)"
  exit 0
fi

# --- copy to C:\ProgramData\dram -----------------------------------------------------------
say "copy to $HOST:C:\\ProgramData\\dram"
ssh "${O[@]}" "$HOST" 'if not exist C:\ProgramData\dram mkdir C:\ProgramData\dram' >/dev/null \
  || die "ssh to $HOST failed (OpenSSH on Windows? docs/platforms/windows/README.md)"
# the hand-written documents of before decisions/0020, so nothing applies them by mistake
ssh "${O[@]}" "$HOST" 'del /q C:\ProgramData\dram\common.winget C:\ProgramData\dram\cabin.winget 2>nul' >/dev/null
# fonts\ and cursors\ only when they changed (their SHA256SUMS go last, so a cut copy is copied
# again); build\ copied over; every other directory replaced whole; the top-level files
# overwritten
send=() dirs=""
for e in "$R"/*; do
  n="${e##*/}"
  if [ "$n" = fonts ] || [ "$n" = cursors ]; then
    win_sums "$e" >"$STAGE/$n.SHA256SUMS"
    # shellcheck disable=SC2029 # $n is meant to expand here, into the Windows command line
    remote="$(ssh "${O[@]}" "$HOST" "type C:\\ProgramData\\dram\\$n\\SHA256SUMS 2>nul" | LC_ALL=C tr -d '\r')"
    if [ "$remote" = "$(cat "$STAGE/$n.SHA256SUMS")" ]; then
      echo "   $n: unchanged ($(wc -l <"$STAGE/$n.SHA256SUMS" | tr -d ' ') files)"
      continue
    fi
    echo "   $n: $(wc -l <"$STAGE/$n.SHA256SUMS" | tr -d ' ') files to copy"
  fi
  [ "$n" = build ] && continue
  [ -d "$e" ] && dirs="$dirs $n"
  send+=("$e")
done
if [ -n "$dirs" ]; then
  # shellcheck disable=SC2029 # $dirs is meant to expand here, into the Windows command line
  ssh "${O[@]}" "$HOST" "for %d in ($dirs) do @if exist C:\\ProgramData\\dram\\%d rmdir /s /q C:\\ProgramData\\dram\\%d" >/dev/null \
    || die "could not clear the build's directories on $HOST"
fi
scp -q -r "${O[@]}" ${send[@]+"${send[@]}"} "$HOST:C:/ProgramData/dram/" || die "could not copy the build"
for n in fonts cursors; do
  [ -f "$STAGE/$n.SHA256SUMS" ] && [ -d "$R/$n" ] || continue
  scp -q "${O[@]}" "$STAGE/$n.SHA256SUMS" "$HOST:C:/ProgramData/dram/$n/SHA256SUMS" || die "could not copy the $n' SHA256SUMS"
done
ssh "${O[@]}" "$HOST" 'if not exist C:\ProgramData\dram\build mkdir C:\ProgramData\dram\build' >/dev/null
docs=()
for d in "$R/build"/*; do [ "${d##*/}" = manifest.json ] || docs+=("$d"); done
scp -q "${O[@]}" ${docs[@]+"${docs[@]}"} "$HOST:C:/ProgramData/dram/build/" || die "could not copy the documents"
scp -q "${O[@]}" "$R/build/manifest.json" "$HOST:C:/ProgramData/dram/build/manifest.json" || die "could not copy manifest.json"
echo "   $(find "$R" -type f | wc -l | tr -d ' ') files in place"

say "converge$([ "$DRY" = 1 ] && echo ' (dry run)')"
flags=""
[ "$DEBLOAT" = 1 ] && flags="$flags -Debloat"
[ "$DRY" = 1 ] && flags="$flags -DryRun"
# shellcheck disable=SC2029 # $flags is meant to expand here, into the Windows command line
ssh "${O[@]}" "$HOST" "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\\ProgramData\\dram\\converge.ps1$flags" 2>&1 | LC_ALL=C tr -d '\r'

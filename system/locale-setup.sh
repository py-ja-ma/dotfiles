#!/usr/bin/env bash
# usage: locale-setup.sh [--dry-run] [--file PATH]
#
# Makes sure en_US.UTF-8 and ru_RU.UTF-8 are generated: the desktop shows a
# Russian date, and without the ru_RU locale compiled `LC_TIME=ru_RU.UTF-8
# date` falls back to C. Edits /etc/locale.gen only when a wanted line is
# still commented, keeps one .bak-<stamp>, and runs locale-gen only when the
# file changed. LANG stays en_US.UTF-8 (/etc/locale.conf is not touched). Safe
# after a pacdiff that commented en_US out. Root, unless --dry-run.
#
#   --dry-run     show the diff, write nothing
#   --file PATH   edit that file instead of /etc/locale.gen (tests)
#   -h, --help    this text
#
# exit: 0 ok · 1 not root or locale-gen failed · 2 bad usage
# see: docs/platforms/arch/install.md

set -uo pipefail
DRY=0
GEN=/etc/locale.gen
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --file)
      GEN="${2:?--file needs a path}"
      shift
      ;; # tests
    -h | --help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown argument '$1'" >&2
      sed -n '2s/^# \{0,1\}//p' "$0" >&2
      exit 2
      ;;
  esac
  shift
done
[ "$DRY" = 1 ] || [ "$(id -u)" -eq 0 ] || {
  echo "Run with sudo (or --dry-run): sudo bash $0" >&2
  exit 1
}
[ -f "$GEN" ] || {
  echo "$GEN not found" >&2
  exit 1
}

WANT=("en_US.UTF-8 UTF-8" "ru_RU.UTF-8 UTF-8")
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
cp "$GEN" "$TMP"
for loc in "${WANT[@]}"; do
  if grep -qE "^${loc//./\\.}[[:space:]]*$" "$TMP"; then
    continue # already active
  elif grep -qE "^#[[:space:]]*${loc//./\\.}[[:space:]]*$" "$TMP"; then
    sed -E "s|^#[[:space:]]*(${loc//./\\.})[[:space:]]*$|\1|" "$TMP" >"$TMP.new" && mv "$TMP.new" "$TMP" # uncomment
  else
    printf '%s\n' "$loc" >>"$TMP" # not even listed: append
  fi
done

if cmp -s "$TMP" "$GEN"; then
  echo "[ok] $GEN already lists: ${WANT[*]} — locale-gen not needed"
  exit 0
fi
diff -u "$GEN" "$TMP" || true
if [ "$DRY" = 1 ]; then
  echo "[dry-run] nothing written, locale-gen not run"
  exit 0
fi
STAMP="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo bak)"
cp -a "$GEN" "$GEN.bak-$STAMP"
echo "[ok] backup -> $GEN.bak-$STAMP"
install -m644 "$TMP" "$GEN"
echo "[..] locale-gen"
locale-gen && echo "[ok] locales generated: $(localedef --list-archive 2>/dev/null | tr '\n' ' ')"

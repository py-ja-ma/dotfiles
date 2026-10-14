#!/usr/bin/env bash
# usage: gaming-switch.sh
#
# Test tier T0 for Gaming Mode switching (decisions/0012), any machine with bash: the
# session names os-session-select maps to, and ly-prepare's one-shot autologin against
# throwaway ini and Lua configs (a fresh request, a stale one, a bad session, a bad
# user, the clear on the next start), and system/apply-ly.sh carrying the two keys over.
# Changes nothing outside a temp dir. bin/check.sh runs it.
#
#   -h, --help    this text
#
# exit: 0 every check passed · 1 a check failed · 2 bad usage
# see: pkgs/dram-gaming-mode/REVIEW.md, docs/toolchain/profiles/gaming.md

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

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
P="$REPO/pkgs/dram-gaming-mode"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAILS=0
ok() { echo "ok   $1"; }
bad() {
  echo "FAIL $1${2:+ — $2}"
  FAILS=$((FAILS + 1))
}
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want '$3', got '$2'"; fi; }

# --- os-session-select: the names ------------------------------------------------
oss() { DRAM_GAMING_MODE_FILE="$T/gaming-mode" bash "$P/os-session-select" --print "$@" 2>/dev/null; }
expect_eq "desktop -> dram-desktop" "$(oss desktop)" dram-desktop
expect_eq "plasma (Steam's name) -> dram-desktop" "$(oss plasma-wayland-persistent)" dram-desktop
expect_eq "default gaming -> dram-gaming" "$(oss)" dram-gaming
expect_eq "big-picture -> dram-gaming" "$(oss big-picture)" dram-gaming
expect_eq "gamescope -> gamescope-session-steam" "$(oss gamescope)" gamescope-session-steam
echo gamescope >"$T/gaming-mode"
expect_eq "promoted: gaming -> gamescope-session-steam" "$(oss gaming)" gamescope-session-steam
rm -f "$T/gaming-mode"
oss nonsense >/dev/null
expect_eq "an unknown name exits 2" "$?" 2
# every session it can name ships as a .desktop file (ours) or comes from gamescope-session-steam
for s in dram-desktop dram-gaming; do
  if [ -f "$P/$s.desktop" ]; then ok "$s.desktop is in the package"; else bad "$s.desktop is in the package"; fi
  if grep -q '^DesktopNames=' "$P/$s.desktop"; then bad "$s.desktop has no DesktopNames= (ly's name match)"; else ok "$s.desktop has no DesktopNames= (ly's name match)"; fi
done
if grep -q "^depends=.*'gamescope-session-steam'" "$P/PKGBUILD"; then
  ok "the package depends on gamescope-session-steam (steamos-session-select)"
else bad "the package depends on gamescope-session-steam (steamos-session-select)"; fi

# --- ly-prepare --------------------------------------------------------------------
mkdir -p "$T/run" "$T/sessions"
touch "$T/sessions/dram-gaming.desktop" "$T/sessions/dram-desktop.desktop"
me="$(id -un)"
prep() { DRAM_LY_CONF="$1" DRAM_RUN="$T/run" DRAM_SESSIONS="$T/sessions" DRAM_MIN_UID=0 bash "$P/ly-prepare" >/dev/null; }
request() { printf '%s\n%s\n' "$1" "$2" >"$T/run/ly-next-session"; }
keys() { grep -cE '^[[:space:]]*auto_login_(session|user)' "$1"; }

printf 'animation = none\nbigclock = en\n' >"$T/c.ini"
request dram-gaming "$me"
prep "$T/c.ini"
expect_eq "ini: a fresh request sets the session" "$(sed -n 's/^auto_login_session = //p' "$T/c.ini")" dram-gaming
expect_eq "ini: … and the user" "$(sed -n 's/^auto_login_user = //p' "$T/c.ini")" "$me"
if [ -e "$T/run/ly-next-session" ]; then bad "the request is consumed"; else ok "the request is consumed"; fi
prep "$T/c.ini"
expect_eq "ini: the next start clears both keys" "$(keys "$T/c.ini")" 0
expect_eq "ini: other keys untouched" "$(grep -c 'bigclock = en' "$T/c.ini")" 1

request dram-gaming "$me"
touch -t 202601010000 "$T/run/ly-next-session"
prep "$T/c.ini"
expect_eq "ini: a stale request is ignored" "$(keys "$T/c.ini")" 0
request ../../etc/passwd "$me"
prep "$T/c.ini"
expect_eq "ini: a session that is not a .desktop file is refused" "$(keys "$T/c.ini")" 0
request dram-gaming 'root;rm'
prep "$T/c.ini"
expect_eq "ini: a malformed user is refused" "$(keys "$T/c.ini")" 0
request dram-gaming nosuchuser_dram
prep "$T/c.ini"
expect_eq "ini: an unknown user is refused" "$(keys "$T/c.ini")" 0

printf 'ly = {\n    animation = "none",\n    bigclock = "en",\n}\n' >"$T/c.lua"
request dram-desktop "$me"
prep "$T/c.lua"
expect_eq "lua: the session goes inside the table" "$(sed -n 's/^    auto_login_session = "\(.*\)",$/\1/p' "$T/c.lua")" dram-desktop
expect_eq "lua: the brace is still the last line" "$(tail -1 "$T/c.lua")" "}"
if command -v lua >/dev/null 2>&1; then
  if lua -e "dofile('$T/c.lua'); assert(ly.auto_login_user == '$me')" 2>/dev/null; then
    ok "lua: the file loads and has the user"
  else bad "lua: the file loads and has the user"; fi
fi
prep "$T/c.lua"
expect_eq "lua: the next start clears both keys" "$(keys "$T/c.lua")" 0

# --- apply-ly.sh carries the keys ------------------------------------------------------
printf 'animation = none\nauto_login_session = dram-gaming\nauto_login_user = %s\n' "$me" >"$T/a.ini"
bash "$REPO/system/apply-ly.sh" --config "$T/a.ini" --hostname t --dry-run >"$T/a.out" 2>&1
if grep -q '^-auto_login' "$T/a.out"; then bad "apply-ly.sh keeps ly-prepare's keys (ini)"; else ok "apply-ly.sh keeps ly-prepare's keys (ini)"; fi

[ "$FAILS" -eq 0 ] || {
  echo "gaming-switch: $FAILS check(s) failed" >&2
  exit 1
}
echo "gaming-switch: all checks passed"

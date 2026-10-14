#!/usr/bin/env bash
# usage: apply-ly.sh [--anim none|matrix] [--dry-run] [--format ini|lua] [--config PATH] [--hostname NAME]
#
# Writes the ly greeter config from the house palette
# (system/house-palette.sh): /etc/ly/config.ini, or config.lua where ly reads
# that (autodetected). Write-on-change; the previous file is kept once as
# config.<ext>.bak-<stamp>. The ly `dur` animation is refused and scrubbed
# every run: it faulted the greeter at boot twice and forced an external-ISO
# recovery. Root, unless --dry-run.
#
#   --anim none|matrix   animation; default none (`none` / `matrix` also accepted bare)
#   --dry-run            no root needed; shows what would change
#   --format ini|lua     override the format autodetection
#   --config PATH        write somewhere else (tests); the format follows the extension
#   --hostname NAME      box_title; default `hostname`
#   -h, --help           this text
#
# exit: 0 ok · 1 not root, refused animation, or write failed · 2 bad usage
# see: docs/platforms/arch/boot-chain.md

# Which file ly reads (verified 2026-10-05 against the upstream tree):
#   * every RELEASE up to and including v1.5.0 (2026-10-04) ships
#     res/config.ini and reads /etc/ly/config.ini — that includes the Arch
#     package `ly 1.4.1-1` installed on both hosts (its PKGBUILD backs up
#     etc/ly/config.ini and vendors the zig `ini` parser);
#   * upstream master has moved to res/config.lua (`ly = { ... }`), so the
#     next major release will read /etc/ly/config.lua.
# Detection: if the installed package ships /etc/ly/config.lua we write lua,
# otherwise ini. Both writers emit the same settings. Only keys that exist in
# BOTH the 1.4.1 and 1.5.0 ini are written (1.5.0 dropped hide_key_hints,
# renamed save -> save_file_dir, added corner_*), so the ini stays loadable
# across the pending upgrade. `tty` is not a config key in any of these
# versions — the TTY comes from the ly@tty2 unit.
#
# !! `animation = dur` (the .dur reader) is BANNED. It faulted the greeter at
# boot TWICE on lantern (2026-07-02) and forced an external-ISO recovery.
# This script never writes it, always blanks dur_file_path and deletes
# /etc/ly/*.dur so it cannot re-arm. `matrix` is an in-process shader — a
# different code path — and is the only motion allowed.
#
# Write-on-change: the file is only replaced when the content differs, and
# the previous file is kept once as config.<ext>.bak-<stamp> (harden.sh style).

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=house-palette.sh
. "$DIR/house-palette.sh"

ANIM=none DRY=0 FORMAT="" CONF="" BOX_TITLE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --anim)
      ANIM="${2:?--anim needs none|matrix}"
      shift
      ;;
    --anim=*) ANIM="${1#--anim=}" ;;
    none | matrix) ANIM="$1" ;; # positional, also accepted
    --dry-run) DRY=1 ;;
    --format)
      FORMAT="${2:?--format needs ini|lua}"
      shift
      ;;
    --format=*) FORMAT="${1#--format=}" ;;
    --config)
      CONF="${2:?--config needs a path}"
      shift
      ;;
    --hostname)
      BOX_TITLE="${2:?--hostname needs a name}"
      shift
      ;;
    -h | --help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown argument '$1' (dur_file is intentionally NOT allowed; use none|matrix)" >&2
      sed -n '2s/^# \{0,1\}//p' "$0" >&2
      exit 2
      ;;
  esac
  shift
done
case "$ANIM" in none | matrix) ;; *)
  echo "animation '$ANIM' refused: only none|matrix (dur is banned, see header)" >&2
  exit 1
  ;;
esac

if [ "$DRY" = 0 ] && [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo (or add --dry-run): sudo bash $0 $*" >&2
  exit 1
fi

# --- which format does the installed ly read? --------------------------------
if [ -z "$FORMAT" ] && [ -n "$CONF" ]; then
  case "$CONF" in *.lua) FORMAT=lua ;; *.ini) FORMAT=ini ;; esac
fi
if [ -z "$FORMAT" ]; then
  if command -v pacman >/dev/null 2>&1 && pacman -Ql ly 2>/dev/null | grep -c '/etc/ly/config\.lua$' >/dev/null; then
    FORMAT=lua
  elif [ -f /etc/ly/config.lua ] && [ ! -f /etc/ly/config.ini ]; then
    FORMAT=lua
  else
    FORMAT=ini
  fi
fi
case "$FORMAT" in ini | lua) ;; *)
  echo "--format must be ini or lua" >&2
  exit 1
  ;;
esac
[ -n "$CONF" ] || CONF="/etc/ly/config.$FORMAT"
[ -n "$BOX_TITLE" ] || BOX_TITLE="$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo arch)"
LYVER="$(pacman -Q ly 2>/dev/null | awk '{print $2}' || true)"

# --- render ------------------------------------------------------------------
BG="$(hp_ly "$HP_PAPER")"
FG="$(hp_ly "$HP_INK")"
BORDER="$(hp_ly "$HP_ACCENT")"
ERR="$(hp_ly "$HP_ACCENT" 01)"
RAIN="$(hp_ly "$HP_SUBTEXT")"
HEAD="$(hp_ly "$HP_INK" 01)"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

if [ "$FORMAT" = ini ]; then
  {
    cat <<EOF
# /etc/ly/config.ini — written by dotfiles/system/apply-ly.sh from the house
# palette. Do not hand-edit: re-run the script. Unlisted keys keep ly's defaults.
# animation=dur is BANNED here (crashed the boot twice, 2026-07-02).
allow_empty_password = false
animation = $ANIM
bg = $BG
fg = $FG
border_fg = $BORDER
error_fg = $ERR
hide_borders = true
blank_box = true
bigclock = en
bigclock_12hr = false
clock = %A, %-d %B
box_title = $BOX_TITLE
text_in_center = true
lang = en
dur_file_path =
# the session's output: ly 1.4 writes ~/ly-session.log unless told
session_log = .local/state/ly-session.log
EOF
    if [ "$ANIM" = matrix ]; then
      cat <<EOF
cmatrix_fg = $RAIN
cmatrix_head_col = $HEAD
cmatrix_min_codepoint = 0x21
cmatrix_max_codepoint = 0x2f
EOF
    fi
  } >"$TMP"
else
  {
    cat <<EOF
-- /etc/ly/config.lua — written by dotfiles/system/apply-ly.sh from the house
-- palette. Do not hand-edit: re-run the script. Unlisted keys keep ly's defaults.
-- animation = "dur" is BANNED here (crashed the boot twice, 2026-07-02).
ly = {
    allow_empty_password = false,
    animation = "$ANIM",
    bg = $BG,
    fg = $FG,
    border_fg = $BORDER,
    error_fg = $ERR,
    hide_borders = true,
    blank_box = true,
    bigclock = "en",
    bigclock_12hr = false,
    clock = "%A, %-d %B",
    box_title = "$BOX_TITLE",
    text_in_center = true,
    lang = "en",
    dur_file_path = nil,
    session_log = ".local/state/ly-session.log",
EOF
    if [ "$ANIM" = matrix ]; then
      cat <<EOF
    cmatrix_fg = $RAIN,
    cmatrix_head_col = $HEAD,
    cmatrix_min_codepoint = 0x21,
    cmatrix_max_codepoint = 0x2f,
EOF
    fi
    echo "}"
  } >"$TMP"
fi

# --- the autologin keys belong to ly-prepare --------------------------------------
# dram-gaming-mode's /usr/lib/dram/ly-prepare sets auto_login_session/auto_login_user for
# one ly start after a Desktop <-> Gaming Mode switch, and clears them on the next
# (decisions/0012). Carry whatever it left, so this rewrite never fights it.
if [ -f "$CONF" ]; then
  CARRY="$(grep -E '^[[:space:]]*auto_login_(session|user)[[:space:]]*=' "$CONF" || true)"
  if [ -n "$CARRY" ]; then
    if [ "$FORMAT" = ini ]; then
      printf '%s\n' "$CARRY" >>"$TMP"
    else
      TMP2="$(mktemp)"
      sed '$d' "$TMP" >"$TMP2" # the table's closing brace is the last line
      printf '%s\n}\n' "$CARRY" >>"$TMP2"
      mv "$TMP2" "$TMP"
    fi
  fi
fi

# --- write on change ---------------------------------------------------------
echo "ly${LYVER:+ $LYVER} -> $CONF (format $FORMAT, animation $ANIM, box_title $BOX_TITLE)"
if [ -f "$CONF" ] && cmp -s "$TMP" "$CONF"; then
  echo "[ok] unchanged"
else
  if [ -f "$CONF" ]; then diff -u "$CONF" "$TMP" || true; else
    echo "(new file)"
    cat "$TMP"
  fi
  if [ "$DRY" = 1 ]; then
    echo "[dry-run] nothing written"
  else
    STAMP="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo bak)"
    if [ -f "$CONF" ]; then
      cp -a "$CONF" "$CONF.bak-$STAMP"
      echo "[ok] backup -> $CONF.bak-$STAMP"
    fi
    install -D -m644 "$TMP" "$CONF"
    echo "[ok] written"
  fi
fi
if [ "$DRY" = 0 ]; then
  rm -f /etc/ly/*.dur 2>/dev/null || true # the banned animation can never re-arm
  echo "Log out (SUPER+X -> Logout) to see it; the greeter only runs at login."
fi

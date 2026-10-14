#!/usr/bin/env bash
# usage: gaming-setup.sh [--dry-run]
#
# The games folder of the gaming role (docs/toolchain/profiles/gaming.md): /data/games, owned by the main
# user, and ~/games -> /data/games. /data/games is the @games subvolume on the data pool
# (decisions/0011), so a reinstall keeps the games; it is root's when the subvolume is new,
# and Steam cannot add a library there until this runs. Elsewhere it is created as a plain
# directory. Steam is told once, by hand (Settings > Storage > Add Drive > /data/games, then
# Make Default; Steam makes /data/games/SteamLibrary; handbook 02 §11): Steam owns its
# library files, so this script never edits them. Steam Remote Play gets its LAN opening in the
# firewall (/etc/nftables.d/steam.nft). Never deletes anything. Idempotent; a
# `dram apply` role hook (system/apply-hooks.tsv). Root, unless --dry-run.
#
#   -n, --dry-run   print what would change
#   -h, --help      this text
#
# env: DRAM_USER (default: the sudo caller, else pj), DRAM_GAMES_ROOT (default /data/games)
# exit: 0 ok · 1 not root or a step failed · 2 bad usage
# see: docs/toolchain/profiles/gaming.md, docs/records/handbook/02-first-login.md

DRY=0
case "${1:-}" in
  "") ;;
  -n | --dry-run) DRY=1 ;;
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
USERNAME="${DRAM_USER:-${SUDO_USER:-pj}}"
ROOT="${DRAM_GAMES_ROOT:-/data/games}"
say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
run() { if [ "$DRY" -eq 1 ]; then printf '  \033[2m[dry-run] %s\033[0m\n' "$*"; else "$@"; fi; }
[ "$(id -u)" -eq 0 ] || [ "$DRY" -eq 1 ] || {
  echo "Run with sudo: sudo bash $0 [--dry-run]"
  exit 1
}
id "$USERNAME" >/dev/null 2>&1 || [ "$DRY" -eq 1 ] || {
  warn "no user $USERNAME (DRAM_USER)"
  exit 1
}
GROUP="$(id -gn "$USERNAME" 2>/dev/null || echo "$USERNAME")"
HOMEDIR="$(getent passwd "$USERNAME" 2>/dev/null | cut -d: -f6)"
HOMEDIR="${HOMEDIR:-/home/$USERNAME}"

say "games folder $ROOT"
if findmnt -n "$ROOT" >/dev/null 2>&1; then ok "$ROOT is its own mount (the @games subvolume)"; else
  warn "$ROOT is not a mount — a plain directory on this disk (older host or one pool; decisions/0011)"
fi
if [ -d "$ROOT" ] && [ "$(stat -c %U "$ROOT")" = "$USERNAME" ]; then
  ok "$ROOT belongs to $USERNAME"
elif [ -d "$ROOT" ]; then
  # the top level only: whatever a library already holds keeps its owners
  run chown "$USERNAME:$GROUP" "$ROOT" || {
    warn "could not hand $ROOT to $USERNAME"
    exit 1
  }
  ok "$ROOT handed to $USERNAME"
else
  run install -d -m 755 -o "$USERNAME" -g "$GROUP" "$ROOT" || {
    warn "could not create $ROOT"
    exit 1
  }
  ok "$ROOT created"
fi

say "games folder in the home directory"
link="$HOMEDIR/games"
if [ -L "$link" ] && [ "$(readlink "$link")" = "$ROOT" ]; then ok "$link -> $ROOT"; elif [ -e "$link" ] || [ -L "$link" ]; then
  warn "$link exists and is not our link — left alone (the games are in $ROOT)"
else
  run ln -s "$ROOT" "$link" && { [ "$DRY" -eq 1 ] || chown -h "$USERNAME:$GROUP" "$link"; } && ok "$link -> $ROOT"
fi
echo "    Steam, once: Settings > Storage > Add Drive > $ROOT (Steam makes $ROOT/SteamLibrary),"
echo "    then its ⋯ menu > Make Default. Move installed games there from the same page (Move)."

# Steam Remote Play and Steam Link from the LAN (the Arch firewall, decisions/log.md#d145, 2026-10-12): UDP
# 27031-27036 and TCP 27036-27037, Valve's ports, $LAN only (system/nftables.conf includes its
# define, /etc/dram/lan.nft, before the role files). A role file in /etc/nftables.d like the recorder's, written once harden.sh has made
# that folder; the firewall is reloaded only when it already runs, so this hook never switches it on.
say "firewall opening for Steam Remote Play (LAN only)"
NFT=/etc/nftables.d/steam.nft
# shellcheck disable=SC2016 # $LAN is nft's own variable, written as is
want='# /etc/nftables.d/steam.nft - written by system/gaming-setup.sh (role gaming).
# Steam Remote Play and Steam Link from the LAN, on Valve'"'"'s ports.
ip saddr $LAN udp dport 27031-27036 counter accept
ip saddr $LAN tcp dport 27036-27037 counter accept'
if [ ! -d /etc/nftables.d ]; then
  ok "no /etc/nftables.d (harden.sh not run): nothing to open yet"
elif [ -f "$NFT" ] && [ "$(cat "$NFT")" = "$want" ]; then
  ok "$NFT unchanged"
elif [ "$DRY" -eq 1 ]; then
  echo "  [dry-run] write $NFT, nft -c; reload nftables if it runs"
else
  [ -f "$NFT" ] && cp -a "$NFT" "$NFT.bak"
  printf '%s\n' "$want" >"$NFT" && chmod 644 "$NFT"
  if ! nft -c -f /etc/nftables.conf; then
    warn "the ruleset does not check with $NFT: restored the previous state"
    if [ -f "$NFT.bak" ]; then mv -f "$NFT.bak" "$NFT"; else rm -f "$NFT"; fi
    exit 1
  fi
  rm -f "$NFT.bak"
  # nftables.service is a oneshot without RemainAfterExit, "inactive" once it has loaded the
  # rules: whether harden.sh's table is in the kernel tells if the firewall is on
  if nft list table inet filter >/dev/null 2>&1; then
    systemctl restart nftables.service && ok "$NFT installed, firewall reloaded" || warn "nftables reload failed: systemctl status nftables"
  else
    ok "$NFT installed (the firewall is off; harden.sh turns it on)"
  fi
fi

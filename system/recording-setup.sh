#!/usr/bin/env bash
# usage: recording-setup.sh [--dry-run]
#
# The recorder's firewall opening (docs/toolchain/profiles/creator.md): OBS's websocket
# (tcp/4455, `rec` on cabin starts and stops recording through it) and the SRT fallback
# (udp/9000), from the creator hosts only — their `address` in modules/hosts/<name>.nix,
# resolved when this runs, this host excluded; nothing at all when no other creator host
# has one. Writes
# /etc/nftables.d/recording.nft (included by system/nftables.conf), checks the whole
# ruleset with `nft -c`, then reloads it. An `ask` hook of `dram apply`: it touches the
# firewall. Root, unless --dry-run.
#
#   -n, --dry-run   print the file and change nothing
#   -h, --help      this text
#
# exit: 0 ok · 1 not root, a bad ruleset, or a step failed · 2 bad usage
# see: docs/toolchain/profiles/creator.md, system/nftables.conf

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
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../install/lib/roles.sh
. "$REPO/install/lib/roles.sh"
SELF="${DRAM_HOST:-$(hostname 2>/dev/null || cat /etc/hostname)}"
OUT=/etc/nftables.d/recording.nft
say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
[ "$(id -u)" -eq 0 ] || [ "$DRY" -eq 1 ] || {
  echo "Run with sudo: sudo bash $0 [--dry-run]"
  exit 1
}

addrs=""
for h in $(hosts_with_role "$REPO" creator); do
  [ "$h" = "$SELF" ] && continue
  a="$(host_addresses "$REPO" | sed -n "s/^$h=//p")"
  [ -n "$a" ] || continue
  # a host file names its host; the rule gets the address it has now. nft would resolve a
  # name while it loads the rules at boot, before the network, and refuse the whole ruleset
  ip="$(getent ahostsv4 "$a" 2>/dev/null | awk 'NR == 1 { print $1 }')"
  if [ -z "$ip" ]; then
    warn "$h ($a) does not resolve here: left out until the next run"
    continue
  fi
  addrs="$addrs${addrs:+, }$ip"
done
if [ -z "$addrs" ]; then
  # nobody to let in: no opening at all (never the whole LAN)
  say "no other creator host has an address in modules/hosts/ — nothing to open"
  if [ -f "$OUT" ]; then
    if [ "$DRY" -eq 1 ]; then echo "  [dry-run] rm $OUT; systemctl restart nftables"; else
      rm -f "$OUT" && systemctl restart nftables.service && ok "$OUT removed, firewall reloaded"
    fi
  fi
  exit 0
fi
from="{ $addrs }"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
cat >"$tmp" <<NFT
# /etc/nftables.d/recording.nft — written by system/recording-setup.sh (role recording).
# OBS websocket (rec start/stop) and the SRT fallback, from the creator hosts only.
ip saddr $from tcp dport 4455 counter accept
ip saddr $from udp dport 9000 counter accept
NFT

say "firewall opening for OBS on this recorder: from $from"
if [ "$DRY" -eq 1 ]; then
  sed 's/^/    /' "$tmp"
  exit 0
fi
if [ -f "$OUT" ] && cmp -s "$tmp" "$OUT"; then
  ok "$OUT unchanged"
  exit 0
fi
install -d -m 755 /etc/nftables.d
[ -f "$OUT" ] && cp -a "$OUT" "$OUT.bak"
install -m 644 "$tmp" "$OUT"
if ! nft -c -f /etc/nftables.conf; then
  warn "the ruleset does not check with $OUT — restored the previous state"
  if [ -f "$OUT.bak" ]; then mv -f "$OUT.bak" "$OUT"; else rm -f "$OUT"; fi
  exit 1
fi
rm -f "$OUT.bak"
systemctl restart nftables.service && ok "$OUT installed, firewall reloaded" || {
  warn "nftables reload failed — systemctl status nftables"
  exit 1
}

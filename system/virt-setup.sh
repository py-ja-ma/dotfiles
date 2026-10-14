#!/usr/bin/env bash
# usage: virt-setup.sh [--dry-run]
#
# virt-manager for the sysadmin role: libvirt answers through its socket (libvirtd.socket
# enabled), and the main user is in `libvirt`, so virt-manager manages the system's VMs
# without asking for a password (log out and in once after the first run). Its NAT network's
# VMs ask the host's dnsmasq for DHCP and DNS on virbr0: /etc/nftables.d/libvirt.nft lets
# exactly that in (the forward chain already passes bridge traffic; system/nftables.conf),
# checked with `nft -c` before the firewall reloads. VM disks belong on /data/vm.
# Idempotent; an `ask` hook of `dram apply` (it touches the firewall). Root, unless --dry-run.
#
#   -n, --dry-run   print what would change
#   -h, --help      this text
#
# env: DRAM_USER (default: the sudo caller, else pj)
# exit: 0 ok · 1 not root, libvirt missing, or a step failed · 2 bad usage
# see: docs/toolchain/development/README.md

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
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}
# shellcheck source=install/lib/detect.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install/lib/detect.sh"
# the VM kit stays on Arch: a WSL clone runs with nested virtualisation off and skips it
# (packages/wsl-skip.tsv, decisions/0021)
if [ "$(detect_platform)" = wsl ]; then
  ok "WSL: no VM kit in the clone (the VMs run on Arch) — nothing to do"
  exit 0
fi
[ "$(id -u)" -eq 0 ] || [ "$DRY" -eq 1 ] || die "run with sudo (or --dry-run)"
command -v libvirtd >/dev/null || [ "$DRY" -eq 1 ] || die "libvirt is not installed (packages/roles/sysadmin.txt: dram apply)"

if systemctl is-enabled -q libvirtd.socket 2>/dev/null; then
  ok "libvirtd.socket enabled"
elif [ "$DRY" -eq 1 ]; then
  echo "  [dry-run] systemctl enable --now libvirtd.socket"
else
  systemctl enable --now libvirtd.socket || die "could not enable libvirtd.socket"
  ok "libvirtd.socket enabled"
fi
if id -nG "$USERNAME" 2>/dev/null | tr ' ' '\n' | grep -qx libvirt; then
  ok "$USERNAME is in libvirt"
elif [ "$DRY" -eq 1 ]; then
  echo "  [dry-run] usermod -aG libvirt $USERNAME"
else
  usermod -aG libvirt "$USERNAME" || die "could not add $USERNAME to libvirt"
  ok "$USERNAME added to libvirt (log out and in once)"
fi

NFT=/etc/nftables.d/libvirt.nft
want="$(
  cat <<'NFT'
# written by dotfiles/system/virt-setup.sh: libvirt's NAT network (virbr0) - its VMs ask
# the host's dnsmasq for DHCP and DNS; included in the input chain of system/nftables.conf
iifname "virbr0" udp dport { 53, 67 } accept
iifname "virbr0" tcp dport 53 accept
NFT
)"
if [ "$(cat "$NFT" 2>/dev/null)" = "$want" ]; then
  ok "$NFT in place"
elif [ "$DRY" -eq 1 ]; then
  echo "  [dry-run] write $NFT (virbr0: udp 53, 67; tcp 53), nft -c, systemctl restart nftables"
elif [ ! -d /etc/nftables.d ]; then
  ok "no /etc/nftables.d (harden.sh not run): the firewall is not ours to extend"
else
  if ! { printf '%s\n' "$want" >"$NFT.new" && mv "$NFT.new" "$NFT"; }; then die "could not write $NFT"; fi
  if ! nft -c -f /etc/nftables.conf; then
    rm -f "$NFT"
    die "the ruleset does not check with $NFT; removed it, the firewall is unchanged"
  fi
  systemctl restart nftables.service || die "nftables did not reload"
  ok "$NFT installed, firewall reloaded"
fi

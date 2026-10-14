#!/usr/bin/env bash
# usage: network-setup.sh [--dry-run] [--remote-ok]
#
# Desktops and laptops (the desktop role) run NetworkManager for Wi-Fi and wired networks
# instead of systemd-networkd + iwd, which the installer sets up (install/arch-install.sh)
# and headless hosts keep. This hook: installs system/networkmanager/dram.conf (DNS via
# systemd-resolved, the wpa_supplicant backend, Wi-Fi power saving off); imports every
# network iwd knows (/var/lib/iwd/*.psk) as a NetworkManager connection so nothing has to
# be typed again; then hands over — systemd-networkd and iwd off, NetworkManager on.
# Over ssh it stops before the hand-over (the link drops for a few seconds while the
# managers swap) and prints the one command to run at the machine, unless --remote-ok.
# Idempotent; a `dram apply` role hook. Root, unless --dry-run.
#
#   -n, --dry-run   print what would change
#   --remote-ok     hand over even from an ssh session
#   -h, --help      this text
#
# needs:  networkmanager, wpa_supplicant, systemd-resolved; root unless --dry-run
# alone:  yes on any Arch host that runs systemd-networkd and iwd; run it at the machine
# here:   an `auto` role hook of `dram apply` for the desktop role (system/apply-hooks.tsv);
#         `dram doctor` ("network") warns when a desktop host is not on NetworkManager
# exit:   0 ok (or left for the local run) · 1 not root or a step failed · 2 bad usage
# see:    docs/security/network/networkmanager.md

# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT

DRY=0 REMOTE_OK=0
for a in "$@"; do
  case "$a" in
    -n | --dry-run) DRY=1 ;;
    --remote-ok) REMOTE_OK=1 ;;
    -h | --help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      sed -n '2s/^# \{0,1\}//p' "$0" >&2
      exit 2
      ;;
  esac
done

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF=/etc/NetworkManager/conf.d/dram.conf
say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
run() { if [ "$DRY" -eq 1 ]; then printf '  \033[2m[dry-run] %s\033[0m\n' "$*"; else "$@"; fi; }
[ "$(id -u)" -eq 0 ] || [ "$DRY" -eq 1 ] || {
  echo "Run with sudo: sudo bash $0 [--dry-run]"
  exit 1
}
command -v NetworkManager >/dev/null 2>&1 || [ "$DRY" -eq 1 ] || {
  warn "NetworkManager is not installed yet — dram apply installs it (packages/roles/desktop.txt)"
  exit 0
}

say "NetworkManager settings: $CONF"
if [ -f "$CONF" ] && cmp -s "$REPO/system/networkmanager/dram.conf" "$CONF"; then ok "$CONF unchanged"; else
  run install -Dm644 "$REPO/system/networkmanager/dram.conf" "$CONF" && ok "$CONF installed"
  [ "$DRY" -eq 1 ] || ! systemctl is-active --quiet NetworkManager || nmcli general reload conf >/dev/null 2>&1 || true
fi

# iwd's known networks -> NetworkManager connections (PSK networks; open networks need none)
say "networks iwd knows"
n=0
for f in /var/lib/iwd/*.psk; do
  [ -f "$f" ] || continue
  ssid="$(basename "$f" .psk)"
  case "$ssid" in =*) ssid="$(python3 -c 'import sys; print(bytes.fromhex(sys.argv[1]).decode())' "${ssid#=}" 2>/dev/null || true)" ;; esac # iwd hex-encodes odd names
  [ -n "$ssid" ] || continue
  psk="$(sed -n 's/^Passphrase=//p' "$f" | head -1)"
  # without the passphrase iwd keeps only the 64-hex PSK, which NetworkManager takes as is
  [ -n "$psk" ] || psk="$(sed -nE 's/^PreSharedKey=([0-9a-fA-F]{64})$/\1/p' "$f" | head -1)"
  if [ -z "$psk" ]; then
    warn "$ssid: no passphrase or PSK in $f — connect once with nmtui"
    continue
  fi
  if [ "$DRY" -eq 0 ] && nmcli -t -f NAME connection show 2>/dev/null | grep -qxF "$ssid"; then
    ok "$ssid already a NetworkManager connection"
    continue
  fi
  if [ "$DRY" -eq 1 ]; then
    printf '  \033[2m[dry-run] nmcli connection add type wifi con-name %q ssid %q wifi-sec.key-mgmt wpa-psk wifi-sec.psk ***\033[0m\n' "$ssid" "$ssid"
  elif systemctl is-active --quiet NetworkManager; then
    nmcli connection add type wifi con-name "$ssid" ssid "$ssid" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$psk" >/dev/null && ok "$ssid imported" || warn "$ssid: import failed"
  else
    # NetworkManager is not running yet: nmcli --offline (1.48+) writes the keyfile it
    # would have written itself; root-only, as NetworkManager requires
    kf="/etc/NetworkManager/system-connections/$(printf '%s' "$ssid" | tr -c 'A-Za-z0-9._-' '_').nmconnection"
    if [ ! -e "$kf" ]; then
      install -d -m 700 /etc/NetworkManager/system-connections
      if (umask 077 && nmcli --offline connection add type wifi con-name "$ssid" ssid "$ssid" \
        wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$psk" >"$kf") && [ -s "$kf" ]; then
        ok "$ssid imported ($kf)"
      else
        rm -f "$kf"
        warn "$ssid: import failed — connect once with nmtui"
      fi
    fi
  fi
  n=$((n + 1))
done
[ "$n" -gt 0 ] || ok "none to import"

say "who manages the network"
# switched = enabled for the next boot AND true for this one: `dram apply` can leave
# networkd disabled but still running beside NetworkManager until a reboot (two DHCP
# leases on one link — cabin, 2026-10-11); that case finishes the hand-over below
if systemctl is-enabled --quiet NetworkManager 2>/dev/null && ! systemctl is-enabled --quiet systemd-networkd 2>/dev/null \
  && systemctl is-active --quiet NetworkManager 2>/dev/null && ! systemctl is-active --quiet systemd-networkd 2>/dev/null; then
  ok "NetworkManager (systemd-networkd off)"
  systemctl is-enabled --quiet iwd 2>/dev/null && { run systemctl disable --now iwd && ok "iwd turned off (NetworkManager uses wpa_supplicant)"; }
  exit 0
fi
# every networkd socket, in one transaction: systemd 258+ has varlink, metrics and
# resolve-hook sockets beside systemd-networkd.socket, and any one left listening starts
# networkd straight back up (cabin, 2026-10-11)
ND_UNITS="systemd-networkd.service $(systemctl list-unit-files --no-legend 'systemd-networkd*.socket' 2>/dev/null | awk '{print $1}' | paste -sd' ' -)"
cmd="systemctl disable --now $ND_UNITS iwd.service; systemctl enable --now NetworkManager.service"
if [ -n "${SSH_CONNECTION:-}" ] && [ "$REMOTE_OK" -eq 0 ] && [ "$DRY" -eq 0 ]; then
  warn "over ssh: the hand-over drops the link for a few seconds — not done. At the machine (or with --remote-ok):"
  echo "    sudo bash $REPO/system/network-setup.sh"
  exit 0
fi
if [ "$DRY" -eq 1 ]; then
  printf '  \033[2m[dry-run] %s\033[0m\n' "$cmd"
  exit 0
fi
# shellcheck disable=SC2086 # one word per unit
systemctl disable --now $ND_UNITS iwd.service >/dev/null 2>&1 || true
if systemctl enable --now NetworkManager.service; then
  ok "NetworkManager now runs the network (nmtui to pick a Wi-Fi network)"
else
  warn "NetworkManager failed to start — giving the network back to systemd-networkd + iwd"
  systemctl enable --now systemd-networkd.service iwd.service
  exit 1
fi

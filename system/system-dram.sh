#!/usr/bin/env bash
# usage: system-dram.sh [--dry-run]
#
# sudo-required system ricing, a thin orchestrator of the boot look, in boot order:
# 1) rEFInd as the themed menu in front of the UKIs, signed (system/apply-refind.sh);
# 2) the Plymouth splash on the UKIs, the fallback UKIs left verbose
# (system/plymouth-setup.sh); 3) the ly greeter in the house palette
# (system/apply-ly.sh); 4) collapse the two Hyprland sessions into one. Steps 1-3 are
# write-on-change with a single .bak-<stamp>; step 4 is idempotent. 1 and 2 need a UKI
# host (install/arch-install.sh) and, with Secure Boot on, sbctl's keys: their hook row
# runs after system/secureboot-setup.sh and the LUKS enrolments, which edit the kernel
# command line. --dry-run is passed through to 1-3 and skips 4. Root, unless --dry-run.
#
#   --dry-run     no root needed; shows the diffs, changes nothing
#   -h, --help    this text
#
# exit: 0 ok · 1 not root or a step failed · 2 bad usage
# see: docs/platforms/arch/boot-chain.md

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY=0
case "${1:-}" in
  "") ;;
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
[ "$DRY" = 1 ] || [ "$(id -u)" -eq 0 ] || {
  echo "Run with sudo: sudo bash $0"
  exit 1
}

say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
DRYFLAG=()
[ "$DRY" = 1 ] && DRYFLAG=(--dry-run)

# --- 1) and 2) the boot menu and the splash (UKI hosts) ------------------------
# a machine install/arch-install.sh made boots UKIs from /efi (decisions/0011); rEFInd
# fronts them since 2026-10-12, systemd-boot stays behind it for the snapshots
if grep -qx 'BOOTLOADER=systemd-boot' /etc/dram/install-facts.env 2>/dev/null; then
  say "rEFInd menu + theme (apply-refind.sh)"
  bash "$DIR/apply-refind.sh" "${DRYFLAG[@]}" || warn "apply-refind.sh failed — read its last line; the firmware still starts systemd-boot"
  say "Plymouth splash (plymouth-setup.sh)"
  bash "$DIR/plymouth-setup.sh" "${DRYFLAG[@]}" || warn "plymouth-setup.sh failed — read its last line before rebooting"
else
  say "rEFInd + Plymouth: this host does not boot UKIs (no BOOTLOADER=systemd-boot in /etc/dram/install-facts.env) — reinstall with install/arch-install.sh"
fi

# --- 3) ly ---------------------------------------------------------------------
say "ly greeter (apply-ly.sh)"
bash "$DIR/apply-ly.sh" --anim none "${DRYFLAG[@]}" || warn "apply-ly.sh failed"

# --- 4) one Hyprland session -------------------------------------------------
say "Collapse duplicate Hyprland sessions"
if [ "$DRY" = 1 ]; then
  echo "[dry-run] would move hyprland-uwsm.desktop out and pin NoExtract in pacman.conf"
  exit 0
fi
SESS=/usr/share/wayland-sessions
DIS=/usr/share/wayland-sessions-disabled
if [ -f "$SESS/hyprland-uwsm.desktop" ]; then
  mkdir -p "$DIS"
  mv "$SESS/hyprland-uwsm.desktop" "$DIS/"
  ok "moved hyprland-uwsm.desktop out — only 'Hyprland' remains at login"
else
  ok "already a single Hyprland session"
fi
# Make it stick: pacman's NoExtract keeps a hyprland upgrade from writing the
# file back (every upgrade used to re-add it and the greeter showed two
# sessions again). Idempotent: only appended when the line is missing.
NOEX='NoExtract = usr/share/wayland-sessions/hyprland-uwsm.desktop'
if grep -qxF "$NOEX" /etc/pacman.conf; then
  ok "pacman.conf already has: $NOEX"
else
  sed -i "/^\[options\]/a $NOEX" /etc/pacman.conf
  ok "pacman.conf: added '$NOEX' under [options] — upgrades can no longer re-add the uwsm session"
fi

say "Done. Log out to see the greeter."

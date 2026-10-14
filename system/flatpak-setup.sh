#!/usr/bin/env bash
# usage: flatpak-setup.sh [--dry-run]
#
# Flatpak for the apps this host's roles list in packages/flatpak/<role>.txt:
# the desktop role's three vendor binaries (Vesktop, LocalSend, Flatseal) and the
# emulation role's Flathub-verified emulators (decisions/0016). Installs flatpak +
# xdg-desktop-portal-gtk, adds the flathub remote at system scope, installs the
# apps, copies the
# overrides from dotfiles/.local/share/flatpak/overrides/ to
# /var/lib/flatpak/overrides/ (every run; a system override whose id has no
# repo file is removed) and prints the remaining user steps. Idempotent; safe
# after every `dram update`. Root, unless --dry-run.
#
#   --dry-run     no root needed; changes nothing
#   -h, --help    this text
#
# exit: 0 ok · 1 not root or a step failed · 2 bad usage
# see: docs/toolchain/packaging/flatpak.md

# The Jagex Launcher stays the AUR package: Flathub has no build of it
# (com.jagex.RuneScape is the RS3 NXT client, unverified, X11-only).
#
# Steps, all idempotent (safe to re-run after every `dram update`):
#   1) pacman: flatpak + xdg-desktop-portal-gtk (file chooser; -hyprland has none)
#   2) flathub remote, SYSTEM scope (/var/lib/flatpak)
#   3) install the role's apps (already-installed ones are skipped)
#   4) overrides: dotfiles/.local/share/flatpak/overrides/<id> ->
#      /var/lib/flatpak/overrides/<id>, re-copied on every run (so the system
#      layer never lags the repo, as cabin's Vesktop one did); files there with
#      no repo counterpart are removed. The user-scope copy is the symlink
#      modules/desktop.nix puts at ~/.local/share/flatpak/overrides.
#   5) print the user steps: scheme handler, verification, AUR removal

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVR_SRC="$DIR/../dotfiles/.local/share/flatpak/overrides"
OVR_DST=/var/lib/flatpak/overrides
FLATHUB=https://dl.flathub.org/repo/flathub.flatpakrepo
REPO="$(cd "$DIR/.." && pwd)"
# shellcheck source=../install/lib/roles.sh
. "$REPO/install/lib/roles.sh"
# the apps: packages/flatpak/<role>.txt for each role of this host (base is no role;
# a host without a host file gets the desktop list, as before roles existed)
HOSTFILE="$REPO/modules/hosts/${DRAM_HOST:-$(hostname 2>/dev/null || cat /etc/hostname)}.nix"
ROLES="$(roles_of "$HOSTFILE")"
[ -n "$ROLES" ] || ROLES=desktop
APPS=()
while IFS= read -r id; do [ -n "$id" ] && APPS+=("$id"); done < <(
  for r in $ROLES; do
    [ -f "$REPO/packages/flatpak/$r.txt" ] && grep -vE '^[[:space:]]*(#|$)' "$REPO/packages/flatpak/$r.txt" | awk '{print $1}'
  done | sort -u
)
# the AUR packages these replace (printed as a removal hint, never removed here)
REPLACED=(vesktop localsend-bin)

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
  echo "Run with sudo: sudo bash $0  (or --dry-run)"
  exit 1
}

say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
run() {
  printf '\033[2m$ %s\033[0m\n' "$*"
  [ "$DRY" = 1 ] && return 0
  "$@"
}
have() { command -v "$1" >/dev/null 2>&1; }

# --- 1) packages --------------------------------------------------------------
say "pacman: flatpak + xdg-desktop-portal-gtk"
if pacman -Qq flatpak xdg-desktop-portal-gtk >/dev/null 2>&1; then
  ok "already installed"
else
  run pacman -S --needed --noconfirm flatpak xdg-desktop-portal-gtk || {
    warn "pacman failed — nothing below can run"
    exit 1
  }
fi
if [ "$DRY" = 1 ] && ! have flatpak; then
  warn "flatpak not installed yet; the rest of the dry run only prints"
fi

# --- 2) flathub, system scope -------------------------------------------------
say "Flathub remote (system installation)"
if have flatpak && flatpak remotes --system --columns=name 2>/dev/null | grep -qx flathub; then
  ok "flathub remote present"
else
  run flatpak remote-add --system --if-not-exists flathub "$FLATHUB" || warn "remote-add failed"
fi

# --- 3) the apps of this host's roles -------------------------------------------
say "Apps: ${APPS[*]}"
MISSING=()
for id in "${APPS[@]}"; do
  if have flatpak && flatpak info --system "$id" >/dev/null 2>&1; then
    ok "$id installed"
  else
    MISSING+=("$id")
  fi
done
if [ "${#MISSING[@]}" -gt 0 ]; then
  run flatpak install --system -y --noninteractive flathub "${MISSING[@]}" || warn "flatpak install failed for: ${MISSING[*]}"
fi

# --- 4) overrides ---------------------------------------------------------------
# One file per app id in the repo, GKeyFile format ([Context], [Session Bus
# Policy], [Environment] — flatpak-metadata(5)). Flatpak merges the system file
# with the user one (~/.local/share/flatpak/overrides, a symlink to the same
# directory), so both installations read the same policy.
say "Sandbox overrides -> $OVR_DST"
[ -d "$OVR_SRC" ] || {
  warn "no overrides directory at $OVR_SRC"
  exit 1
}
[ "$DRY" = 1 ] || install -d -m 755 "$OVR_DST"
for f in "$OVR_SRC"/*; do
  [ -f "$f" ] || continue
  id="$(basename "$f")"
  # always re-copied: same bytes -> same file, and owner/mode drift is fixed too
  if [ -f "$OVR_DST/$id" ] && cmp -s "$f" "$OVR_DST/$id"; then
    run install -m 644 -o root -g root "$f" "$OVR_DST/$id" && ok "$id override unchanged"
  else
    run install -m 644 -o root -g root "$f" "$OVR_DST/$id" && ok "$id override installed"
  fi
done
# prune: a system override for an id that is no longer in the repo dir (an app
# dropped from packages/flatpak/, or a `flatpak override` run as root) would otherwise stay
# forever and keep granting what the repo no longer says
for f in "$OVR_DST"/*; do
  [ -f "$f" ] || continue
  id="$(basename "$f")"
  [ -f "$OVR_SRC/$id" ] && continue
  run rm -f "$f" && warn "$id: stale system override removed (no $OVR_SRC/$id)"
done

# --- 5) what is left for the user -----------------------------------------------
say "Verify (as pj)"
for id in "${APPS[@]}"; do
  echo "    flatpak info --show-permissions $id"
done
echo "    flatpak run dev.vencord.Vesktop   # screen-share goes through xdg-desktop-portal-hyprland (pick a screen in the portal dialog)"

say "User steps (as pj, once per host)"
echo "    dram switch                                   # links ~/.local/share/flatpak/overrides -> the repo, exports XDG_DATA_DIRS"
echo "    xdg-mime default dev.vencord.Vesktop.desktop x-scheme-handler/discord"
echo "    update-desktop-database ~/.local/share/applications 2>/dev/null"
INSTALLED_AUR=()
for p in "${REPLACED[@]}"; do pacman -Qq "$p" >/dev/null 2>&1 && INSTALLED_AUR+=("$p"); done
if [ "${#INSTALLED_AUR[@]}" -gt 0 ]; then
  warn "AUR packages now replaced by Flatpaks are still installed: ${INSTALLED_AUR[*]}"
  echo "    sudo pacman -Rns ${INSTALLED_AUR[*]}"
else
  ok "no replaced AUR package (${REPLACED[*]}) is installed"
fi
echo "    Log out and back in once so nwg-drawer/rofi see the Flatpak .desktop entries (XDG_DATA_DIRS)."
echo "    Updates: 'flatpak update' — docs/toolchain/packaging/flatpak.md has the dram update one-liner."

#!/usr/bin/env bash
# usage: maintenance.sh [--dry-run]
#
# pacman upkeep for an Arch host, declared once, applied idempotently; nothing
# here is boot-critical. Converges the host, does not update it (that is
# `dram update`):
#   1) packages     pacman-contrib, reflector, arch-audit, rebuild-detector
#   2) hooks        50-pkglist.hook (package lists after every transaction),
#                   70-proton-pass-sandbox.hook; verifies rebuild-detector's own hook
#   3) configs      /etc/conf.d/pacman-contrib (paccache -k2),
#                   /etc/xdg/reflector/reflector.conf (MAINT_COUNTRY)
#   4) pacman.conf  Color, VerbosePkgLists, ParallelDownloads = 10, the
#                   hyprland-uwsm NoExtract line (sed on single options only)
#   5) timers       paccache, reflector, arch-audit (+ keyring WKD sync check)
#   6) services     iwd (if a Wi-Fi device exists), bluetooth, WireGuard report
#   7) limits       /etc/security/limits.d/20-hyprland.conf (rtprio 99, nice -10)
# In a WSL clone (decisions/0021) smartd, Bluetooth and the WireGuard tunnel are Windows'
# and are skipped. Root, unless --dry-run. Afterwards: dram doctor.
#
#   -n, --dry-run   no root needed; print what would change
#   -h, --help      this text
#
# env: MAINT_COUNTRY="Germany" sudo -E ...   mirror country (default United States)
#      MAINT_IWD=1                            enable iwd even without a Wi-Fi device
#
# exit: 0 ok · 1 not root or a step failed · 2 bad usage
# see: docs/platforms/arch/hooks.md

set -uo pipefail
DRY=0
case "${1:-}" in
  --dry-run | -n) DRY=1 ;;
  "") ;;
  -h | --help)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "usage: maintenance.sh [--dry-run]" >&2
    exit 2
    ;;
esac
[ "$(id -u)" -eq 0 ] || [ "$DRY" -eq 1 ] || {
  echo "Run with sudo: sudo bash $0 [--dry-run]"
  exit 1
}

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=install/lib/detect.sh
. "$REPO/install/lib/detect.sh"
# wsl: Arch inside WSL 2 (decisions/0021), which has no disks, radios or VPN of its own
PLATFORM="$(detect_platform)"
STAMP="$(date +%Y%m%d-%H%M%S)"
COUNTRY="${MAINT_COUNTRY:-United States}"
# RC: 1 once any step this script ATTEMPTED has failed (reports about the host's
# state stay plain warnings). install/bootstrap.sh reads the exit status.
RC=0

say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
# failed <msg>: a warning that also makes the script exit 1
failed() {
  warn "$*"
  RC=1
}
run() {
  if [ "$DRY" -eq 1 ]; then printf '  \033[2m[dry-run] %s\033[0m\n' "$*"; else "$@"; fi
}
# install_file <src> <dst> [mode]: copy only when content differs; back up the old file
install_file() {
  local src="$1" dst="$2" mode="${3:-0644}"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    ok "$dst already current"
    return 0
  fi
  [ -f "$dst" ] && run cp -a "$dst" "$dst.bak-$STAMP"
  run install -Dm"$mode" "$src" "$dst" && ok "installed $dst" || {
    failed "could not install $dst"
    return 1
  }
}
enable_timer() {
  if ! systemctl list-unit-files "$1" --no-legend 2>/dev/null | grep -c "$1" >/dev/null; then
    # a dry run before step 1 has installed the package legitimately sees no unit
    if [ "$DRY" -eq 1 ]; then warn "$1 does not exist yet (step 1 installs the package)"; else failed "$1 does not exist — package missing?"; fi
    return 1
  fi
  if systemctl is-enabled -q "$1" 2>/dev/null && systemctl is-active -q "$1" 2>/dev/null; then
    ok "$1 enabled + active"
  else
    run systemctl enable --now "$1" && ok "$1 enabled" || {
      failed "could not enable $1"
      return 1
    }
  fi
}

# --- 1) packages --------------------------------------------------------------
say "Maintenance packages"
WANT=(pacman-contrib reflector arch-audit rebuild-detector)
MISSING=()
for p in "${WANT[@]}"; do pacman -Qq "$p" >/dev/null 2>&1 || MISSING+=("$p"); done
if [ "${#MISSING[@]}" -gt 0 ]; then
  # -S without -y: the sync DB is whatever the last `dram update` left; a
  # partial -Sy is never done here. If this fails, run dram update first.
  run pacman -S --needed --noconfirm "${MISSING[@]}" && ok "installed: ${MISSING[*]}" \
    || failed "could not install ${MISSING[*]} — run 'dram update' first, then re-run"
else
  ok "all present: ${WANT[*]}"
fi

# --- 2) pacman hooks ----------------------------------------------------------
say "Pacman hooks"
install_file "$REPO/system/hooks/50-pkglist.hook" /etc/pacman.d/hooks/50-pkglist.hook
# Upstream proton-pass ships chrome-sandbox setuid root; unprivileged user
# namespaces make that unnecessary (docs/security/software-supply/README.md), and
# pkgs/proton-pass-bin already strips the bit in package(). The hook is belt
# and braces: it re-strips after every install/upgrade of the package in case
# a build ever ships it set, and the chmod below does it once now if the
# binary on this box still carries it.
install_file "$REPO/system/hooks/70-proton-pass-sandbox.hook" /etc/pacman.d/hooks/70-proton-pass-sandbox.hook
if [ -u /opt/proton-pass/chrome-sandbox ]; then
  run chmod u-s /opt/proton-pass/chrome-sandbox && ok "stripped setuid from /opt/proton-pass/chrome-sandbox" \
    || failed "could not strip setuid from /opt/proton-pass/chrome-sandbox"
fi
# rebuild-detector ships its own PostTransaction hook (runs checkrebuild after
# every transaction); nothing to add, just make sure it is really there.
if [ -f /usr/share/libalpm/hooks/rebuild-detector.hook ]; then
  ok "rebuild-detector.hook shipped by the package (runs checkrebuild after each transaction)"
else
  warn "no /usr/share/libalpm/hooks/rebuild-detector.hook — rebuild-detector not installed yet?"
fi
# rEFInd's ESP copy is renewed by 99-refind.hook (system/apply-refind.sh installs both)
if [ ! -d /usr/share/refind ]; then
  ok "no rEFInd on this host"
elif [ -f /etc/pacman.d/hooks/99-refind.hook ]; then
  ok "99-refind.hook present (system/apply-refind.sh)"
else
  warn "99-refind.hook missing — sudo bash $REPO/system/apply-refind.sh installs it"
fi

# --- 3) config files ----------------------------------------------------------
say "paccache: keep 2 versions (/etc/conf.d/pacman-contrib)"
install_file "$REPO/system/pacman-contrib.conf" /etc/conf.d/pacman-contrib

say "reflector: country=\"$COUNTRY\", https, 10 newest by rate (/etc/xdg/reflector/reflector.conf)"
TMP_REF="$(mktemp)"
sed "s|@COUNTRY@|$COUNTRY|" "$REPO/system/reflector.conf" >"$TMP_REF"
install_file "$TMP_REF" /etc/xdg/reflector/reflector.conf
rm -f "$TMP_REF"
# failure-tolerant: archlinux.org (the mirror-status source) may be unreachable from this LAN
install_file "$REPO/system/reflector-tolerant.conf" /etc/systemd/system/reflector.service.d/dram.conf
[ "$DRY" -eq 1 ] || systemctl daemon-reload 2>/dev/null || true

# --- 4) pacman.conf: single options only, never a rewrite --------------------
say "/etc/pacman.conf options"
PC=/etc/pacman.conf
PC_BACKED=0
pc_backup() {
  [ "$PC_BACKED" -eq 1 ] && return 0
  run cp -a "$PC" "$PC.bak-$STAMP"
  PC_BACKED=1
}
# set_opt <key> [value]: uncomment "#Key", fix an existing value, or add under [options]
set_opt() {
  local key="$1" val="${2:-}" line="$1"
  [ -n "$val" ] && line="$key = $val"
  if grep -qE "^$key( *=.*)?$" "$PC" && { [ -z "$val" ] || grep -qE "^$key *= *$val$" "$PC"; }; then
    ok "$line"
    return 0
  fi
  pc_backup
  if grep -qE "^#?$key( *=.*)?$" "$PC"; then
    # 0,/re/ : first matching line only, so a stray duplicate is never rewritten twice
    run sed -i -E "0,/^#?$key( *=.*)?$/s|^#?$key( *=.*)?$|$line|" "$PC" || {
      failed "could not set $line in $PC"
      return 1
    }
  else
    run sed -i "/^\[options\]/a $line" "$PC" || {
      failed "could not add $line to $PC"
      return 1
    }
  fi
  ok "set: $line"
}
set_opt Color
set_opt VerbosePkgLists
set_opt ParallelDownloads 10
# The 12 lib32 wine optdeps Arch dropped from [multilib] (Aug 2026) are served by
# [dram] now (pkgs/lib32-*); an earlier run of this script froze them with
# IgnorePkg — drop that line so pacman takes ours again.
if grep -qE '^IgnorePkg = lib32-audit ' "$PC"; then
  pc_backup
  run sed -i -E '/^IgnorePkg = lib32-audit /d' "$PC" && ok "removed: IgnorePkg lib32 freeze (served by [dram] now)" \
    || failed "could not remove the IgnorePkg lib32 line from $PC"
fi
# -x: the whole line must match, so a commented-out "#NoExtract = …" does not
# count as present (it did with -F alone, and the line was never re-added).
NOEX='NoExtract = usr/share/wayland-sessions/hyprland-uwsm.desktop'
if grep -qxF "$NOEX" "$PC"; then
  ok "$NOEX"
else
  pc_backup
  run sed -i "/^\[options\]/a $NOEX" "$PC" && ok "added: $NOEX (one Hyprland session in the greeter)" \
    || failed "could not add $NOEX to $PC"
fi

# --- 5) timers ----------------------------------------------------------------
say "Timers"
enable_timer paccache.timer # weekly: paccache -r $PACCACHE_ARGS
# smartmontools is in packages/metal.txt but its daemon was never enabled: the
# stock /etc/smartd.conf (DEVICESCAN) watches every SMART-capable disk and logs
# to the journal; `dram doctor` checks the unit (review 2026-10-07). A WSL clone has
# no disk of its own (the VHDX is Windows'): smartmontools is metal-only there.
if [ "$PLATFORM" = wsl ]; then
  ok "WSL: no disk of its own — smartd not needed"
else
  enable_timer smartd.service # disk health: SMART self-test/attribute monitoring, journal only
fi
enable_timer reflector.timer # weekly: rewrite /etc/pacman.d/mirrorlist
if systemctl list-unit-files arch-audit.timer --no-legend 2>/dev/null | grep -c arch-audit.timer >/dev/null; then
  enable_timer arch-audit.timer
else
  # Older arch-audit builds shipped no units; a daily CVE scan into the journal.
  warn "arch-audit ships no timer on this build — writing /etc/systemd/system/arch-audit.{service,timer}"
  if [ "$DRY" -eq 0 ]; then
    cat >/etc/systemd/system/arch-audit.service <<'EOF'
[Unit]
Description=Arch Linux security advisory check (arch-audit)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/arch-audit -u
EOF
    cat >/etc/systemd/system/arch-audit.timer <<'EOF'
[Unit]
Description=Daily arch-audit run

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
  fi
  enable_timer arch-audit.timer
fi
# arch-audit exits 1 whenever a vulnerable package is installed (nearly always:
# unfixed CVEs in systemd, wget …), which left the unit "failed" after every
# run and dram doctor red. Exit 1 is a report, not a failure. Needed on BOTH
# paths above — the shipped unit and the one written here (an earlier version
# wrote it only for the shipped unit). Write-on-change.
AA_DROPIN=/etc/systemd/system/arch-audit.service.d/10-dram.conf
TMP_AA="$(mktemp)"
printf '[Service]\nSuccessExitStatus=1\n' >"$TMP_AA"
if [ -f "$AA_DROPIN" ] && cmp -s "$TMP_AA" "$AA_DROPIN"; then
  ok "$AA_DROPIN already current (exit 1 = vulnerable packages listed, counts as success)"
elif [ "$DRY" -eq 1 ]; then
  printf '  \033[2m[dry-run] write %s (SuccessExitStatus=1)\033[0m\n' "$AA_DROPIN"
elif install -Dm0644 "$TMP_AA" "$AA_DROPIN" && systemctl daemon-reload; then
  systemctl reset-failed arch-audit.service 2>/dev/null || true
  ok "arch-audit.service: exit 1 (vulnerable packages listed) counts as success"
else
  failed "could not write $AA_DROPIN"
fi
rm -f "$TMP_AA"
# archlinux-keyring ships a static WKD sync timer (no [Install]); it should
# already be active. Report, never rewrite.
if systemctl is-active -q archlinux-keyring-wkd-sync.timer 2>/dev/null; then
  ok "archlinux-keyring-wkd-sync.timer active (keyring refreshes itself weekly)"
else
  warn "archlinux-keyring-wkd-sync.timer not active — systemctl start archlinux-keyring-wkd-sync.timer"
fi

# --- 6) services (from the old system-tweaks.sh) ------------------------------
say "Services"
if systemctl is-enabled -q NetworkManager 2>/dev/null; then
  ok "NetworkManager runs Wi-Fi (desktop role) — iwd left off (system/network-setup.sh)"
elif ls /sys/class/net/*/wireless >/dev/null 2>&1 || [ "${MAINT_IWD:-0}" = 1 ]; then
  if pacman -Qq iwd >/dev/null 2>&1; then
    systemctl is-enabled -q iwd 2>/dev/null && ok "iwd enabled (Wi-Fi auth; networkd does the IP)" \
      || { run systemctl enable --now iwd && ok "iwd enabled" || failed "could not enable iwd"; }
  else warn "Wi-Fi device present but iwd not installed (packages/metal.txt)"; fi
else
  ok "no Wi-Fi device — iwd left alone (MAINT_IWD=1 to force)"
fi
if pacman -Qq bluez >/dev/null 2>&1; then
  systemctl is-enabled -q bluetooth 2>/dev/null && ok "bluetooth enabled" \
    || { run systemctl enable --now bluetooth && ok "bluetooth enabled" || failed "could not enable bluetooth"; }
elif [ "$PLATFORM" = wsl ]; then
  ok "WSL: no Bluetooth of its own"
else
  warn "bluez not installed (packages/roles/desktop.txt) — skipping bluetooth"
fi
# WireGuard (docs/security/network/vpn.md): the client config is a per-host secret, never in
# the repo. Report only; enabling wg-quick@home is a per-host choice.
if [ "$PLATFORM" = wsl ]; then
  ok "WSL: the WireGuard tunnel is Windows' (mirrored networking carries it into the clone)"
elif [ -f /etc/wireguard/home.conf ]; then
  ok "/etc/wireguard/home.conf present (wg-quick@home: $(systemctl is-enabled wg-quick@home 2>/dev/null || echo disabled))"
else
  warn "no /etc/wireguard/home.conf — export a client from UniFi (docs/security/network/vpn.md); fine on LAN-only desktops"
fi
# Packages the old tweaks script removed, and what the 2026-10-10 compliance swaps took
# out (decisions/0013; `dram apply --prune` also catches them); report, do not remove.
LEFTOVER=()
for p in dolphin hyprpaper paru-debug scdoc paru 7zip unrar unzip qt6ct ipmitool xarchiver papirus-icon-theme papirus-folders bibata-cursor-theme wlogout iwgtk visual-studio-code-bin; do pacman -Qq "$p" >/dev/null 2>&1 && LEFTOVER+=("$p"); done
[ "${#LEFTOVER[@]}" -gt 0 ] && warn "redundant packages installed: ${LEFTOVER[*]}  (sudo pacman -Rns ${LEFTOVER[*]})"

# --- 7) realtime limit for the compositor -------------------------------------
# Hyprland asks for SCHED_RR at sched_get_priority_min on every start
# (NInit::gainRealTime) and logs "Failed to change process scheduling strategy"
# / "Failed to gain realtime scheduling" when pj has no rtprio limit. One
# pam_limits line instead of the rtkit daemon; applies at the next login.
# https://wiki.hypr.land/Configuring/Performance/, docs/platforms/arch/hooks.md
say "Hyprland realtime scheduling (/etc/security/limits.d/20-hyprland.conf)"
install_file "$REPO/system/limits-hyprland.conf" /etc/security/limits.d/20-hyprland.conf

# OBS virtual camera: only where the dkms module is installed (the gaming list).
if pacman -Q v4l2loopback-dkms >/dev/null 2>&1; then
  say "OBS virtual camera (v4l2loopback: modprobe options + load at boot)"
  install_file "$REPO/system/v4l2loopback.conf" /etc/modprobe.d/v4l2loopback.conf
  install_file "$REPO/system/v4l2loopback-load.conf" /etc/modules-load.d/v4l2loopback.conf
  if [ "$DRY" -eq 0 ] && ! lsmod | grep -q '^v4l2loopback'; then
    modprobe v4l2loopback && ok "v4l2loopback loaded (/dev/video10)" || failed "modprobe v4l2loopback failed — dkms build for $(uname -r)? see dkms status"
  fi
fi
# Debian's "plugdev": packaged udev rules that hand devices to it (openFPGALoader's FPGA
# programmers) meet no such group on Arch — udev logs an error per rule per boot and the
# device keeps root's permissions (cabin, 2026-10-11). Created, with the login user in it,
# only when a rule names it.
MAINT_USER="${DRAM_USER:-${SUDO_USER:-pj}}"
if grep -qs 'GROUP="plugdev"' /usr/lib/udev/rules.d/*.rules /etc/udev/rules.d/*.rules; then
  say "plugdev (a packaged udev rule hands devices to it)"
  if getent group plugdev >/dev/null; then ok "group plugdev exists"; else
    run groupadd -r plugdev && ok "group plugdev created" || failed "groupadd plugdev failed"
  fi
  if ! id "$MAINT_USER" >/dev/null 2>&1; then
    warn "no user $MAINT_USER (DRAM_USER) to add to plugdev"
  elif id -nG "$MAINT_USER" | tr ' ' '\n' | grep -cx plugdev >/dev/null; then
    ok "$MAINT_USER is in plugdev"
  else
    run usermod -aG plugdev "$MAINT_USER" && ok "$MAINT_USER in plugdev (from the next login)" || failed "usermod plugdev failed"
  fi
  [ "$DRY" -eq 1 ] || udevadm control --reload 2>/dev/null || true
fi
# system-login includes system-auth, which is where Arch ships the pam_limits line
if grep -qE '^[^#]*pam_limits\.so' /etc/pam.d/system-login /etc/pam.d/system-auth 2>/dev/null; then
  ok "pam_limits.so in the login PAM stack (limit applies at next login)"
else
  warn "pam_limits.so not in /etc/pam.d/system-login — the limits.d file will not apply"
fi

say "Done."
[ "$DRY" -eq 1 ] && echo "  (dry run: nothing was changed)"
[ "$RC" -eq 0 ] || warn "a step failed above (exit 1) — fix it and re-run; the other steps were applied"
echo "  Next: dram doctor   (read-only report; every warning names its fix)"
exit "$RC"

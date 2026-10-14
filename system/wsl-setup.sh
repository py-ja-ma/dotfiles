#!/usr/bin/env bash
# usage: wsl-setup.sh [--dry-run]
#
# The system half of a WSL clone (decisions/0021, docs/platforms/wsl/README.md): what turns
# the official
# Arch image into a converged host, written from the repo and changed only where it differs.
# The wsl pseudo-role's `dram apply` hook (system/apply-hooks.tsv); outside WSL it does
# nothing. In order:
#   1) /etc/wsl.conf from system/wsl/wsl.conf (hostname, default user, systemd,
#      appendWindowsPath=false) and /etc/hostname; a change takes effect once the distro
#      has stopped: `wsl.exe --terminate <distro>` from Windows (the last line says so)
#   2) the units Microsoft lists as breaking WSL stay masked (networkd, resolved,
#      NetworkManager, the tmpfiles units, tmp.mount); the metal units stay off
#   3) linger for the login: its user manager (the agent bridge, rootless Podman) runs
#      without a terminal open
#   4) rootless Podman: subordinate ids for the login, the file capabilities of
#      newuidmap/newgidmap (an imported rootfs loses them), / shared (dram-wsl-rshared)
#   5) sshd for VSCodium's Open Remote - SSH: 127.0.0.1:2222, keys only, a touch for a
#      security key (system/wsl/sshd.conf), the YubiKeys' keys from keys/ssh.pub in
#      /etc/ssh/authorized_keys.d/<login> (as system/harden.sh writes them on metal)
#   6) a YubiKey attached with usbipd: its hidraw node for wheel (system/wsl/*.rules)
# Root, unless --dry-run.
#
#   -n, --dry-run   print what would change
#   -h, --help      this text
#
# env: DRAM_USER (default: the sudo caller, else pj), DRAM_HOST (default: /etc/hostname)
# exit: 0 ok (or not WSL) · 1 not root, not a WSL host file, or a step failed · 2 bad usage
# see: docs/platforms/wsl/README.md, system/wsl/README.md

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
# shellcheck source=install/lib/detect.sh
. "$REPO/install/lib/detect.sh"
# shellcheck source=install/lib/roles.sh
. "$REPO/install/lib/roles.sh"
USERNAME="${DRAM_USER:-${SUDO_USER:-pj}}"
STAMP="$(date +%Y%m%d-%H%M%S)"
RC=0 RESTART=0
say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
failed() {
  warn "$*"
  RC=1
}
run() { if [ "$DRY" -eq 1 ]; then printf '  \033[2m[dry-run] %s\033[0m\n' "$*"; else "$@"; fi; }
[ "$(id -u)" -eq 0 ] || [ "$DRY" -eq 1 ] || {
  echo "Run with sudo: sudo bash $0 [--dry-run]"
  exit 1
}

if [ "$(detect_platform)" != wsl ]; then
  ok "not WSL: nothing to do (the WSL clone's hook, decisions/0021)"
  exit 0
fi
HOST="${DRAM_HOST:-$(cat /etc/hostname 2>/dev/null || uname -n)}"
if [ "$(host_form "$REPO" "$HOST")" != wsl ]; then
  printf '\033[1;31m[x]\033[0m %s\n' "modules/hosts/$HOST.nix is not a WSL clone (form = \"wsl\"): is the distro named after Windows? DRAM_HOST=<host>-wsl sudo -E bash $0 sets it (docs/platforms/wsl/README.md)" >&2
  exit 1
fi
DISTRO="$(host_wsl "$REPO" "$HOST" distro)"
if ! id "$USERNAME" >/dev/null 2>&1; then
  [ "$DRY" -eq 1 ] || {
    printf '\033[1;31m[x]\033[0m %s\n' "no user $USERNAME (DRAM_USER): install/windows/dram-windows/wsl.ps1 creates it" >&2
    exit 1
  }
  warn "no user $USERNAME yet (install/windows/dram-windows/wsl.ps1 creates it): the dry run goes on as if it existed"
fi

# same <a> <b>: identical content (sha256sum: coreutils is in the image's base, cmp is not)
same() { [ -f "$1" ] && [ -f "$2" ] && [ "$(sha256sum <"$1")" = "$(sha256sum <"$2")" ]; }
# install_file <src> <dst> [mode]: copy only when content differs; back up the old file;
# exit 0 when it was (or would be) written, 1 when it was current, 2 when the copy failed
install_file() {
  local src="$1" dst="$2" mode="${3:-0644}"
  if same "$src" "$dst"; then
    ok "$dst current"
    return 1
  fi
  [ -f "$dst" ] && run cp -a "$dst" "$dst.bak-$STAMP"
  if run install -Dm"$mode" "$src" "$dst"; then
    ok "$dst written"
    return 0
  fi
  failed "could not write $dst"
  return 2
}
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- 1) /etc/wsl.conf and the hostname ----------------------------------------------
say "/etc/wsl.conf (hostname $HOST, user $USERNAME) and /etc/hostname"
sed -e "s/@HOST@/$HOST/g" -e "s/@USER@/$USERNAME/g" -e "s/@DISTRO@/$DISTRO/g" "$REPO/system/wsl/wsl.conf" >"$TMP/wsl.conf"
install_file "$TMP/wsl.conf" /etc/wsl.conf && RESTART=1
# written in place, not replaced: WSL may hold /etc/hostname as a mount of its own
if [ "$(cat /etc/hostname 2>/dev/null)" = "$HOST" ]; then
  ok "/etc/hostname is $HOST"
elif [ "$DRY" -eq 1 ]; then
  echo "  [dry-run] write $HOST to /etc/hostname"
elif printf '%s\n' "$HOST" >/etc/hostname; then
  ok "/etc/hostname: $HOST"
  RESTART=1
else
  failed "could not write /etc/hostname"
fi

# --- 2) what breaks WSL stays masked; what is metal's stays off ----------------------
say "units: Microsoft's list masked, metal units off"
for u in systemd-networkd.service systemd-networkd-wait-online.service systemd-resolved.service \
  NetworkManager.service systemd-tmpfiles-setup.service systemd-tmpfiles-setup-dev.service \
  systemd-tmpfiles-setup-dev-early.service systemd-tmpfiles-clean.service systemd-tmpfiles-clean.timer tmp.mount; do
  if [ "$(systemctl is-enabled "$u" 2>/dev/null)" = masked ]; then continue; fi
  if run systemctl mask "$u" >/dev/null 2>&1; then ok "masked $u"; else failed "could not mask $u"; fi
done
for u in nftables.service smartd.service snapper-cleanup.timer snapper-timeline.timer systemd-timesyncd.service; do
  systemctl is-enabled -q "$u" 2>/dev/null || continue
  if run systemctl disable --now "$u" >/dev/null 2>&1; then ok "disabled $u (metal only)"; else failed "could not disable $u"; fi
done
ok "Microsoft's list is masked; no metal unit is enabled"

# --- 3) linger -------------------------------------------------------------------------
say "linger for $USERNAME"
if [ -e "/var/lib/systemd/linger/$USERNAME" ]; then
  ok "linger on"
elif run loginctl enable-linger "$USERNAME"; then
  ok "linger on (the user manager starts with the distro)"
else
  failed "loginctl enable-linger $USERNAME failed"
fi

# --- 4) rootless Podman ------------------------------------------------------------------
say "rootless Podman: subordinate ids, newuidmap/newgidmap, / shared"
for f in /etc/subuid /etc/subgid; do
  grep -q "^$USERNAME:" "$f" 2>/dev/null && continue
  flag=--add-subuids
  [ "$f" = /etc/subgid ] && flag=--add-subgids
  if run usermod "$flag" 100000-165535 "$USERNAME"; then ok "$f: $USERNAME:100000:65536"; else failed "usermod $flag for $USERNAME failed"; fi
done
# shadow ships both with file capabilities, which a rootfs imported from a tarball drops
# ("newuidmap: could not set caps"); the Arch wiki reinstalls shadow, setcap is the same bits
for pair in newuidmap:cap_setuid newgidmap:cap_setgid; do
  b="/usr/bin/${pair%%:*}" cap="${pair#*:}"
  [ -x "$b" ] || {
    failed "$b missing (shadow)"
    continue
  }
  if [ -u "$b" ] || getcap "$b" 2>/dev/null | grep -q "$cap"; then
    ok "$b has $cap"
  elif run setcap "$cap=ep" "$b"; then
    ok "$b: $cap restored"
  else
    failed "setcap $cap=ep $b failed"
  fi
done
if install_file "$REPO/system/wsl/dram-wsl-rshared.service" /etc/systemd/system/dram-wsl-rshared.service; then
  [ "$DRY" -eq 1 ] || systemctl daemon-reload 2>/dev/null || true
fi
if systemctl is-enabled -q dram-wsl-rshared.service 2>/dev/null && [ "$(findmnt -no PROPAGATION / 2>/dev/null)" = shared ]; then
  ok "/ is shared (dram-wsl-rshared.service)"
elif run systemctl enable --now dram-wsl-rshared.service >/dev/null 2>&1; then
  ok "dram-wsl-rshared.service enabled: / is shared"
else
  failed "could not enable dram-wsl-rshared.service"
fi

# --- 5) sshd for VSCodium: loopback, keys only ---------------------------------------------
say "sshd on 127.0.0.1:2222 (VSCodium's Open Remote - SSH from Windows)"
{
  echo "# written by dotfiles/system/wsl-setup.sh from keys/ssh.pub - do not hand-edit (docs/security/identity/yubikeys.md)"
  grep -E '^sk-' "$REPO/keys/ssh.pub" 2>/dev/null || true
} >"$TMP/yk"
SSHD_CHANGED=0
install_file "$TMP/yk" "/etc/ssh/authorized_keys.d/$USERNAME" && SSHD_CHANGED=1
install_file "$REPO/system/wsl/sshd.conf" /etc/ssh/sshd_config.d/10-dram-wsl.conf && SSHD_CHANGED=1
if [ "$DRY" -eq 1 ]; then
  [ "$SSHD_CHANGED" -eq 0 ] || echo "  [dry-run] ssh-keygen -A; sshd -t; systemctl enable sshd; systemctl restart sshd"
elif ! command -v sshd >/dev/null 2>&1; then
  failed "sshd missing (openssh, packages/base.txt): dram apply first"
else
  ssh-keygen -A >/dev/null 2>&1 || true # the host keys sshdgenkeys.service would make at the first start
  if ! sshd -t 2>"$TMP/sshd.err"; then
    rm -f /etc/ssh/sshd_config.d/10-dram-wsl.conf
    failed "sshd -t refused the config ($(head -1 "$TMP/sshd.err")): the drop-in is removed, sshd untouched"
  else
    systemctl is-enabled -q sshd.service 2>/dev/null || systemctl enable sshd.service >/dev/null 2>&1 || failed "could not enable sshd.service"
    if [ "$SSHD_CHANGED" -eq 1 ] || ! systemctl is-active -q sshd.service; then
      if systemctl restart sshd.service; then ok "sshd (re)started: 127.0.0.1:2222"; else failed "sshd did not start: journalctl -u sshd"; fi
    else
      ok "sshd running on 127.0.0.1:2222"
    fi
  fi
fi

# --- 6) a YubiKey through usbipd ---------------------------------------------------------
say "a YubiKey attached with usbipd (hidraw for wheel)"
if install_file "$REPO/system/wsl/70-dram-wsl-yubikey.rules" /etc/udev/rules.d/70-dram-wsl-yubikey.rules; then
  [ "$DRY" -eq 1 ] || udevadm control --reload 2>/dev/null || true
fi
id -nG "$USERNAME" 2>/dev/null | tr ' ' '\n' | grep -cx wheel >/dev/null \
  || warn "$USERNAME is not in wheel: the rule gives the key's node to wheel (usermod -aG wheel $USERNAME)"

say "Done."
[ "$DRY" -eq 1 ] && echo "  (dry run: nothing was changed)"
[ "$RESTART" -eq 1 ] && [ "$DRY" -eq 0 ] && warn "wsl.conf or the hostname changed: from Windows, wsl.exe --terminate $DISTRO, then open the clone again"
[ "$RC" -eq 0 ] || warn "a step failed above (exit 1); the other steps were applied"
exit "$RC"

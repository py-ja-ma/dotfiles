#!/usr/bin/env bash
# usage: harden.sh [--dry-run]
#
# Hardens an Arch host, idempotently: installs system/nftables.conf (default deny,
# SSH and LocalSend from the LAN only), makes sshd keys-only and adds the YubiKeys'
# keys from keys/ssh.pub as /etc/ssh/authorized_keys.d/<login>, sets sysctl limits,
# turns on DNS over TLS where the resolver offers it and turns off LLMNR and mDNS,
# configures faillock and sudo, sets up the ly greeter on tty2 through apply-ly.sh, and
# installs pacman-contrib, arch-audit and rsync. Re-run after editing nftables.conf or
# keys/ssh.pub. Root, unless --dry-run.
#
#   -n, --dry-run   print every change, apply none (no root needed)
#   -h, --help      this text
#
# needs:  nftables, openssh, systemd-resolved, sudo; root unless --dry-run
# alone:  set `define LAN` in nftables.conf to your subnet first, or lose SSH;
#         put your own public keys in keys/ssh.pub
# here:   an `ask` hook of `dram apply` on metal hosts (system/apply-hooks.tsv);
#         `dram doctor --supply` warns when sshd or nftables drift
# exit:   0 ok · 1 not root or a step failed · 2 bad usage
# see:    docs/security/network/hardening.md

# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT

DRY=0
case "${1:-}" in
  --dry-run | -n) DRY=1 ;;
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

# What it changes, in order:
#  1. Firewall: the repo's nftables default-deny ruleset (system/nftables.conf), SSH and
#     LocalSend from the LAN only; nftables marked an explicit package. No ufw or firewalld.
#  2. sysctl: kernel pointers and dmesg restricted, ICMP redirects refused, the BPF JIT
#     hardened, kexec off, martians logged, FIFOs and regular files protected, tcp_rfc1337.
#     User namespaces stay on: Chromium's and Flatpak's sandboxes need them.
#  3. DNS over TLS (opportunistic) through systemd-resolved, Quad9 and Cloudflare; the
#     LLMNR and mDNS responders off, a spoofing surface these hosts need none of.
#  4. faillock: 5 tries, then a 10-minute lock; never even_deny_root, and /run/faillock is
#     tmpfs, so a reboot clears it.
#  5. sudoers: a short ticket per terminal, no password echo (checked with visudo first).
#  6. ly: allow_empty_password=false, enabled on tty2.
#  7. pacman-contrib (pacdiff), arch-audit (the CVE check), rsync.
# Not done here: linux-hardened, AppArmor, USBGuard, firejail, unattended updates
# (docs/security/network/hardening.md); Secure Boot is system/secureboot-setup.sh.

set -euo pipefail
[ "$(id -u)" = 0 ] || [ "$DRY" -eq 1 ] || {
  echo "run with sudo (or --dry-run)"
  exit 1
}
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
say() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
# run <cmd...>: the command, or its [dry-run] line (same shape as maintenance.sh)
run() {
  if [ "$DRY" -eq 1 ]; then printf '  \033[2m[dry-run] %s\033[0m\n' "$*"; else "$@"; fi
}
# write_file <dst> [mode]: stdin becomes <dst>; the dry run only says whether it differs
write_file() {
  local dst="$1" mode="${2:-0644}" tmp
  tmp="$(mktemp)"
  cat >"$tmp"
  if [ "$DRY" -eq 1 ]; then
    if cmp -s "$tmp" "$dst" 2>/dev/null; then printf '  \033[2m[dry-run] %s already current\033[0m\n' "$dst"; else printf '  \033[2m[dry-run] write %s\033[0m\n' "$dst"; fi
  else install -m "$mode" "$tmp" "$dst"; fi
  rm -f "$tmp"
}

# --- 1. firewall -------------------------------------------------------------
say "Firewall: install authored nftables default-deny ruleset"
run pacman -S --needed --noconfirm nftables
# make it explicit so dram harvest records it (it's otherwise only a dependency)
if [ "$DRY" -eq 1 ]; then run pacman -D --asexplicit nftables; else pacman -D --asexplicit nftables >/dev/null 2>&1 || true; fi
# Syntax + semantic check of the REPO copy before anything is installed: a typo
# must never leave the host with the old rules (or none). Arch's unit is a
# oneshot without RemainAfterExit, so `enable --now` happens to re-run nft -f
# today; the explicit restart keeps working if that ever changes.
# role openings live in /etc/nftables.d/*.nft (system/recording-setup.sh writes one); an
# empty placeholder keeps the include pattern matching on hosts without any
if [ "$DRY" -eq 1 ]; then run install -Dm644 /dev/null /etc/nftables.d/00-none.nft; elif [ ! -e /etc/nftables.d/00-none.nft ]; then
  install -d -m 755 /etc/nftables.d && printf '# no role opens a port here (system/harden.sh)\n' >/etc/nftables.d/00-none.nft
fi
# The LAN that may reach sshd and LocalSend is this host's fact, kept in /etc/dram/lan.nft
# (system/nftables.conf includes it), never in the repo. Written once and then left alone,
# so a laptop that runs this away from home keeps its home subnet. The first value: DRAM_LAN,
# else the define of a ruleset installed before the file existed, else the subnet of the
# default route's interface. Private (RFC 1918) ranges only, unless DRAM_LAN says otherwise.
LAN_FILE=/etc/dram/lan.nft
if [ -s "$LAN_FILE" ] && [ -z "${DRAM_LAN:-}" ]; then
  echo "  LAN: $(sed -n 's/^define LAN = //p' "$LAN_FILE") ($LAN_FILE, kept)"
else
  lan="${DRAM_LAN:-}" how="DRAM_LAN"
  if [ -z "$lan" ] && [ -f /etc/nftables.conf ]; then
    lan="$(sed -n 's/^define LAN = \([0-9./]*\).*/\1/p' /etc/nftables.conf | head -n 1)" how="the installed ruleset"
  fi
  if [ -z "$lan" ]; then
    dev="$(ip -4 route show default 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }')"
    [ -n "$dev" ] && lan="$(ip -4 route show dev "$dev" proto kernel scope link 2>/dev/null | awk '$1 ~ /\// { print $1; exit }')"
    how="the default route's interface (${dev:-none})"
    case "$lan" in 10.* | 192.168.* | 172.1[6-9].* | 172.2[0-9].* | 172.3[01].*) ;; *)
      echo "  no private LAN found ($how: '${lan:-none}'): name it, e.g. sudo DRAM_LAN=192.168.1.0/24 bash system/harden.sh" >&2
      exit 1
      ;;
    esac
  fi
  [[ "$lan" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] || {
    echo "  '$lan' is not an IPv4 subnet (a.b.c.d/nn)" >&2
    exit 1
  }
  run install -d -m 0755 /etc/dram
  printf '# written by system/harden.sh from %s: the subnet allowed to reach sshd and LocalSend\n# (system/nftables.conf). On another LAN, edit it and: sudo systemctl restart nftables\ndefine LAN = %s\n' \
    "$how" "$lan" | write_file "$LAN_FILE"
  echo "  LAN: $lan (from $how)"
fi
run nft -c -f "$REPO/system/nftables.conf"
if [ -f /etc/nftables.conf ] && ! cmp -s "$REPO/system/nftables.conf" /etc/nftables.conf; then
  run cp -a /etc/nftables.conf "/etc/nftables.conf.bak-$(date +%Y%m%d-%H%M%S 2>/dev/null || echo bak)"
fi
run install -m 0644 "$REPO/system/nftables.conf" /etc/nftables.conf
run systemctl enable nftables.service
run systemctl restart nftables.service
[ "$DRY" -eq 1 ] || nft list ruleset | grep -Ec 'policy drop' | {
  read -r n
  echo "  chains with default-deny: $n (expect 2)"
} || true

# --- 1b. sshd: keys only -----------------------------------------------------
# Password logins over the LAN were the most concrete exposure in 2026-10
# (docs/security/README.md). The hosts hold the Mac's key and the YubiKeys', so
# passwords buy nothing. Write-on-change; sshd reload keeps existing sessions alive.
say "sshd: public-key authentication only (/etc/ssh/sshd_config.d/10-keys-only.conf)"
SSHD_DROPIN=/etc/ssh/sshd_config.d/10-keys-only.conf
# Never go keys-only without a key to log in with: an empty or missing
# authorized_keys (fresh install before handbook 01 §2, a reinstall that
# restores ~ later) would lock the Mac and the backup peer out at once.
LOGIN="${DRAM_USER:-${SUDO_USER:-pj}}"
AUTH_KEYS="$(getent passwd "$LOGIN" 2>/dev/null | cut -d: -f6)/.ssh/authorized_keys"
# The YubiKeys' SSH keys (keys/ssh.pub, decisions/0019) reach every host through a
# root-owned second AuthorizedKeysFile, so ~/.ssh/authorized_keys stays the place for
# this host's own extra lines. Rewritten from the repo on every run: a line deleted
# there (a lost key) is gone here too.
YK_DIR=/etc/ssh/authorized_keys.d
YK_FILE="$YK_DIR/$LOGIN"
tmp_yk="$(mktemp)"
{
  echo "# written by dotfiles/system/harden.sh from keys/ssh.pub — do not hand-edit (docs/security/identity/ssh.md)"
  grep -E '^sk-' "$REPO/keys/ssh.pub" 2>/dev/null || true
} >"$tmp_yk"
HAVE_KEY=1
grep -qE '^(ssh-|ecdsa-|sk-)' "$AUTH_KEYS" "$tmp_yk" 2>/dev/null || HAVE_KEY=0
if [ "$HAVE_KEY" -eq 0 ] && [ "$DRY" -eq 0 ]; then
  echo "  no public key in $AUTH_KEYS or keys/ssh.pub — refusing to disable password authentication." >&2
  echo "  From the Mac: ssh-copy-id -i ~/.ssh/id_ed25519.pub $LOGIN@$(hostname); then re-run." >&2
  rm -f "$tmp_yk"
  exit 1
fi
if cmp -s "$tmp_yk" "$YK_FILE" 2>/dev/null; then
  echo "  $YK_FILE current ($(grep -c '^sk-' "$tmp_yk") YubiKey key(s))"
else
  run install -d -m 0755 "$YK_DIR"
  run install -m 0644 "$tmp_yk" "$YK_FILE"
  [ "$DRY" -eq 1 ] || echo "  wrote $YK_FILE ($(grep -c '^sk-' "$tmp_yk") YubiKey key(s))"
fi
rm -f "$tmp_yk"
tmp_sshd="$(mktemp)"
cat >"$tmp_sshd" <<'EOF2'
# written by dotfiles/system/harden.sh — do not hand-edit; re-run the script
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
# the host's own lines, then the YubiKeys' (keys/ssh.pub, written by harden.sh)
AuthorizedKeysFile .ssh/authorized_keys /etc/ssh/authorized_keys.d/%u
# a security key must prove a touch on every login, whatever a key line says
PubkeyAuthOptions touch-required
EOF2
if [ "$HAVE_KEY" -eq 0 ]; then
  echo "  !! no public key in $AUTH_KEYS — a real run would stop here; the keys-only drop-in is skipped"
elif [ "$DRY" -eq 1 ] && ! cmp -s "$tmp_sshd" "$SSHD_DROPIN" 2>/dev/null; then
  run install -m 0644 "$tmp_sshd" "$SSHD_DROPIN"
  run systemctl reload sshd
elif ! cmp -s "$tmp_sshd" "$SSHD_DROPIN" 2>/dev/null; then
  install -m 0644 "$tmp_sshd" "$SSHD_DROPIN"
  sshd -t && systemctl reload sshd && echo "  sshd reloaded (keys only)" || {
    rm -f "$SSHD_DROPIN"
    echo "  sshd config test FAILED — drop-in removed, sshd untouched" >&2
  }
  # Arch includes sshd_config.d/ at the TOP of sshd_config (first value wins); say so
  # if a packaging change ever moves it and the YubiKeys' file stops being read
  sshd -T 2>/dev/null | grep -qi '^authorizedkeysfile .*/etc/ssh/authorized_keys.d/%u' \
    || echo "  !! sshd -T does not show /etc/ssh/authorized_keys.d/%u — is the Include still first in sshd_config?" >&2
else
  echo "  already keys-only"
fi
rm -f "$tmp_sshd"

# --- 2. sysctl ---------------------------------------------------------------
say "Sysctl hardening -> /etc/sysctl.d/99-hardening.conf"
write_file /etc/sysctl.d/99-hardening.conf <<'EOF'
## Kernel info leaks
kernel.kptr_restrict = 1
kernel.dmesg_restrict = 1

## Attack surface
kernel.unprivileged_bpf_disabled = 2
net.core.bpf_jit_harden = 2
kernel.yama.ptrace_scope = 1
kernel.kexec_load_disabled = 1

## Filesystem hardlink/symlink + fifo/regular-file protections
fs.protected_symlinks = 1
fs.protected_hardlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2

## Network
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1

## Not set: kernel.unprivileged_userns_clone = 0
## (it would break Flatpak's bubblewrap, the Chromium sandbox and Steam's pressure-vessel)
EOF
run sysctl --system >/dev/null
echo "  kptr_restrict now: $(sysctl -n kernel.kptr_restrict)"

# --- 3. DNS-over-TLS + kill LLMNR/mDNS ---------------------------------------
say "DNS-over-TLS (opportunistic) + disable LLMNR/mDNS via systemd-resolved"
run mkdir -p /etc/systemd/resolved.conf.d
write_file /etc/systemd/resolved.conf.d/dot.conf <<'EOF'
[Resolve]
DNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 2620:fe::fe#dns.quad9.net 1.1.1.1#cloudflare-dns.com
FallbackDNS=1.0.0.1#cloudflare-dns.com
DNSOverTLS=opportunistic
DNSSEC=no
# LLMNR + mDNS are credential-spoofing vectors on hostile networks; this box
# (SSH client + web dev) needs neither. Set MulticastDNS=resolve only if you
# ever address the homelab by *.local names.
LLMNR=no
MulticastDNS=no
EOF
run systemctl restart systemd-resolved
resolvectl status 2>/dev/null | grep -m1 'DNS Servers' || true

# --- 4. faillock (recovery-safe) ---------------------------------------------
say "faillock: recovery-safe lockout policy"
write_file /etc/security/faillock.conf <<'EOF'
# Recovery-safe: 5 tries (the default 3 once locked this account out at hyprlock),
# 10-minute auto-unlock. Never set even_deny_root. /run/faillock is tmpfs, so a
# reboot always clears counters. Manual reset from any logged-in shell:
#   faillock --user <login> --reset      (or: sudo faillock --reset)
deny = 5
unlock_time = 600
fail_interval = 900
EOF
echo "  deny=5 unlock_time=600 (reset cmd: faillock --user $LOGIN --reset)"

# --- 5. sudoers hardening (validated before install) -------------------------
say "sudoers: timestamp + pwfeedback + tty tickets"
tmp_sudo="$(mktemp)"
cat >"$tmp_sudo" <<'EOF'
Defaults timestamp_timeout=10
Defaults !pwfeedback
Defaults tty_tickets
EOF
if visudo -cf "$tmp_sudo" >/dev/null 2>&1; then
  run install -m 0440 "$tmp_sudo" /etc/sudoers.d/10-hardening
  [ "$DRY" -eq 1 ] || echo "  installed /etc/sudoers.d/10-hardening"
else
  echo "  !! sudoers snippet failed validation — NOT installed (left sudo untouched)"
fi
rm -f "$tmp_sudo"

# --- 6. ly greeter -----------------------------------------------------------
say "ly greeter: enforce no-empty-password, enable on tty2"
# apply-ly.sh writes allow_empty_password = false on every run (ini or lua,
# whichever the installed ly reads) and is write-on-change, so this is a no-op
# when the greeter is already in the house configuration.
ly_args=(--anim none)
if [ "$DRY" -eq 1 ]; then ly_args+=(--dry-run); fi
bash "$REPO/system/apply-ly.sh" "${ly_args[@]}" || echo "  !! apply-ly.sh failed — check /etc/ly"
run systemctl enable ly@tty2.service 2>/dev/null || true
echo "  (greeter takes effect next boot)"

# --- 7. hygiene tools --------------------------------------------------------
say "Update-hygiene tools"
run pacman -S --needed --noconfirm pacman-contrib arch-audit rsync

[ "$DRY" -eq 1 ] && {
  say "Dry run: nothing was changed."
  exit 0
}
say "Done. Reboot once, then verify:"
echo "  nft list ruleset | head        # input policy drop"
echo "  resolvectl status | grep -i -E 'llmnr|mdns'   # both off"
echo "  faillock --user $LOGIN             # 0 failures"

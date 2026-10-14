#!/usr/bin/env bash
# usage: gaming-vm.sh [PKGDIR]
#
# Test tier T2 for Gaming Mode switching (decisions/0012), best-effort on the Mac: boots a
# COPY of the disk tests/t2-vm.sh installed, installs ly, polkit, Hyprland, gamescope and
# the built [dram] packages (gamescope-session, gamescope-session-steam, dram-gaming-mode
# from PKGDIR, default ~/vm-bench/b5build/out), then drives a real switch:
#   1. a request for "Desktop" + a restart of ly@tty2 -> ly 1.4.1 autologins pj;
#   2. inside that session the real `steamos-session-select gaming` -> os-session-select
#      -> pkexec (polkit: the active session, no password) -> session-switch, which
#      ends the session and restarts ly -> ly-prepare -> autologin into "Gaming Mode";
#   3. the next plain ly start clears the autologin keys; an ssh caller is refused by
#      polkit; `session-switch --finish` refuses to run under pkexec.
# A VM has no GPU for Hyprland, so /usr/local/bin/start-hyprland is a stand-in that logs
# which session started it (and makes the one switch); everything else is the real chain.
# Work dir ~/vm-bench/gaming; the T2 disk is never modified.
#
#   -h, --help    this text
#
# exit: 0 every check passed · 1 a stage failed · 2 bad usage
# see: docs/toolchain/profiles/gaming.md, pkgs/dram-gaming-mode/REVIEW.md

case "${1:-}" in
  -h | --help)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  -*)
    sed -n '2s/^# \{0,1\}//p' "$0" >&2
    exit 2
    ;;
esac

set -uo pipefail
PKGDIR="${1:-$HOME/vm-bench/b5build/out}"
W="$HOME/vm-bench/gaming"
T2="$HOME/vm-bench/t2/disk.qcow2"
FW=/opt/homebrew/share/qemu
PORT=2224
rm -rf "$W/www" # a package from an earlier run would be offered twice
mkdir -p "$W/www"
die() {
  echo "gaming-vm: FAIL — $*" >&2
  pkill -f "$W/disk.qcow2" 2>/dev/null
  exit 1
}
log() { echo "gaming-vm: $(date +%T) $*"; }
[ -f "$T2" ] || die "no T2 disk — run tests/t2-vm.sh first"
for p in gamescope-session gamescope-session-steam dram-gaming-mode; do
  ls "$PKGDIR"/$p-[0-9r]*.pkg.tar.zst >/dev/null 2>&1 || die "no $p package in $PKGDIR (build pkgs/ first)"
done

log "copy of the T2 disk, plain UEFI"
qemu-img create -q -f qcow2 -b "$T2" -F qcow2 "$W/disk.qcow2" || die "overlay"
cp "$FW/edk2-i386-vars.fd" "$W/vars.fd"
cp "$PKGDIR"/*.pkg.tar.zst "$W/www/"
(cd "$W/www" && exec python3 -m http.server 8002 --bind 127.0.0.1 >"$W/http.log" 2>&1) &
HTTP=$!
trap 'kill $HTTP 2>/dev/null' EXIT
FILES="$(cd "$W/www" && printf "%s\n" gamescope-session-r*.pkg.tar.zst gamescope-session-steam-r*.pkg.tar.zst dram-gaming-mode-*.pkg.tar.zst | tr '\n' ' ')"

rm -f "$W/boot.log"
qemu-system-x86_64 -machine q35 -cpu max -smp 4 -m 4096 -accel "tcg,thread=multi" \
  -drive "if=pflash,format=raw,readonly=on,file=$FW/edk2-x86_64-code.fd" \
  -drive "if=pflash,format=raw,file=$W/vars.fd" \
  -drive "file=$W/disk.qcow2,if=none,id=d0" -device "virtio-blk-pci,drive=d0,serial=VMTEST1" \
  -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$PORT-:22" -device virtio-net-pci,netdev=n0 \
  -display none -no-reboot -serial "file:$W/boot.log" &
VM=$!
for _ in $(seq 360); do
  grep -q 'login:' "$W/boot.log" 2>/dev/null && break
  kill -0 "$VM" 2>/dev/null || die "VM stopped while booting ($W/boot.log)"
  sleep 5
done
grep -q 'login:' "$W/boot.log" || die "no login prompt within 30 min"

# vm <timeout> <cmd>: run cmd as pj over ssh; sudo prompts get the test password
vm() {
  expect -c "
    set timeout $1
    spawn ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p $PORT pj@127.0.0.1 {$2}
    expect {
      -re {assword( for pj)?:} { send \"test\r\"; exp_continue }
      timeout { puts \"\n>>> TIMEOUT\"; exit 124 }
      eof
    }
    catch wait r; exit [lindex \$r 3]
  "
}
for _ in $(seq 30); do
  vm 30 "true" >/dev/null 2>&1 && break
  sleep 5
done
log "booted"
FAILS=0
check() { # check <name> <cmd>
  if vm 120 "$2" >"$W/check.out" 2>&1; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    tr -d '\r' <"$W/check.out" | sed 's/^/     /' | tail -6
    FAILS=$((FAILS + 1))
  fi
}

log "installing ly, polkit, hyprland, gamescope + the built packages (TCG: slow)"
vm 3600 "sudo pacman -Syu --noconfirm --needed ly polkit hyprland gamescope" | tr -d '\r' | tail -3 || die "pacman -S"
vm 600 "cd /tmp && for f in $FILES; do curl -fsSO http://10.0.2.2:8002/\$f || exit 1; done && sudo pacman -U --noconfirm $FILES" | tr -d '\r' | tail -3 || die "pacman -U"

log "the stand-in compositor, ly on tty2"
vm 60 "sudo tee /usr/local/bin/start-hyprland >/dev/null <<'SH'
#!/bin/bash
# gaming-vm.sh stand-in: log the session, make ONE switch from the Desktop, then idle
echo \"\$(date +%s) session=\${DRAM_SESSION:-?} desktop=\${XDG_CURRENT_DESKTOP:-?} args=\$*\" >>/tmp/dram-sessions.log
if [ \"\${DRAM_SESSION:-}\" = desktop ] && [ ! -e /tmp/dram-switched ]; then
  touch /tmp/dram-switched
  sleep 5
  steamos-session-select gaming >/tmp/dram-switch.out 2>&1
fi
exec sleep 900
SH
sudo chmod 755 /usr/local/bin/start-hyprland && mkdir -p ~/.config/hypr && touch ~/.config/hypr/gaming.lua && sudo systemctl disable --now getty@tty2.service 2>/dev/null; sudo systemctl enable ly@tty2.service" >/dev/null || die "stand-in"
check "three ly sessions are installed" "ls /usr/share/wayland-sessions/dram-desktop.desktop /usr/share/wayland-sessions/dram-gaming.desktop /usr/share/wayland-sessions/gamescope-session-steam.desktop"
check "ly@tty2 has the ly-prepare drop-in" "systemctl cat ly@tty2.service | grep -q /usr/lib/dram/ly-prepare"

log "1: request the Desktop, start ly"
vm 60 "sudo install -d /run/dram && printf 'dram-desktop\npj\n' | sudo tee /run/dram/ly-next-session >/dev/null && sudo systemctl restart ly@tty2.service" >/dev/null
sleep 90
check "ly autologged pj into the Desktop" "grep -q 'session=desktop' /tmp/dram-sessions.log"
log "2: the session switched itself to Gaming Mode (waiting)"
for _ in $(seq 24); do
  vm 30 "grep -q 'session=gaming' /tmp/dram-sessions.log" >/dev/null 2>&1 && break
  sleep 10
done
check "Desktop -> Gaming Mode through steamos-session-select" "grep -q 'session=gaming' /tmp/dram-sessions.log"
check "the switch said what it did" "grep -q 'switching pj to dram-gaming' /tmp/dram-switch.out"
check "the request was consumed" "test ! -e /run/dram/ly-next-session"
check "ly-prepare logged the one-shot autologin into Gaming Mode" "sudo journalctl -b -t ly-prepare --no-pager | grep -q 'one-shot autologin pj -> dram-gaming'"
check "Gaming Mode started Hyprland with gaming.lua" "grep 'session=gaming' /tmp/dram-sessions.log | grep -q -- '--config .*/hypr/gaming.lua'"
check "the autologin went through ly-autologin" "sudo journalctl -b --no-pager | grep -q 'pam_unix(ly-autologin:session): session opened for user pj'"
check "XDG_CURRENT_DESKTOP is Hyprland in both sessions" "! grep -v 'desktop=Hyprland' /tmp/dram-sessions.log"

log "3: negatives"
check "an ssh caller is refused by polkit" "! /usr/lib/os-session-select gaming"
check "--finish refuses to run under pkexec" "! sudo env PKEXEC_UID=1000 /usr/lib/dram/session-switch --finish 1 tty2"
vm 60 "sudo systemctl restart ly@tty2.service" >/dev/null
sleep 30
check "a plain ly start clears the autologin keys" "! grep -qE '^auto_login_(session|user)' /etc/ly/config.ini"

vm 60 "sudo systemctl poweroff" >/dev/null 2>&1
for _ in $(seq 60); do
  kill -0 "$VM" 2>/dev/null || break
  sleep 2
done
kill "$VM" 2>/dev/null
[ "$FAILS" -eq 0 ] || die "$FAILS check(s) failed"
log "Gaming Mode switching passed"

#!/usr/bin/env bash
# usage: t2-bootstrap.sh [--keep]
#
# Test tier T2b on the Mac: the first boot of a machine install/arch-install.sh made,
# the way handbook 01 §6 runs it. Boots the T2 disk (made first with `tests/t2-vm.sh
# --roles desktop --sys-gib 28`) through a throwaway qcow2 overlay, commits the host file
# the installer wrote (a flake sees only tracked files), runs `install/bootstrap.sh --yes`
# over ssh (phases 1-5 unasked; `dram apply --yes` skips the ask hooks; phase 6's
# hardening question is answered no), then checks what the chapter promises: the role's
# packages, ly enabled, Nix and the Home Manager generation, `dram` on PATH in a login
# shell, `dram doctor --brief`. The T2 disk itself is never written. Slow under TCG (Nix
# builds the user layer): an hour or more. Logs in ~/vm-bench/t2b.
#
#   --keep        keep the overlay afterwards (default: removed)
#   -h, --help    this text
#
# exit: 0 bootstrap finished and every check passed · 1 a stage failed · 2 bad usage
# see: docs/records/handbook/01-install.md, tests/t2-vm.sh

KEEP=0
case "${1:-}" in
  "") ;;
  --keep) KEEP=1 ;;
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
BASE="$HOME/vm-bench/t2"
W="$HOME/vm-bench/t2b"
FW=/opt/homebrew/share/qemu
PORT=2224
die() {
  echo "t2b: FAIL — $*" >&2
  exit 1
}
log() { echo "t2b: $(date +%T) $*"; }
[ -f "$BASE/disk.qcow2" ] && [ -f "$BASE/vars.fd" ] || die "no T2 disk — run tests/t2-vm.sh --roles desktop --sys-gib 28 first"
mkdir -p "$W"
rm -f "$W/overlay.qcow2" "$W/boot.log"
qemu-img create -q -f qcow2 -b "$BASE/disk.qcow2" -F qcow2 "$W/overlay.qcow2" || die "qemu-img overlay"
cp "$BASE/vars.fd" "$W/vars.fd"

log "booting the T2 disk through an overlay — tail -f $W/boot.log"
qemu-system-x86_64 -machine q35 -cpu max -smp 4 -m 6144 -accel "tcg,thread=multi" \
  -drive "if=pflash,format=raw,readonly=on,file=$FW/edk2-x86_64-code.fd" \
  -drive "if=pflash,format=raw,file=$W/vars.fd" \
  -drive "file=$W/overlay.qcow2,if=none,id=d0" -device "virtio-blk-pci,drive=d0,serial=VMTEST1" \
  -display none -no-reboot -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$PORT-:22" -device virtio-net-pci,netdev=n0 \
  -serial "file:$W/boot.log" &
VM=$!
cleanup() {
  kill "$VM" 2>/dev/null
  wait "$VM" 2>/dev/null
  [ "$KEEP" = 1 ] || rm -f "$W/overlay.qcow2" "$W/vars.fd"
}
trap cleanup EXIT
for _ in $(seq 360); do
  grep -q 'login:' "$W/boot.log" 2>/dev/null && break
  kill -0 "$VM" 2>/dev/null || die "the VM stopped while booting — see $W/boot.log"
  sleep 5
done
grep -q 'login:' "$W/boot.log" || die "no login prompt within 30 min — see $W/boot.log"
# the login prompt comes before sshd listens under TCG: wait until sshd itself answers
# (a refused password in batch mode is the answer; a reset connection is not)
for _ in $(seq 60); do
  ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -p "$PORT" pj@127.0.0.1 true 2>&1 | grep -q 'Permission denied' && break
  sleep 5
done

# vmssh <timeout-seconds> <log> <remote command>: sudo's password and the hardening
# question are answered by expect; everything goes to the log
vmssh() {
  expect -c "
    set timeout $1
    log_file -noappend {$2}
    spawn ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o PubkeyAuthentication=no -o ServerAliveInterval=60 -p $PORT pj@127.0.0.1 {$3}
    expect {
      -re {assword( for [^:]*)?:} { send \"test\r\"; exp_continue }
      -re {Run harden.sh\? \[y/N\]} { send \"n\r\"; exp_continue }
      timeout { puts \"\n>>> TIMEOUT\"; exit 124 }
      eof
    }
    catch wait r; exit [lindex \$r 3]
  " >/dev/null
}

log "committing the host file, then install/bootstrap.sh --yes (Nix under TCG: an hour or more) — tail -f $W/bootstrap.log"
vmssh 14400 "$W/bootstrap.log" 'cd ~/git/dotfiles && git add modules/hosts/vmtest.nix && git -c user.name=t2b -c user.email=t2b@localhost commit -qm "hosts: vmtest" && bash install/bootstrap.sh --yes; echo "== BOOTSTRAP_RC=$?"'
rc="$(sed -n 's/.*== BOOTSTRAP_RC=\([0-9]*\).*/\1/p' "$W/bootstrap.log" | tail -1)"
log "bootstrap exit ${rc:-?}"

CHECKS='set -u; fail=0
chk() { if eval "$2" >/dev/null 2>&1; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
chk "dram is on PATH in a login shell" "bash -lc \"command -v dram\" | grep -q /.local/bin/dram"
chk "the desktop role: hyprland, waybar, kitty, ly" "pacman -Q hyprland waybar kitty ly"
chk "ly enabled on tty2" "systemctl is-enabled ly@tty2.service"
chk "nix is installed" "test -x /nix/var/nix/profiles/default/bin/nix"
chk "a Home Manager generation is active" "test -e ~/.local/state/nix/profiles/home-manager || test -e ~/.local/state/home-manager/gcroots/current-home"
chk "the dotfiles are linked into the checkout" "readlink -f ~/.config/hypr | grep -q git/dotfiles/dotfiles/.config/hypr"
chk "snapper root config" "sudo snapper list-configs | grep -q ^root"
chk "pcscd.socket enabled (units.tsv)" "systemctl is-enabled pcscd.socket"
chk "the pam_u2f line is NOT written (an ask hook; --yes skips it)" "! grep -q pam_u2f /etc/pam.d/sudo"
bash -lc "dram doctor --brief" 2>&1 | tail -25
exit $fail'
log "checks — $W/checks.log"
vmssh 900 "$W/checks.log" "$CHECKS"
crc=$?
grep -E '^(ok|FAIL) ' "$W/checks.log"
[ "${rc:-1}" = 0 ] || die "bootstrap did not finish cleanly (rc ${rc:-?}) — $W/bootstrap.log"
[ "$crc" -eq 0 ] || die "checks failed — $W/checks.log"
log "T2b passed"

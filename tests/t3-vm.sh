#!/usr/bin/env bash
# usage: t3-vm.sh
#
# Test tiers T2-SB and T3 on the Mac (tests/README.md):
# boots a COPY of the disk tests/t2-vm.sh installed, with the Secure Boot OVMF
# in Setup Mode and a swtpm TPM 2.0, then over ssh: full upgrade, snapper +
# sbctl, system/snapshots-setup.sh, system/secureboot-setup.sh --yes; reboot and
# check Secure Boot is enforcing; install a package (pre/post snapshots + a
# signed boot entry per snapshot); boot that snapshot entry once (read-only,
# overlay); roll back to it with dram-snapshot and check the package is gone.
# Work dir ~/vm-bench/t3; the T2 disk is never modified.
#
#   -h, --help    this text
#
# exit: 0 every check passed · 1 a stage failed · 2 bad usage
# see: decisions/0011-disk-boot-secure-boot-snapshots.md

case "${1:-}" in
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

set -uo pipefail
W="$HOME/vm-bench/t3"
T2="$HOME/vm-bench/t2/disk.qcow2"
FW=/opt/homebrew/share/qemu
mkdir -p "$W/tpm"
die() {
  echo "t3: FAIL — $*" >&2
  pkill -f "$W/disk.qcow2" 2>/dev/null
  pkill -f "$W/swtpm.sock" 2>/dev/null
  exit 1
}
log() { echo "t3: $(date +%T) $*"; }
[ -f "$T2" ] || die "no T2 disk — run tests/t2-vm.sh first"
command -v swtpm >/dev/null || die "swtpm missing (brew install swtpm)"

log "copy of the T2 disk, Secure Boot firmware in Setup Mode, swtpm"
qemu-img create -q -f qcow2 -b "$T2" -F qcow2 "$W/disk.qcow2" || die "overlay"
cp "$FW/edk2-i386-vars.fd" "$W/vars.fd"
rm -rf "$W/tpm" && mkdir -p "$W/tpm"

N=0
boot() { # boot <tag>: start the VM, wait for a login prompt on the serial console
  N=$((N + 1))
  local logf="$W/boot-$N-$1.log"
  # swtpm exits when the VM disconnects at poweroff: one per boot, same state dir
  pkill -f "$W/swtpm.sock" 2>/dev/null
  rm -f "$W/swtpm.sock"
  swtpm socket --tpm2 --tpmstate "dir=$W/tpm" --ctrl "type=unixio,path=$W/swtpm.sock" --daemon || die "swtpm"
  qemu-system-x86_64 -machine q35,smm=on -cpu max -smp 4 -m 4096 -accel "tcg,thread=multi" \
    -global driver=cfi.pflash01,property=secure,value=on \
    -drive "if=pflash,format=raw,readonly=on,file=$FW/edk2-x86_64-secure-code.fd" \
    -drive "if=pflash,format=raw,file=$W/vars.fd" \
    -drive "file=$W/disk.qcow2,if=none,id=d0" -device "virtio-blk-pci,drive=d0,serial=VMTEST1" \
    -chardev "socket,id=chrtpm,path=$W/swtpm.sock" -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0 \
    -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2223-:22 -device virtio-net-pci,netdev=n0 \
    -display none -no-reboot -serial "file:$logf" &
  VM=$!
  for _ in $(seq 360); do
    grep -q 'login:' "$logf" 2>/dev/null && break
    kill -0 "$VM" 2>/dev/null || die "VM stopped while booting ($logf)"
    sleep 5
  done
  grep -q 'login:' "$logf" || die "no login prompt within 30 min ($logf)"
  # the login prompt can come before sshd answers: retry a no-op until it does
  for _ in $(seq 30); do
    vm 30 "true" >/dev/null 2>&1 && break
    sleep 5
  done
  log "booted ($1)"
}
# vm <timeout> <cmd>: run cmd as pj over ssh; sudo prompts get the test password
vm() {
  expect -c "
    set timeout $1
    spawn ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p 2223 pj@127.0.0.1 {$2}
    expect {
      -re {assword( for pj)?:} { send \"test\r\"; exp_continue }
      timeout { puts \"\n>>> TIMEOUT\"; exit 124 }
      eof
    }
    catch wait r; exit [lindex \$r 3]
  "
}
halt() { # halt <reboot|poweroff>
  vm 60 "sudo systemctl $1" >/dev/null 2>&1
  for _ in $(seq 60); do
    kill -0 "$VM" 2>/dev/null || break
    sleep 2
  done
  kill "$VM" 2>/dev/null
  wait "$VM" 2>/dev/null
}
check() { # check <name> <cmd>
  if vm 120 "$2" >"$W/check.out" 2>&1; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    sed 's/^/     /' "$W/check.out" | tail -5
    FAILS=$((FAILS + 1))
  fi
}
FAILS=0

# the T2 disk carries the repo as it was at install time: serve the current tree
mkdir -p "$W/www"
COPYFILE_DISABLE=1 tar --no-xattrs --no-mac-metadata -C "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" -cf "$W/www/dotfiles.tar" . || die "tar"
(cd "$W/www" && exec python3 -m http.server 8001 --bind 127.0.0.1 >"$W/http.log" 2>&1) &
HTTP=$!
trap 'kill $HTTP 2>/dev/null' EXIT

boot setup-mode
vm 300 "rm -rf ~/git/dotfiles && mkdir -p ~/git/dotfiles && curl -fsS http://10.0.2.2:8001/dotfiles.tar | tar -x -C ~/git/dotfiles && test -f ~/git/dotfiles/system/snapshots-setup.sh" || die "repo refresh"
vm 3600 "sudo pacman -Syu --noconfirm snapper sbctl arch-install-scripts" | tail -3 || die "pacman"
vm 900 "sudo bash ~/git/dotfiles/system/snapshots-setup.sh" | tail -5 || die "snapshots-setup"
vm 900 "sudo bash ~/git/dotfiles/system/secureboot-setup.sh --yes" | tail -8 || die "secureboot-setup"
check "keys enrolled (sbctl: not in setup mode)" "sudo sbctl status | grep -qi 'Setup Mode:.*Disabled'"
halt poweroff

boot secure-boot
check "Secure Boot enforcing" "bootctl status 2>/dev/null | grep -qiE 'Secure Boot: enabled'"
check "snapper root config" "sudo snapper -c root list >/dev/null"
check "snapper home config" "sudo snapper -c home list >/dev/null"
vm 1800 "sudo pacman -S --noconfirm nano" | tail -4
# the output also carries expect's spawn line (port, address): take the marked line only
PRE="$(vm 60 "sudo snapper -c root --csvout list --columns number,type,description | awk -F, '\$2==\"pre\" && \$3 ~ /nano/ {print \"PRE=\" \$1}' | tail -1" | tr -d '\r' | sed -n 's/^PRE=\([0-9][0-9]*\)$/\1/p' | tail -1)"
[ -n "$PRE" ] || die "no pre snapshot for the nano install"
log "pre snapshot of the nano install: $PRE"
check "boot entry for snapshot $PRE" "sudo test -f /efi/EFI/Linux/arch-snap-$PRE.efi"
check "snapshot entry is signed" "sudo sbctl verify 2>&1 | grep 'arch-snap-$PRE' | grep -q 'is signed'"
check "nano installed" "command -v nano"
vm 60 "sudo bootctl set-oneshot arch-snap-$PRE.efi"
halt reboot

boot snapshot-entry
check "booted the snapshot read-only with an overlay" "grep -q 'subvol=@snapshots/$PRE/snapshot' /proc/cmdline && grep -q systemd.volatile=overlay /proc/cmdline"
check "nano absent in the snapshot" "! command -v nano"
halt reboot

boot after-snapshot
vm 600 "sudo /usr/local/lib/dram/dram-snapshot rollback $PRE" | tail -6 || die "rollback"
halt reboot

boot rolled-back
check "root is @ again" "findmnt -no OPTIONS / | grep -qE 'subvol=/@(,|\$)'"
check "nano gone after rollback" "! command -v nano"
check "old root kept as @.broken-*" "sudo mount -o subvolid=5 \$(findmnt -no SOURCE / | sed 's/\[.*//') /mnt && ls /mnt | grep -q '^@.broken-'; r=\$?; sudo umount /mnt; exit \$r"
check "Secure Boot still enforcing" "bootctl status 2>/dev/null | grep -qiE 'Secure Boot: enabled'"
halt poweroff
pkill -f "$W/swtpm.sock" 2>/dev/null

[ "$FAILS" -eq 0 ] || die "$FAILS check(s) failed"
log "T2-SB + T3 passed"

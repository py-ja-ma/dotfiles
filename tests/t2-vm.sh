#!/usr/bin/env bash
# usage: t2-vm.sh [--keep] [--boot-only] [--bench] [--roles LIST] [--sys-gib N]
#
# Test tier T2 on the Mac (tests/README.md): an unattended
# install into a QEMU x86_64 VM, then a boot of the installed disk with checks
# over ssh. Uses the pinned, verified ISO (install/get-iso.sh), OVMF without
# Secure Boot (tests/t3-vm.sh adds it), TCG emulation (slow: tens of minutes) and a local
# http server that serves tests/vm-auto.sh and a tarball of this repo. Work dir:
# ~/vm-bench/t2 (disk image, firmware vars, logs).
#
#   --keep        keep the disk image afterwards (default: keep too; --clean drops it)
#   --boot-only   skip the install, boot the existing disk and run the checks
#   --bench       the cabin bench preset (decisions/0017): two disks — system + data pool
#                 and a work pool — in ~/vm-bench/t2-bench (the plain T2 disk is untouched)
#   --roles LIST  the new host's roles, comma-separated (default sysadmin; tests/t2-bootstrap.sh
#                 needs desktop)
#   --sys-gib N   the system pool's size (default: the preset's; 12 GiB is too small for
#                 the desktop role plus Nix)
#   -h, --help    this text
#
# exit: 0 installed, booted and every check passed · 1 a stage failed · 2 bad usage
# see: decisions/0010-install-path.md

BOOT_ONLY=0 BENCH=0 ROLES=sysadmin SYS_GIB=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --keep) ;;
    --boot-only) BOOT_ONLY=1 ;;
    --bench) BENCH=1 ;;
    --roles | --sys-gib)
      [ $# -ge 2 ] && [[ $2 =~ ^[a-z0-9,-]+$ ]] || {
        sed -n '2s/^# \{0,1\}//p' "$0" >&2
        exit 2
      }
      [ "$1" = --roles ] && ROLES="$2" || SYS_GIB="$2"
      shift
      ;;
    *)
      sed -n '2s/^# \{0,1\}//p' "$0" >&2
      exit 2
      ;;
  esac
  shift
done

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="$HOME/vm-bench/t2"
[ "$BENCH" = 1 ] && W="$HOME/vm-bench/t2-bench"
FW=/opt/homebrew/share/qemu
# shellcheck source=install/iso.pin
. "$REPO/install/iso.pin"
ISO="$HOME/vm-bench/iso/archlinux-$VERSION-x86_64.iso"
mkdir -p "$W"
die() {
  echo "t2: FAIL — $*" >&2
  exit 1
}
log() { echo "t2: $(date +%T) $*"; }

bash "$REPO/install/get-iso.sh" "$(dirname "$ISO")" >/dev/null || die "ISO not verified"

QEMU=(qemu-system-x86_64 -machine q35 -cpu max -smp 4 -m 4096 -accel "tcg,thread=multi"
  -drive "if=pflash,format=raw,readonly=on,file=$FW/edk2-x86_64-code.fd"
  -drive "if=pflash,format=raw,file=$W/vars.fd"
  -drive "file=$W/disk.qcow2,if=none,id=d0" -device "virtio-blk-pci,drive=d0,serial=VMTEST1"
  -display none -no-reboot)
# the bench's second NVMe (the work pool)
[ "$BENCH" = 1 ] && QEMU+=(-drive "file=$W/work.qcow2,if=none,id=d1" -device "virtio-blk-pci,drive=d1,serial=VMWORK1")
mkdir -p "$W"

if [ "$BOOT_ONLY" = 0 ]; then
  log "fresh disk + firmware vars"
  rm -f "$W/disk.qcow2" "$W/install.log" "$W/boot.log"
  qemu-img create -q -f qcow2 "$W/disk.qcow2" 40G || die "qemu-img"
  [ "$BENCH" = 1 ] && { qemu-img create -q -f qcow2 "$W/work.qcow2" 20G || die "qemu-img (work)"; }
  cp "$FW/edk2-i386-vars.fd" "$W/vars.fd"
  rm -rf "$W/kernel" && mkdir -p "$W/kernel" "$W/www"
  bsdtar -xf "$ISO" -C "$W/kernel" arch/boot/x86_64/vmlinuz-linux arch/boot/x86_64/initramfs-linux.img || die "extract kernel"
  uuid="$(bsdtar -xOf "$ISO" loader/entries/01-archiso-linux.conf | sed -n 's/.*archisosearchuuid=\([^ ]*\).*/\1/p')"
  [ -n "$uuid" ] || die "no archisosearchuuid in the ISO"
  cp "$REPO/tests/vm-auto.sh" "$W/www/vm-auto.sh"
  # the working tree as it is now, .git included (the installed host gets a checkout);
  # without macOS's AppleDouble ._* files, which git reads as broken pack indexes
  COPYFILE_DISABLE=1 tar --no-xattrs --no-mac-metadata -C "$REPO" -cf "$W/www/dotfiles.tar" . || die "tar"
  (cd "$W/www" && exec python3 -m http.server 8000 --bind 127.0.0.1 >"$W/http.log" 2>&1) &
  HTTP=$!
  trap 'kill $HTTP 2>/dev/null' EXIT
  sleep 1
  log "installing (TCG; expect 20-60 min) — tail -f $W/install.log"
  APPEND="archisobasedir=arch archisosearchuuid=$uuid script=http://10.0.2.2:8000/vm-auto.sh console=ttyS0,115200"
  if [ "$BENCH" = 1 ]; then
    # the bench preset at VM scale: a 16 GiB system pool, the serial console for the checks
    APPEND="$APPEND dram.preset=bench dram.sys-gib=16 dram.serial-console=1 dram.work-disk=/dev/disk/by-id/virtio-VMWORK1 dram.wipe-work=VMWORK1"
    APPEND="$APPEND dram.disk=/dev/disk/by-id/virtio-VMTEST1 dram.host=vmtest dram.roles=$ROLES dram.wipe=VMTEST1"
  else
    APPEND="$APPEND dram.preset=vm-test dram.disk=/dev/disk/by-id/virtio-VMTEST1 dram.host=vmtest dram.roles=$ROLES dram.wipe=VMTEST1"
  fi
  [ -n "$SYS_GIB" ] && APPEND="$APPEND dram.sys-gib=$SYS_GIB"
  "${QEMU[@]}" -cdrom "$ISO" -kernel "$W/kernel/arch/boot/x86_64/vmlinuz-linux" \
    -initrd "$W/kernel/arch/boot/x86_64/initramfs-linux.img" -append "$APPEND" \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 -serial "file:$W/install.log" \
    || die "qemu (install) exited non-zero"
  kill "$HTTP" 2>/dev/null
  grep -q '== vm-auto: DONE' "$W/install.log" || die "install did not finish — see $W/install.log"
  log "install finished"
fi

log "booting the installed disk — tail -f $W/boot.log"
rm -f "$W/boot.log" # a stale log would show the old login prompt at once
"${QEMU[@]}" -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22 -device virtio-net-pci,netdev=n0 \
  -serial "file:$W/boot.log" &
VM=$!
for _ in $(seq 360); do
  grep -q 'login:' "$W/boot.log" 2>/dev/null && break
  kill -0 "$VM" 2>/dev/null || die "the VM stopped while booting — see $W/boot.log"
  sleep 5
done
grep -q 'login:' "$W/boot.log" || {
  kill "$VM"
  die "no login prompt within 30 min — see $W/boot.log"
}
log "login prompt reached; checks over ssh"
sleep 20
CHECKS='set -u; fail=0
chk() { if eval "$2" >/dev/null 2>&1; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
chk "hostname is vmtest" "[ \"$(cat /etc/hostname)\" = vmtest ]"
chk "booted via systemd-boot from a UKI" "bootctl status 2>/dev/null | grep -qi \"systemd-boot\""
chk "root is btrfs subvol @" "findmnt -no OPTIONS / | grep -q subvol=/@"
chk "data pool mounted" "findmnt -no SOURCE /data/vm"
if [ -e /etc/dram/install-facts.env ] && grep -q ^PRESET=bench /etc/dram/install-facts.env; then
  chk "bench: /data/games on the data pool (disk 1)" "findmnt -no SOURCE /data/games | grep -q vda3"
  chk "bench: /data/vm on the work pool (disk 2)" "findmnt -no SOURCE /data/vm | grep -q vdb1"
  chk "bench: /data/scratch + /var/lib/containers on the work pool" "findmnt -no SOURCE /data/scratch | grep -q vdb1 && findmnt -no SOURCE /var/lib/containers | grep -q vdb1"
  chk "bench: work pool in the install facts" "grep -qE ^WORK_UUID=.+ /etc/dram/install-facts.env"
  chk "bench: work pool in fstab" "grep -q /data/scratch /etc/fstab"
fi
chk "/data/vm is nodatacow" "lsattr -d /data/vm | cut -c1-20 | grep -q C"
chk "ESP at /efi" "findmnt -no FSTYPE /efi | grep -q vfat"
chk "UKI on the ESP (root-only mount)" "sudo test -f /efi/EFI/Linux/arch-linux.efi"
chk "install facts" "grep -q ^BOOTLOADER=systemd-boot /etc/dram/install-facts.env"
chk "repo checkout" "test -d ~/git/dotfiles/.git"
chk "host file written" "grep -q \"roles = \\[\" ~/git/dotfiles/modules/hosts/vmtest.nix"
chk "networkd online" "systemctl is-active systemd-networkd"
chk "mirrors pinned" "grep -q geo.mirror.pkgbuild.com /etc/pacman.d/mirrorlist"
chk "system state" "systemctl is-system-running | grep -qE \"running|degraded\""
systemctl --failed --no-legend
sync   # the VM is killed next: flush what the first boot wrote (sshd host keys)
exit $fail'
# a one-line `expect { … }` is ONE literal pattern to expect: keep the cases on lines
expect -c "
  set timeout 300
  spawn ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p 2222 pj@127.0.0.1 {$CHECKS}
  expect {
    -re {assword( for [^:]*)?:} { send \"test\r\"; exp_continue }
    timeout { puts \"\n>>> TIMEOUT\"; exit 124 }
    eof
  }
  catch wait r; exit [lindex \$r 3]
" | tee "$W/checks.log"
rc=${PIPESTATUS[0]}
kill "$VM" 2>/dev/null
[ "$rc" -eq 0 ] && grep -q '^ok   system state' "$W/checks.log" && {
  log "T2 passed"
  exit 0
}
die "checks failed (rc $rc) — $W/checks.log"

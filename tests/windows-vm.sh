#!/usr/bin/env bash
# usage: windows-vm.sh --iso PATH [--dir DIR] [--timeout MIN] [--keep] [--dry-run]
#
# Installs Windows 11 in a KVM VM the way cabin gets it (docs/platforms/windows/README.md): UEFI from the
# Secure Boot build of OVMF, a TPM 2.0 (swtpm), the ISO as a SATA CD, and
# install/windows/autounattend.xml with dram-windows\ on a FAT USB stick. Only the answer
# file's windowsPE Setup block (between its dram:pe markers) is swapped, for a generic Pro
# key and the VM's one disk, so the test runs unattended; specialize and oobeSystem run as
# written. The stick is removable, as the real one must be: Setup reads autounattend.xml
# only from removable drives (the iODD's SSD is fixed; 2026-10-11). A vm-test file on the
# stick makes firstlogon.ps1 copy its log there and power
# off; this script then reads the log. It passes when the first logon finished with no
# warning at all. "Press any key to boot from CD" is answered over the QEMU monitor; a screenshot
# every 2 minutes lands in DIR/shots/ (PNG). Runs on cabin: /dev/kvm, the sysadmin role's
# qemu-base, edk2-ovmf, swtpm and mtools, dosfstools from base, python3.
#
#   --iso PATH      the Windows 11 ISO (required)
#   --dir DIR       work directory, writable (default /data/vm/dram-tests/windows)
#   --timeout MIN   give up after MIN minutes (default 120)
#   --keep          keep the VM disk after a pass (it is always kept after a failure)
#   --dry-run       print the VM's answer-file block and the QEMU command; run nothing
#   -h, --help      this text
#
# exit: 0 pass · 1 the install or the first logon failed, or a tool is missing · 2 bad usage
# see: docs/platforms/windows/README.md, install/windows/

ISO="" DIR=/data/vm/dram-tests/windows TIMEOUT=120 KEEP=0 DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --iso)
      ISO="${2:-}"
      shift
      ;;
    --dir)
      DIR="${2:-}"
      shift
      ;;
    --timeout)
      TIMEOUT="${2:-}"
      shift
      ;;
    --keep) KEEP=1 ;;
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
  shift
done
[ -n "$ISO" ] && [ -n "$DIR" ] && [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || {
  sed -n '2s/^# \{0,1\}//p' "$0" >&2
  exit 2
}

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANSWER="$REPO/install/windows/autounattend.xml"
SCRIPT="$REPO/install/windows/dram-windows/firstlogon.ps1"
CODE=/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd
VARS=/usr/share/edk2/x64/OVMF_VARS.4m.fd
say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}

# the answer file with its dram:pe block replaced: a generic Pro key (KMS client keys only
# pick the edition; nothing is activated) and the VM's single disk, wiped
vm_answer() {
  python3 - "$ANSWER" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
block = """<!-- dram:pe-begin (tests/windows-vm.sh: unattended) -->
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <UserData>
        <ProductKey>
          <Key>VK7JG-NPHTM-C97JM-9MPGT-3V66T</Key>
          <WillShowUI>Never</WillShowUI>
        </ProductKey>
        <AcceptEula>true</AcceptEula>
      </UserData>
      <DiskConfiguration>
        <Disk wcm:action="add">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <CreatePartition wcm:action="add"><Order>1</Order><Type>EFI</Type><Size>300</Size></CreatePartition>
            <CreatePartition wcm:action="add"><Order>2</Order><Type>MSR</Type><Size>16</Size></CreatePartition>
            <CreatePartition wcm:action="add"><Order>3</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Format>FAT32</Format><Label>System</Label></ModifyPartition>
            <ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>2</PartitionID></ModifyPartition>
            <ModifyPartition wcm:action="add"><Order>3</Order><PartitionID>3</PartitionID><Format>NTFS</Format><Label>Windows</Label><Letter>C</Letter></ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>
      <ImageInstall>
        <OSImage>
          <InstallTo><DiskID>0</DiskID><PartitionID>3</PartitionID></InstallTo>
        </OSImage>
      </ImageInstall>
    </component>
    <!-- dram:pe-end -->"""
out, n = re.subn(r"<!-- dram:pe-begin -->.*?<!-- dram:pe-end -->", lambda m: block, s, flags=re.S)
if n != 1:
    sys.exit("autounattend.xml: no dram:pe markers")
sys.stdout.write(out)
PY
}

# shellcheck disable=SC2054 # QEMU options are comma-separated
QEMU=(qemu-system-x86_64 -name dram-windows-test
  -machine q35,smm=on,accel=kvm -cpu host,hv_relaxed,hv_spinlocks=0x1fff,hv_vapic,hv_time -smp 8 -m 8192
  -global driver=cfi.pflash01,property=secure,value=on
  -drive "if=pflash,format=raw,unit=0,file=$CODE,readonly=on"
  -drive "if=pflash,format=raw,unit=1,file=$DIR/vars.fd"
  -chardev "socket,id=chrtpm,path=$DIR/swtpm.sock" -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0
  -drive "file=$DIR/disk.qcow2,if=none,id=d0,format=qcow2,cache=unsafe" -device ide-hd,drive=d0,bus=ide.0,bootindex=1
  -drive "file=$ISO,if=none,id=cd0,media=cdrom,readonly=on" -device ide-cd,drive=cd0,bus=ide.1,bootindex=0
  -device qemu-xhci,id=xhci -drive "file=$DIR/usb.img,if=none,id=u0,format=raw" -device usb-storage,bus=xhci.0,drive=u0,removable=on
  -netdev user,id=n0 -device e1000e,netdev=n0
  -vga std -display none -monitor "unix:$DIR/monitor.sock,server,nowait"
  -daemonize -pidfile "$DIR/qemu.pid")

if [ "$DRY" -eq 1 ]; then
  say "the VM's windowsPE Setup block (the rest of $ANSWER as written)"
  vm_answer | sed -n '/dram:pe-begin/,/dram:pe-end/p'
  say "the VM"
  printf '%q ' "${QEMU[@]}"
  echo
  exit 0
fi

say "preflight"
[ -r /dev/kvm ] && [ -w /dev/kvm ] || die "/dev/kvm is not usable (KVM off in the firmware?)"
for t in qemu-system-x86_64 qemu-img swtpm mkfs.fat mcopy mmd python3; do
  command -v "$t" >/dev/null || die "$t missing (the sysadmin role's VM kit: dram apply)"
done
for f in "$CODE" "$VARS" "$ANSWER" "$SCRIPT" "$ISO"; do [ -r "$f" ] || die "cannot read $f"; done
mkdir -p "$DIR" 2>/dev/null && [ -w "$DIR" ] || die "$DIR is not writable: sudo install -d -o $(id -un) -g $(id -gn) $DIR"
[ ! -s "$DIR/qemu.pid" ] || ! kill -0 "$(cat "$DIR/qemu.pid")" 2>/dev/null || die "a test VM is already running (pid $(cat "$DIR/qemu.pid"))"
ok "KVM, the VM kit, the ISO ($(du -h "$ISO" | cut -f1)) and $DIR"

say "the answer-file stick, the disk, the firmware variables and the TPM"
rm -rf "$DIR/shots" "$DIR/tpm" "$DIR/usb.img" "$DIR/disk.qcow2" "$DIR/vars.fd" "$DIR/firstlogon.log" "$DIR"/*.sock "$DIR"/*.pid
mkdir -p "$DIR/shots" "$DIR/tpm"
vm_answer >"$DIR/autounattend.xml" || die "could not build the VM's answer file"
mkfs.fat -C -n DRAMWIN "$DIR/usb.img" 65536 >/dev/null || die "mkfs.fat failed"
: >"$DIR/vm-test"
if ! { mcopy -i "$DIR/usb.img" "$DIR/autounattend.xml" ::/autounattend.xml \
  && mmd -i "$DIR/usb.img" ::/dram-windows \
  && mcopy -i "$DIR/usb.img" "$SCRIPT" "$DIR/vm-test" ::/dram-windows/; }; then
  die "could not fill the stick"
fi
qemu-img create -q -f qcow2 "$DIR/disk.qcow2" 80G || die "qemu-img failed"
cp "$VARS" "$DIR/vars.fd" || die "no OVMF variables"
swtpm socket --tpm2 --tpmstate "dir=$DIR/tpm" --ctrl "type=unixio,path=$DIR/swtpm.sock" \
  --log "file=$DIR/swtpm.log" --pid "file=$DIR/swtpm.pid" --terminate --daemon || die "swtpm did not start"
ok "stick (autounattend.xml, dram-windows\\firstlogon.ps1, vm-test), 80 GB disk, OVMF Secure Boot, TPM 2.0"

# one HMP command over the monitor socket
mon() {
  python3 - "$DIR/monitor.sock" "$1" <<'PY'
import socket, sys, time
s = socket.socket(socket.AF_UNIX)
s.settimeout(3)
s.connect(sys.argv[1])
try:
    s.recv(4096)
except OSError:
    pass
s.sendall((sys.argv[2] + "\n").encode())
time.sleep(0.4)
try:
    s.recv(65536)
except OSError:
    pass
s.close()
PY
}
# screendump writes PPM; the PNG is what an image viewer (and a session) can open
shot() {
  local n
  n="$DIR/shots/$(date +%H%M%S)"
  mon "screendump $n.ppm" 2>/dev/null || return 0
  sleep 1
  [ -s "$n.ppm" ] || return 0
  python3 - "$n.ppm" "$n.png" <<'PY' && rm -f "$n.ppm"
import struct, sys, zlib
d = open(sys.argv[1], "rb").read()
f, i = [], 0
while len(f) < 4:
    while d[i:i + 1].isspace():
        i += 1
    j = i
    while not d[j:j + 1].isspace():
        j += 1
    f.append(d[i:j])
    i = j
i += 1
w, h = int(f[1]), int(f[2])
px = d[i:i + w * h * 3]
raw = b"".join(b"\0" + px[y * w * 3:(y + 1) * w * 3] for y in range(h))
c = lambda t, b: struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b) & 0xFFFFFFFF)
open(sys.argv[2], "wb").write(b"\x89PNG\r\n\x1a\n" + c(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                              + c(b"IDAT", zlib.compress(raw, 6)) + c(b"IEND", b""))
PY
}

say "boot (Setup, its reboots, OOBE, the first logon; up to $TIMEOUT minutes)"
"${QEMU[@]}" || die "QEMU did not start"
# "Press any key to boot from CD or DVD" shows 2-5 s after start, for 5 s; under KVM Setup
# itself is up within ~15 s, and an Enter there presses its Cancel button (first run,
# 2026-10-11) - so only the first 10 seconds get keys
for _ in $(seq 1 10); do
  sleep 1
  mon "sendkey ret" 2>/dev/null
done
shot
start=$(date +%s) last=$start
while kill -0 "$(cat "$DIR/qemu.pid" 2>/dev/null)" 2>/dev/null; do
  now=$(date +%s)
  if [ $((now - start)) -ge $((TIMEOUT * 60)) ]; then
    shot
    kill "$(cat "$DIR/qemu.pid")" 2>/dev/null
    die "no power-off after $TIMEOUT minutes: see $DIR/shots/ (the newest is the last screen)"
  fi
  if [ $((now - last)) -ge 120 ]; then
    shot
    last=$now
    printf '  %3d min\n' $(((now - start) / 60))
  fi
  sleep 10
done
ok "the VM powered off after $((($(date +%s) - start) / 60)) minutes"

say "the first logon's log"
mcopy -n -i "$DIR/usb.img" ::/dram-windows/firstlogon.log "$DIR/firstlogon.log" 2>/dev/null \
  || die "no log on the stick: the first logon never finished (see $DIR/shots/)"
sed 's/^/  /' "$DIR/firstlogon.log"
grep -q '== done:' "$DIR/firstlogon.log" || die "the log stops before its end"
bad="$(grep -F '[!]' "$DIR/firstlogon.log" || true)"
[ -z "$bad" ] || die "first logon warnings: $bad"
if [ "$KEEP" -eq 0 ]; then rm -f "$DIR/disk.qcow2" "$DIR/vars.fd"; else ok "VM disk kept: $DIR/disk.qcow2"; fi
ok "Windows installed from $ISO with the answer file, and its first logon passed"

#!/usr/bin/env bash
# usage: vm-auto.sh
#
# Runs INSIDE the Arch ISO under QEMU (tests/t2-vm.sh boots the ISO with
# script=http://10.0.2.2:8000/vm-auto.sh). Fetches this repo as a tarball from
# the Mac's http server, then runs install/arch-install.sh unattended with the
# vm-test preset; every line goes to the serial console, which t2-vm.sh logs.
# The arch-install.sh options come from the kernel command line (dram.*).
#
#   -h, --help    this text
#
# exit: 0 installed (and powered off) · 1 a step failed · 2 bad usage
# see: tests/t2-vm.sh

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
exec > >(tee /dev/ttyS0) 2>&1
echo "== vm-auto: fetching the repo"
mkdir -p /root/dotfiles
curl -fsS --retry 5 http://10.0.2.2:8000/dotfiles.tar | tar -x -C /root/dotfiles || {
  echo "== vm-auto: FAILED to fetch the repo"
  exit 1
}
printf 'test\n' >/root/pw
echo "== vm-auto: arch-install.sh"
if bash /root/dotfiles/install/arch-install.sh --password-file /root/pw --poweroff; then
  echo "== vm-auto: DONE"
else
  echo "== vm-auto: INSTALL FAILED rc=$?"
  sleep 5
  systemctl poweroff
fi

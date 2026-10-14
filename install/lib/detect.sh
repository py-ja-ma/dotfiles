#!/usr/bin/env bash
# Hardware detection helpers. Sourced by bootstrap.sh; safe to source directly
# for inspection:  bash -c '. install/lib/detect.sh && detect_report'

detect_cpu() { # -> amd | intel | unknown
  local v
  v=$(awk -F': ' '/^vendor_id/{print $2; exit}' /proc/cpuinfo 2>/dev/null)
  case "$v" in
    AuthenticAMD) echo amd ;;
    GenuineIntel) echo intel ;;
    *) echo unknown ;;
  esac
}

detect_gpus() { # -> space-separated list of: nvidia intel amd
  # Match PCI VENDOR IDs on display-class devices (class 03xx), never names:
  # "Intel" also matches audio/USB controllers, and an AMD CPU box with an NVIDIA
  # card has "Advanced Micro Devices" all over lspci. 10de=NVIDIA 1002=AMD 8086=Intel.
  local out=""
  while read -r line; do
    case "$line" in
      *'[10de:'*) out="$out nvidia" ;;
      *'[1002:'*) out="$out amd" ;;
      *'[8086:'*) out="$out intel" ;;
    esac
  done < <(lspci -nn 2>/dev/null | grep -E '\[03[0-9a-f]{2}\]')
  echo "$out" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ' | sed 's/ $//'
}

detect_platform() { # -> wsl | metal
  # Arch inside WSL 2 (decisions/0021): the interop markers WSL itself creates, then
  # systemd's own verdict (it classes WSL as a container), then Microsoft's kernel string
  # (6.x-microsoft-standard-WSL2). Anything else runs on its own hardware (or a VM that
  # boots its own kernel, which is metal here: it has a boot chain of its own).
  # DRAM_FORM=wsl (or laptop|desktop) forces the answer, for a test or a wrong guess; every
  # reader (dram, bootstrap, the system/ hooks) goes through here, so they agree.
  case "${DRAM_FORM:-}" in
    wsl)
      echo wsl
      return
      ;;
    laptop | desktop)
      echo metal
      return
      ;;
  esac
  if [ -n "${WSL_DISTRO_NAME:-}" ] || [ -e /proc/sys/fs/binfmt_misc/WSLInterop ] \
    || [ -e /proc/sys/fs/binfmt_misc/WSLInterop-late ] || [ -d /run/WSL ]; then
    echo wsl
    return
  fi
  if [ "$(systemd-detect-virt -c 2>/dev/null)" = wsl ] \
    || grep -qi 'microsoft-standard-wsl' /proc/sys/kernel/osrelease 2>/dev/null; then
    echo wsl
    return
  fi
  echo metal
}

detect_form_factor() { # -> laptop | desktop | wsl
  # WSL first: the VM has no battery or chassis of its own, and `wsl` is what
  # host_package_files (install/lib/roles.sh) reads as "no hardware lists".
  [ "$(detect_platform)" = wsl ] && {
    echo wsl
    return
  }
  # A battery is the most reliable signal; chassis type is the fallback.
  local b
  for b in /sys/class/power_supply/BAT*; do
    [ -e "$b" ] && {
      echo laptop
      return
    }
  done
  case "$(cat /sys/devices/virtual/dmi/id/chassis_type 2>/dev/null)" in
    8 | 9 | 10 | 11 | 14 | 30 | 31 | 32) echo laptop ;;
    *) echo desktop ;;
  esac
}

detect_nvidia_open_ok() { # -> yes | no
  # nvidia-open requires Turing (TU1xx) or newer. Older cards need nvidia-dkms.
  # Heuristic on the marketing name; conservative — says "no" when unsure.
  local n
  n=$(lspci 2>/dev/null | grep -i 'nvidia' | head -1)
  case "$n" in
    *GA1* | *GA2* | *AD1* | *TU1* | *GB2* | *GH1*) echo yes ;;
    *) echo no ;;
  esac
}

detect_boot_mode() { [ -d /sys/firmware/efi ] && echo uefi || echo bios; }

detect_root_spec() { # what the bootloader needs for root=
  local src uuid
  src=$(findmnt -no SOURCE /)
  case "$src" in
    /dev/mapper/* | /dev/*Vg* | /dev/*vg*) echo "$src" ;; # LVM: use the device path
    *)
      uuid=$(findmnt -no UUID /)
      echo "UUID=$uuid"
      ;; # plain: use UUID
  esac
}

detect_report() {
  printf '  Platform ............ %s\n' "$(detect_platform)"
  printf '  CPU vendor .......... %s\n' "$(detect_cpu)"
  printf '  GPU(s) .............. %s\n' "$(detect_gpus)"
  printf '  nvidia-open usable .. %s\n' "$(detect_nvidia_open_ok)"
  printf '  Form factor ......... %s\n' "$(detect_form_factor)"
  printf '  Boot mode ........... %s\n' "$(detect_boot_mode)"
  printf '  root= spec .......... %s\n' "$(detect_root_spec)"
  printf '  Hostname ............ %s\n' "$(cat /etc/hostname 2>/dev/null)"
  printf '  Kernels installed ... %s\n' "$(ls /usr/lib/modules 2>/dev/null | tr '\n' ' ')"
}

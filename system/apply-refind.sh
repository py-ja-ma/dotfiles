#!/usr/bin/env bash
# usage: apply-refind.sh [--theme letterpress|catppuccin] [--dry-run]
#
# rEFInd as the themed boot menu in front of the UKI chain (docs/platforms/arch/boot-chain.md;
# decisions/0011, 2026-10-12): firmware -> rEFInd -> a signed UKI, Windows or systemd-boot
# -> Plymouth -> ly. Copies /usr/share/refind/refind_x64.efi to <ESP>/EFI/refind/, signed
# by sbctl when it has keys (tracked, so it is signed again on every refind upgrade by
# /usr/local/lib/dram/refind-update through /etc/pacman.d/hooks/99-refind.hook, both
# installed here); system/refind-<theme>/ as the theme; a refind.conf with one entry per
# boot target on the ESP: Arch Linux, Arch Linux LTS, Windows, and "Snapshots & recovery"
# (systemd-boot, whose menu keeps the fallback and snapshot UKIs). Windows on its own ESP
# (label WIN-ESP) is started through its firmware entry (firmware_bootnum), never loaded by
# rEFInd; without one, the tile loads /EFI/Microsoft/Boot/bootmgfw.efi from this ESP. Puts the NVRAM entry
# "rEFInd" first in BootOrder; systemd-boot's entry stays behind it, so the firmware
# falls back to systemd-boot if rEFInd ever fails. The MSI firmware reshuffles BootOrder
# when drives come or go: dram-refind-first.service (installed and enabled here) puts
# rEFInd first again at every boot, moving nothing else. Write-on-change with one .bak-<stamp>.
# Run by system/system-dram.sh (a `dram apply` hook). Root, unless --dry-run.
#
#   --theme NAME   letterpress (default) | catppuccin (the old theme)
#   --dry-run      print what would change; touch nothing
#   -h, --help     this text
#
# exit: 0 ok · 1 not root, no UKIs on the ESP, Secure Boot on without sbctl keys, or a
#       step failed · 2 bad usage
# see: docs/platforms/arch/boot-chain.md

THEME=letterpress DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --theme)
      THEME="${2:-}"
      shift
      ;;
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
case "$THEME" in
  letterpress) THEME_CONF=theme.conf ICONS=icons ;;
  catppuccin) THEME_CONF=mocha.conf ICONS=assets/mocha/icons ;;
  *)
    sed -n '2s/^# \{0,1\}//p' "$0" >&2
    exit 2
    ;;
esac

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC=/usr/share/refind/refind_x64.efi
HOOK=/etc/pacman.d/hooks/99-refind.hook
HELPER=/usr/local/lib/dram/refind-update
STAMP="$(date +%Y%m%d-%H%M%S)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}
# put <file> <new content file> [mode]: write on change, one backup; --dry-run shows the diff
put() {
  if [ -f "$1" ] && cmp -s "$1" "$2"; then
    ok "$1 unchanged"
    return 0
  fi
  if [ "$DRY" = 1 ]; then
    echo "  [dry-run] $1 would become:"
    if [ -f "$1" ]; then diff -u "$1" "$2" | sed -n '3,$p' | sed 's/^/    /'; else sed 's/^/    /' "$2"; fi
    return 0
  fi
  [ -f "$1" ] && cp -p "$1" "$1.bak-$STAMP"
  install -D -m "${3:-644}" "$2" "$1" || die "could not write $1"
  ok "$1 written$([ -f "$1.bak-$STAMP" ] && echo " (previous: $1.bak-$STAMP)")"
}

[ "$DRY" = 1 ] || [ "$(id -u)" -eq 0 ] || die "run with sudo (or --dry-run)"
[ -d "$DIR/refind-$THEME" ] || die "theme source missing: $DIR/refind-$THEME"
ESP="$(bootctl --print-esp-path 2>/dev/null)"
ESP="${ESP:-/efi}"
[ -f "$ESP/EFI/Linux/arch-linux.efi" ] || die "no $ESP/EFI/Linux/arch-linux.efi: not a UKI host (install/arch-install.sh)"
[ -f "$SRC" ] || die "$SRC missing: the refind package (packages/roles/desktop.txt; dram apply)"
sb="$(od -An -t u1 /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c 2>/dev/null | awk '{print $NF}')"
keys=0
command -v sbctl >/dev/null && sbctl status 2>/dev/null | grep -c 'Installed:.*✓' >/dev/null && keys=1
[ "${sb:-0}" != 1 ] || [ "$keys" = 1 ] || die "Secure Boot is on but sbctl has no keys: an unsigned rEFInd would not start (system/secureboot-setup.sh)"

say "rEFInd -> $ESP/EFI/refind/refind_x64.efi$([ "$keys" = 1 ] && echo ', signed')"
DEST="$ESP/EFI/refind/refind_x64.efi"
if [ "$keys" = 1 ]; then
  if [ -f "$DEST" ] && [ "$DEST" -nt "$SRC" ] && sbctl verify "$DEST" 2>/dev/null | grep -c 'is signed' >/dev/null; then
    ok "signed and current"
  elif [ "$DRY" = 1 ]; then
    echo "  [dry-run] sbctl sign -s -o $DEST $SRC"
  else
    if ! { install -d "$ESP/EFI/refind" && sbctl sign -s -o "$DEST" "$SRC" >/dev/null; }; then die "sbctl could not sign rEFInd"; fi
    ok "signed with the db key and tracked by sbctl"
  fi
else
  cp "$SRC" "$TMP/refind_x64.efi"
  put "$DEST" "$TMP/refind_x64.efi"
fi

say "theme $THEME"
TD="$ESP/EFI/refind/themes/$THEME"
if [ -d "$TD" ] && diff -rq "$DIR/refind-$THEME" "$TD" >/dev/null 2>&1; then ok "$TD up to date"; elif [ "$DRY" = 1 ]; then
  echo "  [dry-run] copy $DIR/refind-$THEME -> $TD"
else
  if ! { rm -rf "$TD" && install -d "$TD" && cp -r "$DIR/refind-$THEME/." "$TD/"; }; then die "could not copy the theme"; fi
  ok "theme copied"
fi

say "refind.conf"
ICON="/EFI/refind/themes/$THEME/$ICONS"
entry() { # <name> <icon> <loader>
  [ -f "$ESP$3" ] || return 0
  printf '\nmenuentry "%s" {\n    icon   %s/%s\n    loader %s\n}\n' "$1" "$ICON" "$2" "$3"
}
# Windows with its own ESP (FAT label WIN-ESP; install/windows/dram-windows/own-esp.ps1): its
# tile asks the firmware to start Windows' own NVRAM entry (BootNext + reboot), so rEFInd is
# never in Windows' measured boot path (BitLocker's PCRs stay put when rEFInd updates;
# decisions/log.md#d66). The entry is the "Windows Boot Manager" whose HD() names
# WIN-ESP's PARTUUID; bcdboot can recreate it under a new number, which `dram doctor` catches.
windows_bootnum() {
  local pu
  local dev
  dev="$(readlink -f /dev/disk/by-label/WIN-ESP 2>/dev/null)"
  [ -b "$dev" ] || return 0
  pu="$(lsblk -dno PARTUUID "$dev" 2>/dev/null)"
  [ -n "$pu" ] || return 0
  efibootmgr -v 2>/dev/null | awk -v pu="$pu" 'tolower($0) ~ tolower(pu) && tolower($0) ~ /\\efi\\microsoft\\boot\\bootmgfw\.efi/ { print substr($1, 5, 4); exit }'
}
windows_entry() {
  local n
  n="$(windows_bootnum)"
  if [ -n "$n" ]; then
    printf '\nmenuentry "%s" {\n    icon   %s/%s\n    firmware_bootnum %s\n}\n' "Windows" "$ICON" "os_win.png" "$n"
  else
    entry "Windows" os_win.png /EFI/Microsoft/Boot/bootmgfw.efi
  fi
}
{
  cat <<EOF
# refind.conf - written by dotfiles/system/apply-refind.sh; do not edit by hand, re-run
#   sudo bash ~/git/dotfiles/system/apply-refind.sh
# The UKIs carry their own (signed) command line, so the entries pass no options.

timeout 3
use_nvram false

# These entries only: the fallback, snapshot and duplicate loaders stay behind
# "Snapshots & recovery" (systemd-boot's own menu).
scanfor manual
default_selection "Arch Linux"

include themes/$THEME/$THEME_CONF
EOF
  entry "Arch Linux" os_arch.png /EFI/Linux/arch-linux.efi
  entry "Arch Linux LTS" os_arch.png /EFI/Linux/arch-linux-lts.efi
  windows_entry
  entry "Snapshots & recovery" os_systemd.png /EFI/systemd/systemd-bootx64.efi
} >"$TMP/refind.conf"
put "$ESP/EFI/refind/refind.conf" "$TMP/refind.conf"
grep '^menuentry' "$TMP/refind.conf" | sed 's/^menuentry "\(.*\)" {/    entry: \1/'

say "the pacman hook that keeps the ESP copy current"
cat >"$TMP/refind-update" <<'EOF'
#!/bin/sh
# /usr/local/lib/dram/refind-update - written by dotfiles/system/apply-refind.sh, run by
# /etc/pacman.d/hooks/99-refind.hook after every refind upgrade: the ESP copy of rEFInd
# is sbctl's signed output of /usr/share/refind/refind_x64.efi when sbctl has keys.
esp="$(bootctl --print-esp-path 2>/dev/null)"
dest="${esp:-/efi}/EFI/refind/refind_x64.efi"
[ -f "$dest" ] || exit 0
if command -v sbctl >/dev/null 2>&1 && sbctl status 2>/dev/null | grep -c 'Installed:.*✓' >/dev/null; then
  exec sbctl sign -s -o "$dest" /usr/share/refind/refind_x64.efi
fi
exec install -m 644 /usr/share/refind/refind_x64.efi "$dest"
EOF
put "$HELPER" "$TMP/refind-update" 755
put "$HOOK" "$DIR/99-refind.hook"

say "rEFInd first after every boot (the firmware reshuffles BootOrder)"
cat >"$TMP/refind-first" <<'EOF'
#!/bin/sh
# /usr/local/lib/dram/refind-first - written by dotfiles/system/apply-refind.sh, run at every
# boot by dram-refind-first.service: the MSI firmware reshuffles BootOrder whenever drives
# come or go; this puts the rEFInd entry first again. Nothing else moves, nothing is removed.
n="$(efibootmgr -v 2>/dev/null | awk 'tolower($0) ~ /\\efi\\refind\\refind_x64\.efi/ { print substr($1, 5, 4); exit }')"
[ -n "$n" ] || exit 0
order="$(efibootmgr | sed -n 's/^BootOrder: //p')"
[ "${order%%,*}" = "$n" ] && exit 0
new="$n,$(printf '%s\n' "$order" | tr ',' '\n' | grep -v -x "$n" | paste -sd, -)"
efibootmgr -q -o "$new" && echo "BootOrder was $order; rEFInd (Boot$n) first again: $new"
EOF
cat >"$TMP/dram-refind-first.service" <<'EOF'
# written by dotfiles/system/apply-refind.sh
[Unit]
Description=dram: rEFInd first in the firmware boot order (the MSI firmware reshuffles it)
ConditionPathExists=/sys/firmware/efi/efivars
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/lib/dram/refind-first

[Install]
WantedBy=multi-user.target
EOF
put /usr/local/lib/dram/refind-first "$TMP/refind-first" 755
put /etc/systemd/system/dram-refind-first.service "$TMP/dram-refind-first.service"
if systemctl is-enabled -q dram-refind-first.service 2>/dev/null; then ok "dram-refind-first.service enabled"; elif [ "$DRY" = 1 ]; then
  echo "  [dry-run] systemctl enable dram-refind-first.service"
else
  if ! { systemctl daemon-reload && systemctl enable dram-refind-first.service >/dev/null 2>&1; }; then die "could not enable dram-refind-first.service"; fi
  ok "dram-refind-first.service enabled"
fi

say "firmware boot order: rEFInd first"
command -v efibootmgr >/dev/null || die "efibootmgr missing"
num_of() { efibootmgr -v 2>/dev/null | awk 'tolower($0) ~ /\\efi\\refind\\refind_x64\.efi/ { print substr($1, 5, 4); exit }'; }
n="$(num_of)"
if [ -z "$n" ]; then
  part="$(findmnt -no SOURCE "$ESP")"
  disk="/dev/$(lsblk -no PKNAME "$part" 2>/dev/null)"
  pn="$(cat "/sys/class/block/$(basename "$part")/partition" 2>/dev/null)"
  [ -b "$disk" ] && [ -n "$pn" ] || die "cannot tell the ESP's disk and partition ($part)"
  if [ "$DRY" = 1 ]; then printf '  [dry-run] efibootmgr --create --disk %s --part %s --loader %s --label rEFInd\n' "$disk" "$pn" '\EFI\refind\refind_x64.efi'; else
    efibootmgr -q --create --disk "$disk" --part "$pn" --loader '\EFI\refind\refind_x64.efi' --label rEFInd || die "efibootmgr could not add rEFInd"
    n="$(num_of)"
    [ -n "$n" ] || die "the rEFInd entry did not appear"
    ok "NVRAM entry Boot$n rEFInd"
  fi
fi
if [ -n "$n" ]; then
  order="$(efibootmgr | sed -n 's/^BootOrder: //p')"
  if [ "${order%%,*}" = "$n" ]; then ok "BootOrder $order: rEFInd first"; else
    new="$n,$(tr ',' '\n' <<<"$order" | grep -v -x "$n" | paste -sd, -)"
    if [ "$DRY" = 1 ]; then echo "  [dry-run] efibootmgr -o $new (now $order)"; else
      efibootmgr -q -o "$new" || die "efibootmgr could not reorder"
      ok "BootOrder $new: rEFInd first (was $order)"
    fi
  fi
fi
echo "    reboot: rEFInd's menu for 3 s, Arch Linux by default; if it ever fails, the firmware"
echo "    starts systemd-boot instead (F11 -> Linux Boot Manager does the same)"

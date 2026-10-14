#!/usr/bin/env bash
# usage: plymouth-setup.sh [--theme letterpress|catppuccin] [--dry-run]
#
# The boot splash on the UKI chain (docs/platforms/arch/boot-chain.md; decisions/0011): firmware ->
# rEFInd -> a signed UKI -> Plymouth -> ly. Installs system/plymouth-<theme>/ to
# /usr/share/plymouth/themes/ and makes it the default; puts the `plymouth` hook right
# after `systemd` in the mkinitcpio file that sets HOOKS; adds the splash words to
# /etc/kernel/cmdline and writes /etc/kernel/cmdline.fallback without them, which every
# preset's fallback UKI is built from (the safety net stays verbose); then rebuilds the
# UKIs with `mkinitcpio -P` (sbctl's initcpio hook re-signs them) and checks they are
# signed. Early KMS must exist already (install/bootstrap.sh phase 5: the GPU's modules
# in /etc/mkinitcpio.conf.d/10-kms.conf, or the `kms` hook) or the splash shows late.
# Write-on-change with one .bak-<stamp> per file; rebuilds only when something changed.
# Run by system/system-dram.sh (a `dram apply` hook). Root, unless --dry-run.
#
#   --theme NAME   letterpress (default, the house palette) | catppuccin (the old one)
#   --dry-run      print what would change; touch nothing
#   -h, --help     this text
#
# exit: 0 ok · 1 not root, not a UKI host, plymouth missing, or a step failed · 2 bad usage
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
case "$THEME" in letterpress | catppuccin) ;; *)
  sed -n '2s/^# \{0,1\}//p' "$0" >&2
  exit 2
  ;;
esac

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/plymouth-$THEME"
DEST="/usr/share/plymouth/themes/$THEME"
CMDLINE=/etc/kernel/cmdline
FALLBACK=/etc/kernel/cmdline.fallback
SPLASH="quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0"
STAMP="$(date +%Y%m%d-%H%M%S)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CHANGED=0
say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}
# put <file> <new content file>: write on change, one backup; --dry-run shows the diff
put() {
  if [ -f "$1" ] && cmp -s "$1" "$2"; then
    ok "$1 unchanged"
    return 0
  fi
  CHANGED=1
  if [ "$DRY" = 1 ]; then
    echo "  [dry-run] $1 would become:"
    if [ -f "$1" ]; then diff -u "$1" "$2" | sed -n '3,$p' | sed 's/^/    /'; else sed 's/^/    /' "$2"; fi
    return 0
  fi
  [ -f "$1" ] && cp -p "$1" "$1.bak-$STAMP"
  install -m 644 "$2" "$1" || die "could not write $1"
  ok "$1 written$([ -f "$1.bak-$STAMP" ] && echo " (previous: $1.bak-$STAMP)")"
}

[ "$DRY" = 1 ] || [ "$(id -u)" -eq 0 ] || die "run with sudo (or --dry-run)"
[ -d "$SRC" ] || die "theme source missing: $SRC"
presets="$(grep -l '^default_uki=' /etc/mkinitcpio.d/*.preset 2>/dev/null)"
[ -n "$presets" ] || die "no UKI presets in /etc/mkinitcpio.d: not a UKI host (install/arch-install.sh, system/uki-presets.sh)"
[ -f "$CMDLINE" ] || die "$CMDLINE missing: the UKIs have no command line to extend"
command -v plymouth-set-default-theme >/dev/null || die "plymouth is not installed (packages/roles/desktop.txt: dram apply)"

say "theme $THEME -> $DEST"
if [ -d "$DEST" ] && diff -rq "$SRC" "$DEST" >/dev/null 2>&1; then ok "$DEST up to date"; else
  CHANGED=1
  if [ "$DRY" = 1 ]; then echo "  [dry-run] install $(cd "$SRC" && echo *) -> $DEST"; else
    if ! { rm -rf "$DEST" && install -d "$DEST" && install -m 644 "$SRC"/* "$DEST/"; }; then die "could not install the theme"; fi
    ok "theme installed"
  fi
fi

say "initramfs: the plymouth hook, early KMS"
hookfile=""
for f in /etc/mkinitcpio.conf /etc/mkinitcpio.conf.d/*.conf; do
  [ -f "$f" ] && grep -q '^HOOKS=' "$f" && hookfile="$f"
done
[ -n "$hookfile" ] || die "no HOOKS= line in /etc/mkinitcpio.conf or its drop-ins"
# plymouth goes right after systemd (the Arch wiki's one rule for the systemd initramfs)
awk '/^HOOKS=/ && !/[( ]plymouth[ )]/ { sub(/[( ]systemd[ )]/, "& plymouth "); gsub(/  +/, " "); sub(/\( /, "(") } { print }' \
  "$hookfile" >"$TMP/hooks"
grep -q '^HOOKS=.*[( ]plymouth[ )]' "$TMP/hooks" || die "$hookfile: HOOKS has no systemd hook to put plymouth after"
put "$hookfile" "$TMP/hooks"
if cat /etc/mkinitcpio.conf /etc/mkinitcpio.conf.d/*.conf 2>/dev/null | grep -E '^(MODULES|HOOKS)=' | grep -c -E '[( ](nvidia_drm|i915|xe|amdgpu|radeon|kms)[ )]' >/dev/null; then
  ok "early KMS present (a GPU module in MODULES, or the kms hook)"
else
  warn "no early KMS: the splash comes up late or not at all (install/bootstrap.sh --phase 5 writes it)"
fi

say "kernel command lines: the splash for the UKIs, none for the fallback UKIs"
cur="$(tr -s ' \n' ' ' <"$CMDLINE" | sed 's/^ //; s/ $//')"
plain="$cur"
for w in $SPLASH; do plain="$(printf '%s' " $plain " | sed "s/ $w / /g; s/^ //; s/ $//")"; done
want="$plain $SPLASH"
printf '%s\n' "$want" >"$TMP/cmdline"
printf '%s\n' "$plain" >"$TMP/cmdline.fallback"
put "$CMDLINE" "$TMP/cmdline"
put "$FALLBACK" "$TMP/cmdline.fallback"
for p in $presets; do
  grep -q '^fallback_uki=' "$p" || continue
  if grep -q '^fallback_options=' "$p"; then
    awk -v f="$FALLBACK" '/^fallback_options=/ && index($0, "--cmdline") == 0 { sub(/"$/, " --cmdline " f "\"") } { print }' "$p" >"$TMP/preset"
  else
    {
      cat "$p"
      printf 'fallback_options="--cmdline %s"\n' "$FALLBACK"
    } >"$TMP/preset"
  fi
  put "$p" "$TMP/preset"
done

say "default theme"
cur_theme="$(plymouth-set-default-theme 2>/dev/null || echo '?')"
if [ "$cur_theme" = "$THEME" ]; then ok "default theme: $THEME"; else
  CHANGED=1
  if [ "$DRY" = 1 ]; then echo "  [dry-run] plymouth-set-default-theme $THEME (now: $cur_theme)"; else
    plymouth-set-default-theme "$THEME" || die "plymouth-set-default-theme failed"
    ok "default theme: $THEME (was $cur_theme)"
  fi
fi

say "UKIs"
if [ "$CHANGED" = 0 ]; then
  ok "nothing changed: no rebuild"
elif [ "$DRY" = 1 ]; then
  echo "  [dry-run] mkinitcpio -P (sbctl's initcpio hook signs the new UKIs)"
else
  mkinitcpio -P || die "mkinitcpio -P failed: run it again and read its errors before rebooting (docs/platforms/arch/boot-chain.md#recovery)"
  if command -v sbctl >/dev/null && sbctl status 2>/dev/null | grep -c 'Installed:.*✓' >/dev/null; then
    bad="$(sbctl verify 2>/dev/null | grep -F '/EFI/Linux/' | grep -v -F 'is signed' || true)"
    [ -z "$bad" ] || die "UKIs left unsigned (Secure Boot would refuse them): $bad — sudo sbctl sign-all"
    ok "UKIs rebuilt and signed"
  else
    ok "UKIs rebuilt (no sbctl keys: unsigned, Secure Boot is off)"
  fi
fi
echo "    reboot to see it; the fallback entries (systemd-boot, \"Snapshots & recovery\") stay verbose"

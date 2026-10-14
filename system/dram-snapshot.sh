#!/usr/bin/env bash
# usage: dram-snapshot.sh <pre DESC | post | ukis | list | rollback N> [--dry-run]
#
# The root half of SteamOS-style safety (decisions/0011), installed by
# system/snapshots-setup.sh to /usr/local/lib/dram/dram-snapshot and run by
# pacman hooks and `dram rollback --system`:
#   pre DESC     snapper "pre" snapshot of / before a pacman transaction
#                (system/hooks/00-dram-snap-pre.hook); its number is kept in
#                /run/dram-snap.pre for the post half
#   post         the matching "post" snapshot (zz-dram-snap-post.hook), then ukis
#   ukis         one signed UKI per kept "pre" snapshot (the newest 5), built
#                inside that snapshot from ITS kernel and modules, booting it
#                read-only with a throwaway overlay (systemd.volatile=overlay);
#                stale ones are removed. systemd-boot lists them by themselves.
#   list         the snapshots and which have a boot entry
#   rollback N   make snapshot N the new root: @ -> @.broken-<stamp>, a
#                writable copy of N becomes @, the live UKI is rebuilt inside it;
#                reboot to finish. The broken root stays until you delete it.
# Replaces snap-pac (no release since 2021: decisions/0013 Community). Root.
#
#   --dry-run     print what would happen (rollback, ukis)
#   -h, --help    this text
#
# exit: 0 ok · 1 a step failed or not root · 2 bad usage
# see: decisions/0011-disk-boot-secure-boot-snapshots.md

set -uo pipefail
KEEP=5
ESP=/efi
UKIDIR="$ESP/EFI/Linux"
PRE_FILE=/run/dram-snap.pre
DRY=0

usage_line() { sed -n '2s/^# \{0,1\}//p' "$0" >&2; }
args=()
for a in "$@"; do
  case "$a" in
    -h | --help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --dry-run) DRY=1 ;;
    *) args+=("$a") ;;
  esac
done
set -- "${args[@]+"${args[@]}"}"
cmd="${1:-}"
case "$cmd" in
  pre | post | ukis | list | rollback) ;;
  *)
    usage_line
    exit 2
    ;;
esac
shift

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}
run() { if [ "$DRY" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else "$@"; fi; }
[ "$(id -u)" -eq 0 ] || [ "$DRY" = 1 ] || [ "$cmd" = list ] || die "run as root"
command -v snapper >/dev/null 2>&1 || die "snapper is not installed (packages/metal.txt)"
snapper -c root list-configs >/dev/null 2>&1 || snapper list-configs 2>/dev/null | grep -q '^root ' \
  || die "no snapper config 'root' — run system/snapshots-setup.sh"

# pre snapshots, newest first: "number<TAB>date<TAB>description"
pre_snapshots() {
  snapper -c root --csvout list --columns number,type,date,description 2>/dev/null \
    | awk -F, 'NR>1 && $2=="pre" {print $1"\t"$3"\t"$4}' | sort -rn
}

# the boot entry for snapshot N: built inside the snapshot, so kernel, modules and
# initramfs config are the snapshot's own; signed when sbctl has keys
build_uki() {
  local n="$1" date="$2" desc="$3" root="/.snapshots/$1/snapshot" kver out tmp
  out="$UKIDIR/arch-snap-$n.efi"
  [ -f "$out" ] && return 0
  [ -d "$root/usr/lib/modules" ] || return 0
  kver="$(find "$root/usr/lib/modules" -mindepth 2 -maxdepth 2 -name vmlinuz -printf '%h\n' 2>/dev/null \
    | xargs -r -n1 basename | sort -V | tail -1)"
  [ -n "$kver" ] || {
    warn "snapshot $n has no kernel — no boot entry"
    return 0
  }
  [ -f "$root/etc/kernel/cmdline" ] || {
    warn "snapshot $n has no /etc/kernel/cmdline — no boot entry"
    return 0
  }
  [ -f "$root/etc/initcpio/install/dram-volatile" ] || {
    warn "snapshot $n predates the dram-volatile initramfs hook (snapshots-setup.sh) — no boot entry"
    return 0
  }
  say "boot entry for snapshot $n ($date, kernel $kver)"
  tmp="$(mktemp -d /run/dram-snap.XXXXXX)"
  # the snapshot's cmdline, pointed at the snapshot, read-only with a RAM overlay, no resume
  sed -E "s#rootflags=subvol=[^ ]*#rootflags=subvol=@snapshots/$n/snapshot#; s# resume(_offset)?=[^ ]*##g; s# rw( |\$)# ro\1#" \
    "$root/etc/kernel/cmdline" | tr -d '\n' >"$tmp/cmdline"
  printf ' systemd.volatile=overlay\n' >>"$tmp/cmdline"
  # a snapshot from before libfido2 has no YubiKey stage in its initramfs: with
  # fido2-device= left in, a TPM that refuses would end in systemd-cryptsetup's fatal
  # FIDO2 path instead of the recovery prompt (decisions/0019)
  if grep -q 'fido2-device=' "$tmp/cmdline" && [ ! -e "$root/usr/lib/libfido2.so.1" ]; then
    sed -i -E 's#fido2-device=[^, ]*,?##; s#,( |$)#\1#' "$tmp/cmdline"
    warn "snapshot $n has no libfido2: its entry unlocks with the TPM or the recovery key only"
  fi
  {
    grep -vE '^(PRETTY_NAME|VERSION_ID|IMAGE_ID|IMAGE_VERSION)=' "$root/etc/os-release"
    echo "PRETTY_NAME=\"Arch snapshot $n — $date ${desc:0:40}\""
    # systemd-boot sorts entries by IMAGE_ID (else ID) first: "arch-snapshot" after the
    # live system's "arch", so a snapshot is never the menu's first entry or its default
    echo "IMAGE_ID=arch-snapshot"
    echo "VERSION_ID=snap$n"
  } >"$tmp/os-release"
  if [ "$DRY" = 1 ]; then
    echo "  [dry-run] arch-chroot $root mkinitcpio -k $kver -A dram-volatile -U $out ($(cat "$tmp/cmdline"))"
    rm -rf "$tmp"
    return 0
  fi
  # arch-chroot onto the read-only snapshot mounts fresh /proc /sys /dev /run /tmp;
  # the scratch dir is bound at the snapshot's /mnt and the ESP at its /efi (both
  # directories exist in every snapshot), so mkinitcpio reads the snapshot and writes
  # only the UKI
  mount --bind "$tmp" "$root/mnt" || die "bind $tmp"
  mount --bind "$ESP" "$root$ESP" || {
    umount "$root/mnt"
    die "bind $ESP"
  }
  # -A dram-volatile: the overlay module + systemd-volatile-root (system/initcpio/dram-volatile)
  if arch-chroot "$root" mkinitcpio -k "$kver" -A dram-volatile -U "$out" --cmdline /mnt/cmdline --osrelease /mnt/os-release >"$tmp/log" 2>&1; then
    if [ -f /var/lib/sbctl/keys/db/db.key ] && command -v sbctl >/dev/null 2>&1; then
      sbctl sign "$out" >/dev/null 2>&1 || warn "sbctl sign failed for $out"
    fi
  else
    warn "mkinitcpio failed inside snapshot $n — no boot entry ($(tail -1 "$tmp/log"))"
    rm -f "$out"
  fi
  umount "$root$ESP" "$root/mnt" 2>/dev/null || true
  rm -rf "$tmp"
}

sync_ukis() {
  local keep n date desc f num
  mkdir -p "$UKIDIR"
  keep="$(pre_snapshots | head -n "$KEEP")"
  while IFS=$'\t' read -r n date desc; do
    [ -n "$n" ] && build_uki "$n" "$date" "$desc"
  done <<<"$keep"
  for f in "$UKIDIR"/arch-snap-*.efi; do
    [ -e "$f" ] || continue
    num="${f##*arch-snap-}"
    num="${num%.efi}"
    if ! cut -f1 <<<"$keep" | grep -qx "$num"; then
      say "removing the boot entry of snapshot $num (snapshot gone or older than the newest $KEEP)"
      run rm -f "$f"
    fi
  done
}

case "$cmd" in
  pre)
    desc="$*"
    # NeedsTargets: pacman hands the package names on stdin
    if [ -z "$desc" ] && [ ! -t 0 ]; then desc="pacman: $(tr '\n' ' ' | cut -c1-100)"; fi
    desc="${desc:-pacman transaction}"
    n="$(snapper -c root create --type pre --cleanup-algorithm number --print-number --description "${desc:0:120}")" \
      || die "snapper pre failed"
    echo "$n" >"$PRE_FILE"
    ;;
  post)
    if [ -s "$PRE_FILE" ]; then
      snapper -c root create --type post --cleanup-algorithm number --pre-number "$(cat "$PRE_FILE")" \
        --description "pacman transaction" >/dev/null || warn "snapper post failed"
      rm -f "$PRE_FILE"
    fi
    sync_ukis
    ;;
  ukis) sync_ukis ;;
  list)
    snapper -c root list
    echo
    echo "boot entries: $(find "$UKIDIR" -maxdepth 1 -name 'arch-snap-*.efi' -printf '%f ' 2>/dev/null)"
    ;;
  rollback)
    n="${1:-}"
    [[ "$n" =~ ^[0-9]+$ ]] || {
      usage_line
      exit 2
    }
    src="/.snapshots/$n/snapshot"
    [ -d "$src/usr" ] || die "no snapshot $n (dram-snapshot list)"
    dev="$(findmnt -no SOURCE / | sed 's/\[.*//')"
    stamp="$(date +%Y%m%d-%H%M%S)"
    top="$(mktemp -d /run/dram-top.XXXXXX)"
    say "rollback to snapshot $n: @ -> @.broken-$stamp, snapshot $n -> @ (on $dev)"
    run mount -o subvolid=5 "$dev" "$top"
    [ -d "$top/@" ] || die "no @ subvolume at the top of $dev"
    run mv "$top/@" "$top/@.broken-$stamp"
    run btrfs subvolume snapshot "$top/@snapshots/$n/snapshot" "$top/@"
    # the new root boots the live UKI: rebuild it inside the restored tree, from its own
    # kernel and modules (its fstab mounts the ESP at /efi)
    run arch-chroot "$top/@" sh -c "mount -a -t vfat && mkinitcpio -P"
    if [ -f /var/lib/sbctl/keys/db/db.key ]; then run sbctl sign-all; fi
    run umount -R "$top"
    say "done — reboot into the restored root. The old one is @.broken-$stamp:"
    echo "    when the restored system is good: sudo mount -o subvolid=5 $dev /mnt && sudo btrfs subvolume delete /mnt/@.broken-$stamp"
    ;;
esac

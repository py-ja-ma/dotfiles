#!/usr/bin/env bash
# usage: decommission.sh [--plan | --execute [--dry-run] [--delete-age-key]]
#
# Retires THIS host from the dram. --plan (the default) changes nothing: it
# prints, numbered, every artefact this host holds or is referenced by and
# the exact command that removes each — the copy of its data you keep, the
# .sops.yaml recipient, modules/hosts/<host>.nix + hosts/<host>/, the Mac
# scripts that name it, the [dram] builder role and the signing key's
# custody, the YubiKeys (nothing on them is per host), the UniFi WireGuard
# client + DHCP reservation, the GitHub keys, and the local state. While
# backups are paused (decisions/0014) a host has no peer; with one, the plan
# adds its Borg repo on the peer, its pinned key there and any host whose
# backupPeer is this one. Peer-side and Mac-side steps are PRINTED, never run
# from here: bin/forget-host.sh <host> does the Mac side. --execute runs only
# the local steps a reinstall would undo anyway: stops the user timers,
# removes the Home Manager profiles and state, the builder's /srv/dram and
# chroot, the plaintext Borg passphrase if one exists. It never touches
# ~/backups/borg (a peer's data), ~/.ssh, ~/.gnupg (the signing key) or the
# disk; the age key goes only with --delete-age-key. Asks for the hostname
# typed back and refuses without a terminal. Runs as the host's user; sudo
# only for /srv/dram and the chroot.
#
#   --plan             print the plan (default)
#   --execute          run the local steps, after the typed hostname
#   --dry-run          with --execute: print the commands, change nothing, no prompt
#   --delete-age-key   with --execute: also delete ~/.config/sops/age/keys.txt
#   -h, --help         this text
#
# exit: 0 ok · 1 refused (no terminal, name mismatch, not a dram host) · 2 bad usage
# see: docs/records/handbook/10-teardown.md

set -uo pipefail

MODE=plan DRY=0 DEL_AGE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --plan) MODE=plan ;;
    --execute) MODE=execute ;;
    --dry-run) DRY=1 ;;
    --delete-age-key) DEL_AGE=1 ;;
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

die() {
  printf '\033[1;31m[!]\033[0m %s\n' "$*" >&2
  exit 1
}
say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

# --- facts --------------------------------------------------------------------
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="$(cat /etc/hostname 2>/dev/null || true)"
[ -n "$HOST" ] || die "no /etc/hostname — this runs on the host being retired, not on the Mac"
MOD="$REPO/modules/hosts/$HOST.nix"
[ -f "$MOD" ] || die "no modules/hosts/$HOST.nix — '$HOST' is not a host of this dram"
[ "$(id -u)" != 0 ] || die "run as your user, not root (sudo is used only where a step needs it)"
# shellcheck source=install/lib/roles.sh
. "$REPO/install/lib/roles.sh"

# nixval <flag> <file>: the quoted value of `dram.<flag> = "..."` or `<flag> = "..."`
nixval() { sed -n "s/^[[:space:]]*\(dram\.\)\{0,1\}$1[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\2/p" "$2" | head -1; }
PEER="$(nixval backupPeer "$MOD")"
PEER_ADDR="$(nixval backupPeerAddr "$MOD")"
PEER_USER="$(host_user "$REPO" "${PEER:-none}")"
ME="$(id -un)"
# my LAN address: this host's own `address` (modules/hosts/<host>.nix) first;
# a dependant's backupPeerAddr is the fallback for a host file without one
MY_ADDR="$(nixval address "$MOD")"
# hosts that store THEIR backups here (their backupPeer is this host)
DEPENDANTS=""
for f in "$REPO"/modules/hosts/*.nix; do
  h="$(basename "$f" .nix)"
  [ "$h" != "$HOST" ] || continue
  if [ "$(nixval backupPeer "$f")" = "$HOST" ]; then
    DEPENDANTS="${DEPENDANTS:+$DEPENDANTS }$h"
    [ -n "$MY_ADDR" ] || MY_ADDR="$(nixval backupPeerAddr "$f")"
  fi
done
PUB="$HOME/.ssh/id_ed25519.pub"
KEY_COMMENT="" KEY_FPR=""
if [ -f "$PUB" ]; then
  # field 3 to the end: a comment with spaces stays whole
  KEY_COMMENT="$(cut -d' ' -f3- "$PUB")"
  KEY_FPR="$(ssh-keygen -lf "$PUB" 2>/dev/null | awk '{print $2}')"
fi
AGE_KEY="$HOME/.config/sops/age/keys.txt"
PLAIN="$HOME/.config/borgmatic/passphrase"
GPGKEY_FILE="$HOME/.config/dram/gpgkey"
STAGE=/srv/dram
CHROOT=/var/lib/archbuild/dram-x86_64
BUILDER=0
{ [ -d "$STAGE" ] || [ -d "$CHROOT" ] || [ -s "$GPGKEY_FILE" ]; } && BUILDER=1
# the user timers that exist here (borgmatic.timer only while backups run)
TIMERS=""
for t in borgmatic.timer dram-theme-auto.timer; do
  systemctl --user cat "$t" >/dev/null 2>&1 && TIMERS="${TIMERS:+$TIMERS }$t"
done
[ -n "$TIMERS" ] || TIMERS="dram-theme-auto.timer"
HM_STATE="$HOME/.local/state/nix/profiles $HOME/.local/state/home-manager $HOME/.local/state/dram $HOME/.config/sops-nix"

# --- printing -----------------------------------------------------------------
N=0
item() { # item <title> <where>
  N=$((N + 1))
  printf '\n\033[1m%2d. %s\033[0m  \033[2m[%s]\033[0m\n' "$N" "$1" "$2"
}
cmd() { printf '      $ %s\n' "$*"; }
note() { printf '      %s\n' "$*"; }
present() { if [ -e "$1" ]; then echo "present"; else echo "absent"; fi; }
sz() { du -sh "$1" 2>/dev/null | cut -f1; }

# --- plan ---------------------------------------------------------------------
do_plan() {
  if [ -n "$PEER" ]; then
    printf '\033[1mdecommission plan for %s\033[0m  (peer: %s @ %s; this host as the peer sees it: %s)\n' \
      "$HOST" "$PEER" "${PEER_ADDR:-?}" "${MY_ADDR:-unknown}"
  else
    printf '\033[1mdecommission plan for %s\033[0m  (address: %s; no backup peer — backups are paused, decisions/0014)\n' \
      "$HOST" "${MY_ADDR:-unknown}"
  fi
  echo "nothing below is run by --plan. [peer] and [Mac] steps are never run from this host."

  item "the copy of $HOST's data you keep" "Mac"
  note "what cannot be downloaded again — documents, saves, dumps, photos (handbook 05 §3) — onto the Mac, by rsync:"
  cmd "mkdir -p ~/backups/$HOST && rsync -aHv --info=progress2 $ME@${MY_ADDR:-<address>}:documents/ ~/backups/$HOST/documents/     # on the Mac; add each path you keep"
  note "the git repos this host holds (~/git/dotfiles, ~/documents/vault, ~/documents/finance): every commit pulled to the Mac?"
  cmd "git -C ~/git/dotfiles status --short | head; git -C ~/git/dotfiles log --oneline -3     # here: nothing uncommitted"
  cmd "git pull $ME@${MY_ADDR:-<address>}:git/dotfiles master     # on the Mac"
  if [ -n "$PEER" ]; then
    item "this host's Borg repo on $PEER" "peer, from the Mac"
    note "modules/backup.nix: ssh://$PEER_USER@$PEER_ADDR/./backups/borg/$HOST — every archive of $HOST lives there."
    note "last archives before deciding anything:"
    cmd "dram backup list"
    note "delete on the peer (irreversible; the Mac's copy is the only other one):"
    cmd "ssh $PEER_USER@$PEER_ADDR 'du -sh backups/borg/$HOST && rm -rf backups/borg/$HOST'"
    note "the Mac's copy of THIS host's repo (pull-backups.sh mirrors what $PEER stores): ~/backups/borg/on-$PEER/$HOST"
    cmd "bin/forget-host.sh $HOST --execute --delete-backups     # on the Mac; asks twice"
  fi
  if [ -n "$DEPENDANTS" ]; then
    for d in $DEPENDANTS; do
      note "!! $HOST STORES $d's repo: ~/backups/borg/$d ($(sz "$HOME/backups/borg/$d" || echo '?')). Not touched here — it is $d's data."
      note "   the Mac's ~/backups/borg/on-$HOST/$d is the surviving copy until $d backs up elsewhere."
    done
  fi

  item "this host's key on the other machines" "Mac"
  if [ -n "$PEER" ] && [ -n "$KEY_COMMENT" ]; then
    note "on $PEER, pinned: command=\"borg serve --restrict-to-path …\",restrict … $KEY_COMMENT  ($KEY_FPR)"
    cmd "ssh $PEER_USER@$PEER_ADDR \"grep -n ' $KEY_COMMENT\\$' ~/.ssh/authorized_keys\"     # see it"
    cmd "ssh $PEER_USER@$PEER_ADDR \"sed -i '/ $KEY_COMMENT\\$/d' ~/.ssh/authorized_keys\"   # remove it"
  elif [ -n "$KEY_COMMENT" ]; then
    note "no host should list it (backups are paused); check any you gave it to: $KEY_COMMENT  ($KEY_FPR)"
    cmd "ssh <user>@<host> \"grep -n ' $KEY_COMMENT\\$' ~/.ssh/authorized_keys\"     # from the Mac, per host"
  else
    note "no ~/.ssh/id_ed25519.pub here — nothing to remove elsewhere."
  fi
  note "the keys in THIS host's authorized_keys (the Mac's, the YubiKeys') die with the disk."
  note "the Mac's known_hosts entry for this host:"
  cmd "ssh-keygen -R ${MY_ADDR:-<ip>}     # on the Mac"

  item "sops recipient in .sops.yaml + re-encrypt secrets/pj.yaml" "Mac, then a YubiKey"
  if grep -q "^  # host: $HOST\$" "$REPO/.sops.yaml"; then
    note "$(grep -A1 "^  # host: $HOST\$" "$REPO/.sops.yaml" | tail -1 | sed 's/^ *//')"
  else
    note "no '# host: $HOST' marker in .sops.yaml (already removed?)"
  fi
  cmd "bin/forget-host.sh $HOST --execute      # Mac: drops the marker, the &$HOST anchor and the *$HOST reference"
  cmd "SOPS_AGE_KEY_FILE=~/.config/sops/age/yubikey-primary.txt sops updatekeys -y secrets/pj.yaml   # any host with the stub; commit, release"
  note "every commit of secrets/pj.yaml before that stays decryptable by this host's age key (the local state item)."

  item "modules/hosts/$HOST.nix and hosts/$HOST/" "Mac"
  cmd "git rm -r modules/hosts/$HOST.nix hosts/$HOST     # forget-host.sh does this; flake.nix needs no edit (readDir)"
  note "docs that reference hosts/$HOST/…: $(git -C "$REPO" grep -l "hosts/$HOST/" -- docs README.md 2>/dev/null | grep -v '^docs/commands.md$' | paste -sd' ' - || echo none)"

  if [ -n "$DEPENDANTS" ]; then
    item "hosts whose backupPeer is $HOST" "Mac + that host"
    for d in $DEPENDANTS; do
      note "modules/hosts/$d.nix: backupPeer = \"$HOST\"; backupPeerAddr = \"$MY_ADDR\" — a dead target: $d's 03:00 backup soft-fails (exit 75) every night."
      note "change both to a surviving host, then on $d:"
      cmd "dram switch && borgmatic repo-create --encryption repokey-blake2 && dram backup"
      note "no surviving host? then $d has no target until one exists; the Mac's on-$HOST/$d copy is its last backup."
    done
  fi

  item "Mac scripts that name this host" "Mac"
  for f in bin/pull-backups.sh bin/sync-dram-repo.sh; do
    [ -f "$REPO/$f" ] || continue
    hits="$(grep -n -E "$HOST|${MY_ADDR:-NOADDR}" "$REPO/$f" | grep -v -E '^[0-9]+:[[:space:]]*#' || true)"
    if [ -n "$hits" ]; then
      note "$f:"
      printf '%s\n' "$hits" | sed 's/^/          /'
    else
      note "$f: no entry"
    fi
  done
  note "forget-host.sh edits the pull-backups.sh list; sync-dram-repo.sh (builder -> consumer) is a hand edit;"
  note "bin/release.sh reads the addresses from the host files, so it forgets $HOST with its file."

  item "[dram] builder role" "this host"
  if [ "$BUILDER" = 1 ]; then
    fpr="$(cat "$GPGKEY_FILE" 2>/dev/null || true)"
    note "$STAGE: $(present "$STAGE") ($(sz "$STAGE" || echo -)); $CHROOT: $(present "$CHROOT"); signing key fingerprint: ${fpr:-none in $GPGKEY_FILE}"
    if [ -n "$fpr" ] && gpg --list-secret-keys "$fpr" >/dev/null 2>&1; then
      note "!! the PRIVATE signing key is in ~/.gnupg here and nowhere else (docs/toolchain/packaging/README.md). --execute does not delete it."
      note "   keep it (export BEFORE the disk goes, to Proton Pass or the Mac), or let it go and re-key (below):"
      cmd "gpg --armor --export-secret-keys $fpr > ~/dram-signing-key.private.asc   # then move it off this disk; shred -u it here"
      note "   restore on the next builder: gpg --import dram-signing-key.private.asc; echo $fpr > ~/.config/dram/gpgkey"
      note "   let it go: on the next builder 'dram pkgs key --new' (pins it), commit, 'dram pkgs build' + publish,"
      note "   release; 'sudo bash system/pacman-dram-repo.sh' on every host trusts it and drops this one (handbook 07)."
    fi
    note "the next builder: DRAM_BUILDER_HOST=<host> sudo bash system/dram-builder-setup.sh; bin/sync-dram-repo.sh SRC= that host."
    cmd "sudo rm -rf $STAGE $CHROOT     # --execute does this"
  else
    note "not the builder (no $STAGE, no chroot, no $GPGKEY_FILE). /var/lib/dram-repo is the consumer copy; it dies with the disk."
  fi

  item "YubiKeys" "nothing to do"
  note "nothing on the keys is per host: the SSH credentials (ssh:dram-<label>), the pam-u2f credential"
  note "(pam://dram) and the age identity serve every machine. What this host holds — /etc/dram/u2f_mappings,"
  note "/etc/ssh/authorized_keys.d, ~/.ssh/id_ed25519_sk* (handles, no secret) and, on a laptop, the LUKS FIDO2"
  note "keyslots — dies with the disk. A lost key is docs/security/identity/yubikeys.md \"A key is lost\", not this script."

  item "UniFi: WireGuard client + DHCP reservation" "manual, UniFi console"
  note "Settings -> VPN -> VPN Server -> WireGuard: delete the client named $HOST (docs/security/network/vpn.md)."
  note "the DHCP reservation for ${MY_ADDR:-<ip>} (Client Devices): release it, or keep it for the replacement."
  if sudo -n test -f /etc/wireguard/home.conf 2>/dev/null; then
    note "/etc/wireguard/home.conf: present (holds the client's private key; dies with the disk)"
  else
    note "/etc/wireguard/home.conf: not readable without sudo — verify: sudo ls /etc/wireguard"
  fi

  item "GitHub keys" "manual, github.com/settings/keys"
  if [ -n "$KEY_FPR" ]; then
    note "remove BOTH entries with this fingerprint, if you added them — the authentication key and the signing key (modules/dev.nix):"
    note "  $KEY_FPR  $KEY_COMMENT"
  else
    note "no ~/.ssh/id_ed25519.pub — nothing was registered from this host, or the key is elsewhere."
  fi

  item "local state (what --execute removes)" "this host"
  note "user timers: $(for t in $TIMERS; do printf '%s (%s) ' "$t" "$(systemctl --user is-active "$t" 2>/dev/null || echo unknown)"; done)"
  cmd "systemctl --user disable --now $TIMERS; systemctl --user stop sops-nix.service"
  note "Home Manager profiles + state:"
  for d in $HM_STATE; do note "  $d: $(present "$d")"; done
  cmd "rm -rf $HM_STATE"
  note "  (the dotfile symlinks in ~ keep pointing into /nix/store until the disk is wiped)"
  if [ -e "$PLAIN" ]; then
    note "plaintext Borg passphrase $PLAIN: present — copies: Proton Pass, the Mac's ~/backups/borg/passphrase"
    cmd "rm -f $PLAIN"
  fi
  if [ "$BUILDER" = 1 ]; then cmd "sudo rm -rf $STAGE $CHROOT"; fi
  note "the age key $AGE_KEY: $(present "$AGE_KEY")"
  note "  !! losing it means this host can never decrypt secrets/pj.yaml again — any commit of it. Back it up, or delete it knowing that:"
  cmd "cp $AGE_KEY /some/where/safe/$HOST-age-keys.txt    # or let it die with the disk"
  cmd "bash $0 --execute --delete-age-key                   # the only way --execute removes it"
  note "NOT touched by --execute: ~/backups/borg/* (a peer's data), ~/.ssh, ~/.gnupg, /var/lib/dram-repo, /etc/wireguard, the disk."
  note "the disk: reinstall or wipe it yourself, from live media, never from here — install/arch-install.sh"
  note "  wipes every disk it is given (handbook 01), or: blkdiscard /dev/<disk>  (SSD)  ·  dd if=/dev/zero of=/dev/<disk> bs=4M status=progress"

  printf '\n\033[1morder\033[0m\n'
  if [ -n "$PEER" ]; then
    note "1. dram backup; on the Mac bin/pull-backups.sh   — a last archive, and the copy you keep"
    note "2. bin/forget-host.sh $HOST --execute            — Mac: repo, sops, scripts; then release"
    note "3. the peer-side commands above, from the Mac"
  else
    note "1. the rsync and git pull of item 1                — Mac: the copy you keep"
    note "2. bin/forget-host.sh $HOST --execute            — Mac: repo, sops; then the updatekeys, commit, release"
  fi
  note "then: the builder item if it applies, UniFi, GitHub"
  note "last: bash $0 --execute   — here; then reinstall or wipe"
}

# --- execute ------------------------------------------------------------------
run() {
  if [ "$DRY" = 1 ]; then
    printf '  \033[2m[dry-run] %s\033[0m\n' "$*"
  else
    printf '  $ %s\n' "$*"
    "$@"
  fi
}

do_execute() {
  cat <<EOF

  ##########################################################################
  #  DECOMMISSION $HOST — LOCAL STEPS
  #
  #  This removes, on THIS host: the user timers, the Home Manager profiles
  #  and state, a plaintext Borg passphrase$([ "$BUILDER" = 1 ] && printf ',\n  #  the builder staging dir %s and the chroot' "$STAGE"),
  #  and$([ "$DEL_AGE" = 1 ] && printf ' THE AGE KEY %s (this host can never decrypt\n  #  secrets/pj.yaml again), and' "$AGE_KEY") nothing else.
  #
  #  It does NOT touch: ~/backups/borg (a peer's data), ~/.ssh, ~/.gnupg
  #  (the signing key), /var/lib/dram-repo, /etc/wireguard, the disk.
  #  Peer-side and Mac-side steps are in --plan; run them from the Mac.
  #
  #  Is the copy you keep on the Mac (plan item 1)?
  ##########################################################################

EOF
  if [ "$DRY" = 1 ]; then
    say "dry run: the commands, nothing changes"
  else
    [ -t 0 ] && [ -t 1 ] || die "refusing: --execute needs a terminal (no TTY). --dry-run shows the steps."
    printf 'type the hostname (%s) to continue, anything else to stop: ' "$HOST"
    read -r answer
    [ "$answer" = "$HOST" ] || die "that is not '$HOST' — nothing done"
  fi

  say "timers"
  # shellcheck disable=SC2086 # one word per timer
  run systemctl --user disable --now $TIMERS || true
  run systemctl --user stop sops-nix.service || true

  say "Home Manager profiles + state"
  for d in $HM_STATE; do
    [ -e "$d" ] && run rm -rf "$d"
  done

  if [ -f "$PLAIN" ]; then
    say "plaintext Borg passphrase"
    run rm -f "$PLAIN"
  fi

  if [ "$BUILDER" = 1 ]; then
    say "builder staging dir + chroot (sudo)"
    for d in "$STAGE" "$CHROOT"; do
      [ -e "$d" ] && run sudo rm -rf "$d"
    done
    say "the signing key stays in ~/.gnupg — export it before the wipe, or re-key (the plan's builder item)"
  fi

  if [ "$DEL_AGE" = 1 ]; then
    say "age key"
    [ -f "$AGE_KEY" ] && run rm -f "$AGE_KEY"
  else
    say "age key kept: $AGE_KEY (--delete-age-key removes it)"
  fi

  echo
  if [ "$DRY" = 1 ]; then
    say "dry run: nothing changed. Still yours: the Mac + peer steps in --plan, UniFi, GitHub, then reinstall or wipe."
  else
    say "local steps done. Still yours: the Mac + peer steps in --plan, UniFi, GitHub, then reinstall or wipe."
  fi
}

case "$MODE" in
  plan) do_plan ;;
  execute) do_execute ;;
esac

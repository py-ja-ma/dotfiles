#!/usr/bin/env bash
# usage: backup-eva.sh
#
# Borg backup of the irreplaceable set to the eva drive: an optional offline
# copy next to the real backup (borgmatic host-to-host plus the Mac pull).
# Backs up ~/git/dotfiles, ~/.ssh, ~/pictures and the editor settings;
# everything else is reinstallable or in git. Finds the mounted drive,
# `borg init`s the encrypted repo once, creates a timestamped archive, prunes
# and compacts. The passphrase lives in Proton Pass ("borg eva backup");
# without it the backup is unreadable. Run by hand when the drive is plugged
# in (also the `backup-eva` alias).
#
#   -h, --help    this text
#
# needs:  borg; rsync for the plain mirror; udisksctl to mount the drive; the drive
#         labeled eva, or DRAM_BACKUP_ROOT
# alone:  yes, after changing the label "eva" and the source list
# here:   by hand, or the backup-eva alias (modules/shell.nix), when the drive is plugged in
# env:    BORG_PASSPHRASE=...        non-interactive
#         DRAM_BACKUP_ROOT=/some/dir test/override target
#
# exit:   0 ok · 1 drive not mounted or borg failed · 2 bad usage
# see:    docs/operations/backups/README.md

# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT

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

# Backs up the handful of things that are NOT reproducible from the dram repo:
#   - ~/git/dotfiles        the dram repo itself (+ any other dotfiles repos)
#   - ~/.ssh                private keys + config.d/*.conf (the untracked part)
#   - ~/pictures            wallpapers, screenshots, anything you saved
#   - editor settings       ~/.config/VSCodium/User/settings.json (VS Code reads
#                           the same file via Code/User/; tracked in the repo since,
#                           kept in the set as a harmless duplicate)
#
# Everything else on this box is either reinstallable (packages) or already
# in git (dotfiles), so it is not here. See docs/operations/backups/README.md.
#
# Design: idempotent + safe to run repeatedly.
#   1. find where eva is mounted; fail LOUDLY with instructions if it isn't
#   2. `borg init` the repo once (only if absent), encrypted
#   3. `borg create` a new timestamped archive
#   4. `borg prune` to a sane retention, then `borg compact` to reclaim space
#
# ENCRYPTION: repokey (blake2). The backup set contains ~/.ssh PRIVATE KEYS,
# and eva is a small external drive that can be lost or stolen — so the repo
# is encrypted. "repokey" means the encryption key itself is stored INSIDE the
# repo on eva; the only thing you must remember is the PASSPHRASE that unlocks
# that key.
#
#   >>> Store the passphrase in Proton Pass (entry: "borg eva backup"). <<<
#
# Proton Pass lives in the cloud, so the passphrase survives even if both the
# laptop AND eva die. NEVER store the passphrase only on this laptop.
# WARNING: no passphrase = the backup is permanently unreadable. Put it in
# Proton Pass BEFORE the first backup run.

set -uo pipefail

say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}

command -v borg >/dev/null 2>&1 || die "borg is not installed (sudo pacman -S borg)."

# ---- 1. locate the eva drive ------------------------------------------------
# DRAM_BACKUP_ROOT overrides everything (used by the dry test / custom targets).
if [ -n "${DRAM_BACKUP_ROOT:-}" ]; then
  EVA="$DRAM_BACKUP_ROOT"
  mkdir -p "$EVA" || die "cannot create DRAM_BACKUP_ROOT=$EVA"
else
  EVA=""
  for cand in "/run/media/$USER/eva" "/run/media/pj/eva" "/mnt/eva"; do
    if mountpoint -q "$cand" 2>/dev/null || { [ -d "$cand" ] && mount | grep -qF " $cand "; }; then
      EVA="$cand"
      break
    fi
  done
  # last resort: ask findmnt for anything labelled eva
  if [ -z "$EVA" ] && command -v findmnt >/dev/null 2>&1; then
    EVA="$(findmnt -n -o TARGET LABEL=eva 2>/dev/null | head -1)"
  fi

  # still nothing, but the drive IS plugged in? auto-mount it (udisksctl needs no
  # sudo) so "plug in eva, run backup" just works — then re-detect the mountpoint.
  if [ -z "$EVA" ] && [ -e /dev/disk/by-label/eva ] && command -v udisksctl >/dev/null 2>&1; then
    say "eva is plugged in but not mounted — mounting it…"
    udisksctl mount -b /dev/disk/by-label/eva >/dev/null 2>&1 || true
    EVA="$(findmnt -n -o TARGET LABEL=eva 2>/dev/null | head -1)"
    [ -n "$EVA" ] && ok "mounted eva at $EVA"
  fi

  if [ -z "$EVA" ] || [ ! -d "$EVA" ]; then
    warn "The eva drive is not mounted — nothing was backed up."
    cat >&2 <<'EOF'

  eva is the external NTFS drive (label "eva", usually /dev/sda2). Plug it in, then:

    # normal mount (no sudo):
    udisksctl mount -b /dev/sda2
    # -> mounts at /run/media/pj/eva, then re-run this script.

  If udisksctl fails with "bad superblock" / "dirty flag" (happens after an
  unclean shutdown), clear the NTFS dirty bit once with root, then retry:

    sudo mount -t ntfs-3g -o rw,uid=1000,gid=1000,windows_names /dev/sda2 /mnt && sudo umount /mnt
    udisksctl mount -b /dev/sda2

  Confirm the device name first with:  lsblk -f
EOF
    exit 1
  fi
fi
ok "backup target: $EVA"

# ---- 2. borg repo (init once, encrypted) ------------------------------------
REPO="$EVA/backups/borg-dram"
# the repo was borg-rice until 2026-10-06: move it once, keep the archives
if [ -d "$EVA/backups/borg-rice" ] && [ ! -e "$REPO" ]; then
  mv "$EVA/backups/borg-rice" "$REPO" && ok "moved borg-rice -> borg-dram (rice is now dram)"
fi
export BORG_REPO="$REPO"
# allow the repo to move between mountpoints/drives without an interactive prompt
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes

# is there already a repo, and is it encrypted? (repokey repos carry the key
# inside their config file as a "key = ..." entry; -e none repos don't)
REPO_EXISTS=no ENCRYPTED=yes
if [ -e "$REPO/config" ]; then
  REPO_EXISTS=yes
  grep -q '^key *=' "$REPO/config" || ENCRYPTED=no
fi

if [ "$REPO_EXISTS" = yes ] && [ "$ENCRYPTED" = no ]; then
  # legacy repo from an earlier, unencrypted version of this script.
  # Keep working with it (a backup now beats no backup), but nag.
  warn "the existing repo at $REPO is UNENCRYPTED."
  warn "to switch to encrypted: rename or delete '$REPO' and re-run this script"
  warn "(old archives in the renamed copy stay readable until you remove it)."
  export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
fi

# get the passphrase exactly once per run (borg would otherwise prompt for
# every borg command below). Skipped for a legacy unencrypted repo.
if [ "$ENCRYPTED" = yes ] && [ -z "${BORG_PASSPHRASE:-}" ]; then
  if [ "$REPO_EXISTS" = no ]; then
    say "FIRST RUN — choose the backup passphrase"
    cat <<'EOF'
  This passphrase encrypts the backup (it contains your SSH private keys).
  1. Open Proton Pass and create an entry "borg eva backup" with a strong,
     generated passphrase. Do this FIRST — if the passphrase is ever lost,
     the backup is permanently unreadable.
  2. Paste it below (typing is hidden), twice to confirm.
EOF
    read -rs -p "  new passphrase: " P1
    echo
    read -rs -p "  repeat passphrase: " P2
    echo
    [ -n "$P1" ] || die "empty passphrase — aborting."
    [ "$P1" = "$P2" ] || die "passphrases did not match — nothing was created, just re-run."
    export BORG_PASSPHRASE="$P1"
    unset P1 P2
  else
    read -rs -p "borg passphrase (the 'borg eva backup' entry in Proton Pass): " BORG_PASSPHRASE
    echo
    export BORG_PASSPHRASE
  fi
fi

if [ "$REPO_EXISTS" = no ]; then
  say "initialising new borg repo (repokey-blake2, encrypted) at $REPO"
  mkdir -p "$(dirname "$REPO")" || die "cannot create $(dirname "$REPO")"
  borg init --encryption=repokey-blake2 "$REPO" || die "borg init failed"
  ok "repo initialised — passphrase MUST now be in Proton Pass"
else
  ok "repo already exists — reusing it"
fi

# ---- 3. create the archive --------------------------------------------------
HOST="$(hostname 2>/dev/null || echo host)"
ARCHIVE="dram-${HOST}-$(date +%Y-%m-%d_%H%M%S)"

# the irreplaceable set (only the paths that actually exist get passed to borg)
CANDIDATES=(
  "$HOME/git/dotfiles"
  "$HOME/.ssh"
  "$HOME/pictures"
  "$HOME/.config/VSCodium/User/settings.json"
)
SOURCES=()
for p in "${CANDIDATES[@]}"; do
  if [ -e "$p" ]; then SOURCES+=("$p"); else warn "skipping missing path: $p"; fi
done
[ "${#SOURCES[@]}" -gt 0 ] || die "none of the backup sources exist — aborting."

say "creating archive ::$ARCHIVE"
borg create \
  --verbose --stats --compression zstd,6 \
  --exclude-caches \
  --exclude '**/node_modules' \
  --exclude '**/.cache' \
  --exclude '**/*.tmp' \
  --exclude '**/*.swp' \
  --exclude '**/result' \
  --exclude '**/result-*' \
  "::$ARCHIVE" \
  "${SOURCES[@]}"
rc=$?
# borg exit codes: 0 = ok, 1 = warnings (e.g. a file vanished mid-run) — both fine.
if [ "$rc" -ge 2 ]; then die "borg create failed (exit $rc)"; fi
ok "archive created"

# ---- 4. retention: prune + compact -----------------------------------------
say "pruning old archives (keep daily 7 / weekly 4 / monthly 6)"
# rice-*: archives from before the 2026-10-06 rename age out under the same rule
for glob in 'dram-*' 'rice-*'; do
  borg prune --stats -a "sh:$glob" \
    --keep-daily 7 --keep-weekly 4 --keep-monthly 6 || warn "prune reported an issue ($glob)"
done

say "compacting repo (reclaim freed space)"
borg compact || warn "compact reported an issue"

say "current archives in repo:"
borg list --short "$REPO" 2>/dev/null | sed 's/^/    /'

ok "encrypted borg backup complete -> $REPO"

# ---- 5. plain, browsable mirror of the dram repo ----------------------------
# In ADDITION to the encrypted archive, drop an un-encrypted, directly readable
# copy of the dram repo on eva, so the files can be browsed/restored without borg
# or a passphrase. Safe to leave in the clear ONLY for tracked files: the dram
# repo's git content holds no secrets (~/.ssh lives ONLY in the encrypted archive
# above), but the working tree may carry untracked ones (tool state, decrypted
# secrets/*.plain* scratch), so everything git does not track is
# excluded (`git ls-files --others --directory` = untracked + ignored, as rsync
# patterns), with the sensitive names spelled out too. NTFS-safe rsync flags: no
# perms/owner/group, 2s modify-window; --delete keeps it a true mirror. Machine-
# state symlinks (theme "current", gtk-4.0 -> nix store) and build junk excluded.
if command -v rsync >/dev/null 2>&1; then
  DRAM_REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
  REL="${DRAM_REPO#"$HOME/git/dotfiles/"}"
  [ "$REL" = "$DRAM_REPO" ] && REL="$(basename "$DRAM_REPO")" # not under ~/git/dotfiles
  RAW_DEST="$EVA/backup/$REL"
  say "mirroring the dram repo (plain, browsable; tracked files + .git) -> $RAW_DEST"
  mkdir -p "$RAW_DEST"
  rsync -rlt --modify-window=1 --delete \
    --exclude-from=<(git -C "$DRAM_REPO" ls-files --others --directory 2>/dev/null) \
    --exclude='secrets/*.plain*' --exclude='*.plain.yaml' --exclude='__pycache__/' \
    --exclude='dotfiles/.config/themes/current' \
    --exclude='dotfiles/.config/gtk-4.0/assets' \
    --exclude='dotfiles/.config/gtk-4.0/gtk.css' \
    --exclude='dotfiles/.config/gtk-4.0/gtk-dark.css' \
    --exclude='result' --exclude='result-*' \
    "$DRAM_REPO/" "$RAW_DEST/" && ok "plain mirror updated -> $RAW_DEST" \
    || warn "plain mirror rsync reported an issue (the encrypted archive is still good)"
else
  warn "rsync not installed — skipped the plain mirror (sudo pacman -S rsync); borg archive is still made"
fi

ok "backup complete"

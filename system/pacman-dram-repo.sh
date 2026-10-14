#!/usr/bin/env bash
# usage: pacman-dram-repo.sh [--dry-run] [--migrate-from-rice]
#
# Enables the [dram] package repo on this host: imports and locally signs the
# key in pkgs/dram.asc, writes /etc/pacman.d/dram.conf ([dram], SigLevel =
# Required DatabaseRequired, Server = file:///var/lib/dram-repo), creates
# /var/lib/dram-repo owned by the user who rsyncs into it, and inserts the
# Include above [core] in /etc/pacman.conf once the repo has been synced (a
# missing dram.db would make every pacman -Sy fail). Refuses to run without
# pkgs/dram.asc (generate the key on cabin first: system/dram-builder-setup.sh
# prints the commands) and refuses a dram.asc whose fingerprint is not the
# pinned EXPECTED_FPR below (a rotated key means editing that constant and
# docs/toolchain/packaging/README.md §2 on purpose). Root, idempotent, both hosts. Re-run it on
# BOTH hosts after any change to the key — a new expiry, an added or revoked
# uid: pacman-key --add re-imports the new packets, pacman's keyring keeps the
# old ones otherwise. Afterwards: dram update.
#
#   --migrate-from-rice   the repo was [rice] until 2026-10-06: swap the Include
#                   line to dram.conf in place, drop rice.conf, mv /var/lib/rice-repo
#                   to /var/lib/dram-repo and rename rice.db* / rice.files* inside
#                   it to dram.* (plain renames; the detached signatures stay
#                   valid), then the normal steps and a final pacman -Sy
#   -n, --dry-run   no root needed; print what would change
#   -h, --help      this text
#
# env: DRAM_REPO_OWNER=<user>   default: the sudo caller, else pj
#
# exit: 0 ok · 1 not root, no key, wrong key, or a step failed · 2 bad usage
# see: docs/toolchain/packaging/README.md

set -uo pipefail
DRY=0 MIGRATE=0 SWAPPED=0 RC=0
for a in "$@"; do
  case "$a" in
    --dry-run | -n) DRY=1 ;;
    --migrate-from-rice) MIGRATE=1 ;;
    -h | --help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "usage: pacman-dram-repo.sh [--dry-run] [--migrate-from-rice]" >&2
      exit 2
      ;;
  esac
done
[ "$(id -u)" -eq 0 ] || [ "$DRY" -eq 1 ] || {
  echo "Run with sudo: sudo bash $0 [--dry-run]"
  exit 1
}

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
ASC="$REPO/pkgs/dram.asc"
CONF=/etc/pacman.d/dram.conf
PC=/etc/pacman.conf
DRAM_DIR=/var/lib/dram-repo
OWNER="${DRAM_REPO_OWNER:-${SUDO_USER:-pj}}"
INCLUDE="Include = $CONF"

say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}
failed() { # a warning that also makes the script exit 1
  warn "$*"
  RC=1
}
run() {
  if [ "$DRY" -eq 1 ]; then printf '  \033[2m[dry-run] %s\033[0m\n' "$*"; else "$@"; fi
}
install_file() { # <src> <dst> [mode]: copy only when content differs; back up the old file
  local src="$1" dst="$2" mode="${3:-0644}"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    ok "$dst already current"
    return 0
  fi
  [ -f "$dst" ] && run cp -a "$dst" "$dst.bak-$STAMP"
  run install -Dm"$mode" "$src" "$dst" && ok "installed $dst" || failed "could not install $dst"
}

[ -f "$ASC" ] || die "pkgs/dram.asc missing — no public key to trust. On the builder: dram pkgs key --new, commit, then bring the commit here and re-run (handbook 07)."
command -v gpg >/dev/null 2>&1 || die "gpg not installed (gnupg is in base)"
FPR="$(gpg --batch --with-colons --import-options show-only --import "$ASC" 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}')"
[[ "$FPR" =~ ^[0-9A-F]{40}$ ]] || die "could not read a fingerprint from pkgs/dram.asc"
# The one key this dram trusts for [dram]: ed25519, created 2026-10-11 on cabin,
# expires 2028-10-10 (gpg --show-keys pkgs/dram.asc). pacman-key --lsign-key
# below makes whatever is in pkgs/dram.asc fully trusted for package
# signatures, so a swapped file in a compromised checkout must not get that
# far. A rotation changes this constant and pkgs/dram.asc together:
# `dram pkgs key --new` on the builder writes both in one go.
EXPECTED_FPR=044DFA31C5CD72299A1460B56EF00BFB391BD348
[ "$FPR" = "$EXPECTED_FPR" ] || die "pkgs/dram.asc fingerprint $FPR != expected $EXPECTED_FPR — refusing to lsign an unknown key"
id "$OWNER" >/dev/null 2>&1 || die "no such user: $OWNER"
OWNER_GROUP="$(id -gn "$OWNER")"

# --- 0) --migrate-from-rice: the names of before 2026-10-06 ---------------------
# Plain renames keep the signatures valid: dram.db.sig signs the bytes of
# dram.db.tar.zst, which do not change. repo-add made rice.db / rice.files
# symlinks onto the tarballs, so those are re-pointed rather than moved.
rename_repo_files() { # <dir>: rice.db* and rice.files* -> dram.db* / dram.files*
  local f base new target
  for f in "$1"/rice.db* "$1"/rice.files*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    base="$(basename "$f")"
    new="$1/dram${base#rice}"
    if [ -L "$f" ]; then
      target="$(readlink "$f")"
      # the link must belong to the rsync user: rsync (as $OWNER) re-sets its group on every publish/sync
      run ln -sfn "dram${target#rice}" "$new" && run chown -h "$OWNER:$OWNER_GROUP" "$new" && run rm -f "$f" && ok "$base -> dram${base#rice} (link -> dram${target#rice})" \
        || failed "could not rename $base"
    else
      run mv -n "$f" "$new" && ok "$base -> dram${base#rice}" || failed "could not rename $base"
    fi
  done
}
if [ "$MIGRATE" -eq 1 ]; then
  say "Migrating [rice] (the name until 2026-10-06) to [dram]"
  OLD_CONF=/etc/pacman.d/rice.conf OLD_DIR=/var/lib/rice-repo
  if [ -d "$OLD_DIR" ] && [ ! -e "$DRAM_DIR" ]; then
    run mv "$OLD_DIR" "$DRAM_DIR" && ok "$OLD_DIR -> $DRAM_DIR" || failed "could not move $OLD_DIR"
    if [ "$DRY" -eq 1 ]; then rename_repo_files "$OLD_DIR"; else rename_repo_files "$DRAM_DIR"; fi
  elif [ -d "$DRAM_DIR" ]; then
    ok "$DRAM_DIR already in place"
    rename_repo_files "$DRAM_DIR" # nothing matches once renamed
  else
    warn "neither $OLD_DIR nor $DRAM_DIR exists — nothing to move (bin/sync-dram-repo.sh from the Mac fills it later)"
  fi
  if grep -qxF "Include = $OLD_CONF" "$PC"; then
    run cp -a "$PC" "$PC.bak-$STAMP"
    run sed -i "s|^Include = $OLD_CONF\$|$INCLUDE|" "$PC" && ok "$PC: Include $OLD_CONF -> $CONF (same line, above [core])" \
      || failed "could not swap the Include line in $PC"
    SWAPPED=1
  else
    ok "$PC has no Include line for $OLD_CONF"
  fi
  if [ -e "$OLD_CONF" ]; then run rm -f "$OLD_CONF" && ok "removed $OLD_CONF ($CONF is written below)" || failed "could not remove $OLD_CONF"; else ok "no $OLD_CONF"; fi
fi

# --- 1) key -------------------------------------------------------------------
say "Signing key $FPR in pacman's keyring"
PACGPG=(gpg --homedir /etc/pacman.d/gnupg --batch --with-colons)
if [ "$DRY" -eq 0 ] && [ ! -d /etc/pacman.d/gnupg ]; then
  die "/etc/pacman.d/gnupg missing — pacman-key --init && pacman-key --populate archlinux first"
fi
# --add is run even when the key is already present: a new expiry, an added or
# revoked uid in pkgs/dram.asc reaches pacman's keyring only through a
# re-import (gpg merges the new packets; the local signature stays).
if "${PACGPG[@]}" --list-keys "$FPR" >/dev/null 2>&1; then
  run pacman-key --add "$ASC" && ok "key present (re-imported from pkgs/dram.asc: expiry/uid changes merged)" || failed "pacman-key --add failed"
else
  run pacman-key --add "$ASC" && ok "key added" || failed "pacman-key --add failed"
fi
# A rotated-out [dram] key (the 2026-10 fresh start made a new one) must not stay trusted:
# any other key in pacman's keyring with our uid is deleted (Arch's keys never carry it)
for old in $("${PACGPG[@]}" --list-keys 2>/dev/null | awk -F: '
  $1 == "pub" { want = 1 }
  $1 == "fpr" && want { fpr = $10; want = 0 }
  $1 == "uid" && fpr != "" && $10 ~ /^pj (dram|rice) packages/ { print fpr; fpr = "" }'); do
  [ "$old" = "$FPR" ] && continue
  run pacman-key --delete "$old" && ok "removed the rotated-out [dram] key $old" || failed "could not remove the old key $old"
done
# After --lsign-key the key's validity is f(ull) or u(ltimate); before it is -/q.
VALIDITY="$("${PACGPG[@]}" --list-keys "$FPR" 2>/dev/null | awk -F: '$1=="pub"{print $2; exit}')"
case "$VALIDITY" in
  f | u) ok "key locally signed (validity $VALIDITY)" ;;
  *) run pacman-key --lsign-key "$FPR" && ok "key locally signed" || failed "pacman-key --lsign-key failed" ;;
esac

# --- 2) repo stanza -------------------------------------------------------------
say "$CONF"
TMP="$(mktemp)"
cat >"$TMP" <<EOF
# [dram]: this fleet's own signed package repo (docs/toolchain/packaging/README.md). Installed by
# system/pacman-dram-repo.sh; included from /etc/pacman.conf ABOVE [core], so a
# vendored name beats the official one — dram pkgs check refuses such names
# unless they are listed in pkgs/OVERRIDES. Packages and the database are
# signed with the key in pkgs/dram.asc; nothing listens on the network, the
# files are rsynced from the builder (cabin).
[dram]
SigLevel = Required DatabaseRequired
Server = file://$DRAM_DIR
EOF
install_file "$TMP" "$CONF"
rm -f "$TMP"

# --- 3) repo dir ----------------------------------------------------------------
say "$DRAM_DIR (rsync target, owned by $OWNER)"
if [ -d "$DRAM_DIR" ] && [ "$(stat -c %U "$DRAM_DIR")" = "$OWNER" ]; then
  ok "$DRAM_DIR owned by $OWNER"
else
  run install -d -m 755 -o "$OWNER" -g "$OWNER_GROUP" "$DRAM_DIR" && ok "$DRAM_DIR ready" || failed "could not create $DRAM_DIR"
  [ -d "$DRAM_DIR" ] && [ "$DRY" -eq 0 ] && { run chown "$OWNER:$OWNER_GROUP" "$DRAM_DIR" || failed "could not chown $DRAM_DIR"; }
fi

# --- 4) include above [core] ------------------------------------------------------
say "$PC: $INCLUDE above [core]"
if [ "$SWAPPED" -eq 1 ] || grep -qxF "$INCLUDE" "$PC"; then
  ok "already included"
elif [ ! -f "$DRAM_DIR/dram.db" ] && [ "$DRY" -eq 0 ]; then
  warn "$DRAM_DIR/dram.db does not exist yet — NOT adding the Include (pacman -Sy would fail on it)."
  warn "  cabin:    dram pkgs build && dram pkgs publish"
  warn "  other:    bin/sync-dram-repo.sh from the Mac"
  warn "  then re-run this script."
else
  grep -q '^\[core\]' "$PC" || die "$PC has no [core] section?"
  run cp -a "$PC" "$PC.bak-$STAMP"
  run sed -i "/^\[core\]/i $INCLUDE\n" "$PC" || failed "could not insert the Include into $PC"
  if [ "$DRY" -eq 0 ]; then
    # the stanza must come first: pacman resolves a name from the first repo that has it
    first="$(grep -nE '^(\[[a-z]+\]|Include = /etc/pacman.d/dram.conf)' "$PC" | grep -v ':\[options\]$' | head -1)"
    case "$first" in *dram.conf*) ok "inserted ($first)" ;; *) warn "Include landed after another repo: $first — move it by hand" ;; esac
  fi
fi

if [ "$MIGRATE" -eq 1 ]; then
  say "pacman -Sy (the [dram] database under its new name)"
  run pacman -Sy && ok "synced" || failed "pacman -Sy failed"
fi

say "Done."
[ "$DRY" -eq 1 ] && echo "  (dry run: nothing was changed)"
[ "$RC" -eq 0 ] || warn "a step failed above (exit 1) — fix it and re-run"
echo "  Next: dram update   (pacman -Syu now sees [dram]; pacman -Sl dram lists it)"
exit "$RC"

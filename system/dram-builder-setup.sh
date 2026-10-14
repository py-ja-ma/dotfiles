#!/usr/bin/env bash
# usage: dram-builder-setup.sh [--dry-run] [--refresh] [--migrate-from-rice]
#
# Makes cabin the build host for the [dram] package repo: installs
# packages/roles/builder.txt (devtools, diffoscope), creates the clean chroot
# /var/lib/archbuild/dram-x86_64 from devtools' own pacman.conf (official
# repos only; the chroot must never see [dram], or it would build against
# itself), creates the staging dir /srv/dram owned by the builder user, and
# PRINTS how to make the signing key as pj (`dram pkgs key --new`; it never
# generates a key itself). Root, idempotent.
# Afterwards: dram pkgs build && dram pkgs publish (as pj, not root).
#
#   --refresh       also `pacman -Syu` the existing chroot root (network-heavy;
#                   makechrootpkg -u already updates the working copy per build,
#                   so a plain re-run leaves the root alone)
#   --migrate-from-rice   the builder was set up under the [rice] name (until
#                   2026-10-06): mv /srv/rice to /srv/dram and rename rice.db* /
#                   rice.files* inside it to dram.* (signatures stay valid), mv the
#                   chroot /var/lib/archbuild/rice-x86_64 to dram-x86_64, add the
#                   "pj dram packages" uid to the signing key as the builder user
#                   and make it primary, re-export pkgs/dram.asc; prints the
#                   commit command. Then the normal steps.
#   -n, --dry-run   no root needed; print what would change
#   -h, --help      this text
#
# env: DRAM_BUILDER_HOST=<name>   allow a host other than cabin
#      DRAM_BUILDER_USER=<user>   default: the sudo caller, else pj
#
# exit: 0 ok · 1 not root, wrong host, or a step failed · 2 bad usage
# see: docs/toolchain/packaging/README.md

set -uo pipefail
DRY=0 MIGRATE=0 REFRESH=0 RC=0
for a in "$@"; do
  case "$a" in
    --dry-run | -n) DRY=1 ;;
    --refresh) REFRESH=1 ;;
    --migrate-from-rice) MIGRATE=1 ;;
    -h | --help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "usage: dram-builder-setup.sh [--dry-run] [--refresh] [--migrate-from-rice]" >&2
      exit 2
      ;;
  esac
done
[ "$(id -u)" -eq 0 ] || [ "$DRY" -eq 1 ] || {
  echo "Run with sudo: sudo bash $0 [--dry-run]"
  exit 1
}

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDER_HOST="${DRAM_BUILDER_HOST:-cabin}"
BUILDER_USER="${DRAM_BUILDER_USER:-${SUDO_USER:-pj}}"
CHROOT=/var/lib/archbuild/dram-x86_64
STAGE=/srv/dram
# devtools ships the configs its own extra-x86_64-build uses: official repos only.
PACCONF=/usr/share/devtools/pacman.conf.d/multilib.conf
MKCONF=/usr/share/devtools/makepkg.conf.d/x86_64.conf

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

HOST="$(cat /etc/hostname 2>/dev/null || hostname)"
[ "$HOST" = "$BUILDER_HOST" ] || die "this host is '$HOST'; the builder is '$BUILDER_HOST' (DRAM_BUILDER_HOST=$HOST to override — one builder, one key)"
id "$BUILDER_USER" >/dev/null 2>&1 || die "no such user: $BUILDER_USER"
BUILDER_GROUP="$(id -gn "$BUILDER_USER")"

# --- 0) --migrate-from-rice: the names of before 2026-10-06 ---------------------
# Same rename rule as system/pacman-dram-repo.sh: plain renames, re-pointed
# symlinks, signatures untouched. The user-level dirs (~/.config/rice -> dram)
# are the user's own `dram switch`; the signing key gets a second uid so the
# PACKAGER string in bin/pkgs.sh ("pj dram packages") matches a uid on it.
rename_repo_files() { # <dir>: rice.db* and rice.files* -> dram.db* / dram.files*
  local f base new target
  for f in "$1"/rice.db* "$1"/rice.files*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    base="$(basename "$f")"
    new="$1/dram${base#rice}"
    if [ -L "$f" ]; then
      target="$(readlink "$f")"
      # the link must belong to the builder: rsync (as $BUILDER_USER) re-sets its group on every publish/sync
      run ln -sfn "dram${target#rice}" "$new" && run chown -h "$BUILDER_USER:$BUILDER_GROUP" "$new" && run rm -f "$f" && ok "$base -> dram${base#rice} (link -> dram${target#rice})" \
        || failed "could not rename $base"
    else
      run mv -n "$f" "$new" && ok "$base -> dram${base#rice}" || failed "could not rename $base"
    fi
  done
}
as_builder() { # run a command as the builder user, with the tty for pinentry
  if [ "$DRY" -eq 1 ]; then
    printf '  \033[2m[dry-run] (as %s) %s\033[0m\n' "$BUILDER_USER" "$*"
  elif [ "$(id -un)" = "$BUILDER_USER" ]; then
    "$@"
  else runuser -u "$BUILDER_USER" -- env GPG_TTY="$(tty 2>/dev/null || true)" "$@"; fi
}
if [ "$MIGRATE" -eq 1 ]; then
  say "Migrating the builder from its [rice] names (until 2026-10-06) to [dram]"
  OLD_STAGE=/srv/rice OLD_CHROOT=/var/lib/archbuild/rice-x86_64
  if [ -d "$OLD_STAGE" ] && [ ! -e "$STAGE" ]; then
    run mv "$OLD_STAGE" "$STAGE" && ok "$OLD_STAGE -> $STAGE" || failed "could not move $OLD_STAGE"
    if [ "$DRY" -eq 1 ]; then rename_repo_files "$OLD_STAGE"; else rename_repo_files "$STAGE"; fi
  elif [ -d "$STAGE" ]; then
    ok "$STAGE already in place"
    rename_repo_files "$STAGE"
  else
    warn "neither $OLD_STAGE nor $STAGE exists — step 3 below creates $STAGE empty"
  fi
  if [ -d "$OLD_CHROOT" ] && [ ! -e "$CHROOT" ]; then
    run mv "$OLD_CHROOT" "$CHROOT" && ok "$OLD_CHROOT -> $CHROOT" || failed "could not move $OLD_CHROOT"
  elif [ -d "$CHROOT" ]; then ok "$CHROOT already in place"; else ok "no chroot yet — step 2 creates it"; fi
  MHOME="$(getent passwd "$BUILDER_USER" | cut -d: -f6)"
  MKEY=""
  for f in "$MHOME/.config/dram/gpgkey" "$MHOME/.config/rice/gpgkey"; do
    [ -s "$f" ] && MKEY="$(tr -d '[:space:]' <"$f")" && break
  done
  NEW_UID="pj dram packages <github.project@pseudoaddress.com>"
  if [ -z "$MKEY" ]; then
    warn "no signing key fingerprint in $MHOME/.config/{dram,rice}/gpgkey — skipping the gpg uid step"
  elif [ "$DRY" -eq 0 ] && as_builder gpg --batch --with-colons --list-keys "$MKEY" 2>/dev/null | grep -qF ":$NEW_UID:"; then
    ok "key $MKEY already carries the uid \"$NEW_UID\""
  else
    say "Signing key $MKEY: add the uid \"$NEW_UID\" and make it primary (as $BUILDER_USER; pinentry may ask for the passphrase)"
    if as_builder gpg --quick-add-uid "$MKEY" "$NEW_UID" && as_builder gpg --quick-set-primary-uid "$MKEY" "$NEW_UID"; then
      ok "uid added and primary"
    else
      failed "gpg refused (no pinentry under sudo?). Run as $BUILDER_USER, not root:"
      echo "    gpg --quick-add-uid $MKEY \"$NEW_UID\""
      echo "    gpg --quick-set-primary-uid $MKEY \"$NEW_UID\""
    fi
  fi
  if [ -n "$MKEY" ]; then
    say "Re-export the public key to pkgs/dram.asc (as $BUILDER_USER) and commit it"
    if [ "$DRY" -eq 1 ]; then
      as_builder sh -c "gpg --armor --export $MKEY > $REPO/pkgs/dram.asc"
    else
      as_builder sh -c "gpg --armor --export $MKEY > $REPO/pkgs/dram.asc" && ok "wrote pkgs/dram.asc" || failed "could not re-export pkgs/dram.asc"
    fi
    echo "    git -C $REPO commit -m 'pkgs: dram.asc — signing key re-exported with the dram uid' pkgs/dram.asc"
    echo "    then on every host (after a push): sudo bash system/pacman-dram-repo.sh   (pacman-key --add re-imports the new uid)"
  fi
fi

# --- 1) packages --------------------------------------------------------------
say "Builder packages (packages/roles/builder.txt)"
mapfile -t WANT < <(grep -vE '^[[:space:]]*(#|$)' "$REPO/packages/roles/builder.txt")
MISSING=()
for p in "${WANT[@]}"; do pacman -Qq "$p" >/dev/null 2>&1 || MISSING+=("$p"); done
if [ "${#MISSING[@]}" -gt 0 ]; then
  # -S without -y, as everywhere in system/: never a partial sync.
  run pacman -S --needed --noconfirm "${MISSING[@]}" && ok "installed: ${MISSING[*]}" \
    || failed "could not install ${MISSING[*]} — run 'dram update' first, then re-run"
else
  ok "all present: ${WANT[*]}"
fi

# --- 2) chroot ----------------------------------------------------------------
say "Clean chroot root: $CHROOT/root"
if [ ! -f "$PACCONF" ]; then
  warn "$PACCONF missing — falling back to extra.conf (no [multilib] in the chroot)"
  PACCONF=/usr/share/devtools/pacman.conf.d/extra.conf
fi
if [ -d "$CHROOT/root" ]; then
  if [ "$REFRESH" -eq 1 ]; then
    ok "root exists — refreshing it (arch-nspawn pacman -Syu) so makechrootpkg -u has little to do"
    run arch-nspawn "$CHROOT/root" pacman -Syu --noconfirm || failed "root refresh failed (offline?) — builds still work, -u updates the copy"
  else
    ok "root exists — left alone (makechrootpkg -u updates the working copy per build; --refresh to -Syu the root now)"
  fi
elif command -v mkarchroot >/dev/null 2>&1 || [ "$DRY" -eq 1 ]; then
  run install -d -m 755 "$CHROOT" || failed "could not create $CHROOT"
  # multilib-devel: lib32-* packages need the 32-bit fakeroot/gcc runtime in the
  # chroot; base-devel alone fails with "libfakeroot internal error" (2026-10-06)
  run mkarchroot -C "$PACCONF" -M "$MKCONF" "$CHROOT/root" base-devel multilib-devel && ok "mkarchroot done (official repos only, never [dram])" \
    || failed "mkarchroot failed — no clean chroot; builds cannot run"
else
  failed "mkarchroot not found — devtools did not install; re-run after 'dram update'"
fi

# --- 3) staging dir -----------------------------------------------------------
say "Staging dir: $STAGE (PKGDEST for makechrootpkg, repo-add runs here)"
if [ -d "$STAGE" ] && [ "$(stat -c %U "$STAGE")" = "$BUILDER_USER" ]; then
  ok "$STAGE owned by $BUILDER_USER"
else
  run install -d -m 755 -o "$BUILDER_USER" -g "$BUILDER_GROUP" "$STAGE" && ok "$STAGE created, owner $BUILDER_USER" || failed "could not create $STAGE"
fi
HOMEDIR="$(getent passwd "$BUILDER_USER" | cut -d: -f6)"
# as the user: `install -d -o` makes a MISSING parent (~/.config, ~/.cache on a fresh
# host, before Home Manager ever ran) root's, and Home Manager then cannot write there
# (cabin, 2026-10-11). A parent an earlier run made root's is handed back.
for p in "$HOMEDIR/.config" "$HOMEDIR/.cache"; do
  if [ -d "$p" ] && [ "$(stat -c %U "$p")" = root ]; then
    run chown "$BUILDER_USER:$BUILDER_GROUP" "$p" && ok "$p handed back to $BUILDER_USER"
  fi
done
for d in "$HOMEDIR/.config/dram" "$HOMEDIR/.cache/dram-pkgs"; do
  [ -d "$d" ] || run runuser -u "$BUILDER_USER" -- install -d -m 700 "$d" || failed "could not create $d"
done
ok "$HOMEDIR/.config/dram and ~/.cache/dram-pkgs present (gpgkey, peer, SRCDEST live there)"

# --- 4) signing key — printed, never generated here ---------------------------
say "Signing key"
KEYFILE="$HOMEDIR/.config/dram/gpgkey"
ASC="$REPO/pkgs/dram.asc"
if [ -s "$KEYFILE" ] && [ -f "$ASC" ]; then
  ok "fingerprint in $KEYFILE; public key committed at pkgs/dram.asc"
  ok "next: as $BUILDER_USER →  dram pkgs check && dram pkgs build && dram pkgs publish"
else
  [ -s "$KEYFILE" ] || warn "no $KEYFILE: this host has no signing key yet"
  [ -f "$ASC" ] || warn "no pkgs/dram.asc in the repo"
  cat <<EOF

  Make the key ONCE, as $BUILDER_USER (not root, not with sudo) — a fresh builder
  replaces whatever pkgs/dram.asc holds (handbook 07, "[dram] from scratch"):

    dram pkgs key --new

  It writes ~/.config/dram/gpgkey, exports pkgs/dram.asc and pins the fingerprint in
  system/pacman-dram-repo.sh, then prints the commit. Export the secret key to offline
  media and keep its passphrase in Proton Pass. Then on EVERY host (this one first):
    sudo bash ~/git/dotfiles/system/pacman-dram-repo.sh
EOF
fi

say "Done."
[ "$DRY" -eq 1 ] && echo "  (dry run: nothing was changed)"
[ "$RC" -eq 0 ] || warn "a step failed above (exit 1) — fix it and re-run"
echo "  makechrootpkg re-executes itself with sudo — expect one password prompt per build."
exit "$RC"

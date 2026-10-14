#!/usr/bin/env bash
# usage: pkgs.sh <check|update|build|publish|log|list|key> [args]
#
# Operates the [dram] package repo from ~/git/dotfiles on a host; `dram pkgs
# <cmd>` dispatches here. Every PKGBUILD under pkgs/ is reviewed, pinned and
# signed; `check` runs on the Mac too (pacman checks skipped).
#
#   check   [name...]     every pkgs/<name> is in the manifest at its .SRCINFO
#                         version, no official-repo name is shadowed (unless in
#                         pkgs/OVERRIDES), every source is pinned (no -git, no
#                         pkgver(), no SKIP outside a git checkout, no md5),
#                         .SRCINFO / UPSTREAM / REVIEW.md present, signing keys vendored
#   update  [name...]     clone the AUR repo, show `git diff <UPSTREAM>..HEAD`
#                         (PKGBUILD, *.install, hooks) in $PAGER; on `y` apply
#                         the AUR delta on top of our copy, show the PIN note,
#                         $EDITOR, updpkgsums, makepkg --printsrcinfo, rewrite
#                         UPSTREAM + manifest.txt, git commit
#   build   [name...]     makechrootpkg -c -u in /var/lib/archbuild/dram-x86_64,
#                         local build deps fed in with -I from /srv/dram, every
#                         package file detached-signed with the key in
#                         ~/.config/dram/gpgkey, line appended to pkgs/BUILDLOG
#   publish               repo-add -s -R into /srv/dram/dram.db, rsync to
#                         /var/lib/dram-repo on THIS host. The other host gets
#                         the repo from the Mac (bin/sync-dram-repo.sh): the
#                         hosts' ssh keys for each other are pinned to `borg
#                         serve`, so there is no host-to-host path (the old
#                         `--no-peer` flag is accepted and ignored; `sync` is gone)
#   log     <pkgfile...>  append "name version sha256 date" to pkgs/BUILDLOG
#   list    [--install|--repo]
#                         manifest names. --repo: minus pkgs/BUILD-ONLY (what a host
#                         can install from [dram]). --install: the every-host set,
#                         --repo minus the names a packages list claims (a [dram]
#                         name in packages/roles/gaming.txt installs with that role
#                         through dram apply, not on every host)
#   key     [--new|--uid] the signing key: its fingerprint, expiry and whether
#                         pkgs/dram.asc and system/pacman-dram-repo.sh agree with it.
#                         --new (the builder, as the user, once per key): gpg makes an
#                         ed25519 signing key (asks a passphrase), writes
#                         ~/.config/dram/gpgkey, exports pkgs/dram.asc and pins its
#                         fingerprint in system/pacman-dram-repo.sh — one commit.
#                         --uid (the builder, as the user): gives the key this
#                         script's user ID, revokes its others and exports
#                         pkgs/dram.asc with that one (the same key: hosts keep it)
#   -h, --help            this text
#
# env: DRAM_GPGKEY    signing key fingerprint (else ~/.config/dram/gpgkey)
#      PACKAGER       makepkg PACKAGER; also PAGER, EDITOR
#
# exit: 0 ok · 1 a check or step failed · 2 bad usage
# see: docs/toolchain/packaging/README.md

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKGS="$REPO/pkgs"
REPO_NAME=dram # the pacman section [dram]; the database is $STAGE/$REPO_NAME.db (rice until 2026-10-06)
CHROOT=/var/lib/archbuild/dram-x86_64
STAGE=/srv/dram
LOCAL_REPO=/var/lib/dram-repo
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/dram-pkgs"
OFFICIAL_REPOS="${DRAM_OFFICIAL_REPOS:-core extra multilib}"
# the signing key's one user ID, and the packager string every package carries
KEY_UID="pj dram packages <github.project@pseudoaddress.com>"
PACKAGER="${PACKAGER:-$KEY_UID}"

say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }
ask() { # ask "question" -> 0 for yes; non-interactive = no
  local a
  [ -t 0 ] || return 1
  read -rp "  $1 [y/N] " a
  case "$a" in y | Y) return 0 ;; *) return 1 ;; esac
}
# lines_into <array-name> < input — mapfile for the Mac's bash 3.2 (dram pkgs check runs there)
lines_into() {
  local _line
  eval "$1=()"
  while IFS= read -r _line; do eval "$1+=(\"\$_line\")"; done
}

# --- helpers ------------------------------------------------------------------
manifest_names() { grep -vE '^[[:space:]]*(#|$)' "$PKGS/manifest.txt" | cut -d= -f1; }
manifest_version() { grep -E "^$1=" "$PKGS/manifest.txt" | head -1 | cut -d= -f2; }
build_only_names() { grep -vE '^[[:space:]]*(#|$)' "$PKGS/BUILD-ONLY" 2>/dev/null || true; }
override_names() { grep -vE '^[[:space:]]*(#|$)' "$PKGS/OVERRIDES" 2>/dev/null || true; }
names_from_args() { if [ $# -gt 0 ]; then printf '%s\n' "$@"; else manifest_names; fi; }
pkgdir_of() { # <name> -> the pkgs/ directory that builds it: its own, or the split pkgbase whose .SRCINFO lists it
  local d
  if [ -d "$PKGS/$1" ]; then
    printf '%s\n' "$1"
    return 0
  fi
  for d in "$PKGS"/*/; do
    [ -f "$d.SRCINFO" ] || continue
    if grep -qx "pkgname = $1" "$d.SRCINFO"; then
      basename "$d"
      return 0
    fi
  done
  return 1
}
srcinfo_get() { # <name> <key>  -> values, one per line (tab-indented .SRCINFO keys)
  local d
  d="$(pkgdir_of "$1")" || return 0
  # pkgbase keys are tab-indented; `pkgname = …` lines sit at column 0 (split
  # packages have several) — match both, or nothing is ever signed/-I'd
  sed -n "s/^[[:space:]]*$2 = //p" "$PKGS/$d/.SRCINFO"
}
srcinfo_version() { # <name> -> [epoch:]pkgver-pkgrel
  local e v r
  e="$(srcinfo_get "$1" epoch)"
  v="$(srcinfo_get "$1" pkgver)"
  r="$(srcinfo_get "$1" pkgrel)"
  printf '%s%s-%s\n' "${e:+$e:}" "$v" "$r"
}
local_deps() { # <name> -> depends/makedepends that are themselves in the manifest (not its own split siblings)
  local all self d
  all="$(manifest_names)"
  self="$(pkgdir_of "$1")"
  {
    srcinfo_get "$1" depends
    srcinfo_get "$1" makedepends
  } \
    | sed 's/[<>=].*//' | sort -u | grep -xF -f <(echo "$all") \
    | while IFS= read -r d; do [ "$(pkgdir_of "$d")" = "$self" ] || printf '%s\n' "$d"; done
  return 0
}
gpgkey() {
  local k="${DRAM_GPGKEY:-}"
  [ -n "$k" ] || k="$(tr -d '[:space:]' <"$HOME/.config/dram/gpgkey" 2>/dev/null || true)"
  printf '%s' "$k"
}
stage_pkgfiles() { # <name> -> every /srv/dram/<name>-<version>-<arch>.pkg.tar.zst
  local v
  v="$(srcinfo_version "$1")"
  ls "$STAGE/$1-$v-"*.pkg.tar.zst 2>/dev/null || true
}

# --- check ----------------------------------------------------------------------
cmd_check() {
  local fail=0 names n dir v mv official="" overrides
  names="$(names_from_args "$@")"
  overrides="$(override_names)"
  say "pkgs/: manifest <-> directories"
  for n in $names; do
    [ -d "$PKGS/$n" ] && continue
    if dir="$(pkgdir_of "$n")"; then
      # a split package: built by pkgs/<pkgbase>, listed in the manifest under its own name
      v="$(srcinfo_version "$n")"
      mv="$(manifest_version "$n")"
      if [ "$v" = "$mv" ]; then ok "$n: split package of pkgs/$dir, version $v (manifest agrees)"; else
        warn "$n: split package of pkgs/$dir at $v, manifest says ${mv:-<none>}"
        fail=1
      fi
    else
      warn "$n: no pkgs/$n directory (and no pkgs/*/.SRCINFO lists it as a split pkgname)"
      fail=1
    fi
  done
  for dir in "$PKGS"/*/; do
    n="$(basename "$dir")"
    grep -qE "^$n=" "$PKGS/manifest.txt" || {
      warn "pkgs/$n exists but is not in pkgs/manifest.txt"
      fail=1
    }
    # every pkgname a split PKGBUILD produces must be in the manifest too (it gets published)
    for v in $(srcinfo_get "$n" pkgname); do
      grep -qE "^$v=" "$PKGS/manifest.txt" || {
        warn "pkgs/$n builds $v, which is not in pkgs/manifest.txt"
        fail=1
      }
    done
  done
  if have pacman; then
    official="$(for r in $OFFICIAL_REPOS; do pacman -Slq "$r" 2>/dev/null; done | sort -u)"
    [ -n "$official" ] || warn "pacman -Slq returned nothing (no sync DB?) — shadowing check skipped"
  else
    warn "no pacman here — official-repo shadowing check skipped (run dram pkgs check on a host)"
  fi
  for n in $names; do
    dir="$PKGS/$n"
    [ -d "$dir" ] || continue
    say "$n"
    for f in PKGBUILD .SRCINFO UPSTREAM REVIEW.md; do
      [ -f "$dir/$f" ] || {
        warn "$n: missing $f"
        fail=1
      }
    done
    [ -f "$dir/.SRCINFO" ] || continue
    if ! bash -n "$dir/PKGBUILD" 2>/dev/null; then
      warn "$n: PKGBUILD is not valid bash"
      fail=1
    fi
    v="$(srcinfo_version "$n")"
    mv="$(manifest_version "$n")"
    if [ "$v" = "$mv" ]; then ok "version $v (manifest agrees)"; else
      warn "$n: .SRCINFO says $v, manifest says ${mv:-<none>}"
      fail=1
    fi
    if ! grep -qE '^(aur:[A-Za-z0-9@._+-]+|arch:[A-Za-z0-9@._+/-]+|own:[^ ]+) [0-9a-f]{40} [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$dir/UPSTREAM" 2>/dev/null; then
      warn "$n: UPSTREAM must be 'aur:<pkgbase> <40-hex sha> <YYYY-MM-DD>' (or arch:<gitlab path> …, own:…)"
      fail=1
    fi
    # names: no -git, no pkgver() (VCS-style floating version)
    if echo "$overrides" | grep -qx "$n"; then
      warn "$n is in pkgs/OVERRIDES — shadowing/-git rules waived (reason must be in REVIEW.md)"
    else
      case "$n" in *-git | *-hg | *-svn | *-bzr)
        warn "$n: VCS package name — not allowed (pin a release)"
        fail=1
        ;;
      esac
      if grep -qE '^pkgver\(\)' "$dir/PKGBUILD"; then
        warn "$n: has a pkgver() function — floating version"
        fail=1
      fi
      # every name this directory produces (split packages included)
      for v in $(srcinfo_get "$n" pkgname); do
        if [ -n "$official" ] && echo "$official" | grep -qx "$v"; then
          warn "$n: an official-repo package is named $v ([dram] would shadow it) — refuse unless in pkgs/OVERRIDES"
          fail=1
        fi
      done
    fi
    # sources vs sums, in .SRCINFO order
    if grep -q '^	md5sums' "$dir/.SRCINFO"; then
      warn "$n: md5sums — use sha256/sha512/b2"
      fail=1
    fi
    local -a srcs=() sums=()
    # -E: BSD sed (the Mac) has no \? or \| in basic regexes
    lines_into srcs < <(sed -E -n 's/^	source(_[a-z0-9_]+)? = //p' "$dir/.SRCINFO")
    lines_into sums < <(sed -E -n 's/^	(sha256sums|sha512sums|b2sums|sha384sums)(_[a-z0-9_]+)? = //p' "$dir/.SRCINFO")
    [ "${#srcs[@]}" -eq "${#sums[@]}" ] || {
      warn "$n: ${#srcs[@]} sources but ${#sums[@]} checksums in .SRCINFO"
      fail=1
    }
    local i s c
    for i in "${!srcs[@]}"; do
      s="${srcs[$i]}"
      c="${sums[$i]:-}"
      case "$s" in
        *git+* | git://*)
          if [[ "$s" != *"#commit="* && "$s" != *"#tag="* ]]; then
            warn "$n: git source not pinned (#commit= or #tag=): $s"
            fail=1
          fi
          ;;
        *.sig | *.sig::* | *.asc | *.asc::* | *.sign | *.sign::*)
          # a detached signature: makepkg verifies it against validpgpkeys, so SKIP is
          # the convention — but only when there IS a validpgpkeys line
          if [ "$c" = SKIP ] && [ -z "$(srcinfo_get "$n" validpgpkeys)" ]; then
            warn "$n: SKIP on $s but no validpgpkeys"
            fail=1
          fi
          ;;
        *://* | *::*)
          if [ -z "$c" ] || [ "$c" = SKIP ]; then
            warn "$n: SKIP/missing checksum on a non-git download: $s"
            fail=1
          fi
          ;;
        *) # local file next to the PKGBUILD
          [ -f "$dir/$s" ] || {
            warn "$n: local source $s missing"
            fail=1
          }
          if [ -z "$c" ] || [ "$c" = SKIP ]; then
            warn "$n: SKIP checksum on local file $s"
            fail=1
          fi
          ;;
      esac
    done
    # signing keys vendored for the chroot
    local k
    for k in $(srcinfo_get "$n" validpgpkeys); do
      [ -f "$dir/keys/pgp/$k.asc" ] || {
        warn "$n: validpgpkeys $k has no pkgs/$n/keys/pgp/$k.asc (chroot cannot fetch it)"
        fail=1
      }
    done
    [ "$fail" -eq 0 ] && ok "pinned: ${#srcs[@]} source(s)"
  done
  echo
  if [ "$fail" -eq 0 ]; then ok "pkgs check passed"; else die "pkgs check failed"; fi
}

# --- update ------------------------------------------------------------------------
cmd_update() {
  have git || die "git missing"
  local n p kind sha date base dir head f newver merged delta seen=""
  for n in $(names_from_args "$@"); do
    n="$(pkgdir_of "$n")" || die "$n: no pkgs/$n directory"
    case " $seen " in *" $n "*) continue ;; esac # a split pkgbase, already handled
    seen="$seen $n"
    [ -f "$PKGS/$n/UPSTREAM" ] || die "$n: no pkgs/$n/UPSTREAM"
    read -r kind sha date <"$PKGS/$n/UPSTREAM"
    case "$kind" in
      aur:*) base="${kind#aur:}" ;;
      arch:*)
        warn "$n: vendored from Arch's packaging repo ${kind#arch:} @${sha:0:7} ($date), no AUR to track — bump by hand, see pkgs/$n/PIN"
        continue
        ;;
      *)
        warn "$n: $kind (vendored $date) is not an AUR package — bump by hand, see pkgs/$n/PIN"
        continue
        ;;
    esac
    dir="$CACHE/aur/$base"
    mkdir -p "$CACHE/aur"
    if [ -d "$dir/.git" ]; then
      git -C "$dir" fetch -q origin && git -C "$dir" reset -q --hard origin/HEAD || die "$n: fetch of AUR $base failed"
    else
      # full clone: AUR repos are tiny and the diff needs the recorded commit
      git clone -q "https://aur.archlinux.org/$base.git" "$dir" || die "$n: clone of AUR $base failed"
    fi
    head="$(git -C "$dir" rev-parse HEAD)"
    if [ "$head" = "$sha" ]; then
      ok "$n: AUR $base unchanged since ${sha:0:7} ($date)"
      continue
    fi
    git -C "$dir" cat-file -e "$sha" 2>/dev/null || die "$n: recorded commit $sha is not in AUR $base history (rewritten? look at it by hand)"
    say "$n: AUR $base moved ${sha:0:7} ($date) -> ${head:0:7} ($(git -C "$dir" log -1 --format=%cs "$head"))"
    git -C "$dir" log --format='    %h %as %an  %s' "$sha..$head"
    {
      git -C "$dir" diff --stat "$sha" "$head"
      echo
      git -C "$dir" diff "$sha" "$head" -- PKGBUILD '*.install' '*.hook' '*.sh' '*.desktop' '*.patch' '*.diff'
    } | "${PAGER:-less}"
    if ! ask "Merge the AUR changes into pkgs/$n?"; then
      warn "$n: skipped"
      continue
    fi
    merged=1
    # PKGBUILD: apply the AUR delta on top of OUR copy (we carry local edits); on
    # conflict keep the AUR HEAD next to it and let the operator merge
    delta="$(git -C "$dir" diff "$sha" "$head" -- PKGBUILD)"
    if [ -z "$delta" ]; then
      ok "PKGBUILD: unchanged in the AUR (only other files moved)"
    elif printf '%s\n' "$delta" | patch -p1 -s -d "$PKGS/$n" --no-backup-if-mismatch; then
      ok "PKGBUILD: AUR delta applied on top of ours"
    else
      git -C "$dir" show "$head:PKGBUILD" >"$PKGS/$n/PKGBUILD.aur"
      warn "PKGBUILD: delta did not apply cleanly — AUR HEAD saved as pkgs/$n/PKGBUILD.aur (*.rej next to it); merge by hand"
      merged=0
    fi
    # every other file the AUR changed: copy when ours is still the vendored version
    for f in $(git -C "$dir" diff --name-only "$sha" "$head" | grep -vE '^(PKGBUILD|\.SRCINFO|\.gitignore|\.nvchecker\.toml)$'); do
      if ! git -C "$dir" cat-file -e "$head:$f" 2>/dev/null; then
        if [ -e "$PKGS/$n/$f" ]; then warn "$f: deleted in the AUR — remove pkgs/$n/$f yourself if we no longer need it"; fi
        continue
      fi
      if [ ! -e "$PKGS/$n/$f" ] || git -C "$dir" show "$sha:$f" 2>/dev/null | cmp -s - "$PKGS/$n/$f"; then
        mkdir -p "$(dirname "$PKGS/$n/$f")"
        git -C "$dir" show "$head:$f" >"$PKGS/$n/$f" && ok "copied $f"
      else
        git -C "$dir" show "$head:$f" >"$PKGS/$n/$f.aur"
        warn "$f: ours differs from what we vendored — AUR copy saved as $f.aur"
        merged=0
      fi
    done
    if [ -f "$PKGS/$n/PIN" ]; then
      say "re-pin note (pkgs/$n/PIN)"
      sed 's/^/    /' "$PKGS/$n/PIN"
    fi
    if [ -f "$PKGS/$n/PIN" ] || [ "$merged" -eq 0 ]; then
      if ask "Open pkgs/$n/PKGBUILD in ${EDITOR:-vi} now?"; then "${EDITOR:-vi}" "$PKGS/$n/PKGBUILD"; fi
    fi
    [ -f "$PKGS/$n/PKGBUILD.aur" ] && die "$n: pkgs/$n/PKGBUILD.aur still present — finish the merge, delete it, then re-run"
    have updpkgsums || die "updpkgsums missing (pacman-contrib)"
    (cd "$PKGS/$n" && updpkgsums) || die "$n: updpkgsums failed"
    (cd "$PKGS/$n" && makepkg --printsrcinfo >.SRCINFO) || die "$n: makepkg --printsrcinfo failed"
    printf 'aur:%s %s %s\n' "$base" "$head" "$(git -C "$dir" log -1 --format=%cs "$head")" >"$PKGS/$n/UPSTREAM"
    newver="$(srcinfo_version "$n")"
    # every pkgname the directory builds: a split pkgbase has several manifest lines
    for p in $(srcinfo_get "$n" pkgname); do
      sed -i "s|^$p=.*|$p=$newver|" "$PKGS/manifest.txt"
    done
    # subshell: cmd_check dies itself, the tailored message would never print otherwise
    (cmd_check "$n") || die "$n: check failed after the merge — fix before committing"
    git -C "$REPO" add "pkgs/$n" pkgs/manifest.txt
    git -C "$REPO" commit -q -m "pkgs/$n: sync with AUR $base @${head:0:7} ($newver)" \
      && ok "$n: committed — review REVIEW.md if the build/install behaviour changed, then dram pkgs build $n"
  done
}

# --- build -----------------------------------------------------------------------------
order_with_deps() { # names… -> pkgs/ directories with local deps first, no duplicates (split names → their pkgbase)
  local -a out=()
  local n
  _visit() {
    local x y d
    x="$(pkgdir_of "$1")" || die "$1: no pkgs/$1 directory"
    # ${out[@]+…}: an empty array is "unbound" under set -u on the Mac's bash 3.2
    for y in ${out[@]+"${out[@]}"}; do [ "$y" = "$x" ] && return 0; done
    for d in $(local_deps "$x"); do _visit "$d"; done
    out+=("$x")
  }
  for n in "$@"; do _visit "$n"; done
  [ -n "${out[*]+x}" ] && printf '%s\n' "${out[@]}"
  return 0
}
dep_closure() { # <dir> -> every [dram] package it needs in the chroot, transitively, deps first
  local n="$1" d
  for d in $(local_deps "$n"); do order_with_deps "$d"; done | awk '!seen[$0]++' | grep -vx "$n" || true
}
cmd_build() {
  have makechrootpkg || die "devtools not installed — sudo bash system/dram-builder-setup.sh"
  [ -d "$CHROOT/root" ] || die "no chroot at $CHROOT — sudo bash system/dram-builder-setup.sh"
  [ -d "$STAGE" ] && [ -w "$STAGE" ] || die "$STAGE missing or not writable by $USER — sudo bash system/dram-builder-setup.sh"
  local key n d f before
  key="$(gpgkey)"
  [ -n "$key" ] || die "no signing key in ~/.config/dram/gpgkey — a fresh builder: dram pkgs key --new (handbook 07); an exported key: gpg --import, then its fingerprint into that file"
  gpg --batch --list-secret-keys "$key" >/dev/null 2>&1 || die "no secret key $key in ~/.gnupg"
  mkdir -p "$CACHE/src" "$CACHE/log"
  local -a names=()
  if [ $# -gt 0 ]; then
    lines_into names < <(order_with_deps "$@")
  else
    # shellcheck disable=SC2046 # manifest names are single tokens
    lines_into names < <(order_with_deps $(manifest_names))
  fi
  [ "${#names[@]}" -gt 0 ] || die "nothing to build"
  say "build order: ${names[*]}"
  local p
  for n in "${names[@]}"; do
    (cmd_check "$n" >/dev/null) || die "$n: dram pkgs check fails — not building" # subshell: cmd_check dies itself
    # every [dram] dependency, transitively (pacman -U inside the chroot must see
    # the whole chain: lib32-libcap needs lib32-pam needs lib32-audit …)
    local -a I=()
    for d in $(dep_closure "$n"); do
      for p in $(srcinfo_get "$d" pkgname); do
        f="$(stage_pkgfiles "$p" | head -1)"
        [ -n "$f" ] || die "$n needs $p from $STAGE — build it first (dram pkgs build $d)"
        I+=(-I "$f")
      done
    done
    # Upstream signing keys travel with the PKGBUILD (keys/pgp/<fpr>.asc). makepkg
    # only honours them for some source kinds; import them into our keyring, which
    # makechrootpkg mounts into the chroot — idempotent, fingerprints are what
    # validpgpkeys checks.
    if compgen -G "$PKGS/$n/keys/pgp/*.asc" >/dev/null; then
      gpg --batch --quiet --import "$PKGS/$n"/keys/pgp/*.asc 2>/dev/null || warn "$n: key import failed (gpg)"
    fi
    say "building $n in $CHROOT (clean copy, updated)${I:+ with ${#I[@]} local dep file(s)}"
    before=""
    for p in $(srcinfo_get "$n" pkgname); do before="$before$(stage_pkgfiles "$p")"$'\n'; done
    # PKGDEST: a caller's value wins (bin/repro.sh builds into a scratch dir); default /srv/dram.
    # SRCDEST per package: makepkg reuses a cached source by FILE NAME, and eleven of ours
    # name one "LICENSE" — a shared cache handed xenia-canary another project's (2026-10-11)
    mkdir -p "$CACHE/src/$n" "$CACHE/log"
    (cd "$PKGS/$n" \
      && PKGDEST="${PKGDEST:-$STAGE}" SRCDEST="$CACHE/src/$n" LOGDEST="$CACHE/log" PACKAGER="$PACKAGER" \
        makechrootpkg -c -u -r "$CHROOT" "${I[@]}") || die "$n: makechrootpkg failed (logs in $CACHE/log)"
    # makepkg's debug split packages are noise for a desktop repo and would be
    # unsigned; drop them before signing so publish never trips on them.
    for p in $(srcinfo_get "$n" pkgname); do rm -f "$STAGE/$p"-debug-*.pkg.tar.zst "$STAGE/$p"-debug-*.pkg.tar.zst.sig; done
    for f in $(for p in $(srcinfo_get "$n" pkgname); do stage_pkgfiles "$p"; done); do
      if echo "$before" | grep -qxF "$f" && [ -f "$f.sig" ] && [ "$f.sig" -nt "$f" ]; then
        # already signed before this run: still record it — BUILDLOG is the provenance
        # record every published file must have (this skip is how four went missing)
        cmd_log "$f"
        continue
      fi
      rm -f "$f.sig"
      gpg --batch --yes --detach-sign --local-user "$key" --output "$f.sig" "$f" || die "signing $f failed"
      ok "signed ${f##*/}"
      cmd_log "$f"
    done
  done
  echo
  ok "built: ${names[*]}"
  echo "  next: dram pkgs publish"
}

# --- publish -------------------------------------------------------------------------------
cmd_publish() {
  local key f
  case "${1:-}" in
    "" | --no-peer) ;; # --no-peer: the old default path; accepted for muscle memory, nothing else to do
    *) die "usage: dram pkgs publish" ;;
  esac
  have repo-add || die "repo-add missing (pacman)"
  have rsync || die "rsync missing"
  key="$(gpgkey)"
  [ -n "$key" ] || die "no signing key in ~/.config/dram/gpgkey"
  shopt -s nullglob
  local -a files=("$STAGE"/*.pkg.tar.zst)
  shopt -u nullglob
  [ "${#files[@]}" -gt 0 ] || die "nothing in $STAGE — dram pkgs build first"
  for f in "${files[@]}"; do [ -f "$f.sig" ] || die "unsigned package: $f (dram pkgs build signs; or gpg --detach-sign --local-user $key $f)"; done
  say "repo-add -s -R → $STAGE/$REPO_NAME.db.tar.zst (${#files[@]} packages)"
  repo-add -s -k "$key" -R -p "$STAGE/$REPO_NAME.db.tar.zst" "${files[@]}" || die "repo-add failed"
  say "rsync → $LOCAL_REPO (this host)"
  [ -w "$LOCAL_REPO" ] || die "$LOCAL_REPO not writable — sudo bash system/pacman-dram-repo.sh"
  rsync -a --delete "$STAGE/" "$LOCAL_REPO/" || die "local rsync failed"
  ok "$LOCAL_REPO updated"
  echo "  next: from the Mac, bin/sync-dram-repo.sh (carries /srv/dram to the other host);"
  echo "        then dram update on each host (pacman -Syu installs from [dram]; pacman -Sl dram lists it)"
  echo "        first time only: sudo bash system/pacman-dram-repo.sh adds the Include once dram.db exists"
}

# --- log -------------------------------------------------------------------------------------
cmd_log() {
  local f b arch rest rel ver name sum line
  [ $# -gt 0 ] || die "usage: dram pkgs log <pkgfile…>"
  for f in "$@"; do
    [ -f "$f" ] || die "no such file: $f"
    b="${f##*/}"
    b="${b%.pkg.tar.*}"
    arch="${b##*-}"
    rest="${b%-*}"
    rel="${rest##*-}"
    rest="${rest%-*}"
    ver="${rest##*-}"
    name="${rest%-*}"
    sum="$(sha256sum "$f" | cut -d' ' -f1)"
    line="$name $ver-$rel $sum $(date -u +%F)"
    if grep -qF "$name $ver-$rel $sum" "$PKGS/BUILDLOG" 2>/dev/null; then
      ok "BUILDLOG already has $name $ver-$rel with this sha256 ($arch)"
    else
      # same name+version, other hash = a rebuild under the same pkgrel. pacman upgrades
      # by version, so a host that installed the first build never gets this one.
      if awk -v n="$name" -v v="$ver-$rel" '$1 == n && $2 == v { f = 1 } END { exit !f }' "$PKGS/BUILDLOG" 2>/dev/null; then
        warn "BUILDLOG already has $name $ver-$rel with a DIFFERENT sha256 — same version, different build: bump pkgrel and rebuild (appending anyway)"
      fi
      echo "$line" >>"$PKGS/BUILDLOG" && ok "BUILDLOG += $line"
    fi
  done
}

# --- list ---------------------------------------------------------------------------------------
claimed_names() { # [dram] names that a packages list (base, hardware, role, host) declares
  cat "$REPO"/packages/*.txt "$REPO"/packages/roles/*.txt 2>/dev/null | grep -vE '^[[:space:]]*(#|$)' | awk '{print $1}'
}
cmd_list() {
  case "${1:-}" in
    --repo)
      manifest_names | grep -vxF -f <(
        build_only_names
        echo __none__
      )
      ;;
    --install)
      cmd_list --repo | grep -vxF -f <(
        claimed_names
        echo __none__
      )
      ;;
    *) manifest_names ;;
  esac
}

# --- key ----------------------------------------------------------------------------------------
# The fingerprint pacman-dram-repo.sh pins (EXPECTED_FPR=…): it refuses to lsign any other key,
# so the public key, the pin and the builder's gpgkey file change together, in one commit.
PINFILE="$REPO/system/pacman-dram-repo.sh"
pinned_fpr() { sed -n 's/^EXPECTED_FPR=\([0-9A-F]\{40\}\)$/\1/p' "$PINFILE"; }
asc_fpr() { gpg --batch --with-colons --import-options show-only --import "$PKGS/dram.asc" 2>/dev/null | awk -F: '$1=="fpr"{print $10; exit}'; }
cmd_key() {
  local cfg="$HOME/.config/dram/gpgkey" fpr uid
  case "${1:-}" in
    "")
      fpr="${DRAM_GPGKEY:-$(cat "$cfg" 2>/dev/null)}"
      echo "    pinned (system/pacman-dram-repo.sh): $(pinned_fpr)"
      echo "    pkgs/dram.asc:                       $(asc_fpr)"
      echo "    this host signs with (gpgkey):       ${fpr:-none}"
      [ "$(pinned_fpr)" = "$(asc_fpr)" ] && ok "pkgs/dram.asc is the pinned key" || warn "pkgs/dram.asc is not the pinned key — hosts refuse it"
      if [ -n "$fpr" ]; then
        if gpg --batch --list-secret-keys "$fpr" >/dev/null 2>&1; then
          ok "the secret key is here (expires $(gpg --batch --with-colons --list-keys "$fpr" | awk -F: '$1=="pub"{print $7; exit}' | xargs -r -I{} date -d @{} +%F 2>/dev/null || echo never))"
        else warn "no secret key $fpr in this user's gpg: this host cannot sign"; fi
      fi
      return 0
      ;;
    --uid)
      [ "$(id -u)" -ne 0 ] || die "as your user, never with sudo: the key lives in your ~/.gnupg"
      fpr="${DRAM_GPGKEY:-$(cat "$cfg" 2>/dev/null)}"
      [ -n "$fpr" ] && gpg --batch --list-secret-keys "$fpr" >/dev/null 2>&1 || die "no secret signing key here (~/.config/dram/gpgkey): on the builder"
      [ "$fpr" = "$(pinned_fpr)" ] || die "$fpr is not the pinned key $(pinned_fpr)"
      [ -z "$(git -C "$REPO" status --porcelain -- pkgs/dram.asc)" ] || die "pkgs/dram.asc has uncommitted changes — commit or restore it first"
      uid_list() { gpg --batch --with-colons --list-keys "$fpr" | awk -F: '$1 == "uid" && $2 != "r" { print $10 }'; }
      if ! uid_list | grep -qxF "$KEY_UID"; then
        say "the user ID \"$KEY_UID\" — gpg asks for the key's passphrase (Proton Pass)"
        gpg --quick-add-uid "$fpr" "$KEY_UID" || die "gpg --quick-add-uid failed"
      fi
      gpg --quick-set-primary-uid "$fpr" "$KEY_UID" || die "gpg --quick-set-primary-uid failed"
      uid_list | grep -vxF "$KEY_UID" | while IFS= read -r uid; do
        gpg --quick-revoke-uid "$fpr" "$uid" && ok "revoked \"$uid\"" || warn "could not revoke \"$uid\""
      done
      # only the current user ID leaves this machine: the revoked ones stay in this keyring
      uid="${KEY_UID##*<}"
      gpg --armor --export --export-options export-clean --export-filter "keep-uid=mbox = ${uid%>}" "$fpr" >"$PKGS/dram.asc" \
        || die "could not export the public key"
      [ "$(asc_fpr)" = "$fpr" ] || die "pkgs/dram.asc does not show $fpr — check it by hand"
      gpg --batch --with-colons --import-options show-only --import "$PKGS/dram.asc" 2>/dev/null | awk -F: '$1 == "uid" { print "    user ID: " $10 }'
      ok "pkgs/dram.asc: $fpr with its one user ID"
      echo "    commit it:   git -C $REPO commit -m 'pkgs: dram.asc carries the key's new user ID' pkgs/dram.asc"
      echo "    the hosts re-import it at their next dram apply (system/pacman-dram-repo.sh)"
      return 0
      ;;
    --new) ;;
    *)
      echo "usage: pkgs.sh key [--new|--uid]" >&2
      return 2
      ;;
  esac
  [ "$(id -u)" -ne 0 ] || die "as your user, never with sudo: the key lives in your ~/.gnupg"
  have gpg || die "gpg not installed"
  [ -z "$(git -C "$REPO" status --porcelain -- pkgs/dram.asc "$PINFILE")" ] || die "pkgs/dram.asc or the pin has uncommitted changes — commit or restore them first"
  uid="$KEY_UID"
  say "a new ed25519 signing key, 2 years ($uid) — gpg asks for its passphrase (Proton Pass)"
  gpg --quick-gen-key "$uid" ed25519 sign 2y || die "gpg --quick-gen-key failed"
  fpr="$(gpg --batch --with-colons --list-secret-keys "$uid" | awk -F: '$1=="fpr"{f=$10} END{print f}')"
  [[ $fpr =~ ^[0-9A-F]{40}$ ]] || die "could not read the new key's fingerprint"
  mkdir -p "$(dirname "$cfg")" && printf '%s\n' "$fpr" >"$cfg"
  gpg --armor --export "$fpr" >"$PKGS/dram.asc" || die "could not export the public key"
  sed -i "s/^EXPECTED_FPR=[0-9A-F]\{40\}\$/EXPECTED_FPR=$fpr/" "$PINFILE" || die "could not pin $fpr in $PINFILE"
  [ "$(pinned_fpr)" = "$fpr" ] && [ "$(asc_fpr)" = "$fpr" ] || die "the pin or pkgs/dram.asc does not show $fpr — check them by hand"
  ok "key $fpr: ~/.config/dram/gpgkey, pkgs/dram.asc, the pin in system/pacman-dram-repo.sh"
  echo "    commit it:   git -C $REPO commit -m 'pkgs: a new dram signing key' pkgs/dram.asc system/pacman-dram-repo.sh"
  echo "    keep it:     gpg --armor --export-secret-keys $fpr > <offline media>; the passphrase in Proton Pass"
  echo "    then:        sudo bash $PINFILE   (swaps the trusted key here), dram pkgs build, dram pkgs publish"
}

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }

cmd="${1:-help}"
[ $# -gt 0 ] && shift
case "$cmd" in
  check) cmd_check "$@" ;;
  update) cmd_update "$@" ;;
  build) cmd_build "$@" ;;
  publish) cmd_publish "$@" ;;
  log) cmd_log "$@" ;;
  list) cmd_list "$@" ;;
  key) cmd_key "$@" ;;
  help | -h | --help) usage ;;
  *)
    warn "unknown command: $cmd"
    usage
    exit 2
    ;;
esac

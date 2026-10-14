#!/usr/bin/env bash
# usage: repro.sh [-n|--dry-run] [pkg ...] | --ours <name|file.pkg.tar.zst>
#
# Reproducibility spot-check; runs on an Arch host. Without --ours it rebuilds
# official packages in a clean container (archlinux-repro: `repro <file>`) and
# reports reproducible / NOT reproducible per package; the default set is
# linux linux-lts hyprland openssh sudo systemd pacman (the kernel, the
# compositor, the remote door, the privilege boundary, init, the package
# manager). --ours <name> builds the vendored pkgs/<name> twice with the same
# SOURCE_DATE_EPOCH and diffoscopes the outputs; --ours <file.pkg.tar.zst>
# rebuilds the package that file came from once (its .BUILDINFO builddate
# becomes SOURCE_DATE_EPOCH) and diffoscopes the rebuild against the file — or,
# when every package in the file's build chroot was official, hands it to
# `repro -f` run from pkgs/<name> (-f = use the local PKGBUILD) for an
# independent rebuild from the Arch archive. Logs: ~/.local/state/dram/repro/.
#
#   pkg ...            official packages to check (default: the set above)
#   --ours TARGET      a vendored package name, or a .pkg.tar.zst file
#   -n, --dry-run      print the commands, run nothing
#   -h, --help         this text
#
# needs:  an Arch host, archlinux-repro, sudo (systemd-nspawn); diffoscope and devtools for --ours
# alone:  yes on Arch for official packages; --ours wants a pkgs/<name>/ recipe layout
# here:   by hand, monthly and after an update to the kernel, Hyprland, openssh, sudo,
#         systemd or pacman; logs in ~/.local/state/dram/repro/
# exit:   0 all reproducible · 1 one was not, or a build failed (repro exits 1 for both) · 2 bad usage
# see:    docs/security/software-supply/integrity.md

# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT

# `repro <file>` compares against the packager's .BUILDINFO (same package versions
# in the build chroot, same SOURCE_DATE_EPOCH; the PKGBUILD comes from `pkgctl repo
# clone` at the recorded commit — or, with -f, from the current directory, where it
# must hash-match .BUILDINFO's pkgbuild_sha256sum), so it only works when every
# build input is in the Arch archive: official packages, and a [dram] package
# whose chroot held nothing from [dram]. Its exit 1 means "not reproducible" or
# "the build failed": read the log. A package whose chroot held other [dram]
# packages gets the double build instead: that proves my PKGBUILD is
# deterministic, not that it matches anyone else's. --ours never goes through
# `pkgs.sh build`: that would sign, land in /srv/dram and write pkgs/BUILDLOG,
# and a probe must not change the release staging area.
# archlinux-repro is in packages/base.txt, diffoscope and devtools in
# packages/roles/builder.txt.

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGS="${XDG_STATE_HOME:-$HOME/.local/state}/dram/repro"
CACHE="${REPRO_CACHE:-/var/cache/pacman/pkg}" # override for tests
# as bin/pkgs.sh: the build chroot, where published [dram] files live, the source
# cache, and the packager string (.BUILDINFO carries it, so the rebuild must match)
CHROOT=/var/lib/archbuild/dram-x86_64
STAGE=/srv/dram
SRCDEST="${XDG_CACHE_HOME:-$HOME/.cache}/dram-pkgs/src"
PACKAGER="${PACKAGER:-pj dram packages <github.project@pseudoaddress.com>}"
DEFAULT_SET=(linux linux-lts hyprland openssh sudo systemd pacman)
DRY=0

say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }
run() {
  printf '\033[2m$ %s\033[0m\n' "$*"
  [ "$DRY" -eq 1 ] && return 0
  "$@"
}
as_root() { if [ "$(id -u)" -eq 0 ]; then run "$@"; else run sudo "$@"; fi; }
usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }

# --- official packages: archlinux-repro -----------------------------------------
cached_file() { # cached_file <pkg> -> path of the installed version's package file
  local name="$1" ver arch f
  ver="$(pacman -Q "$name" 2>/dev/null | awk '{print $2}')"
  [ -n "$ver" ] || return 1
  arch="$(pacman -Qi "$name" 2>/dev/null | awk '/^Architecture/ {print $3}')"
  for f in "$CACHE/$name-$ver-$arch.pkg.tar.zst" "$CACHE/$name-$ver-$arch.pkg.tar.xz"; do
    [ -f "$f" ] && {
      echo "$f"
      return 0
    }
  done
  return 1
}

repro_official() {
  have repro || die "repro not found — sudo pacman -S archlinux-repro"
  mkdir -p "$LOGS"
  local pkg f log rc good=0 bad=0 miss=0 results=()
  for pkg in "$@"; do
    say "$pkg"
    if ! pacman -Q "$pkg" >/dev/null 2>&1; then
      warn "$pkg is not installed — skipped"
      miss=$((miss + 1))
      continue
    fi
    if ! f="$(cached_file "$pkg")"; then
      warn "$pkg: installed version is not in $CACHE (paccache trimmed it?) — sudo pacman -Sw --noconfirm $pkg, then rerun"
      miss=$((miss + 1))
      results+=("$pkg: not in cache")
      continue
    fi
    log="$LOGS/$(basename "$f").log"
    echo "    $f"
    echo "    log: $log"
    if [ "$DRY" -eq 1 ]; then
      as_root repro "$f"
      continue
    fi
    # repro bootstraps a container from the Arch archive and rebuilds with the
    # package's own .BUILDINFO (same deps, same SOURCE_DATE_EPOCH) from the PKGBUILD
    # at the recorded commit (`pkgctl repo clone`; no -f, which would read ./PKGBUILD).
    # Root for nspawn.
    as_root repro "$f" >"$log" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
      ok "$pkg: reproducible"
      good=$((good + 1))
      results+=("$pkg: reproducible")
    else
      warn "$pkg: NOT reproducible, or the build failed — repro exits 1 for both (rc=$rc); tail of $log:"
      tail -n 5 "$log" | sed 's/^/      /'
      bad=$((bad + 1))
      results+=("$pkg: NOT reproducible")
    fi
  done
  [ "$DRY" -eq 1 ] && return 0
  say "Summary: $good reproducible, $bad not, $miss skipped"
  printf '    %s\n' "${results[@]}"
  [ "$bad" -eq 0 ]
}

# --- our own packages: repro -f when the chroot was all-official, else double build ---
# What pkgs.sh knows about the tree, in the small (its functions sit behind a
# dispatcher, so it cannot be sourced): .SRCINFO keys, the directory that builds
# a name, and the [dram] dependency closure that cmd_build feeds to makechrootpkg -I.
manifest_names() { grep -vE '^[[:space:]]*(#|$)' "$REPO/pkgs/manifest.txt" | cut -d= -f1; }
# srcinfo_of <dir> <key> -> values, one per line (pkgbase keys are tab-indented)
srcinfo_of() { sed -n "s/^[[:space:]]*$2 = //p" "$REPO/pkgs/$1/.SRCINFO"; }
srcinfo_version() { # <dir> -> [epoch:]pkgver-pkgrel
  local e v r
  e="$(srcinfo_of "$1" epoch)" v="$(srcinfo_of "$1" pkgver)" r="$(srcinfo_of "$1" pkgrel)"
  printf '%s%s-%s\n' "${e:+$e:}" "$v" "$r"
}
pkgdir_of() { # <pkgname> -> the pkgs/ directory that builds it: its own, or the split pkgbase whose .SRCINFO lists it
  local d
  [ -d "$REPO/pkgs/$1" ] && {
    echo "$1"
    return 0
  }
  for d in "$REPO"/pkgs/*/; do
    [ -f "$d.SRCINFO" ] && grep -qx "pkgname = $1" "$d.SRCINFO" && {
      basename "$d"
      return 0
    }
  done
  return 1
}
dram_closure() { # <dir> -> every pkgs/ directory its chroot needs, transitively, deps first (pkgs.sh dep_closure)
  local n="$1" d dd
  {
    srcinfo_of "$n" depends
    srcinfo_of "$n" makedepends
  } | sed 's/[<>=].*//' | sort -u | grep -xF -f <(manifest_names) \
    | while IFS= read -r d; do
      dd="$(pkgdir_of "$d")" || continue
      [ "$dd" = "$n" ] && continue # a split sibling of its own pkgbase
      dram_closure "$dd"
      echo "$dd"
    done | awk '!seen[$0]++'
}
all_deps_official() { # <file> -> 0 when no `installed =` line of its .BUILDINFO names a [dram] package
  pkginfo "$1" .BUILDINFO | sed -n 's/^installed = //p' | sed -E 's/-[^-]+-[^-]+-[^-]+$//' \
    | grep -qxF -f <(manifest_names) && return 1
  return 0
}

build_one() { # build_one <dir> <outdir>: one clean chroot build straight into <outdir>; nothing signed, logged or staged
  local dir="$1" out="$2" d p f
  local -a I=()
  have makechrootpkg || die "devtools not installed — sudo bash system/dram-builder-setup.sh"
  [ -d "$CHROOT/root" ] || die "no chroot at $CHROOT — sudo bash system/dram-builder-setup.sh"
  # every [dram] dependency, transitively, from the published files (pkgs.sh cmd_build's -I loop)
  for d in $(dram_closure "$dir"); do
    for p in $(srcinfo_of "$d" pkgname); do
      f="$(ls "$STAGE/$p-$(srcinfo_version "$d")-"*.pkg.tar.zst 2>/dev/null | head -1)"
      [ -n "$f" ] || die "$dir needs $p from $STAGE — dram pkgs build $d first"
      I+=(-I "$f")
    done
  done
  # per package, as bin/pkgs.sh: makepkg reuses cached sources by file name ("LICENSE")
  mkdir -p "$out" "$SRCDEST/$dir"
  # -c: a fresh copy of the chroot; no -u, so both builds see the same root
  (cd "$REPO/pkgs/$dir" && PKGDEST="$out" SRCDEST="$SRCDEST/$dir" PACKAGER="$PACKAGER" \
    run makechrootpkg -c -r "$CHROOT" ${I[@]+"${I[@]}"}) || return 1
  [ "$DRY" -eq 1 ] && return 0
  [ -n "$(find "$out" -maxdepth 1 -name '*.pkg.tar.*' ! -name '*.sig' | head -1)" ] || {
    warn "no package file appeared in $out"
    return 1
  }
}

pkginfo() { bsdtar -xOf "$1" "$2" 2>/dev/null; }

repro_ours() {
  local target="$1" name dir ref="" work a b epoch p log rc
  if [ -f "$target" ]; then
    ref="$(realpath "$target")"
    name="$(pkginfo "$ref" .PKGINFO | awk -F' = ' '$1 == "pkgname" {print $2}')"
    [ -n "$name" ] || die "$target has no .PKGINFO pkgname — not a pacman package"
    epoch="$(pkginfo "$ref" .BUILDINFO | awk -F' = ' '$1 == "builddate" {print $2}')"
    p="$(pkginfo "$ref" .BUILDINFO | awk -F' = ' '$1 == "packager" {print $2}')"
    [ -n "$p" ] && PACKAGER="$p" # .BUILDINFO is inside the archive: rebuild with the same packager string
  else
    name="$target"
    epoch="${SOURCE_DATE_EPOCH:-$(date +%s)}"
  fi
  dir="$(pkgdir_of "$name")" || die "no pkgs/ directory builds $name in this checkout (not a vendored package)"
  # Stage 1: an independent rebuild. When nothing from [dram] was in the file's
  # build chroot, archlinux-repro recreates that chroot from the Arch archive; -f
  # takes the PKGBUILD from the current directory, which must hash-match
  # .BUILDINFO — a stale or edited pkgs/<name> fails loudly, by design.
  if [ -n "$ref" ] && all_deps_official "$ref"; then
    have repro || die "repro not found — sudo pacman -S archlinux-repro"
    say "$name: build chroot was all-official — archlinux-repro rebuild from the archive (repro -f, PKGBUILD from pkgs/$dir)"
    mkdir -p "$LOGS"
    log="$LOGS/$(basename "$ref").log"
    echo "    log: $log"
    if [ "$DRY" -eq 1 ]; then
      (cd "$REPO/pkgs/$dir" && as_root repro -f "$ref")
      return 0
    fi
    (cd "$REPO/pkgs/$dir" && as_root repro -f "$ref") >"$log" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
      ok "$name: reproducible (independent rebuild matches $ref)"
      return 0
    fi
    warn "$name: NOT reproducible, or the build failed — repro exits 1 for both (rc=$rc); tail of $log:"
    tail -n 5 "$log" | sed 's/^/      /'
    return 1
  fi
  # Stage 2: the double build (the lib32 chain depends on other [dram] packages,
  # which the archive does not have). Same SOURCE_DATE_EPOCH for every build:
  # makepkg writes it into .BUILDINFO and uses it for every mtime inside the
  # archive — the one legitimate difference between two honest builds, removed.
  have diffoscope || die "diffoscope not found — sudo pacman -S diffoscope"
  export SOURCE_DATE_EPOCH="$epoch"
  work="$(mktemp -d "${TMPDIR:-/tmp}/dram-repro-$name.XXXX")"
  a="$work/a" b="$work/b"
  say "$name: SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH, work dir $work"
  if [ -n "$ref" ]; then
    mkdir -p "$a"
    ln -s "$ref" "$a/$(basename "$ref")"
    say "reference: $ref"
    echo "    built with:"
    pkginfo "$ref" .BUILDINFO | grep -E '^(builddate|packager|buildenv|options)' | sed 's/^/      /'
  else
    say "build 1 of 2"
    build_one "$dir" "$a" || die "build 1 failed"
  fi
  say "build $([ -n "$ref" ] && echo 1 of 1 || echo 2 of 2)"
  build_one "$dir" "$b" || die "build failed"
  [ "$DRY" -eq 1 ] && return 0
  local fa fb
  # "$name-*": a split pkgbase leaves several files; compare the one asked for
  fa="$(find "$a" -maxdepth 1 -name "$name-*.pkg.tar.*" ! -name '*.sig' | head -1)"
  fb="$(find "$b" -maxdepth 1 -name "$name-*.pkg.tar.*" ! -name '*.sig' | head -1)"
  [ -f "$fa" ] && [ -f "$fb" ] || die "missing a package file: a=$fa b=$fb"
  say "diffoscope"
  if cmp -s "$fa" "$fb"; then
    ok "$name: bit-for-bit identical ($(basename "$fa"))"
    rm -rf "$work"
    return 0
  fi
  mkdir -p "$LOGS"
  local report
  report="$LOGS/$name-$(date +%Y%m%d-%H%M).html"
  # .BUILDINFO lists the exact packages installed in the build chroot; a chroot
  # that moved on since the reference build shows up there first, not as a bug.
  run diffoscope --exclude-directory-metadata=recursive --html "$report" "$fa" "$fb" | head -n 80
  warn "$name: the two builds differ — full report: $report  (work dir kept: $work)"
  echo "    the usual suspects: .BUILDINFO 'installed =' lines (chroot drifted), embedded timestamps, build paths, parallel link order"
  return 1
}

# --- main -------------------------------------------------------------------
OURS=""
PKGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -n | --dry-run) DRY=1 ;;
    --ours)
      [ -n "${2:-}" ] || die "--ours needs a package name or a .pkg.tar.zst file"
      OURS="$2"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      sed -n '2s/^# \{0,1\}//p' "$0" >&2
      exit 2
      ;;
    *) PKGS+=("$1") ;;
  esac
  shift
done
have pacman || die "this runs on an Arch host (no pacman here)"
if [ -n "$OURS" ]; then
  [ "${#PKGS[@]}" -eq 0 ] || die "--ours takes one target; the official-package list is a separate run"
  repro_ours "$OURS"
else
  [ "${#PKGS[@]}" -gt 0 ] || PKGS=("${DEFAULT_SET[@]}")
  repro_official "${PKGS[@]}"
fi

#!/usr/bin/env bash
# Sourced, not run: a Windows build's files, staged on the Mac (or Arch) in a local directory
# laid out as C:\ProgramData\dram holds them (decisions/0020, docs/operations/releases/pushes.md).
# install/windows/apply-windows.sh and bin/push-windows.sh both stage through it, so the two
# never disagree about a byte, and bin/render-windows.sh locks the fonts through it. What is
# staged is what the render's manifest.json lists, each file from the source it names - the
# repo, the render, or a pinned download (install/windows/fonts.pin and cursors.pin, each cached
# in ~/.cache/dram/<dir> and refused unless its sha256 is the pinned one) - and each must have
# the manifest's sha256. Needs python3, curl, and bsdtar for archive members.
#
#   win_sha256 <file>                its sha256 (sha256sum, or shasum on macOS)
#   win_fetch_pin <repo> <pin> <dir> <out> [ext...]
#                                    every line of install/windows/<pin> fetched once into
#                                    ~/.cache/dram/<dir>, checked, its members put in <out>; two
#                                    lines staging one name are refused; with ext, any other kind
#                                    of file is refused; with WIN_PIN_MEMBERS set, "<id> <pin
#                                    sha256> <name>" is appended there for each file it stages
#   win_sums <dir>                   "<sha256>  <name>" for each file in <dir>
#   win_stage_build <repo> <manifest> <out>
#                                    every files[] entry of the manifest at its path in <out>,
#                                    from its source (repo:<path>, render:<path>,
#                                    pin:<pin file>#<id>), each with the manifest's sha256, and
#                                    nothing else
#   win_fill_release <manifest> <release> <commit>
#                                    the staged copy's release and commit, "unstaged" in the
#                                    render, filled in
#
# needs:  bash, python3, curl, bsdtar; sha256sum or shasum
# alone:  yes, for a manifest of the same shape: files[] entries with path, sha256 and source
# here:   sourced by bin/push-windows.sh, install/windows/apply-windows.sh and
#         bin/render-windows.sh; tests/push-windows.sh covers it (bin/check.sh §19)

# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT

win_die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}

win_sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | awk '{print $1}'; }

win_fetch_pin() {
  local repo="$1" pin="$2" dir="$3" out="$4" cache id url sum rest file got tmp f x n bad
  local -a m opts pats
  shift 4
  command -v bsdtar >/dev/null 2>&1 || win_die "bsdtar missing (libarchive: in Arch's base, and on macOS)"
  cache="${XDG_CACHE_HOME:-$HOME/.cache}/dram/$dir"
  mkdir -p "$cache" "$out" || win_die "cannot create $cache or $out"
  while read -r id url sum rest; do
    case "$id" in '' | '#'*) continue ;; esac
    [ -n "$rest" ] || win_die "$pin: $id names no member"
    file="$cache/$(printf '%.16s' "$sum")-${url##*/}"
    if [ ! -s "$file" ] || [ "$(win_sha256 "$file")" != "$sum" ]; then
      curl -fsSL --retry 3 -o "$file.part" "$url" || win_die "$pin: could not download $id ($url)"
      mv "$file.part" "$file"
    fi
    got="$(win_sha256 "$file")"
    if [ "$got" != "$sum" ]; then
      rm -f "$file"
      win_die "$pin: $id has sha256 $got, pinned $sum - refused"
    fi
    # each line into its own directory first, so a member's line is known and no line
    # overwrites another's file
    tmp="$out/.pin-$id"
    rm -rf "$tmp"
    mkdir -p "$tmp" || win_die "cannot create $tmp"
    read -r -a m <<<"$rest"
    case "${m[0]}" in
      =*) cp "$file" "$tmp/${m[0]#=}" || win_die "$pin: $id: copy failed" ;;
      *)
        opts=() pats=()
        for x in "${m[@]}"; do
          case "$x" in --exclude=*) opts+=("$x") ;; *) pats+=("$x") ;; esac
        done
        (cd "$tmp" && bsdtar -xf "$file" -s '|.*/||' ${opts[@]+"${opts[@]}"} ${pats[@]+"${pats[@]}"}) \
          || win_die "$pin: $id: bsdtar could not extract ${pats[*]}"
        ;;
    esac
    n=0
    for f in "$tmp"/*; do
      [ -f "$f" ] || continue
      x="${f##*/}"
      [ ! -e "$out/$x" ] || win_die "$pin: $id stages $x, which another line staged already"
      mv "$f" "$out/$x" || win_die "$pin: $id: could not stage $x"
      [ -z "${WIN_PIN_MEMBERS:-}" ] || printf '%s %s %s\n' "$id" "$sum" "$x" >>"$WIN_PIN_MEMBERS"
      n=$((n + 1))
    done
    rm -rf "$tmp"
    [ "$n" -gt 0 ] || win_die "$pin: $id: no member matched"
    printf '   %-20s %3d file(s)\n' "$id" "$n"
  done <"$repo/install/windows/$pin"
  [ $# -gt 0 ] || return 0
  # only the kinds the pin is for (a font pin that let a README through would install nothing,
  # but the converge would copy it into C:\Windows\Fonts' folder)
  bad=""
  for x in "$out"/*; do
    [ -f "$x" ] || continue
    case " $* " in *" ${x##*.} "*) ;; *) bad="$bad ${x##*/}" ;; esac
  done
  [ -z "$bad" ] || win_die "$pin: not a $*:$bad"
}

win_sums() { (cd "$1" && for f in *; do if [ -f "$f" ]; then printf '%s  %s\n' "$(win_sha256 "$f")" "$f"; fi; done); }

# the kinds of file a pin may stage (any other is refused)
win_pin_kinds() {
  case "${1##*/}" in
    fonts.pin) echo ttf otf ;;
    cursors.pin) echo cur ani ;;
  esac
}

win_stage_build() {
  local repo="$1" manifest="$2" out="$3" kind src dst
  mkdir -p "$out" || win_die "cannot create $out"
  # the plan: "pin <pin file> <dir>" (a pin's files all go to one directory), then
  # "copy <source> <path>" for the repo's files and the render's
  python3 - "$manifest" >"$out.plan" <<'EOF' || win_die "$manifest: unreadable, or a source of an unknown kind (above)"
import json, os, sys
m = json.load(open(sys.argv[1]))
pins, copies = {}, []
for f in m["files"]:
    kind, _, src = f["source"].partition(":")
    if kind == "pin":
        pin = src.split("#")[0]
        d = os.path.dirname(f["path"])
        if pins.setdefault(pin, d) != d:
            sys.exit("%s stages into %s and %s" % (pin, pins[pin], d))
    elif kind in ("repo", "render"):
        copies.append((src, f["path"]))
    else:
        sys.exit("%s: unknown source %s" % (f["path"], f["source"]))
for pin, d in sorted(pins.items()):
    print("pin\t%s\t%s" % (pin, d))
for src, dst in copies:
    print("copy\t%s\t%s" % (src, dst))
EOF
  while IFS="$(printf '\t')" read -r kind src dst; do
    case "$kind" in
      pin)
        # shellcheck disable=SC2046 # the kinds are words
        win_fetch_pin "$repo" "${src#install/windows/}" "$dst" "$out/$dst" $(win_pin_kinds "$src")
        ;;
      copy)
        mkdir -p "$out/$(dirname "$dst")" && cp "$repo/$src" "$out/$dst" || win_die "could not stage $dst from $src"
        ;;
    esac
  done <"$out.plan"
  rm -f "$out.plan"
  # exactly the manifest's files, each with its sha256 (a pin whose members moved needs a new
  # install/windows/fonts.lock: bin/render-windows.sh --lock)
  python3 - "$manifest" "$out" <<'EOF' || win_die "the staged files are not the build's (above)"
import hashlib, json, os, sys
mf, root = sys.argv[1:]
want = {f["path"]: f["sha256"] for f in json.load(open(mf))["files"]}
bad = []
for p, s in sorted(want.items()):
    q = os.path.join(root, p)
    if not os.path.isfile(q):
        bad.append("%s (missing)" % p)
    elif hashlib.sha256(open(q, "rb").read()).hexdigest() != s:
        bad.append("%s (sha256 differs)" % p)
for d, _, files in os.walk(root):
    for n in files:
        p = os.path.relpath(os.path.join(d, n), root).replace(os.sep, "/")
        if p not in want:
            bad.append("%s (not in the build)" % p)
if bad:
    print("\n".join("   " + b for b in bad[:20]), file=sys.stderr)
    sys.exit(1)
print("   %d files staged, each with the sha256 the render names" % len(want))
EOF
}

win_fill_release() {
  python3 - "$@" <<'EOF' || win_die "$1: no unstaged release and commit to fill in"
import json, sys
path, release, commit = sys.argv[1:]
text = open(path, encoding="utf-8").read()
for k, v in (("release", release), ("commit", commit)):
    if text.count('"%s": "unstaged"' % k) != 1:
        sys.exit(1)
    text = text.replace('"%s": "unstaged"' % k, '"%s": %s' % (k, json.dumps(v)))
with open(path, "w", encoding="utf-8", newline="") as f:
    f.write(text)
EOF
}

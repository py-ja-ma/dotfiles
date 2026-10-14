#!/usr/bin/env bash
# usage: render-windows.sh [HOST...] [--check] [--lock]
#
# Renders each Windows host of windows/hosts/ (default: every one) from the flake into
# windows/build/<HOST>/ (decisions/0020, docs/platforms/windows/renderer.md): its winget
# configuration documents, one per phase and scope, manifest.json (what the converge runs, in
# order, and every file it stages with its sha256) and inputs.json (every repo file the render
# read). Commit the result: install/windows/apply-windows.sh applies a committed build and
# refuses a stale one. Nix evaluates where it is installed (Arch); on the Mac in a throwaway
# nixos/nix container under Colima (decisions/log.md#d26; DOCKER_CONTEXT, default colima), fed
# the tracked files on stdin - what a host's flake sees - with its downloads cached in the
# docker volume dram-nix-cache. When
# install/windows/fonts.pin has moved past install/windows/fonts.lock, the lock is written again
# first (the pinned downloads, cached in ~/.cache/dram/fonts; bsdtar), since Nix downloads
# nothing and the manifest lists every font file.
#
#   --check     no Nix, no network: every committed build is current (each file of its
#               inputs.json hashed again, the directories it read listed again from git, the
#               Markdown pages under windows/ aside) and every host file has a build;
#               bin/check.sh §19 runs it
#   --lock      write install/windows/fonts.lock again even if fonts.pin has not moved
#   -h, --help  this text
#
# exit: 0 rendered, or current · 1 a stale build, a failed lock or a failed render · 2 bad usage
# see: windows/default.nix, docs/platforms/windows/renderer.md

CHECK=0 LOCK=0 HOSTS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1 ;;
    --lock) LOCK=1 ;;
    -h | --help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -* | "")
      sed -n '2s/^# \{0,1\}//p' "$0" >&2
      exit 2
      ;;
    *) HOSTS="$HOSTS $1" ;;
  esac
  shift
done

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1
say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}
ALL="$(for f in windows/hosts/*.nix; do [ -f "$f" ] && basename "$f" .nix; done)"
[ -n "$HOSTS" ] || HOSTS="$ALL"
for h in $HOSTS; do
  printf '%s\n' "$ALL" | grep -qxF "$h" || die "no windows/hosts/$h.nix"
done

# --- the check: no Nix, no network ------------------------------------------------------
# inputs.json lists every file the render read with its sha256, and the directories it read
# whole; git ls-files is what the flake sees of them (tracked files only)
check() {
  # shellcheck disable=SC2086 # host names have no spaces
  python3 - "$@" <<'EOF'
import hashlib, json, os, subprocess, sys

def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()

tracked = [p for p in subprocess.run(["git", "ls-files", "-z"], capture_output=True, check=True,
           text=True).stdout.split("\0") if p and os.path.lexists(p)]
hosts = sys.argv[1:]
known = sorted(f[:-4] for f in os.listdir("windows/hosts") if f.endswith(".nix"))
built = sorted(d for d in os.listdir("windows/build") if os.path.isdir(os.path.join("windows/build", d))) \
    if os.path.isdir("windows/build") else []
bad = 0
for h in sorted(set(built) - set(known)):
    print("windows/build/%s has no windows/hosts/%s.nix (remove it)" % (h, h))
    bad += 1
for h in hosts:
    path = "windows/build/%s/inputs.json" % h
    if not os.path.isfile(path):
        print("%s: not rendered (bin/render-windows.sh %s)" % (h, h))
        bad += 1
        continue
    inputs = json.load(open(path))
    excl = inputs.get("exclude", [])
    why = []
    for p, s in sorted(inputs["files"].items()):
        if not os.path.isfile(p):
            why.append("%s (gone)" % p)
        elif sha(p) != s:
            why.append("%s (changed)" % p)
    for d in inputs["dirs"]:
        for p in tracked:
            # the Markdown pages under windows/ are documentation: windows/render.nix never reads them
            if p.startswith("windows/") and p.endswith(".md"):
                continue
            if p.startswith(d + "/") and p not in inputs["files"] \
                    and not any(p == e or p.startswith(e + "/") for e in excl):
                why.append("%s (new)" % p)
    if why:
        print("%s: stale since %s; bin/render-windows.sh %s" % (h, ", ".join(why[:8]) + (" and %d more" % (len(why) - 8) if len(why) > 8 else ""), h))
        bad += 1
    else:
        print("%s: current (%d inputs)" % (h, len(inputs["files"])))
sys.exit(1 if bad else 0)
EOF
}

if [ "$CHECK" = 1 ]; then
  # shellcheck disable=SC2086 # host names have no spaces
  check $HOSTS
  exit $?
fi

# --- fonts.lock: the files fonts.pin stages, with their sha256 ---------------------------
pins_of() { awk '!/^#/ && NF >= 3 {print $1, $3}' "$1" | sort -u; }
if [ "$LOCK" = 1 ] || [ "$(pins_of install/windows/fonts.pin)" != "$(awk '!/^#/ && NF >= 4 {print $1, $2}' install/windows/fonts.lock 2>/dev/null | sort -u)" ]; then
  say "install/windows/fonts.lock (the pinned downloads)"
  # shellcheck source=install/lib/windows-stage.sh
  . install/lib/windows-stage.sh
  T="$(mktemp -d)"
  trap 'rm -rf "$T"' EXIT
  WIN_PIN_MEMBERS="$T/members" win_fetch_pin "$REPO" fonts.pin fonts "$T/fonts" ttf otf
  {
    cat <<'EOF'
# install/windows/fonts.lock - the files install/windows/fonts.pin stages, one per line:
#   <pin id> <the pin's sha256> <the file's sha256> <the file's name>
# Written by bin/render-windows.sh from the pinned downloads, since Nix downloads nothing: the
# render lists each file in manifest.json, install/windows/apply-windows.sh refuses a staged
# font that differs, and a pin whose sha256 is not the one here stops the render (lock again).
EOF
    while read -r id psum name; do
      printf '%s %s %s %s\n' "$id" "$psum" "$(win_sha256 "$T/fonts/$name")" "$name"
    done <"$T/members"
  } >install/windows/fonts.lock || die "could not write install/windows/fonts.lock"
  echo "   install/windows/fonts.lock: $(grep -vc '^#' install/windows/fonts.lock) files"
fi

# --- the render: the flake's windowsConfigurations.<host>.files ---------------------------
say "render:$HOSTS"
OUT="$(mktemp)"
trap 'rm -f "$OUT"; [ -n "${T:-}" ] && rm -rf "$T"' EXIT
APPLY="cs: builtins.listToAttrs (map (h: { name = h; value = cs.\${h}.files; }) [$(for h in $HOSTS; do printf ' "%s"' "$h"; done) ])"
if command -v nix >/dev/null 2>&1; then
  nix --extra-experimental-features 'nix-command flakes' eval --json "$REPO#windowsConfigurations" --apply "$APPLY" >"$OUT" \
    || die "nix could not render (above)"
else
  command -v docker >/dev/null 2>&1 || die "neither nix nor docker: render on Arch, or start Colima on the Mac"
  # the tracked files that exist, NUL-separated, as one tar on the container's stdin (without
  # macOS's ._ AppleDouble members and extended attributes, which would become files there)
  python3 -c 'import os, subprocess, sys
fs = subprocess.run(["git", "ls-files", "-z"], capture_output=True, check=True).stdout.split(b"\0")
sys.stdout.buffer.write(b"".join(f + b"\0" for f in fs if f and os.path.lexists(f)))' \
    | COPYFILE_DISABLE=1 tar --no-xattrs --null -T - -cf - \
    | docker --context "${DOCKER_CONTEXT:-colima}" run --rm -i -v dram-nix-cache:/root/.cache/nix nixos/nix:latest \
      sh -c 'mkdir -p /repo && tar -xf - -C /repo && nix --extra-experimental-features "nix-command flakes" eval --json "path:/repo#windowsConfigurations" --apply "$1"' \
      sh "$APPLY" >"$OUT" || die "the nixos/nix container could not render (above; is Colima running?)"
fi

# write each build exactly as rendered; a file the render no longer makes goes
python3 - "$OUT" <<'EOF' || die "could not write windows/build"
import json, os, sys
for host, files in sorted(json.load(open(sys.argv[1])).items()):
    d = os.path.join("windows", "build", host)
    os.makedirs(d, exist_ok=True)
    for old in sorted(os.listdir(d)):
        if old not in files:
            os.remove(os.path.join(d, old))
            print("   %s/%s: removed" % (d, old))
    for name, text in sorted(files.items()):
        p = os.path.join(d, name)
        cur = open(p, encoding="utf-8", newline="").read() if os.path.exists(p) else None
        if cur != text:
            with open(p, "w", encoding="utf-8", newline="") as f:
                f.write(text)
        print("   %s: %s" % (p, "unchanged" if cur == text else "written"))
EOF
# shellcheck disable=SC2086 # host names have no spaces
check $HOSTS

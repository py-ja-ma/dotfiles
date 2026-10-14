#!/usr/bin/env bash
# usage: push-windows.sh <host> [--apply] [--dry-run] [--to USER@ADDR] [--force]
#
# Puts a Windows host's release on it (decisions/0020, docs/operations/releases/pushes.md): the flake's render
# of the host (windows/build/<host>/: manifest.json and the winget documents, its release and
# commit filled in) and every file its manifest lists, staged from this commit the way
# install/windows/apply-windows.sh stages them (install/lib/windows-stage.sh: each from the
# source the manifest names - the repo, the render, the fonts and cursors of fonts.pin and
# cursors.pin, each download refused unless its sha256 is pinned). Every file's sha256 must be
# what the manifest says, so a stale render or a changed source stops here, before anything is
# copied; bin/render-windows.sh --check runs first when the renderer is in the tree. Then
# dram.ps1 on Windows takes it: `dram receive` checks every file again and switches
# C:\ProgramData\dram to the release; --apply also converges.
#
# Only what changed travels: the host's build\files.sha256 (its live release) is read first,
# and a file already there with the same sha256 is not sent; the render, the engine (dram.ps1)
# and the full list always are. They land in C:\ProgramData\dram\incoming, and the incoming
# dram.ps1 runs the receive, so the first push installs dram (dram.cmd on the machine PATH)
# and a release can change dram itself. Also staged: build\push.json (this commit's version,
# build and commit) and build\packages.tsv (the winget and Store ids the documents declare,
# for dram harvest and rollback). Windows' OpenSSH runs cmd.exe: every remote command here is
# one plain cmd line, or one `powershell -File` with nothing after it.
#
# Address: --to, else address (and user) in windows/hosts/<host>.nix, else that of the WSL
# clone whose wsl.windowsHost is <host> without -win (the clone's address is its PC's). The
# host key is checked as HostKeyAlias <host> on a connection of its own (never multiplexed),
# so Arch answering at the same address is refused, not written to. Needs a clean tree.
#
#   --apply          then dram apply: each phase's documents and scripts, the desktop step
#   --dry-run        nothing on Windows changes but dram's staging area: without --apply the
#                    release is checked in incoming\ (dram receive -DryRun), not switched; with
#                    it, received, then dram apply -DryRun (winget configure test, -DryRun)
#   --to USER@ADDR   the ssh target, instead of the host files'
#   --force          dram receive -Force: a push the host's channel (stable: tagged releases
#                    only) or its computer name would refuse
#   -h, --help       this text
#
# needs:  git, ssh, scp, python3, curl, bsdtar; install/lib/windows-stage.sh and the
#         committed render in windows/build/<host>/; Windows' OpenSSH on the PC
# alone:  no: it stages from this repo's render and pins, for dram.ps1 on the PC
# here:   by hand on the Mac after bin/render-windows.sh; tests/push-windows.sh runs it
#         against stand-ins (bin/check.sh §19)
# env:    DRAM_WIN_SSH   extra ssh/scp options, before this script's own (for example -i KEY)
# exit:   0 received (and applied) · 1 a check, the copy, the receive or the apply failed ·
#         2 bad usage
# see:    docs/operations/releases/pushes.md, docs/operations/dram/windows.md,
#         install/windows/dram-windows/dram.ps1

# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT

usage_line() { sed -n '2s/^# \{0,1\}//p' "$0" >&2; }
HOST="" APPLY=0 DRY=0 FORCE=0 TO=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --apply) APPLY=1 ;;
    --dry-run) DRY=1 ;;
    --force) FORCE=1 ;;
    --to)
      TO="${2:-}"
      case "$TO" in *@*) ;; *)
        usage_line
        exit 2
        ;;
      esac
      shift
      ;;
    -*)
      usage_line
      exit 2
      ;;
    *)
      [ -z "$HOST" ] || {
        usage_line
        exit 2
      }
      HOST="$1"
      ;;
  esac
  shift
done
case "$HOST" in "" | *[!A-Za-z0-9-]*)
  usage_line
  exit 2
  ;;
esac

set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"
# shellcheck source=install/lib/roles.sh
. "$REPO/install/lib/roles.sh"
# shellcheck source=install/lib/windows-stage.sh
. "$REPO/install/lib/windows-stage.sh"
say() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die() {
  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2
  exit 1
}
W='C:\ProgramData\dram'
RENDER="$REPO/windows/build/$HOST"
MANIFEST="$RENDER/manifest.json"

# manifest_py <mode> <args...>: the manifest's rules and what follows from it, in python3
#   check <manifest> <host> <render>   refuse a manifest the host would refuse; print
#                                      "<path>\t<sha256>" for each files[] entry
#   extras <manifest> <render> <tree> <out> <version> <tagged> <ahead> <build> <commit>
#          <branch> <date> <pushed_at> <host>
#                                      write <out>/packages.tsv (unless the render has one)
#                                      and <out>/push.json
manifest_py() {
  python3 -I - "$@" <<'PY'
import json, os, re, sys

PHASES = ("00", "10", "20", "30", "40", "50")
OWN = ("incoming", "build.previous", "bin", "state.json", "state.json.new", "dram.log")


def fail(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


def safe(p):
    # what dram.ps1's Test-SafePath takes: relative, no .. or drive, not dram's bookkeeping
    if not isinstance(p, str) or not p or p[0] in "/\\" or ":" in p or re.search(r'[\x00-\x1f*?"<>|]', p):
        return False
    segs = re.split(r"[\\/]", p)
    return all(s not in ("", ".", "..") for s in segs) and segs[0] not in OWN


def render_files(render):
    out = set()
    for d, _, names in os.walk(render):
        for n in names:
            out.add(os.path.relpath(os.path.join(d, n), render).replace(os.sep, "/"))
    return out


def load(path):
    try:
        with open(path, encoding="utf-8-sig") as f:
            m = json.load(f)
    except ValueError as e:
        fail("%s is not JSON: %s" % (path, e))
    if not isinstance(m, dict):
        fail("%s is not a JSON object" % path)
    return m


def check(path, host, render):
    m = load(path)
    if m.get("host") != host:
        fail("the manifest is for %r, not %s" % (m.get("host"), host))
    for k in ("release", "commit"):
        if not isinstance(m.get(k), str):
            fail("the manifest has no %s" % k)
    for k in ("documents", "scripts", "files"):
        if not isinstance(m.get(k), list):
            fail("the manifest's %s is not a list" % k)
    sums = {}
    for f in m["files"]:
        p = f.get("path") if isinstance(f, dict) else None
        h = f.get("sha256") if isinstance(f, dict) else None
        if not safe(p):
            fail("files[]: %r is not a path dram may write under C:\\ProgramData\\dram" % (p,))
        p = p.replace("\\", "/")
        if not isinstance(h, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", h):
            fail("files[] %s: %r is not a sha256" % (p, h))
        if p in sums:
            fail("files[] lists %s twice" % p)
        sums[p] = h.lower()
    have = render_files(render)
    for own in ("push.json", "files.sha256"):
        if own in have:
            fail("the render holds %s, a name this push writes itself" % own)

    def entry(kind, e):
        f = e.get("file") if isinstance(e, dict) else None
        if not safe(f):
            fail("%s: %r is not a file name dram may use" % (kind, f))
        f = f.replace("\\", "/")
        if e.get("phase") not in PHASES:
            fail("%s %s: phase %r is none of %s" % (kind, f, e.get("phase"), " ".join(PHASES)))
        if f not in have and "build/" + f not in sums and f not in sums:
            fail("%s %s is neither in the render nor in files[]" % (kind, f))
        return f

    for d in m["documents"]:
        entry("document", d)
        if d.get("scope") not in ("machine", "user"):
            fail("document %s: scope %r is neither machine nor user" % (d.get("file"), d.get("scope")))
    for s in m["scripts"]:
        f = entry("script", s)
        if not f.endswith(".ps1"):
            fail("script %s is not a .ps1" % f)
        a = s.get("args", [])
        if not isinstance(a, list) or not all(isinstance(x, str) and x for x in a):
            fail("script %s: args is not a list of words" % f)
    for p, h in sums.items():
        print("%s\t%s" % (p, h))


# --- packages.tsv: the WinGetPackage units of the documents, and the ids a Script unit installs
UNIT = re.compile(r"""^(\s*)-\s+(?:resource|type)\s*:\s*["']?([^"'\s#]+)""")
KV = re.compile(r"""(_?[A-Za-z]+)\s*:\s*("[^"]*"|'[^']*'|[^,}]+)""")


def clean(v):
    v = v.strip()
    if v[:1] in "\"'":
        return v[1:-1]
    return re.sub(r"\s+#.*$", "", v).strip()


def units(path):
    out, cur = [], None
    with open(path, encoding="utf-8-sig") as f:
        for line in f.read().splitlines():
            u = UNIT.match(line)
            if u:
                cur = (u.group(2), len(u.group(1)), [])
                out.append(cur)
                continue
            if cur is None:
                continue
            s = line.strip()
            if s and not s.startswith("#") and len(line) - len(line.lstrip()) <= cur[1]:
                cur = None  # back out of the list item
                continue
            cur[2].append(line)
    return out


def settings(lines):
    for i, line in enumerate(lines):
        m = re.match(r"^(\s*)(?:settings|properties)\s*:\s*(.*)$", line)
        if not m:
            continue
        rest = m.group(2).strip()
        if rest.startswith("{"):
            body = rest[1 : rest.rfind("}")] if "}" in rest else rest[1:]
            return {k.lower(): clean(v) for k, v in KV.findall(body)}
        kv, ind = {}, None
        for nxt in lines[i + 1 :]:
            s = nxt.strip()
            if not s or s.startswith("#"):
                continue
            n = len(nxt) - len(nxt.lstrip())
            if n <= len(m.group(1)):
                break
            ind = n if ind is None else ind
            k = re.match(r"^\s*(_?[A-Za-z]+)\s*:\s*(.*)$", nxt)
            if n == ind and k:
                kv[k.group(1).lower()] = clean(k.group(2))
        return kv
    return {}


def packages(docs, tree):
    rows, seen = [], set()
    for name, path in docs:
        for res, _, lines in units(path):
            found = []
            if re.search(r"(WinGetPackage|WinGet/Package)$", res):
                kv = settings(lines)
                if kv.get("id"):
                    absent = kv.get("ensure", "").lower() == "absent" or kv.get("_exist", "").lower() == "false"
                    found.append((kv["id"], kv.get("source") or "winget", "Absent" if absent else "Present"))
            elif res.endswith("/Script"):
                # a rendered Script unit runs its file (units\<id>.ps1, staged in the tree): what
                # it installs is written there
                for f in sorted(set(re.findall(r"""units\\\\?([\w.-]+\.ps1)""", "\n".join(lines)))):
                    p = os.path.join(tree, "units", f)
                    if os.path.isfile(p):
                        with open(p, encoding="utf-8-sig") as fh:
                            lines = lines + fh.read().splitlines()
                for line in lines:
                    for m in re.finditer(r"""--id\s+["']?([A-Za-z0-9][\w.+-]*)""", line):
                        src = re.search(r"""--source\s+["']?(\w+)""", line)
                        found.append((m.group(1), src.group(1) if src else "winget", "Present"))
            for pid, src, ensure in found:
                if pid.lower() not in seen:
                    seen.add(pid.lower())
                    rows.append("\t".join((pid, src, ensure, name)))
    return rows


def extras(path, render, tree, out, version, tagged, ahead, build, commit, branch, date, pushed, host):
    m = load(path)
    os.makedirs(out, exist_ok=True)
    if not os.path.exists(os.path.join(render, "packages.tsv")):
        # a document is where dram.ps1 looks for it: in the render, else a files[] path
        docs = []
        for d in m["documents"]:
            f = d["file"].replace("\\", "/")
            cands = [os.path.join(render, f[6:])] if f.startswith("build/") else [os.path.join(render, f), os.path.join(tree, f)]
            for c in cands:
                if os.path.isfile(c):
                    docs.append((f, c))
                    break
        with open(os.path.join(out, "packages.tsv"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write("# id\tsource\tensure\tdocument - the winget and Store ids the documents declare (bin/push-windows.sh)\n")
            for r in packages(docs, tree):
                fh.write(r + "\n")
    push = {"host": host, "version": version, "tagged": tagged == "true", "ahead": int(ahead), "build": build,
            "commit": commit, "branch": branch, "date": date, "pushed_at": pushed}
    with open(os.path.join(out, "push.json"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(push) + "\n")


if sys.argv[1] == "check":
    check(*sys.argv[2:5])
elif sys.argv[1] == "extras":
    extras(*sys.argv[2:15])
else:
    fail("manifest_py: no mode %s" % sys.argv[1])
PY
}

# target_for <host>: user@address from the host files, '' when none names one
target_for() {
  local f h addr
  f="$REPO/windows/hosts/$1.nix"
  if [ -f "$f" ]; then
    addr="$(sed -nE 's/^[[:space:]]*(dram\.)?address[[:space:]]*=[[:space:]]*"([^"]+)".*/\2/p' "$f" | head -1)"
    if [ -n "$addr" ]; then
      echo "$(sed -nE 's/^[[:space:]]*(dram\.)?user[[:space:]]*=[[:space:]]*"([^"]+)".*/\2/p' "$f" | head -1 | grep . || echo pj)@$addr"
      return 0
    fi
  fi
  for f in "$REPO"/modules/hosts/*.nix; do
    h="$(basename "$f" .nix)"
    [ "$(host_form "$REPO" "$h")" = wsl ] || continue
    [ "$(host_wsl "$REPO" "$h" windowsHost)" = "${1%-win}" ] || continue
    addr="$(sed -nE 's/^[[:space:]]*(dram\.)?address[[:space:]]*=[[:space:]]*"([^"]+)".*/\2/p' "$f" | head -1)"
    if [ -n "$addr" ]; then
      echo "$(host_user "$REPO" "$h")@$addr"
      return 0
    fi
  done
  return 0
}

[ -z "$(git status --porcelain)" ] || die "uncommitted changes: commit first (the release is this commit)"

say "$HOST: the render (windows/build/$HOST)"
if [ -f "$REPO/bin/render-windows.sh" ]; then
  out="$(bash "$REPO/bin/render-windows.sh" --check 2>&1)" || die "the render is stale (bin/render-windows.sh --check):
$out
    render it (bin/render-windows.sh), commit, push again"
  ok "the render is current (bin/render-windows.sh --check)"
else
  warn "bin/render-windows.sh is not in this tree yet: the render's freshness is not checked (each file's sha256 still is)"
fi
[ -f "$MANIFEST" ] || die "no render for $HOST ($MANIFEST): bin/render-windows.sh $HOST, then commit"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/incoming/build"
manifest_py check "$MANIFEST" "$HOST" "$RENDER" >"$STAGE/files.tsv" 2>"$STAGE/err" || die "$(cat "$STAGE/err")"
ok "manifest.json: $(wc -l <"$STAGE/files.tsv" | tr -d ' ') files listed"

# the release's identity: this commit, its nearest release tag (exactly it: a tagged release)
COMMIT="$(git rev-parse HEAD)"
TAG="$(git describe --tags --exact-match --match 'v*' HEAD 2>/dev/null || true)"
NEAR="$(git describe --tags --abbrev=0 --match 'v*' HEAD 2>/dev/null || true)"
VERSION="${NEAR:-0.0.0-dev}" TAGGED=false AHEAD=0
if [ -n "$TAG" ]; then
  VERSION="$TAG" TAGGED=true
elif [ -n "$NEAR" ]; then
  AHEAD="$(git rev-list --count "$NEAR..HEAD")"
fi
BUILD_ID="$(git log -1 --date=format:%Y%m%d --format=%cd HEAD).$(git rev-parse --short HEAD)"

say "staging (install/lib/windows-stage.sh)"
# every files[] entry from the source the manifest names, each checked against its sha256
win_stage_build "$REPO" "$MANIFEST" "$STAGE/tree"
manifest_py extras "$MANIFEST" "$RENDER" "$STAGE/tree" "$STAGE/incoming/build" \
  "$VERSION" "$TAGGED" "$AHEAD" "$BUILD_ID" "$COMMIT" "$(git rev-parse --abbrev-ref HEAD)" \
  "$(git log -1 --format=%cI HEAD)" "$(date +%Y-%m-%dT%H:%M:%S%z | sed 's/\(..\)$/:\1/')" "$HOST" \
  2>"$STAGE/err" || die "$(cat "$STAGE/err")"
cp -R "$RENDER/." "$STAGE/incoming/build/"
# the render's release and commit ("unstaged" in the repo) are this one's
win_fill_release "$STAGE/incoming/build/manifest.json" "$(git describe --tags --always)" "$COMMIT"
cp "$REPO/install/windows/dram-windows/dram.ps1" "$STAGE/incoming/dram.ps1"
# the release's full list: every files[] entry, as staged here, must be what the render says
: >"$STAGE/list"
while IFS=$'\t' read -r p sum; do
  src="$STAGE/tree/$p"
  [ -f "$src" ] || die "the manifest lists $p, and nothing here stages it (install/lib/windows-stage.sh): is the render from another tree?"
  got="$(win_sha256 "$src")"
  [ "$got" = "$sum" ] || die "$p: sha256 $got here, $sum in the render - the render is stale or its source changed: render, commit, push again"
  printf '%s  %s\n' "$sum" "$p" >>"$STAGE/list"
done <"$STAGE/files.tsv"
(cd "$STAGE/incoming" && find build -type f) | LC_ALL=C sort | while IFS= read -r p; do
  printf '%s  %s\n' "$(win_sha256 "$STAGE/incoming/$p")" "$p"
done >>"$STAGE/list"
printf '%s  %s\n' "$(win_sha256 "$STAGE/incoming/dram.ps1")" dram.ps1 >>"$STAGE/list"
# one line per path, sorted; the same path twice must agree
dup="$(awk '{ p = substr($0, 67); if ((p in h) && h[p] != substr($0, 1, 64)) print p; h[p] = substr($0, 1, 64) }' "$STAGE/list")"
[ -z "$dup" ] || die "listed twice with two sha256: $dup"
awk '!seen[substr($0, 67)]++ { print substr($0, 67) "\t" $0 }' "$STAGE/list" | LC_ALL=C sort | cut -f2- >"$STAGE/stage.sha256"
ok "$(wc -l <"$STAGE/stage.sha256" | tr -d ' ') files in the release, each with the sha256 the render names"

[ -n "$TO" ] || TO="$(target_for "$HOST")"
[ -n "$TO" ] || die "no address for $HOST in windows/hosts/$HOST.nix or a WSL clone's host file: --to USER@ADDR"
# DRAM_WIN_SSH first: for each option ssh keeps the first value it is given
# shellcheck disable=SC2206 # DRAM_WIN_SSH is a list of options, split into words
O=(${DRAM_WIN_SSH:-} -o "HostKeyAlias=$HOST" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10
  -o ServerAliveInterval=30 -o ControlMaster=no -o ControlPath=none -o LogLevel=ERROR)
win() { ssh -n "${O[@]}" "$TO" "$@"; }

say "$TO ($HOST): what its live release holds"
win "if not exist $W mkdir $W" >/dev/null || die "ssh to $TO as $HOST failed (Windows on, its OpenSSH up? a PC in another OS answers with another host key)"
win "type $W\\build\\files.sha256 2>nul" 2>/dev/null | LC_ALL=C tr -d '\r' >"$STAGE/live" || true
send=0 kept=0
while IFS= read -r line; do
  p="${line:66}"
  case "$p" in build/* | dram.ps1) continue ;; esac
  if grep -qxF -- "$line" "$STAGE/live"; then
    kept=$((kept + 1))
    continue
  fi
  mkdir -p "$STAGE/incoming/$(dirname "$p")"
  cp "$STAGE/tree/$p" "$STAGE/incoming/$p"
  send=$((send + 1))
done <"$STAGE/stage.sha256"
cp "$STAGE/stage.sha256" "$STAGE/incoming/stage.sha256"
ok "$kept file(s) already there; $send to send, with the render and dram.ps1"

say "copy to $W\\incoming"
win "if exist $W\\incoming rmdir /s /q $W\\incoming" >/dev/null || die "could not clear $W\\incoming"
scp -q -r "${O[@]}" "$STAGE/incoming" "$TO:C:/ProgramData/dram/" || die "could not copy the release to $TO"
ok "staged: $VERSION (build $BUILD_ID)"

flags=""
[ "$DRY" = 1 ] && [ "$APPLY" = 0 ] && flags=" -DryRun"
[ "$FORCE" = 1 ] && flags="$flags -Force"
say "dram receive$flags"
win "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $W\\incoming\\dram.ps1 receive$flags" 2>&1 \
  | LC_ALL=C tr -d '\r' || die "dram receive refused the release or stopped (above)"
if [ "$APPLY" = 1 ]; then
  flags=""
  [ "$DRY" = 1 ] && flags=" -DryRun"
  say "dram apply$flags"
  win "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $W\\dram.ps1 apply$flags" 2>&1 \
    | LC_ALL=C tr -d '\r' || die "dram apply exited nonzero (above): dram doctor there names what is left"
fi
if [ "$DRY" = 1 ] && [ "$APPLY" = 0 ]; then
  ok "$HOST: $VERSION (build $BUILD_ID) checked in $W\\incoming, not switched: dram receive (or dram update) there takes it"
elif [ "$DRY" = 1 ]; then
  ok "$HOST: $VERSION (build $BUILD_ID) received; the dry run changed nothing else"
elif [ "$APPLY" = 1 ]; then
  ok "$HOST: $VERSION (build $BUILD_ID) received and applied"
else
  ok "$HOST: $VERSION (build $BUILD_ID) received: dram apply there (or --apply) converges to it"
fi

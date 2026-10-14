#!/usr/bin/env bash
# usage: push-windows.sh
#
# Test tier T0 for bin/push-windows.sh, install/windows/apply-windows.sh and
# install/lib/windows-stage.sh (decisions/0020), any machine with bash,
# git, python3, bsdtar and curl; no Windows, no network. A throwaway repo holds the sources the
# fixture names, stand-in pins (fonts and cursors fetched from file://) and the render
# tests/fixtures/cabin-win.manifest.json with its three documents (tests/fixtures/cabin-win/),
# in the renderer's shape (bin/render-windows.sh): each files[] entry with its source, the
# documents under build/; each sha256 is filled in from the sources and the stand-ins. It
# pushes to a stand-in ssh and scp that log every command and play cmd.exe on a directory
# standing for C:\. Checked: bad usage, a dirty tree, a missing or stale render, the renderer's
# check, manifests a host would refuse, the library (the manifest's files and nothing else,
# members, --exclude, a pin's sha256, two lines staging one name, the members list), the first
# push (every file, stage.sha256 = the manifest's sums, the release filled in, packages.tsv with
# a Script unit's id from its file, push.json, the address from the WSL clone's host file, then
# from windows/hosts/, HostKeyAlias, no multiplexing), the next one (only what changed travels),
# the receive and apply calls and their flags, a failed connection, receive or apply, and
# install/windows/apply-windows.sh staging the same files through the library, the render in
# build\. dram.ps1 cannot run here (no PowerShell): the stand-in plays its receive. Changes
# nothing outside a temp dir. bin/check.sh runs it.
#
#   -h, --help    this text
#
# exit: 0 every check passed · 1 a check failed · 2 bad usage
# see: docs/operations/releases/pushes.md

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

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAILS=0
ok() { echo "ok   $1"; }
bad() {
  echo "FAIL $1${2:+ — $2}"
  FAILS=$((FAILS + 1))
}
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want '$3', got '$2'"; fi; }
expect() { if eval "$2"; then ok "$1"; else bad "$1" "$(tail -3 "$T/out" 2>/dev/null | tr '\n' ' ')"; fi; }
sha() { shasum -a 256 "$1" | awk '{print $1}'; }

# --- the stand-ins: ssh and scp to a Windows PC --------------------------------------------------
mkdir -p "$T/bin"
cat >"$T/bin/ssh" <<'EOF'
#!/usr/bin/env bash
# a stand-in for ssh to a Windows PC: logs each command (its options in $FAKE_LOG.opts), and
# plays cmd.exe for the ones push-windows.sh and apply-windows.sh send, on $FAKE_C standing for C:\
o=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o | -i | -p | -F | -l | -J)
      o="$o $1 $2"
      shift 2
      ;;
    -*)
      o="$o $1"
      shift
      ;;
    *) break ;;
  esac
done
t="$1"
shift
cmd="$*"
printf 'ssh %s %s\n' "$t" "$cmd" >>"$FAKE_LOG"
printf '%s\n' "$o" >>"$FAKE_LOG.opts"
[ "${FAKE_SSH_DOWN:-0}" = 1 ] && exit 255
c() { printf '%s' "$1" | sed -e 's|^[Cc]:[\\/]|'"$FAKE_C"'/|' -e 's|\\|/|g'; }
D="$FAKE_C/ProgramData/dram"
case "$cmd" in
  'if not exist '*' mkdir '*) mkdir -p "$(c "${cmd##* mkdir }")" ;;
  'if exist '*' rmdir /s /q '*' & mkdir '*)
    a="${cmd#* rmdir /s /q }"
    rm -rf "$(c "${a%% & *}")"
    mkdir -p "$(c "${cmd##* mkdir }")"
    ;;
  'if exist '*' rmdir /s /q '*) rm -rf "$(c "${cmd##* rmdir /s /q }")" ;;
  'type '*' 2>nul')
    f="${cmd#type }"
    f="$(c "${f% 2>nul}")"
    [ -f "$f" ] || exit 1
    awk '{ printf "%s\r\n", $0 }' "$f"
    ;;
  'for %d in ('*' rmdir /s /q '*)
    n="${cmd#*(}"
    for x in ${n%%)*}; do rm -rf "${D:?}/$x"; done
    ;;
  'for %d in ('*)
    n="${cmd#*(}"
    for x in ${n%%)*}; do mkdir -p "$D/$x"; done
    ;;
  *'incoming\dram.ps1 receive'*)
    case "$cmd" in *-DryRun*)
      echo "[ok] stand-in receive -DryRun"
      exit "${FAKE_RECEIVE_RC:-0}"
      ;;
    esac
    if [ "${FAKE_RECEIVE_RC:-0}" != 0 ]; then
      echo "[x] stand-in receive refused"
      exit "$FAKE_RECEIVE_RC"
    fi
    (cd "$D/incoming" && find . -type f ! -path './build/*' ! -name stage.sha256) | while IFS= read -r f; do
      mkdir -p "$D/$(dirname "$f")"
      cp "$D/incoming/$f" "$D/$f"
    done
    rm -rf "$D/build"
    mv "$D/incoming/build" "$D/build"
    cp "$D/incoming/stage.sha256" "$D/build/files.sha256"
    rm -rf "$D/incoming"
    echo "[ok] stand-in receive"
    ;;
  *'dram.ps1 apply'*)
    echo "[ok] stand-in apply"
    exit "${FAKE_APPLY_RC:-0}"
    ;;
  powershell*) echo "stand-in powershell" ;;
esac
exit 0
EOF
cat >"$T/bin/scp" <<'EOF'
#!/usr/bin/env bash
# a stand-in for scp to a Windows PC: copies into $FAKE_C (C:\); what a copy of incoming\
# carried is listed in $FAKE_SENT
a=()
while [ $# -gt 0 ]; do
  case "$1" in
    -o | -i | -P | -F | -l | -J | -S) shift 2 ;;
    -*) shift ;;
    *)
      a+=("$1")
      shift
      ;;
  esac
done
n=$((${#a[@]} - 1))
dest="${a[$n]}"
printf 'scp %s\n' "${a[*]}" >>"$FAKE_LOG"
[ "${FAKE_SSH_DOWN:-0}" = 1 ] && exit 255
d="$FAKE_C/${dest#*:C:/}"
i=0
while [ "$i" -lt "$n" ]; do
  s="${a[$i]}"
  case "$d" in
    */) mkdir -p "$d" && cp -R "$s" "$d" ;;
    *) if [ -d "$d" ]; then cp -R "$s" "$d/"; else cp -R "$s" "$d"; fi ;;
  esac
  if [ -d "$s" ] && [ "${s##*/}" = incoming ]; then (cd "$s/.." && find incoming -type f | LC_ALL=C sort) >"$FAKE_SENT"; fi
  i=$((i + 1))
done
exit 0
EOF
chmod +x "$T/bin/ssh" "$T/bin/scp"

# --- the throwaway repo -------------------------------------------------------------------------
SB="$T/repo"
FIX="$REPO/tests/fixtures/cabin-win.manifest.json"
mkdir -p "$SB/bin" "$SB/modules" "$SB/windows/build/cabin-win"
cp "$REPO/bin/push-windows.sh" "$SB/bin/"
cp -R "$REPO/install" "$SB/"
cp -R "$REPO/modules/hosts" "$SB/modules/"
cp "$REPO"/tests/fixtures/cabin-win/*.winget "$SB/windows/build/cabin-win/"
# shellcheck source=install/lib/windows-stage.sh
. "$REPO/install/lib/windows-stage.sh"
# every repo file the fixture stages, from this tree
python3 -I -c 'import json, sys
for f in json.load(open(sys.argv[1]))["files"]:
    k, _, s = f["source"].partition(":")
    if k == "repo":
        print(s)' "$FIX" | while IFS= read -r src; do
  mkdir -p "$SB/$(dirname "$src")" && cp "$REPO/$src" "$SB/$src"
done
# the stand-in downloads: an archive with a member to take, one to --exclude and one no pattern
# names; single files taken as themselves (one under a name with brackets, as EB Garamond's)
mkdir -p "$T/src/z/monaspace/fonts"
printf 'xenon\n' >"$T/src/z/monaspace/fonts/MonaspaceXenon-Regular.otf"
printf 'wide\n' >"$T/src/z/monaspace/fonts/MonaspaceXenonWide-Regular.otf"
printf 'readme\n' >"$T/src/z/monaspace/README.md"
(cd "$T/src/z" && bsdtar -a -cf "$T/src/monaspace.zip" monaspace)
printf 'symbols\n' >"$T/src/symbols.ttf"
printf 'garamond\n' >"$T/src/garamond.ttf"
printf 'arrow\n' >"$T/src/default.cur"
printf 'busy\n' >"$T/src/progress.ani"
{
  echo "# stand-in fonts.pin (tests/push-windows.sh)"
  echo "monaspace file://$T/src/monaspace.zip $(sha "$T/src/monaspace.zip") --exclude=*Wide* *MonaspaceXenon-*.otf"
  echo "nerd-symbols file://$T/src/symbols.ttf $(sha "$T/src/symbols.ttf") =SymbolsNerdFontMono-Regular.ttf"
  echo "eb-garamond file://$T/src/garamond.ttf $(sha "$T/src/garamond.ttf") =EBGaramond[wght].ttf"
} >"$SB/install/windows/fonts.pin"
{
  echo "# stand-in cursors.pin (tests/push-windows.sh)"
  echo "Arrow file://$T/src/default.cur $(sha "$T/src/default.cur") =default.cur"
  echo "AppStarting file://$T/src/progress.ani $(sha "$T/src/progress.ani") =progress.ani"
} >"$SB/install/windows/cursors.pin"
export XDG_CACHE_HOME="$T/cache"
# the stand-in pins' files, fetched once by the library, for the fixture's pin: sums
(win_fetch_pin "$SB" fonts.pin fonts "$T/pins/fonts" ttf otf && win_fetch_pin "$SB" cursors.pin cursors "$T/pins/cursors" cur ani) \
  >"$T/pins.out" 2>&1 || bad "the stand-in pins stage" "$(tail -2 "$T/pins.out" | tr '\n' ' ')"
fill() { # fill <out>: the fixture with each files[] sha256 from its source (a pin's: the stand-in's file)
  python3 -I - "$FIX" "$1" "$SB" "$T/pins" <<'PY'
import hashlib, json, os, sys
src, out, repo, pins = sys.argv[1:5]
with open(src) as f:
    m = json.load(f)
for e in m["files"]:
    kind, _, s = e["source"].partition(":")
    p = os.path.join(pins, e["path"]) if kind == "pin" else os.path.join(repo, s)
    with open(p, "rb") as f:
        e["sha256"] = hashlib.sha256(f.read()).hexdigest()
with open(out, "w") as f:
    json.dump(m, f, indent=1)
PY
}
stage_tree() { # stage_tree [manifest]: what the library stages from the throwaway repo, in $T/tree
  rm -rf "$T/tree"
  (win_stage_build "$SB" "${1:-$MAN}" "$T/tree") >"$T/stage.out" 2>&1
}
g() { git -C "$SB" -c user.name=t -c user.email=t@example.invalid -c init.defaultBranch=main "$@"; }
commit() { g add -A && g commit -qm "$1"; }
MAN="$SB/windows/build/cabin-win/manifest.json"
fill "$MAN"
cp "$MAN" "$T/manifest.good"
g init -q
commit fixture

# --- the library ------------------------------------------------------------------------------
stage_tree
expect_eq "lib: the render stages" "$?" 0
L="$T/tree"
python3 -I -c 'import json, os, sys
want = {f["path"] for f in json.load(open(sys.argv[1]))["files"]}
have = {os.path.relpath(os.path.join(d, n), sys.argv[2]).replace(os.sep, "/") for d, _, ns in os.walk(sys.argv[2]) for n in ns}
sys.exit(0 if want == have else 1)' "$MAN" "$L"
expect_eq "lib: exactly the manifest's files, at its paths" "$?" 0
expect "lib: the documents under build/, a unit's file under units/" '[ -f "$L/build/30-machine.winget" ] && [ -f "$L/units/battle-net.ps1" ] && [ -f "$L/look.ps1" ]'
if cmp -s "$L/letterpress.png" "$SB/system/refind-letterpress/background.png"; then ok "lib: letterpress.png is the rEFInd art"; else bad "lib: letterpress.png is the rEFInd art"; fi
if cmp -s "$L/starship.toml" "$SB/dotfiles/.config/starship.toml"; then ok "lib: starship.toml byte for byte"; else bad "lib: starship.toml byte for byte"; fi
expect "lib: the archive's member is taken" '[ -f "$L/fonts/MonaspaceXenon-Regular.otf" ]'
expect "lib: --exclude drops a matching member" '[ ! -e "$L/fonts/MonaspaceXenonWide-Regular.otf" ]'
expect "lib: a member no pattern names stays out" '[ ! -e "$L/fonts/README.md" ]'
expect "lib: =NAME keeps a name with brackets" '[ -f "$L/fonts/EBGaramond[wght].ttf" ]'
expect "lib: cursors with their pin and the NOTICE" '[ -f "$L/cursors/default.cur" ] && [ -f "$L/cursors/cursors.pin" ] && grep -q "GNOME Project" "$L/cursors/NOTICE"'
python3 -I -c 'import json, sys
m = json.load(open(sys.argv[1]))
m["files"][0]["sha256"] = "f" * 64
json.dump(m, open(sys.argv[2], "w"))' "$MAN" "$T/man.bad"
stage_tree "$T/man.bad"
expect_eq "lib: a file whose sha256 is not the manifest's is refused" "$?:$(grep -c 'sha256 differs' "$T/stage.out")" "1:1"
python3 -I -c 'import json, sys
m = json.load(open(sys.argv[1]))
m["files"][0]["source"] = "http:" + m["files"][0]["source"]
json.dump(m, open(sys.argv[2], "w"))' "$MAN" "$T/man.bad"
stage_tree "$T/man.bad"
expect_eq "lib: a source of an unknown kind is refused" "$?:$(grep -c 'unknown source' "$T/stage.out")" "1:1"
mkdir -p "$T/badrepo/install/windows"
printf 'x file://%s/src/symbols.ttf %s =x.ttf\n' "$T" "$(printf '%064d' 0)" >"$T/badrepo/install/windows/fonts.pin"
out="$( (win_fetch_pin "$T/badrepo" fonts.pin bad "$T/bad") 2>&1)"
rc=$?
expect_eq "lib: a download whose sha256 is not the pin's is refused" "$rc:$(printf '%s' "$out" | grep -c 'refused')" "1:1"
printf 'x file://%s/src/symbols.ttf %s =README.md\n' "$T" "$(sha "$T/src/symbols.ttf")" >"$T/badrepo/install/windows/fonts.pin"
out="$( (win_fetch_pin "$T/badrepo" fonts.pin bad2 "$T/bad2" ttf otf) 2>&1)"
rc=$?
expect_eq "lib: a file of another kind than the pin's is refused" "$rc:$(printf '%s' "$out" | grep -c 'not a ttf otf')" "1:1"
printf 'x file://%s/src/symbols.ttf %s =x.ttf\ny file://%s/src/garamond.ttf %s =x.ttf\n' "$T" "$(sha "$T/src/symbols.ttf")" "$T" "$(sha "$T/src/garamond.ttf")" >"$T/badrepo/install/windows/fonts.pin"
out="$( (win_fetch_pin "$T/badrepo" fonts.pin bad3 "$T/bad3") 2>&1)"
rc=$?
expect_eq "lib: two lines staging one name are refused" "$rc:$(printf '%s' "$out" | grep -c 'staged already')" "1:1"
out="$( (WIN_PIN_MEMBERS="$T/members" win_fetch_pin "$SB" fonts.pin m "$T/m") 2>&1)"
expect_eq "lib: the members list names each file with its line" "$(cut -d' ' -f1,3 "$T/members" | LC_ALL=C sort | tr '\n' ';')" "eb-garamond EBGaramond[wght].ttf;monaspace MonaspaceXenon-Regular.otf;nerd-symbols SymbolsNerdFontMono-Regular.ttf;"

# --- push-windows.sh -------------------------------------------------------------------------------
run() { # run <args...>: bin/push-windows.sh in the throwaway repo; output in $T/out, exit code in RC
  : >"$T/log"
  : >"$T/log.opts"
  rm -f "$T/sent"
  (cd "$SB" && env PATH="$T/bin:$PATH" FAKE_C="$T/C" FAKE_LOG="$T/log" FAKE_SENT="$T/sent" \
    FAKE_SSH_DOWN="${FAKE_SSH_DOWN:-0}" FAKE_RECEIVE_RC="${FAKE_RECEIVE_RC:-0}" FAKE_APPLY_RC="${FAKE_APPLY_RC:-0}" \
    bash bin/push-windows.sh "$@") >"$T/out" 2>&1
  RC=$?
}
logged() { grep -cF -- "$1" "$T/log" | tr -d ' '; } # how many logged commands hold the text
logged_end() { S="$1" awk 'BEGIN { s = ENVIRON["S"] } substr($0, length($0) - length(s) + 1) == s { n++ } END { print n + 0 }' "$T/log"; }
D="$T/C/ProgramData/dram"

run
expect_eq "no host: exit 2" "$RC" 2
run cabin-win --bogus
expect_eq "a bogus flag: exit 2" "$RC" 2
run cabin-win --help
expect_eq "--help: exit 0, a usage: line" "$RC:$(head -1 "$T/out" | cut -c1-6)" "0:usage:"
touch "$SB/stray"
run cabin-win
expect_eq "a dirty tree: exit 1, nothing sent" "$RC:$(wc -l <"$T/log" | tr -d ' ')" "1:0"
rm -f "$SB/stray"
run thermos --to pj@10.0.0.9
expect "no render for the host: exit 1, said so" '[ "$RC" = 1 ] && grep -q "no render for thermos" "$T/out"'

with_manifest() { # with_manifest <python on m> <what>: a manifest changed so, committed; expects a refusal
  python3 -I -c 'import json, sys
m = json.load(open(sys.argv[1]))
exec(sys.argv[2])
json.dump(m, open(sys.argv[1], "w"), indent=1)' "$MAN" "$1"
  commit "$2"
  run cabin-win
  expect "refused before any ssh: $2" '[ "$RC" = 1 ] && [ ! -s "$T/log" ]'
  cp "$T/manifest.good" "$MAN"
  commit "the good manifest again"
}
with_manifest 'm["files"].append({"path": "../evil.ps1", "sha256": "0" * 64})' "a path outside C:\\ProgramData\\dram"
with_manifest 'm["files"].append({"path": "letterpress/nope.json", "sha256": "0" * 64})' "a file nothing stages"
with_manifest 'm["host"] = "thermos"' "a manifest for another host"
with_manifest 'm["scripts"][0]["phase"] = "60"' "an unknown phase"
with_manifest 'm["documents"].append({"file": "gone.winget", "phase": "10", "scope": "user"})' "a document in neither the render nor files[]"
with_manifest 'm["documents"][0]["scope"] = "everyone"' "a scope neither machine nor user"
with_manifest 'm["files"][0]["sha256"] = "f" * 64' "a sha256 that is not the staged file's (a stale render)"

printf '#!/usr/bin/env bash\nexit 3\n' >"$SB/bin/render-windows.sh"
commit "a renderer that finds the render stale"
run cabin-win
expect "the renderer's check fails: exit 1, nothing sent" '[ "$RC" = 1 ] && grep -q "the render is stale" "$T/out" && [ ! -s "$T/log" ]'
rm -f "$SB/bin/render-windows.sh"
commit "no renderer"

# the first push: everything travels
run cabin-win
expect_eq "first push: exit 0" "$RC" 0
expect "first push: says the renderer is not in the tree" 'grep -q "render-windows.sh is not in this tree yet" "$T/out"'
expect "first push: the address from cabin-wsl's host file" 'grep -q "^ssh pj@cabin if not exist" "$T/log"'
expect "first push: the live list read with type" '[ "$(logged "type C:\\ProgramData\\dram\\build\\files.sha256 2>nul")" = 1 ]'
expect "first push: one scp, of incoming" '[ "$(grep -c "^scp " "$T/log")" = 1 ] && grep -q "^scp .*/incoming pj@cabin:C:/ProgramData/dram/$" "$T/log"'
expect "first push: the incoming dram.ps1 receives, no -DryRun, no apply" '[ "$(logged_end "incoming\\dram.ps1 receive")" = 1 ] && [ "$(logged " apply")" = 0 ]'
# files[] (its documents are the render's), the render's manifest, packages.tsv, push.json, dram.ps1, stage.sha256
expect_eq "first push: every file travels" "$(grep -c . "$T/sent")" "$(($(grep -c '"path"' "$MAN") + 5))"
expect "first push: the render, the engine and the list travel" 'grep -qx incoming/build/manifest.json "$T/sent" && grep -qx incoming/build/30-machine.winget "$T/sent" && grep -qx incoming/dram.ps1 "$T/sent" && grep -qx incoming/stage.sha256 "$T/sent"'
expect "every ssh: -n, HostKeyAlias=cabin-win, never multiplexed" '[ "$(grep -c . "$T/log.opts")" = "$(grep -c "^ssh " "$T/log")" ] && [ "$(grep -vc -- "-n .*HostKeyAlias=cabin-win .*-o ControlMaster=no -o ControlPath=none" "$T/log.opts")" = 0 ]'
python3 -I - "$MAN" "$D/build/files.sha256" "$D" >"$T/py.out" 2>&1 <<'PY'
import hashlib, json, sys
man, lst, root = sys.argv[1:4]
m = {e["path"]: e["sha256"] for e in json.load(open(man))["files"]}
got = {}
for l in open(lst):
    h, p = l.rstrip("\n").split("  ", 1)
    got[p] = h
bad = [p for p, h in m.items() if got.get(p) != h]
bad += [p for p, h in got.items() if hashlib.sha256(open(root + "/" + p, "rb").read()).hexdigest() != h]
extra = sorted(set(got) - set(m))
print("bad=%d" % len(bad))
print("extra: " + " ".join(extra))
PY
expect "stage.sha256: each files[] path with the manifest's sha256, each file as listed" 'grep -qx "bad=0" "$T/py.out"'
expect "stage.sha256: beyond files[], only the render's manifest, push.json, packages.tsv and the engine" 'grep -qx "extra: build/manifest.json build/packages.tsv build/push.json dram.ps1" "$T/py.out"'
P="$D/build/packages.tsv"
units="$(cat "$SB"/windows/build/cabin-win/*.winget | grep -c 'resource: "Microsoft.WinGet.DSC/WinGetPackage"')"
expect_eq "packages.tsv: each WinGetPackage unit, and the id in battle-net's unit file" "$(grep -vc '^#' "$P")" "$((units + 1))"
TAB=$'\t'
for row in "Valve.Steam${TAB}winget${TAB}Present${TAB}30-machine.winget" "9NCBCSZSJRSB${TAB}msstore${TAB}Present${TAB}30-user.winget" \
  "glzr-io.zebar${TAB}winget${TAB}Present${TAB}30-machine.winget" "Blizzard.BattleNet${TAB}winget${TAB}Present${TAB}30-machine.winget"; do
  id="${row%%"$TAB"*}"
  if grep -qxF "$row" "$P"; then ok "packages.tsv: $id"; else bad "packages.tsv: $id" "$(grep -F "$id" "$P")"; fi
done
J="$D/build/push.json"
pj() { python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$J" "$1"; }
expect_eq "push.json: this commit" "$(pj commit)" "$(g rev-parse HEAD)"
expect_eq "push.json: no tag yet" "$(pj version):$(pj tagged)" "0.0.0-dev:False"
expect "push.json: build <date>.<sha>" 'pj build | grep -qE "^[0-9]{8}\.[0-9a-f]{7,}$"'
mj() { python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$D/build/manifest.json" "$1"; }
expect_eq "the received manifest: release and commit filled in, unstaged in the repo" \
  "$(mj release):$(mj commit):$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["commit"])' "$MAN")" \
  "$(g describe --tags --always):$(g rev-parse HEAD):unstaged"

# the next push: only what changed travels
printf '{"accent": "changed"}\n' >"$SB/install/windows/letterpress/accent.json"
fill "$MAN"
cp "$MAN" "$T/manifest.good"
commit "a palette change"
g tag v2026.10.99
run cabin-win --apply
expect_eq "next push --apply: exit 0" "$RC" 0
expect "next push: the changed file travels" 'grep -qx incoming/letterpress/accent.json "$T/sent"'
expect "next push: an unchanged file stays home" '! grep -qE "incoming/(avatar|fonts)/|incoming/look.ps1" "$T/sent"'
expect "next push: the render, the engine and the list still travel" 'grep -qx incoming/build/manifest.json "$T/sent" && grep -qx incoming/dram.ps1 "$T/sent" && grep -qx incoming/stage.sha256 "$T/sent"'
expect "next push --apply: receive, then apply (no -DryRun)" 'awk "/ receive\$/ { r = NR } / apply\$/ { a = NR } END { exit !(r && a && r < a) }" "$T/log"'
expect_eq "push.json: the tag" "$(pj version):$(pj tagged):$(pj ahead)" "v2026.10.99:True:0"

run cabin-win --dry-run
expect "--dry-run: receive -DryRun, no apply" '[ "$RC" = 0 ] && [ "$(logged_end "receive -DryRun")" = 1 ] && [ "$(logged " apply")" = 0 ]'
run cabin-win --apply --dry-run --force
expect "--apply --dry-run --force: receive -Force, then apply -DryRun" '[ "$RC" = 0 ] && [ "$(logged_end "receive -Force")" = 1 ] && [ "$(logged_end "apply -DryRun")" = 1 ]'
run cabin-win --to someone@10.0.0.9
expect "--to: the ssh target" '[ "$RC" = 0 ] && grep -q "^ssh someone@10.0.0.9 " "$T/log" && ! grep -q "@cabin" "$T/log"'
mkdir -p "$SB/windows/hosts"
printf '{ ... }:\n{\n  windows = {\n    host = "cabin-win";\n    address = "10.0.0.5";   # a comment\n    user = "pj";\n  };\n}\n' >"$SB/windows/hosts/cabin-win.nix"
commit "a host file with an address"
run cabin-win
expect "the address from windows/hosts/<host>.nix first" '[ "$RC" = 0 ] && grep -q "^ssh pj@10.0.0.5 if not exist" "$T/log" && ! grep -q "@cabin" "$T/log"'
rm -rf "$SB/windows/hosts"
commit "the host file gone again"
FAKE_SSH_DOWN=1 run cabin-win
expect "no connection: exit 1, nothing copied" '[ "$RC" = 1 ] && grep -q "ssh to pj@cabin as cabin-win failed" "$T/out" && [ "$(grep -c "^scp " "$T/log")" = 0 ]'
FAKE_RECEIVE_RC=1 run cabin-win --apply
expect "a refused receive: exit 1, no apply" '[ "$RC" = 1 ] && [ "$(logged " apply")" = 0 ]'
FAKE_APPLY_RC=1 run cabin-win --apply
expect "a failed apply: exit 1" '[ "$RC" = 1 ] && grep -q "dram apply exited nonzero" "$T/out"'

# --- apply-windows.sh: the same staging through the library ---------------------------------------
: >"$T/log"
(cd "$SB" && env PATH="$T/bin:$PATH" FAKE_C="$T/C2" FAKE_LOG="$T/log" FAKE_SENT="$T/sent" \
  bash install/windows/apply-windows.sh --host pj@10.0.0.7 --dry-run) >"$T/out" 2>&1
RC=$?
# shellcheck disable=SC2034 # read by the expect lines below
A="$T/C2/ProgramData/dram"
expect_eq "apply-windows.sh --dry-run: exit 0" "$RC" 0
expect "apply-windows.sh: the fonts and their SHA256SUMS" '[ -f "$A/fonts/MonaspaceXenon-Regular.otf" ] && [ -f "$A/fonts/EBGaramond[wght].ttf" ] && [ -f "$A/fonts/SHA256SUMS" ]'
expect "apply-windows.sh: the cursors, the pin and the NOTICE" '[ -f "$A/cursors/progress.ani" ] && [ -f "$A/cursors/cursors.pin" ] && grep -q "GNOME Project" "$A/cursors/NOTICE"'
expect "apply-windows.sh: letterpress, the art, the seal, the shared files" '[ -f "$A/letterpress/accent.json" ] && [ -f "$A/letterpress.png" ] && [ -f "$A/avatar/pj-32.png" ] && [ -f "$A/librewolf/userChrome.css" ] && [ -f "$A/letterpress-colors.css" ]'
expect "apply-windows.sh: the units' files" '[ -f "$A/units/battle-net.ps1" ] && [ -f "$A/units/fonts-machine.ps1" ]'
expect "apply-windows.sh: the render in build\\, its release filled in" '[ -f "$A/build/30-user.winget" ] && [ "$(python3 -I -c "import json, sys; print(json.load(open(sys.argv[1]))[\"commit\"])" "$A/build/manifest.json")" = "$(g rev-parse HEAD)" ]'
expect "apply-windows.sh: says the renderer is not in the tree" 'grep -q "render-windows.sh is not in this tree" "$T/out"'
expect "apply-windows.sh: the converge, as a dry run" '[ "$(logged "converge.ps1 -DryRun")" = 1 ]'
# a second run: the fonts and cursors stay where they are
: >"$T/log"
(cd "$SB" && env PATH="$T/bin:$PATH" FAKE_C="$T/C2" FAKE_LOG="$T/log" FAKE_SENT="$T/sent" \
  bash install/windows/apply-windows.sh --host pj@10.0.0.7 --dry-run) >"$T/out" 2>&1
expect "apply-windows.sh again: fonts and cursors unchanged, not copied" 'grep -q "fonts: unchanged" "$T/out" && grep -q "cursors: unchanged" "$T/out" && ! grep -q "^scp .*/fonts " "$T/log"'

[ "$FAILS" -eq 0 ] || {
  echo "push-windows: $FAILS check(s) failed" >&2
  exit 1
}
echo "push-windows: all checks passed"

#!/usr/bin/env bash
# check.sh — repo invariants that need NO nix, runnable on the Mac (bash 3.2)
# or any host. `dram check` runs this, then `nix flake check` where nix exists.
#
#   1. every link "..." target in modules/*.nix exists under dotfiles/
#      (gitignored runtime seeds excepted)
#   2. hosts agree: modules/hosts/<h>.nix <-> hosts/<h>/ (flake.nix derives its
#      outputs from the directory)
#   3. packages/*.txt + packages/roles/*.txt: no inline comments, no duplicates, no AUR
#      names in repo lists; warns when a declared name is installed on no host, or a
#      host's explicit package is in no manifest that host reads (hosts/<h>/packages/ is
#      the evidence; a host's lists come from install/lib/roles.sh, decisions/0009; a
#      metal host reads metal.txt and its hardware lists, a WSL clone neither);
#      with CHECK_PKGDB=1, every name must resolve in core/extra/multilib or [dram]
#      (bin/check-pkgnames.py; downloads the sync databases, so it is opt-in)
#   4. shellcheck + shfmt -i 2 -ci -bn -d on every bash script (legacy/ excluded)
#   5. no python program hiding behind a .sh name
#   6. docs at any depth: every relative Markdown link and #anchor resolves, every
#      backticked repo path exists, every see: line of a script header names a real
#      path (bin/check-docs.py links see; docs/history/ and decisions/0007 excluded)
#   7. no tracked secrets
#   8. flake.lock age (warn > 60 days)
#   9. every /usr/bin/<bin> referenced by modules/*.nix is a package in a manifest
#  10. waybar *.jsonc parse as JSON once // comments are stripped; captions and
#      spacing follow docs/design/README.md (bin/check-waybar.py)
#  11. every modules/hosts/<h>.nix sets dram.hostName, dram.roles (one line, every role
#      a packages/roles/<r>.txt), dram.isLaptop, dram.gpu (no defaults in options.nix);
#      backupPeer/backupPeerAddr only matter with dram.backup.enable (decisions/0014)
#  12. pkgs/: manifest <-> directories, pins, no shadowing (bin/pkgs.sh check)
#  13. every script answers --help on a stub PATH, a bogus flag exits 2, scripts
#      with a usage: header are 100755; docs/commands.md matches the headers
#  14. themes/<t>/ share one schema (bin/check-themes.py); /home/pj is
#      hardcoded nowhere under dotfiles/.config
#  15. every installed name has a verdict in packages/register.tsv; no expired waiver,
#      no forbidden name (bin/check-register.py, decisions/0013); swap/pending warn,
#      and fail under CHECK_ROLLOUT=1 (set it before rebuilding a machine). Windows' lists
#      (packages/winget/) too: every WinGetPackage unit in install/windows/*.winget is
#      listed, and a "= <name> (Arch)" row keeps that Arch row's verdict and date
#  16. Gaming Mode switching (tests/gaming-switch.sh); hypr/*.lua parse
#  17. recording: rec against a mock obs-websocket; dotfiles/obs/ holds no keys
#  18. YubiKeys: keys/ssh.pub and keys/pam-u2f.txt formats, one label per key across
#      them and .sops.yaml; the pam_u2f hook and --register-yubikey (tests/yubikey-t0.sh)
#  19. Windows: install/windows/letterpress/ matches what bin/gen-windows-look.py renders
#      from the palettes; every build in windows/build/ is current - the stamp: each file its
#      inputs.json lists hashed again, the directories it read listed again (bin/render-windows.sh
#      --check, no Nix; `nix flake check` compares the build itself, decisions/0020); every
#      *.ps1, *.winget and build file under install/windows and windows is ASCII (Windows
#      PowerShell 5.1 reads a BOM-less file as the ANSI code page); bin/push-windows.sh,
#      install/windows/apply-windows.sh and install/lib/windows-stage.sh against a stand-in
#      ssh/scp (tests/push-windows.sh, T0)
#  20. the case display (pkgs/dram-case-display): tests/case-display.py (T0) — the frame's
#      test vectors, the usbfs ioctls, the sysfs lookup, NVML and the loop against fakes
#  21. WSL clones (decisions/0021): every packages/wsl-skip.tsv row has a reason and names
#      something a list declares; a clone's plan (base + roles + the [dram] every-host set,
#      minus wsl-skip) holds no metal/hardware name and no [dram] name; no session role
#  22. the org chart: docs/map.tsv places every tracked path; every directorate and
#      division of the chart has its page (bin/check-docs.py map)
#  23. the generated records pages are current: docs/catalogue.md (bin/gen-catalogue.py,
#      from each module README's fact box), decisions/README.md and the chart in README.md
#      and docs/README.md (bin/gen-org-doc.py)
#  24. no private words in tracked text (bin/check-docs.py private): addresses, serial
#      numbers, mail addresses and other terms the clone's own list names, outside the repo
#
# Exit 1 on any failure; warnings do not fail. A shfmt diff is a failure (the
# scripts have been shfmt-clean since 2026-10-07); the remaining style finding
# (python behind a .sh name) is a warning unless CHECK_STRICT=1. §6, §22 and §24
# follow DOCS_GUARDS below: failures, or warnings with CHECK_DOCS=warn. Needs git, grep,
# awk, python3; the two linters are
# skipped with a warning when not installed.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1
FAIL=0 WARN=0
sec() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
fail() {
  FAIL=$((FAIL + 1))
  printf '\033[1;31m[FAIL]\033[0m %s\n' "$*"
}
warn() {
  WARN=$((WARN + 1))
  printf '\033[1;33m[warn]\033[0m %s\n' "$*"
}
have() { command -v "$1" >/dev/null 2>&1; }
# style: warn by default, fail with CHECK_STRICT=1
style() { if [ "${CHECK_STRICT:-0}" = 1 ]; then fail "$@"; else warn "$@"; fi; }

# The documentation guards (§6, §22, §24) fail on a finding. CHECK_DOCS=warn turns their
# findings into warnings for one run, with the first 25 of each listed.
DOCS_GUARDS="${CHECK_DOCS:-fail}"
# docs_check <check>...: one ok, warn or fail line per check from bin/check-docs.py, then
# its first 25 findings; a failure only when DOCS_GUARDS is fail
docs_check() {
  local dargs="" out line rest name found=""
  [ "$DOCS_GUARDS" = fail ] && dargs="--strict"
  # shellcheck disable=SC2086 # dargs is empty or one flag
  out="$(python3 -I bin/check-docs.py $dargs "$@" 2>&1)"
  while IFS= read -r line; do
    rest="${line#* }" name="${line#* }"
    name="${name%%:*}"
    case "$line" in
      "FAIL "*" finding(s) in "* | "WARN "*" finding(s) in "*)
        if [ "$DOCS_GUARDS" = fail ]; then fail "$rest"; else warn "$rest (DOCS_GUARDS=warn)"; fi
        blist "$found" 25
        printf '      every one: python3 bin/check-docs.py %s\n' "$name"
        found=""
        ;;
      "FAIL "* | "WARN "*) found="${found:+$found
}${rest#"$name": }" ;;
      "OK "*) ok "$rest" ;;
      ?*) fail "check-docs.py: $line" ;;
    esac
  done <<<"$out"
}

# --- 1) link targets ------------------------------------------------------------
sec "1. dotfile link targets (modules/*.nix -> dotfiles/)"
n=0 bad=0
for p in $(grep -ohE '= link "[^"]+"' modules/*.nix modules/hosts/*.nix | sed 's/= link "//; s/"$//' | sort -u); do
  n=$((n + 1))
  if [ -e "dotfiles/$p" ]; then continue; fi
  if git check-ignore -q "dotfiles/$p"; then continue; fi # runtime seed (themes/current, cava/config...)
  fail "link target missing: dotfiles/$p"
  bad=1
done
[ "$bad" -eq 0 ] && ok "$n link targets exist"

# --- 2) hosts ----------------------------------------------------------------------
# flake.nix derives homeConfigurations + checks from modules/hosts/*.nix (readDir),
# so the only thing that can drift is the harvest directory.
sec "2. hosts: modules/hosts/<h>.nix <-> hosts/<h>/"
HOSTS="$(for f in modules/hosts/*.nix; do [ -f "$f" ] && basename "$f" .nix; done | sort -u)"
[ -n "$HOSTS" ] || fail "modules/hosts/ has no host module"
for h in $HOSTS; do
  [ -d "hosts/$h" ] || fail "modules/hosts/$h.nix has no hosts/$h/ (run dram harvest on it)"
done
for d in hosts/*/; do
  h="$(basename "$d")"
  echo "$HOSTS" | grep -qx "$h" || fail "hosts/$h/ has no modules/hosts/$h.nix"
done
ok "hosts: $(echo "$HOSTS" | tr '\n' ' ')"

# --- 3) package manifests ---------------------------------------------------------
sec "3. packages/*.txt + packages/roles/*.txt"
# shellcheck source=install/lib/roles.sh
. install/lib/roles.sh
bad=0
for f in packages/*.txt packages/roles/*.txt; do
  if grep -nE '^[^#[:space:]].*[[:space:]]#' "$f" | grep -q .; then
    fail "$f has inline comments (own-line comments only; bootstrap strips whole lines):"
    grep -nE '^[^#[:space:]].*[[:space:]]#' "$f" | sed 's/^/      /'
    bad=1
  fi
  if grep -nE '^[^#[:space:]]+[[:space:]]+[^#[:space:]]' "$f" | grep -q .; then
    fail "$f has lines with more than one token:"
    grep -nE '^[^#[:space:]]+[[:space:]]+[^#[:space:]]' "$f" | sed 's/^/      /'
    bad=1
  fi
done
REPO_LISTS=""
for f in packages/*.txt packages/roles/*.txt; do [ "$f" = packages/aur.txt ] || REPO_LISTS="$REPO_LISTS $f"; done
# shellcheck disable=SC2086
dups="$(cat $REPO_LISTS | grep -vE '^[[:space:]]*(#|$)' | sort | uniq -d)"
if [ -n "$dups" ]; then
  fail "duplicate package names across repo lists: $(echo "$dups" | tr '\n' ' ')"
  bad=1
fi
dups="$(grep -vE '^[[:space:]]*(#|$)' packages/aur.txt | sort | uniq -d)"
[ -n "$dups" ] && {
  fail "duplicates in packages/aur.txt: $(echo "$dups" | tr '\n' ' ')"
  bad=1
}
# AUR names in a repo list: anything the hosts report as foreign, or packages/aur.txt lists
AURNAMES="$(cat packages/aur.txt hosts/*/packages/aur.txt 2>/dev/null | grep -vE '^[[:space:]]*(#|$)' | sort -u)"
# shellcheck disable=SC2086
hits="$(cat $REPO_LISTS | grep -vE '^[[:space:]]*(#|$)' | sort -u | comm -12 - <(echo "$AURNAMES"))"
if [ -n "$hits" ]; then
  fail "AUR/foreign names inside repo lists (pacman -S cannot install them): $(echo "$hits" | tr '\n' ' ')"
  bad=1
fi
[ "$bad" -eq 0 ] && ok "no inline comments, no duplicates, no AUR names in repo lists"
if [ "${CHECK_PKGDB:-0}" = 1 ]; then
  if out="$(python3 -I bin/check-pkgnames.py 2>&1)"; then
    ok "$out"
  else
    fail "package names (bin/check-pkgnames.py):"
    printf '%s\n' "$out" | sed 's/^/      /'
  fi
fi

# host-aware rules over the harvested truth (hosts/<h>/packages/versions.lock = installed,
# explicit.txt = explicit). A host's manifest set is derived from hosts/<h>/hardware.txt the
# way `dram apply` does it (cpu/gpu vendor, form), plus the host's roles from
# modules/hosts/<h>.nix — the builder role included, which system/dram-builder-setup.sh
# installs — plus packages/host-<h>.txt when the host has one. Both rules WARN, not fail:
# hosts/ holds the pre-wipe harvests until each machine is rebuilt.
host_lists() { # host_lists <h>: the packages/*.txt files host <h> reads, one per line
  local hw="hosts/$1/hardware.txt" cpu gpu
  echo packages/base.txt
  # a WSL clone (decisions/0021): base + roles, no metal or hardware list (its harvest says form: wsl)
  if [ "$(host_form . "$1")" = wsl ] || grep -qiE '^[[:space:]]*form:[[:space:]]*wsl' "$hw"; then
    role_files . "$1" | sed 's|^\./||'
    [ -f "packages/host-$1.txt" ] && echo "packages/host-$1.txt"
    return 0
  fi
  echo packages/metal.txt
  cpu="$(grep -im1 '^[[:space:]]*cpu' "$hw" | tr '[:upper:]' '[:lower:]')"
  gpu="$(grep -im1 '^[[:space:]]*gpu' "$hw" | tr '[:upper:]' '[:lower:]')"
  case "$cpu" in *amd*) echo packages/cpu-amd.txt ;; *intel*) echo packages/cpu-intel.txt ;; esac
  case "$gpu" in *nvidia*) echo packages/gpu-nvidia.txt ;; esac
  case "$gpu" in *intel*) echo packages/gpu-intel.txt ;; esac
  case "$gpu" in *"advanced micro"* | *"[amd"* | *" amd "* | *" amd/"*) echo packages/gpu-amd.txt ;; esac
  grep -qiE '^[[:space:]]*form.*laptop' "$hw" && echo packages/laptop.txt
  role_files . "$1" | sed 's|^\./||'
  [ -f "packages/host-$1.txt" ] && echo "packages/host-$1.txt"
  return 0
}
names() { grep -hvE '^[[:space:]]*(#|$)' "$@" | sort -u; } # package names in the given lists
# blist "<text>" [max]: indented, bounded to max lines + a count
blist() {
  local max="${2:-20}" n
  n="$(printf '%s\n' "$1" | wc -l | tr -d ' ')"
  printf '%s\n' "$1" | head -n "$max" | sed 's/^/      /'
  [ "$n" -gt "$max" ] && printf '      ... and %s more\n' "$((n - max))"
  return 0
}
if ls hosts/*/packages/versions.lock >/dev/null 2>&1; then
  installed="$(awk '{print $1}' hosts/*/packages/versions.lock | sort -u)"
  dram_names="$(grep -vE '^[[:space:]]*(#|$)' pkgs/manifest.txt | sed 's/=.*//' | sort -u)"
  all_wanted="" undeclared_n=0
  for h in $HOSTS; do
    [ -f "hosts/$h/hardware.txt" ] && [ -f "hosts/$h/packages/explicit.txt" ] || continue
    lists="$(host_lists "$h" | tr '\n' ' ')"
    # shellcheck disable=SC2086
    wanted="$(names $lists)"
    # a WSL clone never installs what packages/wsl-skip.tsv names, whatever its roles say
    [ "$(host_form . "$h")" = wsl ] && wanted="$(printf '%s\n' "$wanted" | grep -vxF -f <(wsl_skip_names .) || true)"
    all_wanted="$all_wanted
$wanted"
    # (b) explicit on the host, in no list the host reads, not a [dram] package
    undeclared="$(sort -u "hosts/$h/packages/explicit.txt" | comm -23 - <(echo "$wanted") | comm -23 - <(echo "$dram_names"))"
    if [ -n "$undeclared" ]; then
      n="$(echo "$undeclared" | wc -l | tr -d ' ')"
      undeclared_n=$((undeclared_n + n))
      warn "hosts/$h: $n explicit package(s) declared in none of: ${lists% } (declare it in one, or pacman -D --asdeps / -Rns on the host):"
      blist "$undeclared"
    fi
  done
  # (a) declared in a list some host reads, installed (explicit or dependency) on no host
  nowhere="$(echo "$all_wanted" | grep -v '^$' | sort -u | comm -23 - <(echo "$installed"))"
  if [ -n "$nowhere" ]; then
    warn "declared but installed nowhere (pacman -S on a host + dram harvest, or drop the line): $(echo "$nowhere" | tr '\n' ' ' | sed 's/ $//')"
  fi
  [ -z "$nowhere" ] && [ "$undeclared_n" -eq 0 ] && ok "every declared name is installed on a host; every explicit package is declared"
fi

# --- 4) shell scripts -------------------------------------------------------------
sec "4. bash scripts: shellcheck + shfmt"
SCRIPTS=""
# pkgs/ is vendored upstream code kept byte-identical for review diffs (pkgs/README.md),
# excluded here as in flake.nix's shellcheck hook
for f in $(git ls-files | grep -vE '^legacy/|^pkgs/|/(plymouth|refind)-catppuccin/'); do
  [ -f "$f" ] || continue
  if head -1 "$f" 2>/dev/null | grep -qE '^#!.*\bbash\b'; then SCRIPTS="$SCRIPTS $f"; fi
done
SCRIPTS="$SCRIPTS dotfiles/.local/share/bash-completion/completions/dram"
cnt=0
for f in $SCRIPTS; do cnt=$((cnt + 1)); done
if have shellcheck; then
  bad=0
  for f in $SCRIPTS; do
    # shellcheck disable=SC2086
    if ! shellcheck -S warning -s bash $f >/dev/null 2>&1; then
      fail "shellcheck: $f"
      shellcheck -S warning -s bash -f gcc "$f" 2>/dev/null | head -5 | sed 's/^/      /'
      bad=1
    fi
  done
  [ "$bad" -eq 0 ] && ok "shellcheck clean on $cnt scripts"
else warn "shellcheck not installed — skipped"; fi
if have shfmt; then
  bad=0
  for f in $SCRIPTS; do
    if ! shfmt -i 2 -ci -bn -d "$f" >/dev/null 2>&1; then
      fail "shfmt: $f   (shfmt -i 2 -ci -bn -w $f)" # the tree has been shfmt-clean since 2026-10-07; a drift is a failure
      bad=1
    fi
  done
  [ "$bad" -eq 0 ] && ok "shfmt -i 2 -ci -bn clean on $cnt scripts"
else warn "shfmt not installed — skipped"; fi

# --- 5) python behind a .sh name --------------------------------------------------
sec "5. interpreter vs extension"
bad=0
for f in $(git ls-files '*.sh' | grep -v '^legacy/'); do
  if head -1 "$f" | grep -q python; then
    style "$f is a python program with a .sh name (rename to .py: the modules/*.nix link + every caller)"
    bad=1
  fi
done
[ "$bad" -eq 0 ] && ok "every *.sh is a shell script"

# --- 6) docs: links, backticked paths and see: lines resolve ----------------------------
# Every tracked *.md at any depth: a relative link and its #anchor must resolve, a
# backticked repo path (`system/...`) must exist, from the root or the page's directory;
# `...`, ALL-CAPS segments (hosts/OLD/) and newbox are placeholders. docs/history/ holds
# frozen pages that describe a different tree on purpose (its README says so), and
# decisions/0007 (the rice -> dram rename) tabulates the old paths next to the new ones.
# Then the see: line of every script and module header. DOCS_GUARDS sets warn or fail.
sec "6. docs: links, backticked repo paths and see: lines resolve (bin/check-docs.py; $DOCS_GUARDS)"
docs_check links see

# --- 7) secrets ----------------------------------------------------------------------
sec "7. no tracked secrets"
bad=0
# The sops scaffold is allowed to carry the word: modules/secrets.nix, docs/*.md (prose),
# secrets/README.md, .sops.yaml, system/secrets-bootstrap.sh, and secrets/*.yaml (sops
# ciphertext, tracked on purpose). Anything decrypted (*.plain, *.plain.yaml) stays
# caught — and gitignored.
hits="$(git ls-files | grep -iE '(^|/)(id_[a-z0-9]+|.*\.(key|pem))$|passphrase|secret|token' | grep -v '\.pub$' \
  | grep -vE '^(modules/secrets\.nix|docs/.*\.md|secrets/README\.md|\.sops\.yaml|system/secrets-bootstrap\.sh|secrets/[A-Za-z0-9_-]+\.yaml)$')"
[ -n "$hits" ] && {
  fail "secret-looking tracked files: $(echo "$hits" | tr '\n' ' ')"
  bad=1
}
# any PEM private key (RSA/OPENSSH/EC/DSA/PGP/ENCRYPTED ...), an age identity (the
# sops key), a GitHub PAT, an AWS access key id
hits="$(git grep -lE -- '-----BEGIN [A-Z ]*PRIVATE KEY|AGE-SECRET-KEY-1[0-9A-Z]{20,}|ghp_[A-Za-z0-9]{36}|AKIA[0-9A-Z]{16}' -- . 2>/dev/null)"
[ -n "$hits" ] && {
  fail "private key / token material in: $(echo "$hits" | tr '\n' ' ')"
  bad=1
}
[ "$bad" -eq 0 ] && ok "nothing secret-looking is tracked"

# --- 8) flake.lock age --------------------------------------------------------------
sec "8. flake.lock age"
ts="$(git log -1 --format=%ct -- flake.lock 2>/dev/null)"
if [ -n "$ts" ]; then
  days=$((($(date +%s) - ts) / 86400))
  if [ "$days" -gt 60 ]; then warn "flake.lock last bumped $days days ago (dram update --full)"; else ok "flake.lock bumped $days days ago"; fi
else warn "flake.lock has no git history"; fi

# --- 9) /usr/bin references in nix ---------------------------------------------------
sec "9. /usr/bin/<bin> in modules/*.nix is in a package manifest"
bad=0
for b in $(grep -ohE '/usr/bin/[A-Za-z0-9_.-]+' modules/*.nix modules/hosts/*.nix | sed 's|/usr/bin/||' | sort -u); do
  if grep -hqxF "$b" packages/*.txt packages/roles/*.txt; then continue; fi
  if grep -hqE "^# $b: provided by " packages/*.txt packages/roles/*.txt; then continue; fi # the binary's package has another name
  fail "/usr/bin/$b is referenced by nix but no packages/*.txt lists a package named '$b' (add it, or a '# $b: provided by <pkg>' comment and the pkg)"
  bad=1
done
[ "$bad" -eq 0 ] && ok "every /usr/bin reference has a manifest entry"

# --- 10) waybar: jsonc parses, captions and spacing follow the house rules -------------
# bin/check-waybar.py: both jsonc parse once // lines are stripped, ZERO
# private-use codepoints (the masthead has no icons), every caption sits in the
# one house span (`smcp, lnum, tnum`), custom/date runs waybar-date.sh,
# hyprland/window + workspaces are wired, style.css names no hex, bars have
# spacing 0, the `, "battery"` literal laptop.nix strips is intact, the
# scripts compile.
sec "10. waybar: *.jsonc parse; captions and spacing (docs/design/README.md → Captions and spacing)"
if out="$(python3 bin/check-waybar.py 2>&1)"; then
  ok "waybar config.jsonc + modules.jsonc parse;${out#  }"
else
  fail "waybar caption/spacing rules (bin/check-waybar.py):"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# --- 11) host flags ---------------------------------------------------------------------
# modules/laptop.nix, gpu.nix and backup.nix branch on these; a host that forgets
# one only fails at `nix flake check` (no default in options.nix), so catch it
# here, nix-free. `address` has a default ("" = not pushed) and is not required.
sec "11. modules/hosts/*.nix set dram.hostName, roles, isLaptop, gpu"
bad=0
for f in modules/hosts/*.nix; do
  # roles: on one line (install/lib/roles.sh greps it) and every role has its manifest
  rl="$(roles_of "$f")"
  if [ -z "$rl" ]; then
    fail "$f has no one-line roles = [ \"…\" ]; (decisions/0009)"
    bad=1
  fi
  for r in $rl; do
    [ -f "packages/roles/$r.txt" ] || {
      fail "$f names role '$r' but packages/roles/$r.txt does not exist"
      bad=1
    }
  done
  for flag in hostName isLaptop gpu; do
    # accepts both `dram.<flag> = ...;` and `<flag> = ...;` inside `dram = { ... };`
    grep -qE "^[[:space:]]*(dram\.)?${flag}[[:space:]]*=" "$f" || {
      fail "$f does not set dram.$flag"
      bad=1
    }
  done
done
[ "$bad" -eq 0 ] && ok "every host sets hostName, roles (all with a manifest), isLaptop, gpu"

sec "12. pkgs/: manifest, pins, no shadowing (bin/pkgs.sh check)"
if out="$(bash bin/pkgs.sh check 2>&1)"; then
  ok "pkgs check passed"
  # on the Mac there is no pacman: the official-repo shadowing rule was NOT checked,
  # and bin/release.sh gates on this run — say so instead of swallowing the [!] line
  if printf '%s\n' "$out" | grep -q 'shadowing check skipped'; then
    warn "pkgs check: official-repo shadowing check skipped here (no pacman) — run dram pkgs check on a host before publishing"
  fi
else
  fail "dram pkgs check:"
  printf '%s\n' "$out" | grep '\[!\]' | sed 's/^/      /'
fi

# --- 13) every script answers --help; docs/commands.md is current ----------------------
# Stub PATH first: no-op ssh/hyprctl/rofi/home-manager/borgmatic/pacman/
# notify-send, so a script whose help is broken cannot act. `--help` must exit 0
# with a `usage:` first line; a bogus flag must exit 2 (dram-switch forwards its
# flags by contract and is excepted). Then docs/commands.md must equal what
# bin/gen-commands-doc.py renders from the headers.
sec "13. every script answers --help (stub PATH); docs/commands.md is up to date"
STUB="$(mktemp -d)"
for b in ssh hyprctl rofi home-manager borgmatic pacman notify-send; do
  printf '#!/bin/sh\nexit 0\n' >"$STUB/$b"
  chmod +x "$STUB/$b"
done
HPATH="$STUB:$REPO/dotfiles/.local/bin:$PATH"
bad=0 n=0
for f in dotfiles/.local/bin/* bin/*.sh bin/*.py system/*.sh system/*.py install/*.sh; do
  [ -f "$f" ] || continue
  case "$f" in */house-palette.sh | bin/check.sh) continue ;; esac
  if head -1 "$f" | grep -q python; then interp=python3; elif head -1 "$f" | grep -q bash; then interp=bash; else continue; fi
  n=$((n + 1))
  out="$(PATH="$HPATH" "$interp" "$f" --help 2>&1 </dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ] || ! printf '%s\n' "$out" | head -1 | grep -q '^usage:'; then
    fail "$f --help: exit $rc / first line is not 'usage:'"
    bad=1
  fi
  case "$f" in */dram-switch) continue ;; esac
  PATH="$HPATH" "$interp" "$f" --no-such-option >/dev/null 2>&1 </dev/null
  rc=$?
  [ "$rc" -eq 2 ] || {
    fail "$f --no-such-option: exit $rc, want 2 (one-line usage on stderr)"
    bad=1
  }
done
[ "$bad" -eq 0 ] && ok "$n scripts: --help exits 0 with a usage: line; a bogus flag exits 2"
# Every `dram` SUBCOMMAND too (`dram <cmd> --help` is documented as working for
# all of them). A bogus flag must exit 2 without side effects, so this runs
# against a throwaway clone (DRAM_REPO) with a throwaway HOME: `dram harvest`
# writes hosts/<host>/ and `dram channel` writes ~/.config/dram otherwise.
# `switch` passes its arguments to home-manager by contract and is excepted.
SANDBOX="$(mktemp -d)"
git clone -q --shared "$REPO" "$SANDBOX/repo" 2>/dev/null
mkdir -p "$SANDBOX/home"
bad=0 n=0
for sub in switch update receive version channel changelog theme check doctor pacnew rollback builds backup harvest apply pkgs yubikey; do
  n=$((n + 1))
  out="$(HOME="$SANDBOX/home" DRAM_REPO="$SANDBOX/repo" PATH="$HPATH" bash dotfiles/.local/bin/dram "$sub" --help 2>&1 </dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ] || ! printf '%s\n' "$out" | head -1 | grep -q '^usage:'; then
    fail "dram $sub --help: exit $rc / first line is not 'usage:'"
    bad=1
  fi
  [ "$sub" = switch ] && continue
  HOME="$SANDBOX/home" DRAM_REPO="$SANDBOX/repo" PATH="$HPATH" bash dotfiles/.local/bin/dram "$sub" --no-such-option >/dev/null 2>&1 </dev/null
  rc=$?
  [ "$rc" -eq 2 ] || {
    fail "dram $sub --no-such-option: exit $rc, want 2"
    bad=1
  }
done
[ -z "$(git -C "$SANDBOX/repo" status --porcelain 2>/dev/null)" ] || {
  fail "a dram subcommand with a bogus flag wrote into the repo: $(git -C "$SANDBOX/repo" status --porcelain | tr '\n' ' ')"
  bad=1
}
rm -rf "$SANDBOX" "$STUB"
[ "$bad" -eq 0 ] && ok "$n dram subcommands: --help exits 0 with a usage: line; a bogus flag exits 2 and writes nothing"
# A script with a usage: header is meant to be run by path, so it must be
# executable in the index too — a clone otherwise gets "permission denied".
bad=0 n=0
while read -r mode _ _ f; do
  sed -n 2p "$f" 2>/dev/null | grep -q 'usage:' || continue
  n=$((n + 1))
  [ "$mode" = 100755 ] || {
    fail "$f has a usage: header but is mode $mode in the index (git update-index --chmod=+x $f)"
    bad=1
  }
done < <(git ls-files -s dotfiles/.local/bin bin system install)
[ "$bad" -eq 0 ] && ok "$n scripts with a usage: header are mode 100755 in the index"
if out="$(python3 bin/gen-commands-doc.py --check 2>&1)"; then
  ok "docs/commands.md matches the scripts' headers"
else
  fail "docs/commands.md is stale — python3 bin/gen-commands-doc.py:"
  printf '%s\n' "$out" | head -15 | sed 's/^/      /'
fi

# --- 14) themes: one schema; the home path is spelled out nowhere ---------------------
# The GTK stylesheets (waybar, swaync, swayosd, nwg-drawer)
# @import themes/current RELATIVELY (resolved against the ~/.config/<app>
# symlink), so `/home/pj` may appear in no tracked file (qt6ct.conf, the one
# exception, left with qt6ct 2026-10-10).
# Tracked files only (git grep): on a host the gitignored runtime seeds under
# dotfiles/.config (themes/current, gtk-*/gtk.css, cava/config …) carry $HOME.
# bin/check-themes.py: every themes/<t>/ has the same file set, the same key
# set per hand-written palette file, a unique MENU_NAME, VSCODIUM_THEME =
# "Letterpress — <MENU_NAME>", its yazi flavor dir, and one accent hex across
# the hand-written accent slots (documented exceptions live in the script).
sec "14. themes: identical schema; no hardcoded /home/pj under dotfiles/.config"
hits="$(git grep -l '/home/pj' -- dotfiles/.config)"
if [ -n "$hits" ]; then
  fail "hardcoded /home/pj (use a relative @import, or \$HOME): $(echo "$hits" | tr '\n' ' ')"
else
  ok "/home/pj appears nowhere under dotfiles/.config"
fi
if out="$(python3 -I bin/check-themes.py 2>&1)"; then
  ok "themes:${out#  }"
else
  fail "theme schema (bin/check-themes.py):"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# --- 15) the software register: FOSS / Origin / Community verdicts (decisions/0013) ----
sec "15. packages/register.tsv: every installed name has a verdict (bin/check-register.py)"
rargs=""
[ "${CHECK_ROLLOUT:-0}" = 1 ] && rargs="--rollout"
# shellcheck disable=SC2086 # rargs is empty or one flag
out="$(python3 -I bin/check-register.py $rargs 2>&1)"
while IFS= read -r line; do
  case "$line" in
    "FAIL "*) fail "${line#FAIL }" ;;
    "WARN "*) warn "${line#WARN }" ;;
    "OK "*) ok "${line#OK }" ;;
    ?*) fail "check-register.py: $line" ;;
  esac
done <<<"$out"

# --- 16) Gaming Mode switching and the Hyprland Lua configs (decisions/0012) ----------
sec "16. Gaming Mode: tests/gaming-switch.sh (T0); hypr/*.lua parse"
if out="$(bash tests/gaming-switch.sh 2>&1)"; then
  ok "$(tail -1 <<<"$out")"
else
  fail "tests/gaming-switch.sh:"
  grep -E '^FAIL' <<<"$out" | sed 's/^/      /'
fi
if command -v luac >/dev/null 2>&1; then
  for f in dotfiles/.config/hypr/*.lua; do
    if out="$(luac -p "$f" 2>&1)"; then ok "$f parses"; else fail "$f: $out"; fi
  done
else
  warn "luac not installed — the hypr/*.lua syntax check is skipped"
fi

# --- 17) recording: rec against a mock obs-websocket; OBS templates are safe to track ---
sec "17. recording: tests/rec-websocket.py (T0); dotfiles/obs/ holds no keys or home paths"
if out="$(python3 tests/rec-websocket.py 2>&1)"; then
  ok "$(tail -1 <<<"$out")"
else
  fail "tests/rec-websocket.py:"
  grep -E '^FAIL' <<<"$out" | sed 's/^/      /'
fi
# a stream key, a server password or an absolute home path must never be committed
# (rec templates-save copies live OBS files here)
bad="$(grep -rnE '"(key|server_password|password)"[[:space:]]*:|/home/[a-z_]' dotfiles/obs 2>/dev/null || true)"
if [ -n "$bad" ]; then
  fail "dotfiles/obs/ holds a key, password or /home path:"
  printf '%s\n' "$bad" | sed 's/^/      /'
else
  ok "dotfiles/obs/: no stream keys, passwords or home paths"
fi
for f in dotfiles/obs/*/scenes/*.json; do
  [ -e "$f" ] || continue
  python3 -m json.tool "$f" >/dev/null 2>&1 || fail "$f is not valid JSON"
done

# --- 18) YubiKeys: the public halves in keys/, the pam_u2f line (decisions/0019) -------
sec "18. YubiKeys: keys/ formats and labels; tests/yubikey-t0.sh (T0)"
bad=0
# ssh.pub: resident FIDO2 keys only, each with a `yubikey:<label>` comment, labels unique
hits="$(grep -vE '^[[:space:]]*(#|$)' keys/ssh.pub | grep -vE '^sk-(ssh-ed25519|ecdsa-sha2-nistp256)@openssh\.com AAAA[A-Za-z0-9+/]+=* yubikey:[a-z][a-z0-9-]{0,15}$' || true)"
[ -z "$hits" ] || {
  fail "keys/ssh.pub: not '<sk-type> <base64> yubikey:<label>': $(printf '%s' "$hits" | head -1 | cut -c1-60)…"
  bad=1
}
# pam-u2f.txt: `<label>:<KeyHandle>,<UserKey>,<CoseType>,<Options>` (system/yubikey-setup.sh's rule)
# options exactly +presence: ly would answer a +pin credential's PIN prompt with the password
hits="$(grep -vE '^[[:space:]]*(#|$)' keys/pam-u2f.txt | grep -vE '^[a-z][a-z0-9-]{0,15}:[A-Za-z0-9+/=_-]+,[A-Za-z0-9+/=_-]+,(es256|eddsa|rs256),\+presence$' || true)"
[ -z "$hits" ] || {
  fail "keys/pam-u2f.txt: not '<label>:<KeyHandle>,<UserKey>,<CoseType>,+presence': $(printf '%s' "$hits" | head -1 | cut -c1-60)…"
  bad=1
}
ssh_l="$(grep -oE ' yubikey:[a-z][a-z0-9-]*$' keys/ssh.pub | cut -d: -f2 | sort)"
u2f_l="$(grep -vE '^[[:space:]]*(#|$)' keys/pam-u2f.txt | cut -d: -f1 | sort)"
age_l="$(awk '$1 == "#" && $2 == "yubikey:" { print $3 }' .sops.yaml | sort)"
for pair in "keys/ssh.pub:$ssh_l" "keys/pam-u2f.txt:$u2f_l" ".sops.yaml:$age_l"; do
  d="$(printf '%s\n' "${pair#*:}" | grep -v '^$' | uniq -d)"
  [ -z "$d" ] || {
    fail "${pair%%:*}: label listed twice: $(printf '%s' "$d" | paste -sd' ' -)"
    bad=1
  }
done
all_l="$(printf '%s\n%s\n%s\n' "$ssh_l" "$u2f_l" "$age_l" | grep -v '^$' | sort -u)"
for l in $all_l; do
  miss=""
  printf '%s\n' "$ssh_l" | grep -qx "$l" || miss="$miss keys/ssh.pub"
  printf '%s\n' "$u2f_l" | grep -qx "$l" || miss="$miss keys/pam-u2f.txt"
  printf '%s\n' "$age_l" | grep -qx "$l" || miss="$miss .sops.yaml"
  [ -z "$miss" ] || warn "YubiKey '$l' is not in:$miss (enrolled for only part of its jobs? docs/security/identity/yubikeys.md)"
done
[ "$bad" -eq 0 ] && ok "keys/: $(printf '%s\n' "$all_l" | grep -c .) YubiKey label(s), formats valid"
if out="$(bash tests/yubikey-t0.sh 2>&1)"; then
  ok "$(tail -1 <<<"$out")"
else
  fail "tests/yubikey-t0.sh:"
  grep -E '^FAIL' <<<"$out" | sed 's/^/      /'
fi

# --- 19) Windows: the generated Letterpress files, the rendered builds, the push; ASCII ----
sec "19. Windows: install/windows/letterpress and windows/build are current; *.ps1, *.winget and the builds are ASCII; tests/push-windows.sh (T0)"
if out="$(python3 bin/gen-windows-look.py --check 2>&1)"; then
  ok "install/windows/letterpress matches the palettes (bin/gen-windows-look.py)"
else
  fail "install/windows/letterpress is stale — python3 bin/gen-windows-look.py:"
  printf '%s\n' "$out" | head -15 | sed 's/^/      /'
fi
# the stamp: a build made from other inputs than the repo's is stale (decisions/0020); a
# host file without a build too
if out="$(bash bin/render-windows.sh --check 2>&1)"; then
  ok "windows/build: $(tr '\n' ';' <<<"$out" | sed 's/;$//; s/;/; /g')"
else
  fail "windows/build is stale — bin/render-windows.sh, then commit windows/build:"
  printf '%s\n' "$out" | head -15 | sed 's/^/      /'
fi
# shellcheck disable=SC2016 # the python program is single-quoted on purpose
if out="$(git ls-files 'install/windows/*.ps1' 'install/windows/*.winget' 'windows/*.ps1' 'windows/build/*' | python3 -c '
import sys
bad = []
for p in sys.stdin.read().split():
    for n, line in enumerate(open(p, "rb"), 1):
        if any(b > 127 for b in line):
            bad.append("%s:%d" % (p, n))
print(" ".join(bad[:10]))
sys.exit(1 if bad else 0)
' 2>&1)"; then
  ok "install/windows and windows: every *.ps1, *.winget and build file is ASCII"
else
  fail "non-ASCII bytes in Windows sources (use [char]0x2014 and friends): $out"
fi
if out="$(bash tests/push-windows.sh 2>&1)"; then
  ok "$(tail -1 <<<"$out")"
else
  fail "tests/push-windows.sh:"
  grep -E '^FAIL' <<<"$out" | sed 's/^/      /'
fi

# --- 20) the case display: frame encoder, usbfs sequence (pkgs/dram-case-display) -------
sec "20. case display: tests/case-display.py (T0)"
if out="$(python3 -I tests/case-display.py 2>&1)"; then
  ok "$(tail -1 <<<"$out")"
else
  fail "tests/case-display.py:"
  grep -E '^FAIL' <<<"$out" | sed 's/^/      /'
fi
# --- 21) the WSL clones: what they skip; nothing metal in their plan (decisions/0021) ----
# A clone's plan is what `dram apply` declares there: base + its roles (+ host-<h>.txt) +
# the [dram] every-host set, minus packages/wsl-skip.tsv. It must hold no name of a metal
# or hardware list (kernel, firmware, boot, microcode, GPU driver, a metal host's own
# extras) and no [dram] name ([dram] is not configured in the clone), and the clone takes
# no session or hardware role. Every wsl-skip.tsv row names something a list declares.
sec "21. WSL clones: packages/wsl-skip.tsv; no metal, hardware or [dram] name in a clone's plan"
bad=0
every_host="$(bash bin/pkgs.sh list --install 2>/dev/null)"
dram_repo="$(bash bin/pkgs.sh list --repo 2>/dev/null)"
declared_all="$(printf '%s\n%s\n' "$(names packages/*.txt packages/roles/*.txt)" "$every_host" | grep -v '^$' | sort -u)"
n=0
while IFS= read -r line; do
  case "$line" in '' | '#'*) continue ;; esac
  n=$((n + 1))
  name="$(printf '%s\n' "$line" | cut -f1)"
  [ -n "$(printf '%s\n' "$line" | cut -sf2-)" ] || {
    fail "packages/wsl-skip.tsv: '$name' has no reason (name<TAB>why)"
    bad=1
  }
  printf '%s\n' "$declared_all" | grep -qxF "$name" || {
    fail "packages/wsl-skip.tsv: '$name' is declared by no packages list (drop the row)"
    bad=1
  }
done <packages/wsl-skip.tsv
metal_lists="packages/metal.txt packages/laptop.txt $(ls packages/cpu-*.txt packages/gpu-*.txt | tr '\n' ' ')"
for h in $HOSTS; do
  [ "$(host_form . "$h")" = metal ] && [ -f "packages/host-$h.txt" ] && metal_lists="$metal_lists packages/host-$h.txt"
done
# shellcheck disable=SC2086 # a list of paths without spaces
metal_names="$(names $metal_lists)"
clones=""
for h in $HOSTS; do
  [ "$(host_form . "$h")" = wsl ] || continue
  clones="$clones $h"
  for r in $(roles_of "modules/hosts/$h.nix"); do
    case "$r" in desktop | gaming | emulation | creator | recording | builder)
      fail "modules/hosts/$h.nix is a WSL clone with the $r role (a session, hardware or the build chroot: never in WSL, decisions/0021)"
      bad=1
      ;;
    esac
  done
  # shellcheck disable=SC2046 # one file per line, no spaces in the repo's paths
  plan="$(printf '%s\n%s\n' "$(names $(host_package_files . "$h" "" wsl))" "$every_host" \
    | grep -v '^$' | sort -u | grep -vxF -f <(wsl_skip_names .) || true)"
  hits="$(printf '%s\n' "$plan" | grep -xF -f <(printf '%s\n' "$metal_names") || true)"
  [ -z "$hits" ] || {
    fail "$h (form wsl) would install metal or hardware names: $(printf '%s' "$hits" | tr '\n' ' ') (move them to packages/metal.txt or list them in packages/wsl-skip.tsv)"
    bad=1
  }
  hits="$(printf '%s\n' "$plan" | grep -xF -f <(printf '%s\n' "$dram_repo") || true)"
  [ -z "$hits" ] || {
    fail "$h (form wsl) would install [dram] names, which the clone cannot reach: $(printf '%s' "$hits" | tr '\n' ' ') (list them in packages/wsl-skip.tsv)"
    bad=1
  }
done
[ "$bad" -eq 0 ] && ok "$n wsl-skip row(s), each declared somewhere; clones:${clones:- none} — no metal, hardware or [dram] name in their plans"

# --- 22) the org chart: every tracked path has a place (docs/map.tsv) -----------------
# The last matching row of docs/map.tsv places a path in a directorate, a division and a
# branch; a path that only the catch-all row matches is unmapped. Every directorate and
# division of the chart, and every page a row names, must exist. DOCS_GUARDS sets warn or
# fail. `python3 bin/check-docs.py map --list` prints every path with its place.
sec "22. the org chart: docs/map.tsv places every tracked path (bin/check-docs.py map; $DOCS_GUARDS)"
docs_check map

# --- 23) the generated records pages ---------------------------------------------------
# docs/catalogue.md is written from the fact box at the top of each module README;
# decisions/README.md from each record's title and status line and the open decisions of
# decisions/log.md; the chart in README.md and docs/README.md from docs/map.tsv. Each
# must equal what its generator writes, as docs/commands.md does in §13.
sec "23. generated records pages: docs/catalogue.md, decisions/README.md, the chart in README.md and docs/README.md"
if out="$(python3 -I bin/gen-catalogue.py --check 2>&1)"; then
  ok "docs/catalogue.md matches the module READMEs' fact boxes"
else
  fail "docs/catalogue.md is stale, or a fact box is malformed — python3 bin/gen-catalogue.py:"
  printf '%s\n' "$out" | head -15 | sed 's/^/      /'
fi
if out="$(python3 -I bin/gen-org-doc.py --check 2>&1)"; then
  ok "decisions/README.md and the charts in README.md and docs/README.md are current"
else
  fail "a generated records page is stale — python3 bin/gen-org-doc.py:"
  printf '%s\n' "$out" | head -15 | sed 's/^/      /'
fi

# --- 24) no private words -------------------------------------------------------------
# What must not be published stays out of the tree: the LAN's addresses, serial numbers, a
# mail address. The list of those words cannot live in the repo, which would publish it:
# each clone keeps its own in <git dir>/info/private.tsv (bin/check-docs.py describes the
# format), and a clone without one checks nothing. DOCS_GUARDS sets warn or fail.
sec "24. no private words in tracked text (bin/check-docs.py private; $DOCS_GUARDS)"
docs_check private

# --- summary -------------------------------------------------------------------------
echo
if [ "$FAIL" -gt 0 ]; then
  printf '\033[1;31m%s failure(s)\033[0m, %s warning(s)\n' "$FAIL" "$WARN"
  exit 1
fi
printf '\033[1;32mall checks passed\033[0m, %s warning(s)\n' "$WARN"

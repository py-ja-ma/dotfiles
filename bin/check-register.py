#!/usr/bin/env python3
"""usage: check-register.py [--rollout] [--list]

Checks packages/register.tsv, the machine-readable half of decisions/0013: every
name this repo installs must carry a verdict against the three rules (FOSS,
Origin, Community). Names come from four places: the pacman lists
(packages/*.txt + packages/roles/*.txt, aur.txt excepted), the [dram] install set
(pkgs/manifest.txt minus pkgs/BUILD-ONLY), the Flatpak apps (packages/flatpak/<role>.txt, read by
system/flatpak-setup.sh) and the Nix user layer (home.packages lists,
programs.* and ${pkgs.<name>} references in modules/*.nix). Windows has lists
of its own: packages/winget/<role>.txt and host-<host>.txt, one winget:<id>,
msstore:<id> or manual:<name> (a Script unit's or a hand install) per line.

Verdicts: pass · pass-flag (Origin unclear, accepted by a ruling) · waiver
(signed exception; the until column is its re-check date) · swap (decided to go,
the note names the replacement) · pending (awaiting a ruling) · fail (must never
be installed).

Failures: a declared name with no row; an unknown verdict; a duplicate row; a
waiver without a date or past its date; a declared name whose verdict is fail.
Warnings: declared names still marked swap or pending (failures with --rollout,
run before a machine is rebuilt), and rows whose name nothing declares (fail rows
excepted: they exist to forbid).
The Windows names follow the same rules, and besides fail on: a list line that
is not one prefixed name, or a name in two lists; a WinGetPackage unit of a
rendered build (windows/build/<host>/*.winget, decisions/0020) whose package no
list names (an Ensure: Absent one needs a fail row instead); a
Windows row whose note starts "= <name> (Arch)" with another verdict or until
than that Arch row. Windows swap and pending names only warn: --rollout is the
gate of an Arch rebuild.
Output lines start with FAIL, WARN or OK; bin/check.sh §15 runs this.

  --rollout     swap and pending (Arch names) are failures, not warnings
  --list        print every declared name with its source and verdict, then exit 0
  -h, --help    this text

needs:  Python 3 (standard library); the repo's package lists and packages/register.tsv
alone:  yes: start an empty register and point declared() at your own lists
here:   bin/check.sh §15 runs it on every check; CHECK_ROLLOUT=1 adds --rollout
exit:   0 no failures · 1 failures (listed) · 2 bad usage
see:    docs/security/software-supply/register.md, decisions/0013-software-rules-and-waivers.md,
        docs/records/handbook/07-packages.md
"""
# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT

import datetime
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGISTER = os.path.join(ROOT, "packages", "register.tsv")
VERDICTS = ("pass", "pass-flag", "waiver", "swap", "pending", "fail")
NIX_WORDS = {"with", "pkgs", "lib", "optionals", "elem", "config", "dram", "roles", "in", "let", "inherit"}
# a Windows name: winget's PackageIdentifier (two to eight dotted parts), a Microsoft Store
# product id, or a lowercase name for what a Script unit installs or is installed by hand
WIN_IDS = {
    "winget": re.compile(r'[^.\s\\/:*?"<>|]{1,32}(\.[^.\s\\/:*?"<>|]{1,32}){1,7}'),
    "msstore": re.compile(r"[0-9A-Z]{12}|XP[0-9A-Z]{12}"),
    "manual": re.compile(r"[a-z0-9][a-z0-9.+-]*"),
}
WIN_PREFIXES = tuple(k + ":" for k in WIN_IDS)
TWIN = re.compile(r"= (\S+) \(Arch\)")


def usage(code):
    if code == 0:
        print(__doc__.strip())
    else:
        print(__doc__.splitlines()[0], file=sys.stderr)
    sys.exit(code)


def lines(path):
    with open(path, encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if s and not s.startswith("#"):
                yield s


def pacman_names(out):
    for sub in ("packages", os.path.join("packages", "roles")):
        d = os.path.join(ROOT, sub)
        for fn in sorted(os.listdir(d)):
            if fn.endswith(".txt") and fn != "aur.txt":
                for s in lines(os.path.join(d, fn)):
                    out.setdefault(s, os.path.join(sub, fn))


def dram_names(out):
    build_only = set(lines(os.path.join(ROOT, "pkgs", "BUILD-ONLY")))
    for s in lines(os.path.join(ROOT, "pkgs", "manifest.txt")):
        name = s.split("=")[0]
        if name not in build_only:
            out.setdefault(name, "pkgs/manifest.txt")


def flatpak_names(out):
    d = os.path.join(ROOT, "packages", "flatpak")
    for fn in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if fn.endswith(".txt"):
            for app in lines(os.path.join(d, fn)):
                out.setdefault(app, os.path.join("packages", "flatpak", fn))


def user_tool_names(out):
    # per-user tools the re-lab role installs (re-lab-tools): uv tools and Ghidra extensions
    d = os.path.join(ROOT, "packages", "uv")
    for fn in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if fn.endswith(".txt"):
            for s in lines(os.path.join(d, fn)):
                out.setdefault(re.split(r"[=<>~!]", s)[0], os.path.join("packages", "uv", fn))
    for s in lines(os.path.join(ROOT, "packages", "ghidra-extensions.tsv")):
        out.setdefault(s.split("\t")[0], "packages/ghidra-extensions.tsv")


def nix_names(out):
    d = os.path.join(ROOT, "modules")
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".nix"):
            continue
        with open(os.path.join(d, fn), encoding="utf-8") as f:
            t = f.read()
        # ${pkgs.<name>} in strings (initExtra, ExecCondition, …) installs <name> too
        for p in re.findall(r"\$\{pkgs\.([A-Za-z0-9_+-]+)\}", t):
            out.setdefault(p, "modules/%s (${pkgs.%s})" % (fn, p))
        t = re.sub(r"#.*", "", t)
        t = re.sub(r'"[^"]*"', "", t)
        t = re.sub(r"with\s+[A-Za-z0-9_.]+\s*;", "", t)
        for m in re.finditer(r"home\.packages\s*=", t):
            stmt = t[m.end():t.index(";", m.end())]
            for block in re.findall(r"\[([^\]]*)\]", stmt):
                for tok in re.findall(r"[A-Za-z0-9_.+-]+", block):
                    tok = tok[5:] if tok.startswith("pkgs.") else tok
                    if tok not in NIX_WORDS:
                        out.setdefault(tok, "modules/" + fn)
        for p in re.findall(r"programs\.([A-Za-z0-9_-]+)", t):
            out.setdefault(p, "modules/%s (programs.%s)" % (fn, p))


def declared():
    out = {}
    pacman_names(out)
    dram_names(out)
    flatpak_names(out)
    user_tool_names(out)
    nix_names(out)
    return out


def is_windows(name):
    return name.startswith(WIN_PREFIXES)


def winget_names(out, fails):
    # packages/winget/<role>.txt and host-<host>.txt: one prefixed name per line, own-line
    # comments only, a name in ONE list (bin/check.sh §3's rules for the Arch lists)
    d = os.path.join(ROOT, "packages", "winget")
    for fn in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if not fn.endswith(".txt"):
            continue
        src = os.path.join("packages", "winget", fn)
        with open(os.path.join(d, fn), encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                s = line.strip()
                if not s or s.startswith("#"):
                    continue
                kind, _, ident = s.partition(":")
                if kind not in WIN_IDS or not WIN_IDS[kind].fullmatch(ident):
                    fails.append("%s:%d: %r is not one winget:<Publisher.Package>, msstore:<Store id> or "
                                 "manual:<lowercase-name> (own-line comments only)" % (src, n, s))
                elif s in out:
                    fails.append("%s:%d: %s is listed in %s already (a name sits in one list)" % (src, n, s, out[s]))
                else:
                    out[s] = src


def flow_map(text):
    # '{ id: X, source: winget }' -> {"id": "X", "source": "winget"}: the one-line flow mapping
    # the .winget files give settings (keys lower-cased, quotes stripped, no nesting)
    out = {}
    if "}" not in text:
        return out
    for part in re.findall(r"""(?:[^,'"]|'[^']*'|"[^"]*")+""", text[text.index("{") + 1:text.rindex("}")]):
        k, sep, v = part.partition(":")
        if sep:
            out[k.strip().lower()] = v.strip().strip("'\"")
    return out


def winget_units(fails):
    # every Microsoft.WinGet.DSC/WinGetPackage unit of the rendered builds,
    # windows/build/<host>/*.winget (decisions/0020; configuration 0.2, Microsoft.WinGet/Package
    # once DSC v3): ("file:line", register name, absent)
    out = []
    builds = os.path.join(ROOT, "windows", "build")
    files = [(h, fn) for h in (sorted(os.listdir(builds)) if os.path.isdir(builds) else [])
             if os.path.isdir(os.path.join(builds, h))
             for fn in sorted(os.listdir(os.path.join(builds, h))) if fn.endswith(".winget")]
    for h, fn in files:
        src = "windows/build/%s/%s" % (h, fn)
        with open(os.path.join(builds, h, fn), encoding="utf-8") as f:
            text = f.read().split("\n")
        for i, line in enumerate(text):
            m = re.match(r"""(\s*)- resource:\s*['"]?([^'"\s#]+)""", line)
            if not m or not re.search(r"(^|/)WinGetPackage$|^Microsoft\.WinGet/Package$", m.group(2)):
                continue
            settings = None
            for j in range(i + 1, len(text)):
                s = text[j]
                if s.strip() and not s.lstrip().startswith("#") and len(s) - len(s.lstrip()) <= len(m.group(1)):
                    break  # the next unit
                sm = re.match(r"(\s*)settings:\s*(.*)$", s)
                if sm and sm.group(2).startswith("{"):
                    settings = flow_map(sm.group(2))
                elif sm:  # a block mapping: the more-indented lines below
                    settings = {}
                    for t in text[j + 1:]:
                        if t.strip() and len(t) - len(t.lstrip()) <= len(sm.group(1)):
                            break
                        km = re.match(r"\s*([A-Za-z_]+):\s*(.*?)\s*$", t)
                        if km:
                            settings[km.group(1).lower()] = re.sub(r"\s+#.*$", "", km.group(2)).strip("'\"")
                if settings is not None:
                    break
            pkg = (settings or {}).get("id", "")
            if not pkg:
                fails.append("%s:%d: a WinGetPackage unit whose settings name no package id" % (src, i + 1))
                continue
            kind = "msstore" if settings.get("source", "winget").lower() == "msstore" else "winget"
            absent = settings.get("ensure", "").lower() == "absent" or settings.get("_exist", "").lower() == "false"
            out.append(("%s:%d" % (src, i + 1), "%s:%s" % (kind, pkg), absent))
    return out


def check_windows(rows, wnames, fails, warns):
    # the Windows half: a row per listed name, the verdict rules, the twins, the .winget units;
    # returns the listed names by verdict, the units and the number of twin rows
    missing = sorted(n for n in wnames if n not in rows)
    if missing:
        fails.append("%d Windows name(s) without a register row: %s" % (len(missing), " ".join(
            "%s (%s)" % (n, wnames[n]) for n in missing)))
    by = {v: [] for v in VERDICTS}
    for name in sorted(wnames):
        verdict = rows.get(name, (None,))[0]
        if verdict in by:
            by[verdict].append(name)
    if by["fail"]:
        fails.append("listed for Windows but forbidden (verdict fail): %s" % " ".join(
            "%s (%s)" % (n, wnames[n]) for n in by["fail"]))
    for verdict, what in (("swap", "decided to go"),
                          ("pending", "awaiting a ruling (docs/security/software-supply/register.md)")):
        if by[verdict]:
            warns.append("%d Windows name(s) %s: %s" % (len(by[verdict]), what, " ".join(by[verdict])))
    twins = 0
    for name, (verdict, until, note, n) in sorted(rows.items()):
        m = TWIN.match(note) if is_windows(name) else None
        if not m:
            continue
        twins += 1
        arch = rows.get(m.group(1))
        if arch is None or is_windows(m.group(1)):
            fails.append("register.tsv:%d: %s twins %s, which has no Arch row" % (n, name, m.group(1)))
        elif (verdict, until) != arch[:2]:
            fails.append("register.tsv:%d: %s is %s %s, but its Arch twin %s is %s %s (line %d): a twin keeps "
                         "the Arch verdict and date" % (n, name, verdict, until, m.group(1), arch[0], arch[1], arch[3]))
    unused = sorted(n for n, r in rows.items() if is_windows(n) and n not in wnames and r[0] != "fail")
    if unused:
        warns.append("%d Windows register row(s) name nothing in packages/winget/ (drop them, or mark fail to "
                     "forbid): %s" % (len(unused), " ".join(unused)))
    units = winget_units(fails)
    loose = ["%s (%s)" % (name, where) for where, name, absent in units if not absent and name not in wnames]
    if loose:
        fails.append("%d WinGetPackage unit(s) in windows/build/*/*.winget install what no packages/winget list "
                     "names: %s" % (len(loose), " ".join(loose)))
    gone = ["%s (%s)" % (name, where) for where, name, absent in units if absent and rows.get(name, (None,))[0] != "fail"]
    if gone:
        fails.append("%d Ensure: Absent unit(s) in windows/build/*/*.winget remove what no fail row forbids: %s" % (
            len(gone), " ".join(gone)))
    return by, units, twins


def read_register(fails):
    rows = {}
    with open(REGISTER, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            cols = line.split("\t")
            if len(cols) != 4:
                fails.append("register.tsv:%d: want 4 tab-separated columns (name, verdict, until, note), got %d" % (n, len(cols)))
                continue
            name, verdict, until, note = (c.strip() for c in cols)
            if name in rows:
                fails.append("register.tsv:%d: duplicate row for %s" % (n, name))
            if verdict not in VERDICTS:
                fails.append("register.tsv:%d: %s has unknown verdict %r (one of %s)" % (n, name, verdict, ", ".join(VERDICTS)))
            if not note:
                fails.append("register.tsv:%d: %s has no note (say which rule and why)" % (n, name))
            rows[name] = (verdict, until, note, n)
    return rows


def main():
    rollout = listing = False
    for a in sys.argv[1:]:
        if a in ("-h", "--help"):
            usage(0)
        elif a == "--rollout":
            rollout = True
        elif a == "--list":
            listing = True
        else:
            usage(2)
    fails, warns = [], []
    wfails, wwarns = [], []  # the Windows names' (packages/winget/)
    if not os.path.exists(REGISTER):
        print("FAIL packages/register.tsv does not exist")
        sys.exit(1)
    rows = read_register(fails)
    names = declared()
    wnames = {}
    winget_names(wnames, wfails)
    if listing:
        for name, src in sorted(names.items()):
            print("%-34s %-10s %s" % (name, rows.get(name, ("-",))[0], src))
        for name, src in sorted(wnames.items(), key=lambda kv: kv[0].lower()):
            print("%-34s %-10s %s" % (name, rows.get(name, ("-",))[0], src))
        sys.exit(0)
    today = datetime.date.today()
    missing = sorted(n for n in names if n not in rows)
    if missing:
        fails.append("%d declared name(s) without a register row: %s" % (len(missing), " ".join(
            "%s (%s)" % (n, names[n]) for n in missing)))
    by = {v: [] for v in VERDICTS}
    for name in sorted(names):
        verdict = rows.get(name, (None,))[0]
        if verdict in by:
            by[verdict].append(name)
    for name, (verdict, until, note, n) in sorted(rows.items()):
        if verdict == "waiver":
            f = wfails if is_windows(name) else fails
            try:
                due = datetime.date.fromisoformat(until)
            except ValueError:
                f.append("register.tsv:%d: waiver %s needs a re-check date YYYY-MM-DD in the until column" % (n, name))
                continue
            if due < today:
                f.append("waiver for %s expired %s — re-check it (decisions/0013) and move the date or the package" % (name, until))
    if by["fail"]:
        fails.append("declared but forbidden (verdict fail): %s" % " ".join(
            "%s (%s)" % (n, names[n]) for n in by["fail"]))
    for verdict, what in (("swap", "decided to go"),
                          ("pending", "awaiting an Origin ruling (docs/security/software-supply/register.md)")):
        if by[verdict]:
            msg = "%d declared name(s) %s: %s" % (len(by[verdict]), what, " ".join(by[verdict]))
            (fails if rollout else warns).append(msg)
    unused = sorted(n for n, r in rows.items() if n not in names and r[0] != "fail" and not is_windows(n))
    if unused:
        warns.append("%d register row(s) name nothing declared (drop them, or mark fail to forbid): %s" % (
            len(unused), " ".join(unused)))
    wby, units, twins = check_windows(rows, wnames, wfails, wwarns)
    for m in fails + wfails:
        print("FAIL " + m)
    for m in warns + wwarns:
        print("WARN " + m)
    if not fails:
        counts = ", ".join("%d %s" % (len(by[v]), v) for v in VERDICTS if by[v])
        print("OK %d declared names all have a verdict (%s); %d waiver(s) in date" % (
            len(names), counts, sum(1 for n, r in rows.items() if r[0] == "waiver" and not is_windows(n))))
    if not wfails:
        counts = ", ".join("%d %s" % (len(wby[v]), v) for v in VERDICTS if wby[v])
        converged = {name for _, name, absent in units if not absent}
        print("OK %d Windows names (packages/winget/) all have a verdict (%s); %d waiver(s) in date; %d twin "
              "row(s) agree with Arch; the %d WinGetPackage unit(s) of windows/build are listed (%d listed "
              "winget/msstore name(s) no build installs)" % (
                  len(wnames), counts, sum(1 for n, r in rows.items() if r[0] == "waiver" and is_windows(n)), twins,
                  len(converged), sum(1 for n in wnames if not n.startswith("manual:") and n not in converged)))
    sys.exit(1 if fails or wfails else 0)


if __name__ == "__main__":
    main()

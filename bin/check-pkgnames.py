#!/usr/bin/env python3
"""usage: check-pkgnames.py [--refresh] [--mirror URL]

Checks that every name in packages/*.txt and packages/roles/*.txt (aur.txt
excepted) is something `pacman -S` can resolve: a package, a provided name or a
group in core, extra or multilib — or a [dram] package from pkgs/manifest.txt.
Works without pacman (the Mac): it downloads the three sync databases from an
Arch mirror into ~/.cache/dram/pkgdb/ (re-used for 24 h) and reads them in
memory. A T1-lite: names only, no dependency solving. `bin/check.sh` runs it
when CHECK_PKGDB=1 is set (it needs the network, so it is opt-in).

  --refresh       download the databases even if the cached copies are fresh
  --mirror URL    mirror base (default https://geo.mirror.pkgbuild.com); never
                  archlinux.org, which this LAN cannot reach
  -h, --help      this text

needs:  python3 and network access to an Arch mirror; pkgs/manifest.txt for [dram]
alone:  yes, for any directory of pacman lists: change the paths it reads
here:   bin/check.sh §3 when CHECK_PKGDB=1
exit:   0 every name resolves · 1 unknown names (listed) or a download failed · 2 bad usage
see:    docs/records/handbook/07-packages.md, decisions/0009-roles-and-host-shape.md,
        docs/operations/quality/README.md
"""
# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT

import os
import sys
import tarfile
import time
import urllib.request

REPOS = ("core", "extra", "multilib")
MAX_AGE = 24 * 3600


def usage(code):
    if code == 0:
        print(__doc__.strip())
    else:
        print(__doc__.splitlines()[0], file=sys.stderr)
    sys.exit(code)


def parse_args(argv):
    refresh, mirror = False, "https://geo.mirror.pkgbuild.com"
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("-h", "--help"):
            usage(0)
        elif a == "--refresh":
            refresh = True
        elif a == "--mirror" and i + 1 < len(argv):
            mirror = argv[i + 1].rstrip("/")
            i += 1
        else:
            usage(2)
        i += 1
    return refresh, mirror


def fetch(mirror, repo, cache, refresh):
    path = os.path.join(cache, f"{repo}.db")
    fresh = os.path.exists(path) and time.time() - os.path.getmtime(path) < MAX_AGE
    if refresh or not fresh:
        url = f"{mirror}/{repo}/os/x86_64/{repo}.db"
        tmp = path + ".part"
        with urllib.request.urlopen(url, timeout=120) as r, open(tmp, "wb") as out:
            out.write(r.read())
        os.replace(tmp, path)
    return path


def read_db(path, names, provides, groups):
    with tarfile.open(path, mode="r:*") as tar:
        for m in tar:
            if not m.isfile() or not m.name.endswith("/desc"):
                continue
            field, text = None, tar.extractfile(m).read().decode("utf-8", "replace")
            for line in text.splitlines():
                if line.startswith("%") and line.endswith("%"):
                    field = line
                elif not line:
                    field = None
                elif field == "%NAME%":
                    names.add(line)
                elif field == "%PROVIDES%":
                    provides.add(line.split("=")[0].split("<")[0].split(">")[0])
                elif field == "%GROUPS%":
                    groups.add(line)


def wanted(repo_root):
    out = {}
    dirs = [os.path.join(repo_root, "packages"), os.path.join(repo_root, "packages", "roles")]
    for d in dirs:
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".txt") or fn == "aur.txt":
                continue
            rel = os.path.relpath(os.path.join(d, fn), repo_root)
            with open(os.path.join(d, fn), encoding="utf-8") as f:
                for line in f:
                    s = line.strip()
                    if s and not s.startswith("#"):
                        out.setdefault(s, rel)
    return out


def dram_names(repo_root):
    path = os.path.join(repo_root, "pkgs", "manifest.txt")
    names = set()
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            for line in f:
                s = line.strip()
                if s and not s.startswith("#"):
                    names.add(s.split("=")[0])
    return names


def main():
    refresh, mirror = parse_args(sys.argv[1:])
    host = mirror.split("//", 1)[-1].split("/")[0]
    if host == "archlinux.org" or host.endswith(".archlinux.org"):
        print("error: archlinux.org is unreachable from this LAN; use a mirror", file=sys.stderr)
        sys.exit(2)
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    cache = os.path.join(os.path.expanduser("~"), ".cache", "dram", "pkgdb")
    os.makedirs(cache, exist_ok=True)
    names, provides, groups = set(), set(), set()
    try:
        for repo in REPOS:
            read_db(fetch(mirror, repo, cache, refresh), names, provides, groups)
    except (OSError, tarfile.TarError) as e:
        print(f"error: could not read the sync databases from {mirror}: {e}", file=sys.stderr)
        sys.exit(1)
    ours = dram_names(repo_root)
    bad = []
    for pkg, where in sorted(wanted(repo_root).items()):
        if pkg in names or pkg in provides or pkg in groups or pkg in ours:
            continue
        bad.append(f"{pkg}  ({where})")
    if bad:
        print(f"{len(bad)} name(s) pacman -S cannot resolve from {'/'.join(REPOS)} or [dram]:")
        for b in bad:
            print(f"  {b}")
        sys.exit(1)
    print(f"every listed name resolves ({len(names)} packages in {'/'.join(REPOS)}, {len(ours)} in [dram])")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""usage: check-docs.py [--strict] [--list] [map|links|see|private ...] [-- <file> ...]

Checks that the documentation holds together, with the standard library only.

  map      every tracked path matches a rule of docs/map.tsv other than the catch-all;
           every directorate and division of the chart has its page; every page a rule
           names exists
  links    in every tracked *.md at any depth: each relative Markdown link (and its
           #anchor) resolves, and each backticked repo path (`system/...`, `docs/...`)
           exists; docs/history/ (frozen pages) and decisions/0007 (old paths
           tabulated beside the new) are left out
  see      every repo path on a `see:` line of a script or module header exists (and
           its #anchor, when it has one)
  private  tracked text carries none of the words this clone keeps out of the tree:
           addresses, serial numbers, mail addresses and any other term its owner lists
           in <git dir>/info/private.tsv, outside the repo, since a list in the repo
           would publish what it guards; a clone without that file checks nothing
  (none)   all four

  --strict      findings are failures (FAIL lines, exit 1); without it they are warnings
  --list        map: print every tracked path with its directorate, division and branch
  -- <file>...  links, see, private: only these files
  -h, --help    this text

Output lines start with FAIL, WARN or OK; bin/check.sh §6 (links, see), §22 (map) and
§24 (private) run this, in the mode its DOCS_GUARDS switch sets.

exit: 0 no failures · 1 failures (with --strict) · 2 bad usage
see: docs/map.tsv, docs/records/style.md, docs/records/README.md
"""
import os
import posixpath
import re
import subprocess
import sys
import urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAP = "docs/map.tsv"
SELF = "bin/check-docs.py"

# Top-level directories whose paths the docs cite in backticks and on see: lines.
TOPDIRS = ("system", "bin", "install", "modules", "packages", "docs", "dotfiles", "hosts",
           "decisions", "pkgs", "secrets", "windows", "tests", "keys", "templates",
           ".github", "LICENSES")
# Pages that describe another tree on purpose: frozen history, a rename table.
LINKS_SKIP = (re.compile(r"^docs/history/"), re.compile(r"^decisions/0007-"),
              re.compile(r"^system/refind-catppuccin/"))
BINARY_EXT = {".png", ".jpg", ".jpeg", ".gif", ".ico", ".icns", ".bmp", ".webp", ".ttf",
              ".otf", ".woff", ".woff2", ".crt", ".der", ".cer", ".p7b", ".vsix", ".zip",
              ".gz", ".xz", ".zst", ".tar", ".pdf", ".mp4", ".webm", ".ogg", ".wav", ".bin"}


def usage(err=None):
    if err:
        print("check-docs.py: %s" % err, file=sys.stderr)
    print(__doc__.split("\n", 1)[0], file=sys.stderr)
    sys.exit(2)


# --------------------------------------------------------------------------- the repo
def tracked():
    out = subprocess.run(["git", "-C", ROOT, "ls-files", "-z"], capture_output=True, check=True)
    files = [f for f in out.stdout.decode("utf-8", "surrogateescape").split("\0") if f]
    return [f for f in files if os.path.lexists(os.path.join(ROOT, f))]


def read_text(rel):
    if os.path.splitext(rel)[1].lower() in BINARY_EXT:
        return None
    p = os.path.join(ROOT, rel)
    if os.path.islink(p) or not os.path.isfile(p):
        return None
    try:
        with open(p, "rb") as f:
            data = f.read()
    except OSError:
        return None
    if b"\0" in data[:8192]:
        return None
    return data.decode("utf-8", "replace")


class Paths:
    """What exists: tracked files, the directories that hold them, and ignored runtime paths."""

    def __init__(self, files):
        self.files = set(files)
        self.dirs = set()
        for f in files:
            d = posixpath.dirname(f)
            while d and d not in self.dirs:
                self.dirs.add(d)
                d = posixpath.dirname(d)
        self._ignored = {}

    def exists(self, rel):
        rel = rel.rstrip("/")
        if rel in self.files or rel in self.dirs:
            return True
        return os.path.exists(os.path.join(ROOT, rel)) or self.ignored(rel)

    def ignored(self, rel):
        # a runtime seed (themes/current, a gitignored *.default copy) is a real path on a host
        if rel not in self._ignored:
            r = subprocess.run(["git", "-C", ROOT, "check-ignore", "-q", "--no-index", rel],
                               capture_output=True)
            self._ignored[rel] = r.returncode == 0
        return self._ignored[rel]

    def prefix(self, rel):
        # shorthand such as decisions/0011 names decisions/0011-<title>.md
        return any(f.startswith(rel) for f in self.files)


# --------------------------------------------------------------------------- markdown
FENCE = re.compile(r"^\s{0,3}(```+|~~~+)")
HEADING = re.compile(r"^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$")
EXPLICIT_ID = re.compile(r"""<a\s+[^>]*?(?:id|name)\s*=\s*["']([^"']+)["']""", re.I)
INLINE_CODE = re.compile(r"(`+)(.+?)\1")
MD_LINK = re.compile(r"!?\[(?:[^\[\]\\]|\\.|\[[^\]]*\])*\]\(\s*(<[^>]*>|[^()\s]+(?:\([^()\s]*\)[^()\s]*)*)(?:\s+(?:\"[^\"]*\"|'[^']*'))?\s*\)")
REF_DEF = re.compile(r"^\s{0,3}\[[^\]]+\]:\s*(<[^>]*>|\S+)")
HTML_REF = re.compile(r"""<(?:a|img|source)\s[^>]*?(?:href|src)\s*=\s*["']([^"']+)["']""", re.I)
SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")


def md_lines(text):
    """(lineno, line) for every line outside fenced code blocks."""
    fence = None
    for n, line in enumerate(text.split("\n"), 1):
        m = FENCE.match(line)
        if fence:
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence):
                fence = None
            continue
        if m:
            fence = m.group(1)
            continue
        yield n, line


def slug(text):
    t = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", text)
    t = re.sub(r"<[^>]+>", "", t)
    t = t.strip().lower()
    t = re.sub(r"[^\w\- ]", "", t)
    return t.replace(" ", "-")


_anchor_cache = {}


def anchors(rel):
    if rel in _anchor_cache:
        return _anchor_cache[rel]
    text = read_text(rel) or ""
    seen, out = {}, set()
    for _, line in md_lines(text):
        for m in EXPLICIT_ID.finditer(line):
            out.add(m.group(1))
        h = HEADING.match(line)
        if h:
            s = slug(h.group(2))
            k = seen.get(s, 0)
            seen[s] = k + 1
            out.add(s if k == 0 else "%s-%d" % (s, k))
    _anchor_cache[rel] = out
    return out


def has_anchor(rel, frag):
    frag = urllib.parse.unquote(frag)
    a = anchors(rel)
    return frag in a or frag.lower() in a


def target_md(paths, rel):
    """The Markdown page a link to `rel` opens: the file, or a directory's README.md."""
    if rel in paths.files:
        return rel if rel.endswith(".md") else None
    readme = posixpath.join(rel, "README.md") if rel else "README.md"
    return readme if readme in paths.files else None


BACKTICK_PATH = re.compile(r"^(?:\./)?(?:%s)/[A-Za-z0-9_./#-]*$" % "|".join(re.escape(d) for d in TOPDIRS))
PLACEHOLDER = re.compile(r"(^|/)[A-Z][A-Z0-9_]+(\.[a-z]+|/|$)")


def path_problem(paths, rel, frag=None):
    """None when rel (repo-relative, no leading ./) exists and frag resolves in it."""
    rel = posixpath.normpath(rel) if rel not in ("", ".") else ""
    if rel.startswith(".."):
        return "points outside the repo"
    if rel and not paths.exists(rel):
        return "does not exist"
    if frag:
        md = target_md(paths, rel)
        if md and not has_anchor(md, frag):
            return "has no #%s" % frag
    return None


def check_links(paths, files, report):
    pages = [f for f in files if f.endswith(".md") and not any(p.search(f) for p in LINKS_SKIP)]
    n_links = n_paths = 0
    for page in pages:
        text = read_text(page)
        if text is None:
            continue
        here = posixpath.dirname(page)
        for n, line in md_lines(text):
            # backticked repo paths, as §6 always read them: from the repo root
            for m in INLINE_CODE.finditer(line):
                span = m.group(2).strip()
                if not BACKTICK_PATH.match(span) or "..." in span or "newbox" in span or PLACEHOLDER.search(span):
                    continue
                n_paths += 1
                path, _, frag = span.partition("#")
                path = path[2:] if path.startswith("./") else path
                prob = path_problem(paths, path, frag or None)
                if prob and not frag and paths.prefix(path.rstrip("/")):
                    prob = None
                if prob and not frag:
                    alt = posixpath.normpath(posixpath.join(here, path))
                    if not alt.startswith("..") and paths.exists(alt):
                        prob = None
                if prob:
                    report("%s:%d: `%s` %s" % (page, n, span, prob))
            bare = INLINE_CODE.sub("", line)
            targets = [m.group(1) for m in MD_LINK.finditer(bare)]
            targets += [m.group(1) for m in REF_DEF.finditer(bare)]
            targets += [m.group(1) for m in HTML_REF.finditer(bare)]
            for t in targets:
                t = t.strip("<>").strip()
                if not t or SCHEME.match(t) or t.startswith("//"):
                    continue
                n_links += 1
                path, _, frag = t.partition("#")
                path = urllib.parse.unquote(path.split("?", 1)[0])
                if not path:
                    if frag and not has_anchor(page, frag):
                        report("%s:%d: link #%s: no such heading or anchor on this page" % (page, n, frag))
                    continue
                rel = path.lstrip("/") if path.startswith("/") else posixpath.join(here, path)
                prob = path_problem(paths, rel, frag or None)
                if prob:
                    report("%s:%d: link %s %s" % (page, n, t, prob))
    return "%d page(s): %d relative link(s), %d backticked path(s)" % (len(pages), n_links, n_paths)


# --------------------------------------------------------------------------- see:
SEE = re.compile(r"^\s*(?:#|//|--|;|\*|/\*|\"\"\"|''')?\s*see:\s*(.*)$")
SEE_MORE = re.compile(r"^\s*(?:#|//|--|;|\*)?\s{4,}(\S.*)$")
SEE_PATH = re.compile(r"(?<![\w/.-])((?:%s)/[A-Za-z0-9_./-]*[A-Za-z0-9_/-](?:#[A-Za-z0-9_-]+)?)" % "|".join(re.escape(d) for d in TOPDIRS))


def check_see(paths, files, report):
    n_files = n_refs = 0
    for f in files:
        if f.endswith(".md") or f == SELF:
            continue
        text = read_text(f)
        if text is None:
            continue
        lines = text.split("\n")[:120]
        found = False
        for i, line in enumerate(lines):
            m = SEE.match(line)
            if not m:
                continue
            found = True
            chunk = [m.group(1)]
            for nxt in lines[i + 1:i + 4]:
                mm = SEE_MORE.match(nxt)
                if not mm or re.match(r"^[a-z]+:\s", mm.group(1)):
                    break
                chunk.append(mm.group(1))
            for ref in SEE_PATH.findall(" ".join(chunk)):
                n_refs += 1
                path, _, frag = ref.partition("#")
                if "..." in path or PLACEHOLDER.search(path):
                    continue
                prob = path_problem(paths, path, frag or None)
                if prob and not frag and paths.prefix(path.rstrip("/")):
                    prob = None
                if prob:
                    report("%s:%d: see: %s %s" % (f, i + 1, ref, prob))
        n_files += found
    return "%d header(s) with a see: line, %d repo path(s) on them" % (n_files, n_refs)


# --------------------------------------------------------------------------- the map
def compile_pattern(pat):
    anchored = "/" in pat.rstrip("/")
    p = pat.strip("/") if pat != "/" else ""
    out, i = "", 0
    while i < len(p):
        if p.startswith("**/", i):
            out, i = out + "(?:.*/)?", i + 3
        elif p.startswith("**", i):
            out, i = out + ".*", i + 2
        elif p[i] == "*":
            out, i = out + "[^/]*", i + 1
        elif p[i] == "?":
            out, i = out + "[^/]", i + 1
        else:
            out, i = out + re.escape(p[i]), i + 1
    head = "^" if anchored else "^(?:.*/)?"
    # a pattern that names a directory also covers everything under it
    return re.compile(head + out + "(?:/.*)?$")


def load_map(report):
    chart, rules = {}, []
    path = os.path.join(ROOT, MAP)
    if not os.path.isfile(path):
        report("%s is missing" % MAP)
        return chart, rules
    with open(path, encoding="utf-8") as fh:
        for n, raw in enumerate(fh, 1):
            line = raw.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            cols = line.split("\t")
            if line.startswith("="):
                if len(cols) != 3:
                    report("%s:%d: a chart row is =<directorate>[/<division>]<TAB><title><TAB><page>" % (MAP, n))
                    continue
                chart[cols[0][1:]] = (cols[1], cols[2], n)
                continue
            if len(cols) != 5:
                report("%s:%d: a rule is <pattern><TAB><directorate><TAB><division><TAB><branch><TAB><page>" % (MAP, n))
                continue
            rules.append((cols[0], compile_pattern(cols[0]), cols[1], cols[2], cols[3], cols[4], n))
    return chart, rules


def placement(rules, f):
    hit = None
    for r in rules:
        if r[1].match(f):
            hit = r
    return hit


def check_map(paths, files, report, listing=False):
    chart, rules = load_map(report)
    if not rules:
        return "no rules"
    missing = {}  # page -> the map lines that name it
    for node, (title, page, n) in chart.items():
        if page != "-" and not paths.exists(page):
            missing.setdefault(page, []).append(n)
    catch_all = rules[0]
    for r in rules:
        pat, _, d, div, br, page, n = r
        node = d if div == "-" else "%s/%s" % (d, div)
        if d not in chart or node not in chart:
            report("%s:%d: %s names %s, which the chart does not have" % (MAP, n, pat, node))
        if page != "-" and not paths.exists(page):
            missing.setdefault(page, []).append(n)
    for page in sorted(missing):
        lines = missing[page]
        report("%s does not exist (named on %d line(s) of %s, the first %d)" % (page, len(lines), MAP, lines[0]))
    unmapped = []
    for f in files:
        r = placement(rules, f)
        if listing:
            print("%s\t%s" % (f, "\t".join(r[2:5]) if r else "-"))
        if r is None or r is catch_all:
            unmapped.append(f)
    if unmapped:
        groups = {}
        for f in unmapped:
            groups.setdefault(posixpath.dirname(f) or ".", []).append(posixpath.basename(f))
        for d in sorted(groups):
            names = groups[d]
            shown = ", ".join(names[:6]) + (" and %d more" % (len(names) - 6) if len(names) > 6 else "")
            report("unmapped (only the catch-all row matches): %s/: %s" % (d, shown))
    return "%d tracked path(s), %d chart node(s), %d rule(s); %d unmapped" % (
        len(files), len(chart), len(rules), len(unmapped))


# --------------------------------------------------------------------------- private
# <git dir>/info/private.tsv, one rule per line: a name, a Python regular expression, and
# optionally a second expression that allows the match (it sees the line and the one
# before it, since comments wrap). Blank lines and lines starting with # are skipped; a
# pattern that should ignore case starts with (?i).
def private_rules(report):
    try:
        gitdir = subprocess.run(["git", "rev-parse", "--git-common-dir"], capture_output=True,
                                text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None, []
    path = os.path.join(os.path.abspath(gitdir), "info", "private.tsv")
    if not os.path.isfile(path):
        return path, None
    rules = []
    with open(path, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 2 or not parts[1]:
                report("%s:%d: a rule needs a name and a pattern" % (path, n))
                continue
            try:
                pat = re.compile(parts[1])
                allow = re.compile(parts[2]) if len(parts) > 2 and parts[2] else None
            except re.error as e:
                report("%s:%d: %s" % (path, n, e))
                continue
            rules.append((parts[0], pat, allow))
    return path, rules


def check_private(files, report):
    path, rules = private_rules(report)
    if rules is None:
        return "no %s in this clone: nothing to check" % (path or "git directory")
    n_files = 0
    for f in files:
        text = read_text(f)
        if text is None:
            continue
        n_files += 1
        prev = ""
        for n, line in enumerate(text.split("\n"), 1):
            context = prev + "\n" + line
            prev = line
            for name, pat, allow in rules:
                m = pat.search(line)
                if not m or (allow and allow.search(context)):
                    continue
                excerpt = line.strip()
                if len(excerpt) > 110:
                    s0 = max(0, m.start() - len(line) + len(line.lstrip()) - 40)
                    excerpt = ("…" if s0 else "") + excerpt[s0:s0 + 110] + "…"
                report("%s:%d: %s: %s" % (f, n, name, excerpt))
                break
    return "%d text file(s) read, %d rule(s)" % (n_files, len(rules))


# --------------------------------------------------------------------------- main
def main(argv):
    strict = listing = False
    checks, only = [], None
    args = list(argv)
    while args:
        a = args.pop(0)
        if a in ("-h", "--help"):
            print(__doc__.strip("\n"))
            return 0
        if a == "--strict":
            strict = True
        elif a == "--list":
            listing = True
        elif a == "--":
            only = args
            args = []
        elif a in ("map", "links", "see", "private"):
            checks.append(a)
        else:
            usage("unknown argument: %s" % a)
    checks = checks or ["map", "links", "see", "private"]
    os.chdir(ROOT)
    files = tracked()
    paths = Paths(files)
    scope = files
    if only is not None:
        scope = [posixpath.normpath(f) for f in only]
    word = "FAIL" if strict else "WARN"
    total = 0
    for c in checks:
        found = []
        if c == "map":
            summary = check_map(paths, files, found.append, listing)
        elif c == "links":
            summary = check_links(paths, scope, found.append)
        elif c == "see":
            summary = check_see(paths, scope, found.append)
        else:
            summary = check_private(scope, found.append)
        for line in found:
            print("%s %s: %s" % (word, c, line))
        if not found:
            print("OK %s: %s" % (c, summary))
        else:
            print("%s %s: %d finding(s) in %s" % (word, c, len(found), summary))
        total += len(found)
    return 1 if (strict and total) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

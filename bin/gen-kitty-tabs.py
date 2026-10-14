#!/usr/bin/env python3
"""usage: gen-kitty-tabs.py [theme ...]

Rewrites the five tab-colour lines of every theme's kitty.conf (or the named themes') from colours the theme already states elsewhere; touches only those five lines and prints the files it rewrote. A dev-time generator; commit the output.

The tab bar is a running head (dotfiles/.config/kitty/README.md → "The running
head"): no fills, the accent as ink on the active title, the subtext ink on the
rest, the page colour behind everything. Each theme already states those
colours elsewhere, so the five lines are derived, not hand-edited:

    active_tab_foreground    = cursor_trail_color   (themes/<t>/kitty.conf — the accent)
    active_tab_background    = background           (themes/<t>/kitty.conf)
    inactive_tab_foreground  = @subtext             (themes/<t>/waybar.css)
    inactive_tab_background  = background
    tab_bar_background       = background

Run from anywhere:  python3 bin/gen-kitty-tabs.py [theme ...]
No arguments = every theme dir. Idempotent; touches only those five lines and
prints the files it rewrote.

  theme ...     theme dir ids under dotfiles/.config/themes (default: every theme)
  -h, --help    this text

exit: 0 ok · 1 a theme failed to render · 2 bad usage
see: dotfiles/.config/kitty/README.md
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THEMES = os.path.join(ROOT, "dotfiles", ".config", "themes")
KEYS = ("active_tab_foreground", "active_tab_background",
        "inactive_tab_foreground", "inactive_tab_background", "tab_bar_background")


def kitty_value(text, key):
    m = re.search(rf"^{key}\s+(#[0-9a-fA-F]{{6}})\s*$", text, re.M)
    return m.group(1).lower() if m else None


def subtext(path):
    s = open(path, encoding="utf-8").read()
    m = re.search(r"@define-color\s+subtext\s+(#[0-9a-fA-F]{6})\s*;", s)
    return m.group(1).lower() if m else None


def render(theme):
    d = os.path.join(THEMES, theme)
    target = os.path.join(d, "kitty.conf")
    src = open(target, encoding="utf-8").read()
    bg = kitty_value(src, "background")
    accent = kitty_value(src, "cursor_trail_color")
    sub = subtext(os.path.join(d, "waybar.css"))
    if not (bg and accent and sub):
        sys.exit(f"{theme}: need background + cursor_trail_color (kitty.conf) and @subtext (waybar.css)")
    want = {"active_tab_foreground": accent, "active_tab_background": bg,
            "inactive_tab_foreground": sub, "inactive_tab_background": bg,
            "tab_bar_background": bg}
    out, seen = [], set()
    for line in src.splitlines(keepends=True):
        m = re.match(r"^(\S+)(\s+)#[0-9a-fA-F]{6}(\s*)$", line)
        if m and m.group(1) in want:
            seen.add(m.group(1))
            line = f"{m.group(1)}{m.group(2)}{want[m.group(1)]}{m.group(3)}"
        out.append(line)
    missing = [k for k in KEYS if k not in seen]
    if missing:
        sys.exit(f"{theme}: kitty.conf lacks {missing}")
    new = "".join(out)
    if new != src:
        open(target, "w", encoding="utf-8").write(new)
        print("wrote", os.path.relpath(target, ROOT))


def _parse_args():
    """argparse over the module docstring: usage line, description, hidden flags."""
    import argparse
    doc = (__doc__ or "").strip().splitlines()
    ap = argparse.ArgumentParser(
        prog=doc[0].split()[1], usage=doc[0][len("usage: "):],
        description="\n".join(doc[1:]).strip(), add_help=False,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-h", "--help", action="help", help=argparse.SUPPRESS)
    ap.add_argument("theme", nargs="*", help=argparse.SUPPRESS)
    return ap.parse_args()


def main(argv):
    themes = argv or sorted(
        t for t in os.listdir(THEMES)
        if os.path.isdir(os.path.join(THEMES, t)) and t != "current"
    )
    for t in themes:
        render(t)


if __name__ == "__main__":
    main(_parse_args().theme)

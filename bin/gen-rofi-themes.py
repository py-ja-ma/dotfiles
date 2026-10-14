#!/usr/bin/env python3
"""usage: gen-rofi-themes.py [theme ...]

Writes every theme's rofi.rasi (or the named themes') from one template, dotfiles/.config/rofi/theme.rasi.tmpl, and the theme's palette; prints the files it rewrote. A dev-time generator; commit the output.

The 17 rofi files are identical except for seven colours, so they are generated:
    dotfiles/.config/rofi/theme.rasi.tmpl   (layout, fonts, hairlines)
  + dotfiles/.config/themes/<t>/waybar.css  (base/surface0/surface1/text/subtext/red/accent)
  + dotfiles/.config/themes/<t>/palette.lua (accent, when waybar.css has none)
  = dotfiles/.config/themes/<t>/rofi.rasi   (committed — rofi reads it directly)

Run from anywhere:  python3 bin/gen-rofi-themes.py [theme ...]
No arguments = every theme dir. Idempotent; prints the files it rewrote.
See dotfiles/.config/rofi/README.md ("The generated theme").

  theme ...     theme dir ids under dotfiles/.config/themes (default: every theme)
  -h, --help    this text

exit: 0 ok · 1 a theme failed to render · 2 bad usage
see: dotfiles/.config/rofi/README.md
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THEMES = os.path.join(ROOT, "dotfiles", ".config", "themes")
TMPL = os.path.join(ROOT, "dotfiles", ".config", "rofi", "theme.rasi.tmpl")

KEYS = {  # template token -> waybar.css @define-color name
    "BASE": "base", "SURFACE0": "surface0", "SURFACE1": "surface1",
    "TEXT": "text", "SUBTEXT": "subtext", "RED": "red", "ACCENT": "accent",
}


def define_colors(path):
    s = open(path, encoding="utf-8").read()
    return dict(re.findall(r"@define-color\s+(\S+)\s+(#[0-9a-fA-F]{6})\s*;", s))


def accent_from_palette(path):
    s = open(path, encoding="utf-8").read()
    m = re.search(r'accent\s*=\s*"rgba\(([0-9a-fA-F]{6})[0-9a-fA-F]{2}\)"', s)
    return "#" + m.group(1).lower() if m else None


def render(theme):
    d = os.path.join(THEMES, theme)
    cols = define_colors(os.path.join(d, "waybar.css"))
    cols.setdefault("accent", accent_from_palette(os.path.join(d, "palette.lua")) or cols.get("blue"))
    missing = [k for k, v in KEYS.items() if not cols.get(v)]
    if missing:
        sys.exit(f"{theme}: waybar.css lacks {missing}")
    out = open(TMPL, encoding="utf-8").read()
    out = out.replace("{{NAME}}", theme)
    for tok, name in KEYS.items():
        out = out.replace("{{" + tok + "}}", cols[name].lower())
    target = os.path.join(d, "rofi.rasi")
    old = open(target, encoding="utf-8").read() if os.path.exists(target) else None
    if old != out:
        open(target, "w", encoding="utf-8").write(out)
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

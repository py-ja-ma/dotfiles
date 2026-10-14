#!/usr/bin/env python3
"""usage: gen-browser-css.py [theme ...]

Writes the browser/mail chrome palette (themes/<t>/browser.css) for every dram theme, or for the named ones. A dev-time generator: run it after editing a theme's palette and commit the output; dram-theme only links the files.

LibreWolf and Thunderbird take their chrome from a userChrome.css in the PROFILE
dir. The rules are static and tracked once (dotfiles/.librewolf/chrome/userChrome.css,
dotfiles/.thunderbird-chrome/userChrome.css); the colours are this file's output,
one per theme, which both sheets @import as `letterpress-colors.css`:

    dotfiles/.config/themes/<t>/waybar.css   base/mantle/crust/text/subtext/overlay/
                                             surface0/surface1/red/green/yellow/blue
  + dotfiles/.config/themes/<t>/palette.lua  accent, accent_dim (the ONE accent ink)
  + dotfiles/.config/themes/<t>/meta.sh      COLOR_SCHEME (prefer-light -> light derivations)
  = dotfiles/.config/themes/<t>/browser.css  `:root { color-scheme: dark; --lp-base: … }`

dram-theme links <profile>/chrome/letterpress-colors.css -> themes/current/browser.css,
so a theme switch swaps the colours without touching the rules. The file defines
ONLY --lp-* custom properties (+ color-scheme): the mapping onto Firefox's and
Thunderbird's own variables lives in the two userChrome.css files, where it is
reviewed against the app's stylesheet version (dotfiles/.librewolf/README.md).
Same light/dark derivations as bin/gen-gtk-css.py:

    view   = mantle (dark) | base mixed 45 % toward white (light)   the reading surface
    raised = surface0 (dark) | view (light)                          popovers, menus, panels
    rule   = alpha(text, .18)   the hairline       shade = alpha(text, .10)
    hover  = alpha(text, .08)   active = alpha(text, .14)   faint = alpha(text, .55)
    accent_fg = best contrast of white / crust / text on the accent

Run from anywhere:  python3 bin/gen-browser-css.py [theme ...]
No arguments = every theme dir. Idempotent; prints the files it rewrote.

  theme ...     theme dir ids under dotfiles/.config/themes (default: every theme)
  -h, --help    this text

exit: 0 ok · 1 a theme failed to render · 2 bad usage
see: dotfiles/.librewolf/README.md
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THEMES = os.path.join(ROOT, "dotfiles", ".config", "themes")
NEEDED = ["base", "mantle", "crust", "text", "subtext", "overlay",
          "surface0", "surface1", "red", "green", "yellow", "blue"]
ALPHAS = {"rule": 0.18, "shade": 0.10, "hover": 0.08, "active": 0.14, "faint": 0.55}


# ---- colour maths (as gen-gtk-css.py) -------------------------------------------
def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hexs(c):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(v))) for v in c)


def mix(a, b, t):  # t=0 -> a, t=1 -> b
    a, b = rgb(a), rgb(b)
    return hexs(tuple(a[i] + (b[i] - a[i]) * t for i in range(3)))


def luminance(h):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(v) for v in rgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def rgba(h, a):
    return "rgba(%d, %d, %d, %.2f)" % (rgb(h) + (a,))


# ---- inputs ---------------------------------------------------------------------
def define_colors(path):
    s = open(path, encoding="utf-8").read()
    return {k: v.lower() for k, v in re.findall(r"@define-color\s+(\S+)\s+(#[0-9a-fA-F]{6})\s*;", s)}


def palette_color(path, key):
    # palette.lua is `return { accent = "rgba(RRGGBBAA)", ... }`; the alpha is Hyprland's
    s = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
    m = re.search(r'^\s*%s\s*=\s*"rgba\(([0-9a-fA-F]{6})[0-9a-fA-F]{2}\)"' % re.escape(key), s, re.M)
    return "#" + m.group(1).lower() if m else None


def color_scheme(path):
    s = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
    m = re.search(r'^COLOR_SCHEME="([^"]*)"', s, re.M)
    return m.group(1) if m else "prefer-dark"


# ---- the palette ----------------------------------------------------------------
def derive(cols, accent, accent_dim, light):
    base, mantle, text, crust = cols["base"], cols["mantle"], cols["text"], cols["crust"]
    view = mix(base, "#ffffff", 0.45) if light else mantle
    raised = view if light else cols["surface0"]
    v = [
        ("base", base), ("mantle", mantle), ("crust", crust),
        ("surface0", cols["surface0"]), ("surface1", cols["surface1"]),
        ("view", view), ("raised", raised),
        ("text", text), ("subtext", cols["subtext"]), ("overlay", cols["overlay"]),
        ("accent", accent), ("accent-dim", accent_dim),
        ("accent-fg", max(["#ffffff", crust, text], key=lambda c: contrast(accent, c))),
        ("red", cols["red"]), ("green", cols["green"]), ("yellow", cols["yellow"]), ("blue", cols["blue"]),
    ]
    v += [(k, rgba(text, a)) for k, a in ALPHAS.items()]
    return v


def render(theme):
    d = os.path.join(THEMES, theme)
    cols = define_colors(os.path.join(d, "waybar.css"))
    missing = [k for k in NEEDED if k not in cols]
    if missing:
        sys.exit(f"{theme}: waybar.css lacks {missing}")
    accent = palette_color(os.path.join(d, "palette.lua"), "accent") or cols.get("accent")
    if not accent:
        sys.exit(f"{theme}: no accent in palette.lua or waybar.css")
    accent_dim = palette_color(os.path.join(d, "palette.lua"), "accent_dim") or mix(accent, cols["crust"], 0.3)
    light = color_scheme(os.path.join(d, "meta.sh")) == "prefer-light"
    out = (
        f"/* {theme} — browser + mail chrome palette. GENERATED by bin/gen-browser-css.py\n"
        f" * from waybar.css + palette.lua + meta.sh ({'light' if light else 'dark'}); do not edit, regenerate.\n"
        " * @import'ed as letterpress-colors.css by ~/.librewolf/chrome/userChrome.css and\n"
        " * ~/.thunderbird-chrome/userChrome.css (dotfiles/.librewolf/README.md).\n"
        " * Only --lp-* names here; the app variables are mapped in the two static sheets.\n"
        " * userChrome.css is a USER sheet under the app's own AUTHOR sheets, hence the\n"
        " * !important on color-scheme (the --lp-* names are ours alone and need none). */\n"
        ":root {\n"
        f"  color-scheme: {'light' if light else 'dark'} !important;\n"
    )
    for k, val in derive(cols, accent, accent_dim, light):
        out += f"  --lp-{k}: {val};\n"
    out += "}\n"
    target = os.path.join(d, "browser.css")
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

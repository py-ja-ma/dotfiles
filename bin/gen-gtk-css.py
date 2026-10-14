#!/usr/bin/env python3
"""usage: gen-gtk-css.py [theme ...]

Recolours adw-gtk3 / libadwaita for every dram theme, or for the named ones: writes themes/<t>/gtk.css (GTK4) and gtk3.css (GTK3) from the theme's palette. A dev-time generator; commit the output.

One GTK theme (adw-gtk3, pacman `adw-gtk-theme`) serves all 17 dram themes; the
colours come from two generated user stylesheets per theme, written here:

    dotfiles/.config/themes/<t>/waybar.css   base/mantle/crust/text/surface0/red/green/yellow
                                             (+accent fallback)
  + dotfiles/.config/themes/<t>/palette.lua  accent (the one accent ink)
  + dotfiles/.config/themes/<t>/meta.sh      COLOR_SCHEME (prefer-light -> light derivations)
  = dotfiles/.config/themes/<t>/gtk.css      GTK4 / libadwaita: `:root { --accent-bg-color }`
                                             variables, the legacy `@define-color` aliases,
                                             and the Letterpress chrome (3 px radii, hairlines,
                                             no heavy shadows)
  = dotfiles/.config/themes/<t>/gtk3.css     GTK3 / adw-gtk3: `@define-color` ONLY

dram-theme links ~/.config/gtk-4.0/gtk.css -> themes/current/gtk.css and
~/.config/gtk-3.0/gtk.css -> themes/current/gtk3.css. Two files because GTK3
cannot parse `:root { --var }` (it would log a parse error in every GTK3 app),
and gtk3.css carries no selector rules: GTK loads the user stylesheet
at GTK_STYLE_PROVIDER_PRIORITY_USER (800), above an application's own CSS (600),
so a `button {}` rule there would restyle waybar and nwg-drawer, both GTK3, over
their themed stylesheets. Named colours are harmless (the
libadwaita names do not collide with the waybar.css palette names).

Colour mapping (palette field -> GTK named colour / variable):
    base      -> window_bg, headerbar_bg (flat page: the headerbar is the window)
    mantle    -> view_bg (dark) | sidebar_bg
    base+white-> view_bg (light: a lighter step derived from base)
    surface0  -> card_bg, popover_bg, dialog_bg, thumbnail_bg (dark); light uses view_bg
    text      -> every *_fg colour, and the hairline alpha(text, .18)
    accent    -> accent_bg_color, accent_color; accent_fg = best contrast of white/crust/text
    red       -> destructive_*, error_*     green -> success_*     yellow -> warning_*

Run from anywhere:  python3 bin/gen-gtk-css.py [theme ...]
No arguments = every theme dir. Idempotent; prints the files it rewrote.
See docs/design/themes/generators.md ("GTK").

  theme ...     theme dir ids under dotfiles/.config/themes (default: every theme)
  -h, --help    this text

exit: 0 ok · 1 a theme failed to render · 2 bad usage
see: docs/design/themes/generators.md
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THEMES = os.path.join(ROOT, "dotfiles", ".config", "themes")
HAIRLINE = 0.18  # the Letterpress hairline: 1 px in alpha(@text, .18) (docs/design/README.md)
SHADE = 0.10     # softer than the hairline: toolbar/scrolled-window shade lines

NEEDED = ["base", "mantle", "crust", "text", "surface0", "red", "green", "yellow"]


# ---- colour maths -------------------------------------------------------------
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


def best_fg(bg, candidates):
    return max(candidates, key=lambda c: contrast(bg, c))


def rgba(h, a):
    return "rgba(%d, %d, %d, %.2f)" % (rgb(h) + (a,))


# ---- inputs -------------------------------------------------------------------
def define_colors(path):
    s = open(path, encoding="utf-8").read()
    return {k: v.lower() for k, v in re.findall(r"@define-color\s+(\S+)\s+(#[0-9a-fA-F]{6})\s*;", s)}


def accent_from_palette(path):
    # palette.lua is `return { accent = "rgba(RRGGBBAA)", ... }`; the alpha is Hyprland's
    s = open(path, encoding="utf-8").read()
    m = re.search(r'^\s*accent\s*=\s*"rgba\(([0-9a-fA-F]{6})[0-9a-fA-F]{2}\)"', s, re.M)
    return "#" + m.group(1).lower() if m else None


def color_scheme(path):
    s = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
    m = re.search(r'^COLOR_SCHEME="([^"]*)"', s, re.M)
    return m.group(1) if m else "prefer-dark"


# ---- the mapping ----------------------------------------------------------------
def derive(theme, cols, accent, light):
    base, mantle, crust, text = cols["base"], cols["mantle"], cols["crust"], cols["text"]
    surface0 = cols["surface0"]
    if light:
        view = mix(base, "#ffffff", 0.45)   # paper's lighter step: the reading surface
        raised = view                      # cards/popovers/dialogs sit above the page
    else:
        view = mantle                      # the page's darker step
        raised = surface0                  # cards/popovers/dialogs lift off the page
    secondary_sidebar = mix(mantle, base, 0.5)
    hairline = rgba(text, HAIRLINE)
    shade = rgba(text, SHADE)
    fg_candidates = ["#ffffff", crust, text]

    c = {}
    c["accent_bg_color"] = accent
    c["accent_fg_color"] = best_fg(accent, fg_candidates)
    c["accent_color"] = accent
    for role, hue in (("destructive", cols["red"]), ("error", cols["red"]),
                      ("success", cols["green"]), ("warning", cols["yellow"])):
        c[role + "_bg_color"] = hue
        c[role + "_fg_color"] = best_fg(hue, fg_candidates)
        c[role + "_color"] = hue
    c["window_bg_color"] = base
    c["window_fg_color"] = text
    c["view_bg_color"] = view
    c["view_fg_color"] = text
    c["headerbar_bg_color"] = base
    c["headerbar_fg_color"] = text
    c["headerbar_border_color"] = hairline
    c["headerbar_backdrop_color"] = base
    c["headerbar_shade_color"] = hairline
    c["headerbar_darker_shade_color"] = hairline
    c["sidebar_bg_color"] = mantle
    c["sidebar_fg_color"] = text
    c["sidebar_backdrop_color"] = mantle
    c["sidebar_border_color"] = hairline
    c["sidebar_shade_color"] = shade
    c["secondary_sidebar_bg_color"] = secondary_sidebar
    c["secondary_sidebar_fg_color"] = text
    c["secondary_sidebar_backdrop_color"] = secondary_sidebar
    c["secondary_sidebar_border_color"] = hairline
    c["secondary_sidebar_shade_color"] = shade
    c["card_bg_color"] = raised
    c["card_fg_color"] = text
    c["card_shade_color"] = shade
    c["dialog_bg_color"] = raised
    c["dialog_fg_color"] = text
    c["popover_bg_color"] = raised
    c["popover_fg_color"] = text
    c["popover_shade_color"] = shade
    c["thumbnail_bg_color"] = raised
    c["thumbnail_fg_color"] = text
    c["shade_color"] = shade
    return c, hairline


def header(theme, light, kind):
    return (
        f"/* {theme} — {kind}. GENERATED by bin/gen-gtk-css.py from waybar.css +\n"
        f" * palette.lua + meta.sh ({'light' if light else 'dark'}); do not edit, regenerate.\n"
        f" * Letterpress (docs/design/README.md): one accent ink, flat page, 1 px hairlines. */\n"
    )


def render_gtk3(theme, c, light):
    out = header(theme, light, "GTK3 / adw-gtk3 named colours")
    out += ("/* Named colours only — NO selector rules: GTK3 loads this at priority 800,\n"
            " * above waybar's and nwg-drawer's own CSS (600); a `button {}` rule\n"
            " * here would restyle the bar. The chrome rules live in gtk.css (GTK4). */\n")
    for k, v in c.items():
        out += f"@define-color {k} {v};\n"
    return out


def render_gtk4(theme, c, hairline, light):
    out = header(theme, light, "GTK4 / libadwaita user stylesheet")
    out += "/* libadwaita >= 1.6 reads the variables; the @define-color aliases feed older\n"
    out += " * apps and plain-GTK4 widgets that still resolve the named colours. */\n"
    for k, v in c.items():
        out += f"@define-color {k} {v};\n"
    out += "\n:root {\n"
    for k, v in c.items():
        out += f"  --{k.replace('_', '-')}: {v};\n"
    out += f"  --border-color: {hairline};\n"
    out += "  --window-radius: 4px;   /* = Hyprland decoration.rounding */\n"
    out += "}\n"
    out += f"""
/* Letterpress chrome: square-ish (3 px), separated by hairlines, no heavy shadows.
 * Insets rather than borders so nothing grows by a pixel. */
button, entry, spinbutton, tooltip, popover > contents,
dropdown > button, menubutton > button, .card, .toast, searchbar > revealer > box {{
  border-radius: 3px;
}}
button:not(.flat):not(.suggested-action):not(.destructive-action):not(.circular) {{
  box-shadow: inset 0 0 0 1px {hairline};
}}
entry, spinbutton {{
  box-shadow: inset 0 0 0 1px {hairline};
}}
headerbar, .top-bar, toolbarview > .top-bar {{
  box-shadow: inset 0 -1px {hairline};
}}
popover > contents, tooltip {{
  box-shadow: 0 0 0 1px {hairline}, 0 2px 6px rgba(0, 0, 0, 0.18);
}}
window.csd:not(.tiled):not(.maximized):not(.fullscreen) decoration {{
  box-shadow: 0 0 0 1px {hairline}, 0 2px 8px rgba(0, 0, 0, 0.22);
}}
"""
    return out


def write(target, out):
    old = open(target, encoding="utf-8").read() if os.path.exists(target) else None
    if old != out:
        open(target, "w", encoding="utf-8").write(out)
        print("wrote", os.path.relpath(target, ROOT))


def render(theme):
    d = os.path.join(THEMES, theme)
    cols = define_colors(os.path.join(d, "waybar.css"))
    missing = [k for k in NEEDED if k not in cols]
    if missing:
        sys.exit(f"{theme}: waybar.css lacks {missing}")
    accent = accent_from_palette(os.path.join(d, "palette.lua")) or cols.get("accent")
    if not accent:
        sys.exit(f"{theme}: no accent in palette.lua or waybar.css")
    light = color_scheme(os.path.join(d, "meta.sh")) == "prefer-light"
    c, hairline = derive(theme, cols, accent, light)
    write(os.path.join(d, "gtk3.css"), render_gtk3(theme, c, light))
    write(os.path.join(d, "gtk.css"), render_gtk4(theme, c, hairline, light))


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

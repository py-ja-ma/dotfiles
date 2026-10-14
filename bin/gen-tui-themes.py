#!/usr/bin/env python3
"""usage: gen-tui-themes.py [theme ...]

Writes every theme's btop.theme and cava.theme (or the named themes') in the Letterpress style from the theme's palette. A dev-time generator; commit the output.

The two TUI monitors are the printed page again: paper (the terminal's own
background, so kitty's grain shows through), ink text, hairline boxes, and ONE
accent ink that carries every graph as a three-stop gradient from a faint tint of
itself to the full colour. Nothing is a rainbow.

    dotfiles/.config/themes/<t>/waybar.css   base/text/subtext/overlay/surface0/surface1/red
  + dotfiles/.config/themes/<t>/palette.lua  accent (the ONE accent ink)
  = dotfiles/.config/themes/<t>/btop.theme   (committed — dram-theme points color_theme at it)
  = dotfiles/.config/themes/<t>/cava.theme   (committed — dram-theme splices its [color] block)

Mapping (palette field -> btop key / cava key):
    (empty)              -> main_bg                 terminal background; btop.conf also sets
                                                    theme_background = false
    text                 -> main_fg, title          ink; box captions are bold ink
    accent               -> hi_fg, selected_fg      the rubric: hotkey letters, the cursor row
    surface0             -> selected_bg
    overlay              -> inactive_fg
    subtext              -> graph_text, proc_misc
    surface1             -> meter_bg
    mix(base,subtext,.4) -> cpu_box mem_box net_box proc_box div_line   one hairline grey
    faint -> mid -> accent  cpu_*, free_*, used_*, available_*, download_*, process_*
                            (faint = accent mixed 55 % toward the paper, mid = 25 %)
    faint -> mid -> subtext cached_*, upload_*      the muted second tone
    faint -> accent -> red  temp_*                  warm within the accent hue; red only at the end
    cava: gradient_count = 3 (faint, mid, accent), foreground = text, background = default

Run from anywhere:  python3 bin/gen-tui-themes.py [theme ...]
No arguments = every theme dir. Idempotent; prints the files it rewrote.
See docs/design/shell-and-bars/terminal.md ("TUI monitors").

  theme ...     theme dir ids under dotfiles/.config/themes (default: every theme)
  -h, --help    this text

exit: 0 ok · 1 a theme failed to render · 2 bad usage
see: docs/design/shell-and-bars/terminal.md
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THEMES = os.path.join(ROOT, "dotfiles", ".config", "themes")

NEEDED = ["base", "text", "subtext", "overlay", "surface0", "surface1", "red"]
HAIRLINE = 0.40  # the box rules: subtext at 40 % over the paper
FAINT = 0.55     # gradient start: the ink mixed 55 % toward the paper
MID = 0.25       # gradient middle: 25 % toward the paper


# ---- colour maths -------------------------------------------------------------
def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hexs(c):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(v))) for v in c)


def mix(a, b, t):  # t=0 -> a, t=1 -> b
    a, b = rgb(a), rgb(b)
    return hexs(tuple(a[i] + (b[i] - a[i]) * t for i in range(3)))


# ---- inputs -------------------------------------------------------------------
def define_colors(path):
    s = open(path, encoding="utf-8").read()
    return {k: v.lower() for k, v in re.findall(r"@define-color\s+(\S+)\s+(#[0-9a-fA-F]{6})\s*;", s)}


def accent_from_palette(path):
    # palette.lua is `return { accent = "rgba(RRGGBBAA)", ... }`; the alpha is Hyprland's
    s = open(path, encoding="utf-8").read()
    m = re.search(r'^\s*accent\s*=\s*"rgba\(([0-9a-fA-F]{6})[0-9a-fA-F]{2}\)"', s, re.M)
    return "#" + m.group(1).lower() if m else None


def theme_title(path):
    # the first line of waybar.css is `/* <Name> — waybar palette ... */`
    s = open(path, encoding="utf-8").readline()
    m = re.match(r"/\*\s*(.+?)\s+—", s)
    return m.group(1) if m else os.path.basename(os.path.dirname(path))


# ---- the mapping ----------------------------------------------------------------
def gradient(ink, paper):
    return mix(ink, paper, FAINT), mix(ink, paper, MID), ink


def derive(cols, accent):
    paper, text, subtext = cols["base"], cols["text"], cols["subtext"]
    hairline = mix(paper, subtext, HAIRLINE)
    acc = gradient(accent, paper)
    mut = gradient(subtext, paper)
    c = {
        "main_bg": "",
        "main_fg": text,
        "title": text,
        "hi_fg": accent,
        "selected_bg": cols["surface0"],
        "selected_fg": accent,
        "inactive_fg": cols["overlay"],
        "graph_text": subtext,
        "meter_bg": cols["surface1"],
        "proc_misc": subtext,
        "cpu_box": hairline,
        "mem_box": hairline,
        "net_box": hairline,
        "proc_box": hairline,
        "div_line": hairline,
    }
    for key, (start, mid, end) in (
        ("temp", (acc[0], accent, cols["red"])),
        ("cpu", acc), ("free", acc), ("cached", mut), ("available", acc), ("used", acc),
        ("download", acc), ("upload", mut), ("process", acc),
    ):
        c[key + "_start"], c[key + "_mid"], c[key + "_end"] = start, mid, end
    return c, acc


def render_btop(name, c):
    out = [f"# {name} — btop (Letterpress: paper, ink, one accent; generated by bin/gen-tui-themes.py)"]
    out += [f'theme[{k}]="{v}"' for k, v in c.items()]
    return "\n".join(out) + "\n"


def render_cava(name, cols, acc):
    out = [
        f"# {name} — cava [color] block (Letterpress; generated by bin/gen-tui-themes.py)",
        "gradient = 1",
        "gradient_count = 3",
    ]
    out += [f"gradient_color_{i} = '{v}'" for i, v in enumerate(acc, 1)]
    out += [f"foreground = '{cols['text']}'", "background = default"]
    return "\n".join(out) + "\n"


def write(target, out):
    old = open(target, encoding="utf-8").read() if os.path.exists(target) else None
    if old != out:
        open(target, "w", encoding="utf-8").write(out)
        print("wrote", os.path.relpath(target, ROOT))


def render(theme):
    d = os.path.join(THEMES, theme)
    cols = define_colors(os.path.join(d, "waybar.css"))
    missing = [k for k in NEEDED if not cols.get(k)]
    if missing:
        sys.exit(f"{theme}: waybar.css lacks {missing}")
    accent = accent_from_palette(os.path.join(d, "palette.lua")) or cols.get("accent") or cols["blue"]
    name = theme_title(os.path.join(d, "waybar.css"))
    c, acc = derive(cols, accent)
    write(os.path.join(d, "btop.theme"), render_btop(name, c))
    write(os.path.join(d, "cava.theme"), render_cava(name, cols, acc))


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

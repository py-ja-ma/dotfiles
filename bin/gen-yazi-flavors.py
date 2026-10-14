#!/usr/bin/env python3
"""usage: gen-yazi-flavors.py [theme ...]

Writes a Letterpress yazi flavor per dram theme (or per named theme) under dotfiles/.config/yazi/flavors/. A dev-time generator; commit the output.

yazi is the printed page again: paper is the terminal's own background (no
`bg` anywhere yazi lets us leave it out, so kitty's grain shows through), ink
text, hairline rules, and ONE accent ink. The cursor row is accent ink on the
`surface0` tint, not a reversed-video block; the mode word in the status bar is
a plain bold word in the accent, not a powerline pill; the file-type colours
are restrained (dirs in the accent's dim ink, executables green, symlinks
italic, media and archives in the muted inks). No Nerd-font icons: the
`[icon]` tables are emptied and the few glyphs yazi prints by itself (notify,
completion) are typographic marks, never private-use codepoints.

    dotfiles/.config/themes/<t>/waybar.css   base/text/subtext/overlay/surface0/surface1
                                             red/green/yellow/blue/teal/peach/mauve
  + dotfiles/.config/themes/<t>/palette.lua  accent, accent_dim (the ONE accent ink)
  = dotfiles/.config/yazi/flavors/letterpress-<t>.yazi/
        flavor.toml   the theme (every key is one yazi 26.9.1 ships in its preset)
        tmtheme.xml   a minimal TextMate theme for the code preview
        README.md, LICENSE (MIT, ours)

Mapping (palette field -> flavor key):
    (none)                     [app] overall, every bg not listed   the terminal's paper
    accent                     mgr.cwd, find_keyword, indicator.current/parent fg,
                               mode.normal_main, tabs.active, marker_selected,
                               which.cand, help.chord, *.title, pick/tasks/cmp/help.hovered
    accent_dim (lifted to      filetype `*/` (directories, bold), marker_marked
      >= 3:1 against the paper)
    surface0                   indicator.* bg (the cursor row), count_* bg, hovered rows
    surface1                   input.selected bg, progress bg
    text                       which.desc, help.action, progress_label
    subtext                    symlink_target, find_position, tabs.inactive, mode.*_alt,
                               perm_read/perm_write, comments (tmtheme, italic),
                               images (plain) and audio/video (italic)
    overlay                    which.rest, perm_sep, archives, vfs ghosts
    mix(base, subtext, .40)    every border (one hairline grey, like btop's boxes)
    yellow                     marker_copied, count_copied, mode.select_main, strings
    red                        marker_cut, count_cut, mode.unset_main, orphans, errors
    green                      executables, perm_exec, notify info, diff inserted
    blue / teal / peach / mauve  tmtheme only: types, attributes, numbers, tags

Run from anywhere:  python3 bin/gen-yazi-flavors.py [theme ...]
No arguments = every theme dir. Idempotent; prints the files it rewrote.
See dotfiles/.config/yazi/README.md ("The flavors").

  theme ...     theme dir ids under dotfiles/.config/themes (default: every theme)
  -h, --help    this text

exit: 0 ok · 1 a theme failed to render · 2 bad usage
see: dotfiles/.config/yazi/README.md
"""
import os
import re
import sys
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THEMES = os.path.join(ROOT, "dotfiles", ".config", "themes")
FLAVORS = os.path.join(ROOT, "dotfiles", ".config", "yazi", "flavors")

NEEDED = ["base", "text", "subtext", "overlay", "surface0", "surface1",
          "red", "green", "yellow", "blue", "teal", "peach", "mauve"]
HAIRLINE = 0.40      # borders: subtext at 40 % over the paper (same rule as btop)
DIR_CONTRAST = 3.0   # directories: accent_dim, lifted toward accent until readable
UUID_NS = uuid.UUID("5a1b1d6e-8c3f-4b0e-9d2a-7f6e5c4b3a21")  # stable per-theme uuids


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


def lift(ink, toward, paper, want):
    """mix `ink` toward `toward` in 5 % steps until it reads at `want`:1 on the paper"""
    for i in range(21):
        c = mix(ink, toward, i / 20)
        if contrast(c, paper) >= want:
            return c
    return toward


# ---- inputs -------------------------------------------------------------------
def define_colors(path):
    s = open(path, encoding="utf-8").read()
    return {k: v.lower() for k, v in re.findall(r"@define-color\s+(\S+)\s+(#[0-9a-fA-F]{6})\s*;", s)}


def palette_field(path, field):
    # palette.lua is `return { accent = "rgba(RRGGBBAA)", ... }`; the alpha is Hyprland's
    s = open(path, encoding="utf-8").read()
    m = re.search(r'^\s*%s\s*=\s*"rgba\(([0-9a-fA-F]{6})[0-9a-fA-F]{2}\)"' % field, s, re.M)
    return "#" + m.group(1).lower() if m else None


def theme_title(path):
    # the first line of waybar.css is `/* <Name> — waybar palette ... */`
    s = open(path, encoding="utf-8").readline()
    m = re.match(r"/\*\s*(.+?)\s+—", s)
    return m.group(1) if m else os.path.basename(os.path.dirname(path))


# ---- the mapping ----------------------------------------------------------------
def derive(cols, accent, accent_dim):
    paper, text, subtext, overlay = cols["base"], cols["text"], cols["subtext"], cols["overlay"]
    c = dict(cols)
    c["accent"] = accent
    c["accent_dim"] = accent_dim
    c["hairline"] = mix(paper, subtext, HAIRLINE)
    c["dir"] = lift(accent_dim, accent, paper, DIR_CONTRAST)
    c["is_dark"] = luminance(paper) < 0.5
    return c


def style(**kw):
    """{ fg = "#..", bold = true } in yazi's own inline-table spelling"""
    parts = []
    for k, v in kw.items():
        if v is None:
            continue
        parts.append(f'{k} = "{v}"' if isinstance(v, str) else f"{k} = {str(v).lower()}")
    return "{ " + ", ".join(parts) + " }" if parts else "{}"


def render_flavor(theme, name, c):
    A, D, S0, S1 = c["accent"], c["dir"], c["surface0"], c["surface1"]
    T, ST, OV, H = c["text"], c["subtext"], c["overlay"], c["hairline"]
    R, G, Y = c["red"], c["green"], c["yellow"]
    L = [
        f"# {name} — yazi flavor (Letterpress: paper, ink, one accent; generated by bin/gen-yazi-flavors.py)",
        "# Every key is one yazi 26.9.1 ships in yazi-config/preset/theme-dark.toml. No bg = the terminal's paper.",
        "",
        "[mgr]",
        f"cwd = {style(fg=A, bold=True)}",
        "",
        "# Find",
        f"find_keyword  = {style(fg=A, bold=True, underline=True)}",
        f"find_position = {style(fg=ST, bg='reset', italic=True)}",
        "",
        "# Symlink",
        f"symlink_target = {style(fg=ST, italic=True)}",
        "",
        "# Marker — a 1-cell rule in the margin: selected = accent, copied = yellow, cut = red",
        f"marker_copied   = {style(fg=Y, bg=Y)}",
        f"marker_cut      = {style(fg=R, bg=R)}",
        f"marker_marked   = {style(fg=D, bg=D)}",
        f"marker_selected = {style(fg=A, bg=A)}",
        'marker_symbol   = "│"',
        "",
        "# Count — a coloured figure on the surface tint, not a filled badge",
        f"count_copied   = {style(fg=Y, bg=S0, bold=True)}",
        f"count_cut      = {style(fg=R, bg=S0, bold=True)}",
        f"count_selected = {style(fg=A, bg=S0, bold=True)}",
        "",
        "# Border — one hairline grey",
        'border_symbol = "│"',
        f"border_style  = {style(fg=H)}",
        "",
        "[tabs]",
        f"active   = {style(fg=A, bold=True)}",
        f"inactive = {style(fg=ST)}",
        'sep_inner = { open = "", close = "" }',
        'sep_outer = { open = "", close = "" }',
        "",
        "# Mode — a plain bold word, no powerline pill",
        "[mode]",
        f"normal_main = {style(fg=A, bold=True)}",
        f"normal_alt  = {style(fg=ST)}",
        f"select_main = {style(fg=Y, bold=True)}",
        f"select_alt  = {style(fg=ST)}",
        f"unset_main  = {style(fg=R, bold=True)}",
        f"unset_alt   = {style(fg=ST)}",
        "",
        "# The cursor row — accent ink on the surface tint, never reversed video",
        "[indicator]",
        f"parent  = {style(fg=D, bg=S0)}",
        f"current = {style(fg=A, bg=S0, bold=True)}",
        f"preview = {style(bg=S0)}",
        'padding = { open = "", close = "" }',
        "",
        "[status]",
        "overall   = {}",
        'sep_left  = { open = "", close = "" }',
        'sep_right = { open = "", close = "" }',
        "",
        "# Permissions",
        f"perm_sep   = {style(fg=OV)}",
        f"perm_type  = {style(fg=A)}",
        f"perm_read  = {style(fg=ST)}",
        f"perm_write = {style(fg=ST)}",
        f"perm_exec  = {style(fg=G)}",
        "",
        "# Progress",
        f"progress_label  = {style(fg=T, bold=True)}",
        f"progress_normal = {style(fg=A, bg=S1)}",
        f"progress_error  = {style(fg=R, bg=S1)}",
        "",
        "[which]",
        f"border          = {style(fg=H)}",
        "cols            = 3",
        "mask            = {}",
        f"cand            = {style(fg=A)}",
        f"rest            = {style(fg=OV)}",
        f"desc            = {style(fg=T)}",
        'separator       = "  "',
        f"separator_style = {style(fg=OV)}",
        "",
        "[confirm]",
        f"border     = {style(fg=H)}",
        f"title      = {style(fg=A, bold=True)}",
        "body       = {}",
        "list       = {}",
        f"btn_yes    = {style(fg=A, bold=True)}",
        f"btn_no     = {style(fg=ST)}",
        'btn_labels = [ "  [Y]es  ", "  (N)o  " ]',
        "",
        "[spot]",
        f"border   = {style(fg=H)}",
        f"title    = {style(fg=A, bold=True)}",
        f"tbl_col  = {style(fg=A)}",
        f"tbl_cell = {style(fg=T, bg=S0)}",
        "",
        "[notify]",
        f"title_info  = {style(fg=G)}",
        f"title_warn  = {style(fg=Y)}",
        f"title_error = {style(fg=R)}",
        'icon_info  = "·"',
        'icon_warn  = "!"',
        'icon_error = "×"',
        "",
        "[pick]",
        f"border   = {style(fg=H)}",
        f"active   = {style(fg=A, bold=True)}",
        "inactive = {}",
        "",
        "[input]",
        f"border   = {style(fg=H)}",
        f"title    = {style(fg=A, bold=True)}",
        "value    = {}",
        f"selected = {style(bg=S1)}",
        "",
        "[cmp]",
        f"border   = {style(fg=H)}",
        f"active   = {style(fg=A, bg=S0)}",
        "inactive = {}",
        'icon_file    = "·"',
        'icon_folder  = "/"',
        'icon_command = ":"',
        "",
        "[tasks]",
        f"border  = {style(fg=H)}",
        f"title   = {style(fg=A, bold=True)}",
        f"hovered = {style(fg=A, bg=S0)}",
        "",
        "[help]",
        f"border  = {style(fg=H)}",
        f"chord   = {style(fg=A)}",
        f"action  = {style(fg=T)}",
        f"hovered = {style(fg=A, bg=S0, bold=True)}",
        "",
        "# File-specific styles — first match wins",
        "[filetype]",
        "rules = [",
        "\t# Broken things",
        f"\t{{ url = \"*\", is = \"orphan\", fg = \"{R}\", italic = true }},",
        f"\t{{ url = \"*\", is = \"dummy\", fg = \"{R}\", italic = true }},",
        f"\t{{ url = \"*/\", is = \"dummy\", fg = \"{R}\", italic = true }},",
        "\t# Symlinks are italic, in whatever colour the ink is",
        "\t{ url = \"*\", is = \"link\", italic = true },",
        "\t{ url = \"*/\", is = \"link\", fg = \"%s\", italic = true }," % D,
        "\t# Executables",
        f"\t{{ url = \"*\", is = \"exec\", fg = \"{G}\" }},",
        "\t# Image",
        f"\t{{ mime = \"**/image/*\", fg = \"{ST}\" }},",
        "\t# Media",
        f"\t{{ mime = \"**/{{audio,video}}/*\", fg = \"{ST}\", italic = true }},",
        "\t# Archive",
        f"\t{{ mime = \"**/application/{{zip,rar,7z*,tar,gzip,xz,zstd,bzip*,lzma,compress,archive,cpio,arj,xar,ms-cab*}}\", fg = \"{OV}\" }},",
        "\t# Virtual file system",
        f"\t{{ mime = \"vfs/{{absent,stale}}\", fg = \"{OV}\" }},",
        "\t# Directories",
        f"\t{{ url = \"*/\", fg = \"{D}\", bold = true }},",
        "]",
        "",
        "# No icons: Letterpress sets its chrome in words, not Nerd-font glyphs",
        "[icon]",
        "globs = []",
        "dirs  = []",
        "files = []",
        "exts  = []",
        "conds = []",
    ]
    return "\n".join(L) + "\n"


# ---- tmTheme ---------------------------------------------------------------------
def x(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def tm_rule(name, scope, **settings):
    out = ["      <dict>",
           f"        <key>name</key>\n        <string>{x(name)}</string>",
           f"        <key>scope</key>\n        <string>{x(scope)}</string>",
           "        <key>settings</key>",
           "        <dict>"]
    for k, v in settings.items():
        if v:
            out.append(f"          <key>{k}</key>\n          <string>{x(v)}</string>")
    out += ["        </dict>", "      </dict>"]
    return "\n".join(out)


def render_tmtheme(theme, name, c):
    A, T, ST, OV = c["accent"], c["text"], c["subtext"], c["overlay"]
    R, G, Y, B = c["red"], c["green"], c["yellow"], c["blue"]
    TE, P, M = c["teal"], c["peach"], c["mauve"]
    uid = str(uuid.uuid5(UUID_NS, theme))
    kind = "dark" if c["is_dark"] else "light"
    rules = [
        tm_rule("Comments", "comment, punctuation.definition.comment", foreground=ST, fontStyle="italic"),
        tm_rule("Strings", "string, punctuation.definition.string", foreground=Y),
        tm_rule("Escapes", "constant.character.escape", foreground=P),
        tm_rule("Numbers and constants", "constant.numeric, constant.language, constant.character, constant.other", foreground=P),
        tm_rule("Keywords", "keyword, keyword.control, keyword.operator.logical, keyword.operator.word, storage, storage.type, storage.modifier", foreground=A),
        tm_rule("Operators and punctuation", "keyword.operator, punctuation, punctuation.separator, punctuation.terminator, meta.brace", foreground=ST),
        tm_rule("Functions", "entity.name.function, support.function, meta.function-call", foreground=T, fontStyle="bold"),
        tm_rule("Types and classes", "entity.name.type, entity.name.class, entity.name.struct, entity.name.enum, entity.name.namespace, support.type, support.class, storage.type.primitive", foreground=B),
        tm_rule("Variables", "variable, variable.other, variable.other.readwrite, support.variable", foreground=T),
        tm_rule("Parameters", "variable.parameter", foreground=T, fontStyle="italic"),
        tm_rule("Properties and members", "variable.other.member, variable.other.property, variable.other.object.property, meta.property-name, support.type.property-name, entity.other.attribute-name.id", foreground=TE),
        tm_rule("Tags", "entity.name.tag, punctuation.definition.tag", foreground=A),
        tm_rule("Attributes", "entity.other.attribute-name, meta.attribute", foreground=TE),
        tm_rule("Modules and imports", "entity.name.module, entity.name.import, support.module", foreground=M),
        tm_rule("Regular expressions", "string.regexp", foreground=M),
        tm_rule("Annotations and decorators", "meta.annotation, entity.name.decorator, punctuation.definition.annotation, meta.decorator", foreground=M, fontStyle="italic"),
        tm_rule("Preprocessor", "meta.preprocessor, keyword.control.import, keyword.control.directive", foreground=A),
        tm_rule("Invalid", "invalid, invalid.illegal", foreground=R, fontStyle="underline"),
        tm_rule("Deprecated", "invalid.deprecated", foreground=OV, fontStyle="italic"),
        tm_rule("Markup headings", "markup.heading, markup.heading entity.name, punctuation.definition.heading", foreground=A, fontStyle="bold"),
        tm_rule("Markup emphasis", "markup.italic", fontStyle="italic"),
        tm_rule("Markup strong", "markup.bold", fontStyle="bold"),
        tm_rule("Markup underline and links", "markup.underline, markup.underline.link, string.other.link", foreground=TE, fontStyle="underline"),
        tm_rule("Markup raw and code", "markup.raw, markup.raw.inline, markup.raw.block", foreground=ST),
        tm_rule("Markup lists and quotes", "markup.list, punctuation.definition.list_item, markup.quote", foreground=ST),
        tm_rule("Diff inserted", "markup.inserted, meta.diff.header.to-file", foreground=G),
        tm_rule("Diff deleted", "markup.deleted, meta.diff.header.from-file", foreground=R),
        tm_rule("Diff changed", "markup.changed", foreground=Y),
        tm_rule("Diff ranges and headers", "meta.diff.range, meta.diff.header, meta.separator", foreground=ST, fontStyle="italic"),
        tm_rule("JSON and YAML keys", "meta.mapping.key string, source.json meta.structure.dictionary.json support.type.property-name.json, entity.name.tag.yaml", foreground=TE),
        tm_rule("TOML and INI keys", "keyword.key.toml, entity.name.section, entity.name.tag.toml, keyword.other.definition.ini", foreground=TE),
        tm_rule("Shell builtins and variables", "support.function.builtin.shell, variable.other.bracket.shell, variable.other.normal.shell, punctuation.definition.variable.shell", foreground=TE),
    ]
    head = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- {x(name)} — Letterpress tmTheme for yazi's code preview (generated by bin/gen-yazi-flavors.py).
     No background: the paper is the terminal's own. -->
<plist version="1.0">
  <dict>
    <key>name</key>
    <string>Letterpress {x(name)}</string>
    <key>semanticClass</key>
    <string>theme.{kind}.letterpress-{theme}</string>
    <key>uuid</key>
    <string>{uid}</string>
    <key>author</key>
    <string>Patrick Jordan</string>
    <key>colorSpaceName</key>
    <string>sRGB</string>
    <key>settings</key>
    <array>
      <dict>
        <key>settings</key>
        <dict>
          <key>foreground</key>
          <string>{T}</string>
          <key>caret</key>
          <string>{A}</string>
          <key>invisibles</key>
          <string>{OV}</string>
          <key>lineHighlight</key>
          <string>{c['surface0']}</string>
          <key>selection</key>
          <string>{c['surface1']}</string>
          <key>gutterForeground</key>
          <string>{OV}</string>
        </dict>
      </dict>
"""
    tail = """    </array>
  </dict>
</plist>
"""
    return head + "\n".join(rules) + "\n" + tail


# ---- the prose ---------------------------------------------------------------------
LICENSE = """MIT License

Copyright (c) 2026 Patrick Jordan

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""


def render_readme(theme, name, c):
    kind = "dark" if c["is_dark"] else "light"
    return f"""# letterpress-{theme}.yazi

The {name} dram theme as a [yazi](https://yazi-rs.github.io) flavor, set the
Letterpress way: the paper is the terminal's own background, the text is ink,
the rules are hairlines, and one accent ink ({c['accent']}) carries the cursor
row, the working directory, the mode word and the selection mark.

Generated by `bin/gen-yazi-flavors.py` in the dotfiles repo from
`themes/{theme}/waybar.css` + `palette.lua` — do not edit by hand. A {kind}
flavor; `dram-theme` points `~/.config/yazi/theme.toml` at it:

```toml
[flavor]
dark  = "letterpress-{theme}"
light = "letterpress-{theme}"
```

`tmtheme.xml` is a minimal TextMate theme for the code preview (comments
subtext italic, strings yellow, keywords accent). MIT, see `LICENSE`.
"""


# ---- driver ----------------------------------------------------------------------
def write(target, out):
    os.makedirs(os.path.dirname(target), exist_ok=True)
    old = open(target, encoding="utf-8").read() if os.path.exists(target) else None
    if old != out:
        open(target, "w", encoding="utf-8").write(out)
        print("wrote", os.path.relpath(target, ROOT))


def check_no_pua(text, where):
    for ch in text:
        if 0xE000 <= ord(ch) <= 0xF8FF or 0xF0000 <= ord(ch) <= 0x10FFFD:
            sys.exit(f"{where}: private-use codepoint U+{ord(ch):04X} (Nerd glyph) in a Letterpress flavor")


def render(theme):
    d = os.path.join(THEMES, theme)
    cols = define_colors(os.path.join(d, "waybar.css"))
    missing = [k for k in NEEDED if not cols.get(k)]
    if missing:
        sys.exit(f"{theme}: waybar.css lacks {missing}")
    pal = os.path.join(d, "palette.lua")
    accent = palette_field(pal, "accent") or cols.get("accent") or cols["blue"]
    accent_dim = palette_field(pal, "accent_dim") or mix(accent, cols["base"], 0.3)
    name = theme_title(os.path.join(d, "waybar.css"))
    c = derive(cols, accent, accent_dim)
    out = os.path.join(FLAVORS, f"letterpress-{theme}.yazi")
    flavor = render_flavor(theme, name, c)
    check_no_pua(flavor, f"{theme}/flavor.toml")
    write(os.path.join(out, "flavor.toml"), flavor)
    write(os.path.join(out, "tmtheme.xml"), render_tmtheme(theme, name, c))
    write(os.path.join(out, "README.md"), render_readme(theme, name, c))
    write(os.path.join(out, "LICENSE"), LICENSE)


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

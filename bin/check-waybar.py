#!/usr/bin/env python3
"""usage: check-waybar.py

The waybar masthead invariants, nix-free; run by bin/check.sh §10 (`dram check`). Reads dotfiles/.config/waybar/ and the waybar-*.sh scripts and prints every rule that fails.

Run by bin/check.sh §10 (`dram check`); exit 1 on any failure.

The rules (dotfiles/.config/waybar/README.md → Captions and spacing). The bar
is words, not icons: a Nerd glyph that slips in brings back the font-metric
gaps this design removed, and a caption outside the house span loses its small
caps and lining figures.

  1. config.jsonc + modules.jsonc parse once // comment lines are stripped.
  2. config.jsonc still contains the literal `, "battery"` that
     modules/laptop.nix strips with replaceStrings.
  3. ZERO private-use codepoints (U+E000–F8FF, U+F0000–FFFFD) in
     modules.jsonc, config.jsonc and every waybar-*.sh / waybar-*.py.
  4. every font_features attribute is exactly `smcp, lnum, tnum`, and the
     caption span is spelled exactly <span font_features='smcp, lnum, tnum'>.
  5. every custom/date* exec runs waybar-date.sh, which consults `locale -a`
     for ru_RU before it asks for a Russian date.
  6. every hyprland/window* has separate-outputs: true and a max-length
     (≤ 48; the compact one ≤ 32); there is no custom/window* any more.
  7. every hyprland/workspaces* has active-only: true and a format that
     starts with "№ " (U+2116 + space).
  8. style.css defines @define-color rule, resets #workspaces button, gives
     window#waybar its border-bottom, and names no hex colour outside comments.
  9. both bars set "spacing": 0 (style.css owns every gap).
 10. the waybar python scripts (if any) byte-compile.

  -h, --help    this text

exit: 0 ok · 1 a rule failed · 2 bad usage
see: dotfiles/.config/waybar/README.md
"""
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WB = os.path.join(REPO, "dotfiles/.config/waybar")
BIN = os.path.join(REPO, "dotfiles/.local/bin")
CAPTION_SPAN = "<span font_features='smcp, lnum, tnum'>"
FEATURES = "smcp, lnum, tnum"
FAILS = []


def fail(msg):
    FAILS.append(msg)


def is_pua(ch):
    o = ord(ch)
    return 0xE000 <= o <= 0xF8FF or 0xF0000 <= o <= 0xFFFFD


def strip_comments(s):
    return re.sub(r"^\s*//.*$", "", s, flags=re.M)


def load_jsonc(path):
    s = open(path, encoding="utf-8").read()
    try:
        return json.loads(strip_comments(s))
    except ValueError as e:
        fail("%s: not JSON once // lines are stripped: %s" % (os.path.relpath(path, REPO), e))
        return None


def walk_strings(obj, path=()):
    if isinstance(obj, dict):
        for k, v in obj.items():
            yield from walk_strings(v, path + (k,))
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            yield from walk_strings(v, path + (str(i),))
    elif isinstance(obj, str):
        yield path, obj


def check_no_pua():
    """Rule 3: raw file scan (comments included — a stray glyph anywhere is a tell)."""
    files = [os.path.join(WB, "config.jsonc"), os.path.join(WB, "modules.jsonc")]
    for fn in sorted(os.listdir(BIN)):
        if fn.startswith("waybar-") and (fn.endswith(".sh") or fn.endswith(".py")):
            files.append(os.path.join(BIN, fn))
    for p in files:
        for ln, line in enumerate(open(p, encoding="utf-8"), 1):
            glyphs = ["U+%04X" % ord(c) for c in line if is_pua(c)]
            if glyphs:
                fail("%s:%d: private-use codepoint %s — the masthead has no icons"
                     % (os.path.relpath(p, REPO), ln, ", ".join(glyphs)))


def check_spans(mods):
    """Rule 4 over every string in modules.jsonc."""
    for path, s in walk_strings(mods):
        where = "modules.jsonc %s" % "/".join(path)
        for m in re.finditer(r"<span\b([^>]*)>", s):
            attrs = m.group(1)
            fm = re.search(r"font_features\s*=\s*(['\"])(.*?)\1", attrs)
            if fm is None:
                continue
            if fm.group(2) != FEATURES:
                fail("%s: font_features must be exactly %r, got %r" % (where, FEATURES, fm.group(2)))
            if m.group(0) != CAPTION_SPAN:
                fail("%s: the caption span must be spelled exactly %s, got %s" % (where, CAPTION_SPAN, m.group(0)))


def check_modules(mods):
    # rule 5
    dates = [k for k in mods if k == "custom/date" or k.startswith("custom/date#")]
    if not dates:
        fail("modules.jsonc: no custom/date module")
    for k in dates:
        ex = mods[k].get("exec", "")
        if "waybar-date.sh" not in ex:
            fail("modules.jsonc %s: exec must run waybar-date.sh, got %r" % (k, ex))
    p = os.path.join(BIN, "waybar-date.sh")
    if not os.path.isfile(p):
        fail("dotfiles/.local/bin/waybar-date.sh is missing")
    else:
        src = open(p, encoding="utf-8").read()
        if "locale -a" not in src or "ru_RU" not in src:
            fail("waybar-date.sh must check `locale -a` for ru_RU before asking for a Russian date")
    # rule 6
    for k in mods:
        if k == "custom/window" or k.startswith("custom/window#") or k == "custom/window-icon":
            fail("modules.jsonc %s: the title is hyprland/window now (no custom/window*)" % k)
    wins = [k for k in mods if k == "hyprland/window" or k.startswith("hyprland/window#")]
    if not wins:
        fail("modules.jsonc: no hyprland/window module")
    for k in wins:
        m = mods[k]
        if m.get("separate-outputs") is not True:
            fail("modules.jsonc %s: needs \"separate-outputs\": true (each bar shows its own monitor's window)" % k)
        ml = m.get("max-length")
        limit = 32 if "compact" in k else 48
        if not isinstance(ml, int) or ml < 1 or ml > limit:
            fail("modules.jsonc %s: needs an integer \"max-length\" ≤ %d (clock must not shift), got %r" % (k, limit, ml))
    # rule 7
    wss = [k for k in mods if k == "hyprland/workspaces" or k.startswith("hyprland/workspaces#")]
    if not wss:
        fail("modules.jsonc: no hyprland/workspaces module")
    for k in wss:
        m = mods[k]
        if m.get("active-only") is not True:
            fail("modules.jsonc %s: needs \"active-only\": true" % k)
        if not str(m.get("format", "")).startswith("№ "):
            fail("modules.jsonc %s: format must start with \"№ \" (U+2116 + space), got %r" % (k, m.get("format")))


def check_config(bars):
    raw = strip_comments(open(os.path.join(WB, "config.jsonc"), encoding="utf-8").read())
    if raw.count('"battery"') == 0 or raw.count('"battery"') != raw.count(', "battery"'):
        fail("config.jsonc: every \"battery\" must be spelled `, \"battery\"` — modules/laptop.nix strips exactly that literal")
    if not isinstance(bars, list) or not bars:
        fail("config.jsonc: expected a list of bars")
        return
    for bar in bars:
        name = bar.get("name", "?")
        if bar.get("spacing", None) != 0:
            fail("config.jsonc bar %s: \"spacing\" must be 0 — style.css owns every gap" % name)


def check_css():
    css = open(os.path.join(WB, "style.css"), encoding="utf-8").read()
    if not re.search(r"@define-color\s+rule\b", css):
        fail("style.css: no `@define-color rule` (the hairline ink)")
    m = re.search(r"#workspaces\s+button\s*\{([^}]*)\}", css)
    if not m:
        fail("style.css: no `#workspaces button` reset rule")
    else:
        body = m.group(1)
        for prop in ("background", "border", "box-shadow", "min-width", "padding"):
            if not re.search(r"\b%s\b" % prop, body):
                fail("style.css #workspaces button: the reset must set %s" % prop)
    m = re.search(r"window#waybar\s*\{([^}]*)\}", css)
    if not m or "border-bottom" not in m.group(1):
        fail("style.css: `window#waybar { … border-bottom … }` (the masthead rule) is missing")
    code = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
    for ln, line in enumerate(code.splitlines(), 1):
        for hx in re.finditer(r"#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})\b", line):
            # a selector like #cpu or #battery is not a hex colour; a hex colour follows ':' or a space in a declaration
            before = line[: hx.start()]
            if ":" in before and "{" not in line[hx.start():]:
                fail("style.css:%d: hex colour %s — every colour is a theme @name" % (ln, hx.group(0)))


def check_python():
    for fn in sorted(os.listdir(BIN)):
        if fn.startswith("waybar-") and fn.endswith(".py"):
            p = os.path.join(BIN, fn)
            try:
                compile(open(p, encoding="utf-8").read(), p, "exec")
            except SyntaxError as e:
                fail("%s does not compile: %s" % (fn, e))


def _parse_args():
    """argparse over the module docstring: usage line, description, hidden flags."""
    import argparse
    doc = (__doc__ or "").strip().splitlines()
    ap = argparse.ArgumentParser(
        prog=doc[0].split()[1], usage=doc[0][len("usage: "):],
        description="\n".join(doc[1:]).strip(), add_help=False,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-h", "--help", action="help", help=argparse.SUPPRESS)
    return ap.parse_args()


def main():
    mods = load_jsonc(os.path.join(WB, "modules.jsonc"))
    bars = load_jsonc(os.path.join(WB, "config.jsonc"))
    check_no_pua()
    if mods is not None:
        check_spans(mods)
        check_modules(mods)
    if bars is not None:
        check_config(bars)
    check_css()
    check_python()
    if FAILS:
        for f in FAILS:
            print("  " + f)
        return 1
    spans = sum(s.count(CAPTION_SPAN) for _, s in walk_strings(mods or {}))
    print("  no icons (0 private-use codepoints), %d caption spans, hyprland/window + workspaces + ru_RU date wired, spacing is CSS" % spans)
    return 0


if __name__ == "__main__":
    _parse_args()
    sys.exit(main())

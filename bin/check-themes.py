#!/usr/bin/env python3
"""usage: check-themes.py

The theme-schema invariants, nix-free; run by bin/check.sh §14 (`dram check`).
Reads every dotfiles/.config/themes/<id>/ and prints every rule that fails.

The apps assume every theme dir has the same shape
(dotfiles/.config/themes/README.md → "What each theme file controls"; handbook 6
→ "Adding a theme"), and dram-theme / waybar / the picker read meta.sh by name.
Nothing else enforces that, so this does:

  1. every theme has the same file set as every other.
  2. the hand-written palette files define the same key set in every theme:
     @define-color names in waybar.css, swaync.css, swayosd.css;
     $vars in hyprlock.conf; keys in palette.lua; colour keys in kitty.conf.
  3. meta.sh sources under bash and sets MENU_NAME, VSCODIUM_THEME, YAZI_FLAVOR;
     MENU_NAME is unique (case-insensitive) and is no other theme's dir id.
  4. VSCODIUM_THEME == "Letterpress — <MENU_NAME>" (gen-vscode-themes.py's label).
  5. YAZI_FLAVOR == "letterpress-<id>" and
     dotfiles/.config/yazi/flavors/<YAZI_FLAVOR>.yazi/ exists.
  6. the accent is one hex across the hand-written slots: waybar @accent,
     swaync @accent, swayosd @osd-progress, hyprlock $accent,
     palette.lua accent, kitty cursor_trail_color — except the documented
     EXCEPTIONS below.

Contrast is not measured yet: I have not decided about solarized-paper's
accent (2026-10-07).

  -h, --help    this text

exit: 0 ok · 1 a rule failed · 2 bad usage
see: dotfiles/.config/themes/README.md
"""
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THEMES = os.path.join(REPO, "dotfiles/.config/themes")
FLAVORS = os.path.join(REPO, "dotfiles/.config/yazi/flavors")
META_KEYS = ("MENU_NAME", "VSCODIUM_THEME", "YAZI_FLAVOR")
CSS_FILES = ("waybar.css", "swaync.css", "swayosd.css")
# (theme id, slot) -> why this slot may differ from waybar @accent
EXCEPTIONS = {
    ("solarized-paper", "swayosd @osd-progress"):
        "#826200 (the theme's @yellow) instead of #b58900: darkened so the OSD bar reads on the paper; "
        "lifting the whole accent is a design decision, not a fix (2026-10-07)",
}
FAILS = []


def fail(msg):
    FAILS.append(msg)


def read(theme, name):
    with open(os.path.join(THEMES, theme, name), encoding="utf-8") as f:
        return f.read()


def define_colors(text):
    """@define-color NAME VALUE; -> {NAME: VALUE}"""
    return {k: v.strip() for k, v in re.findall(r"@define-color\s+(\S+)\s+([^;]+);", text)}


def hyprlock_vars(text):
    return {k: v.strip() for k, v in re.findall(r"^\$(\w+)\s*=\s*(.+?)\s*$", text, re.M)}


def palette_lua(text):
    return {k: v.rstrip(",").strip() for k, v in re.findall(r"^\s*(\w+)\s*=\s*(.+?),?\s*(?:--.*)?$", text, re.M)}


def kitty_colors(text):
    return dict(re.findall(r"^(\w+)\s+(#[0-9a-fA-F]{6})\s*$", text, re.M))


def source_meta(theme):
    """Source meta.sh in a bash subshell (it is `.`-sourced by dram-theme the same way)."""
    path = os.path.join(THEMES, theme, "meta.sh")
    script = ('set -e; . "$1"; for k in ' + " ".join(META_KEYS) +
              '; do printf "%s=%s\\0" "$k" "${!k-__UNSET__}"; done')
    out = subprocess.run(["bash", "-c", script, "_", path], capture_output=True, text=True)
    if out.returncode != 0:
        fail("%s/meta.sh does not source under bash: %s" % (theme, out.stderr.strip()))
        return None
    d = dict(kv.split("=", 1) for kv in out.stdout.split("\0") if kv)
    for k in META_KEYS:
        if d.get(k, "__UNSET__") == "__UNSET__":
            fail("%s/meta.sh: %s is not set" % (theme, k))
    return d


def rgba_hex(v):
    """hyprlock `rgba(r, g, b, a)` -> #rrggbb (lower-case), else the value as is."""
    m = re.match(r"rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,", v)
    return "#%02x%02x%02x" % tuple(int(m.group(i)) for i in (1, 2, 3)) if m else v.lower()


def lua_hex(v):
    """palette.lua `"rgba(rrggbbaa)"` -> #rrggbb, else the value as is."""
    m = re.match(r'"rgba\(([0-9a-fA-F]{6})[0-9a-fA-F]{2}\)"', v)
    return "#" + m.group(1).lower() if m else v.lower()


def main():
    themes = sorted(t for t in os.listdir(THEMES)
                    if os.path.isdir(os.path.join(THEMES, t)) and t != "current")
    if len(themes) < 2:
        fail("fewer than two theme dirs under dotfiles/.config/themes")
        return
    # 1. file set
    filesets = {t: sorted(os.listdir(os.path.join(THEMES, t))) for t in themes}
    ref_t, ref = themes[0], filesets[themes[0]]
    for t in themes[1:]:
        if filesets[t] != ref:
            fail("%s: file set differs from %s: extra %s, missing %s" % (
                t, ref_t, sorted(set(filesets[t]) - set(ref)), sorted(set(ref) - set(filesets[t]))))
    # 2. key sets per hand-written file (+ collect the accent slots for 6)
    keysets = {}   # file -> theme -> frozenset(keys)
    accents = {}   # theme -> [(slot, value)]
    for t in themes:
        acc = []
        for f in CSS_FILES:
            if f not in filesets[t]:
                continue
            dc = define_colors(read(t, f))
            keysets.setdefault(f, {})[t] = frozenset(dc)
            app = f[:-4]
            if f == "swayosd.css":
                acc.append(("swayosd @osd-progress", dc.get("osd-progress", "").lower()))
            else:
                acc.append(("%s @accent" % app, dc.get("accent", "").lower()))
        if "hyprlock.conf" in filesets[t]:
            hv = hyprlock_vars(read(t, "hyprlock.conf"))
            keysets.setdefault("hyprlock.conf", {})[t] = frozenset(hv)
            acc.append(("hyprlock $accent", rgba_hex(hv.get("accent", ""))))
        if "palette.lua" in filesets[t]:
            pl = palette_lua(read(t, "palette.lua"))
            keysets.setdefault("palette.lua", {})[t] = frozenset(pl)
            acc.append(("palette.lua accent", lua_hex(pl.get("accent", ""))))
        if "kitty.conf" in filesets[t]:
            kc = kitty_colors(read(t, "kitty.conf"))
            keysets.setdefault("kitty.conf", {})[t] = frozenset(kc)
            acc.append(("kitty cursor_trail_color", kc.get("cursor_trail_color", "").lower()))
        accents[t] = acc
    for f, per in keysets.items():
        allk = frozenset().union(*per.values())
        for t in themes:
            if t not in per:
                continue
            missing = sorted(allk - per[t])
            if missing:
                fail("%s/%s: missing keys other themes define: %s" % (t, f, " ".join(missing)))
    # 3-5. meta.sh
    names = {}
    for t in themes:
        d = source_meta(t)
        if d is None:
            continue
        name = d.get("MENU_NAME", "")
        if name and name != "__UNSET__":
            names.setdefault(name.lower(), []).append(t)
        want = "Letterpress — " + name
        if d.get("VSCODIUM_THEME") != want:
            fail("%s/meta.sh: VSCODIUM_THEME=%r, want %r" % (t, d.get("VSCODIUM_THEME"), want))
        if d.get("YAZI_FLAVOR") != "letterpress-" + t:
            fail("%s/meta.sh: YAZI_FLAVOR=%r, want %r" % (t, d.get("YAZI_FLAVOR"), "letterpress-" + t))
        if not os.path.isdir(os.path.join(FLAVORS, d.get("YAZI_FLAVOR", "") + ".yazi")):
            fail("%s: yazi flavor dir missing: dotfiles/.config/yazi/flavors/%s.yazi (bin/gen-yazi-flavors.py %s)" % (
                t, d.get("YAZI_FLAVOR"), t))
    for n, ts in sorted(names.items()):
        if len(ts) > 1:
            fail("MENU_NAME %r is used by %s (`dram theme %s` is ambiguous)" % (n, ", ".join(ts), n))
        if n in themes and ts != [n]:
            fail("MENU_NAME %r (%s) is another theme's dir id" % (n, ", ".join(ts)))
    # 6. one accent across the hand-written slots
    for t in themes:
        slots = dict(accents[t])
        a = slots.get("waybar @accent", "")
        if not re.match(r"^#[0-9a-f]{6}$", a):
            fail("%s/waybar.css: @define-color accent is %r, not #rrggbb" % (t, a))
            continue
        for slot, v in accents[t]:
            if v == a:
                continue
            if (t, slot) in EXCEPTIONS:
                continue
            fail("%s: %s = %r but waybar @accent = %s (one accent ink per theme; or list it in EXCEPTIONS)" % (t, slot, v, a))
    for (t, slot) in EXCEPTIONS:
        if t in themes and dict(accents[t]).get(slot, "") == dict(accents[t]).get("waybar @accent"):
            fail("EXCEPTIONS lists %s %s but it equals the accent now — drop the entry" % (t, slot))
    if not FAILS:
        print("  %d themes, %d files each, one key set per file, %d unique names, %d accent exception(s)" % (
            len(themes), len(ref), len(names), len(EXCEPTIONS)))


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


if __name__ == "__main__":
    _parse_args()
    main()
    if FAILS:
        for f in FAILS:
            print("  " + f)
        sys.exit(1)
    sys.exit(0)

#!/usr/bin/env python3
r"""usage: gen-windows-look.py [theme] [--check]

Writes install/windows/letterpress/, the Letterpress look for Windows and its apps, from the palette files Arch already uses. A dev-time generator like gen-browser-css.py: run it after editing a palette and commit the output; install/windows/apply-windows.sh copies the directory to C:\ProgramData\dram\letterpress, where the desktop role's units (windows/roles/desktop.nix) and dram-windows/look.ps1 put it in place (docs/design/themes/windows.md).

    dotfiles/.config/themes/<t>/kitty.conf   color0-15, foreground, background, cursor, selection
  + dotfiles/.config/themes/<t>/waybar.css   base mantle crust text subtext overlay surface0/1, hues
  + dotfiles/.config/themes/<t>/palette.lua  accent, accent_dim (the ONE accent ink)
  + dotfiles/.config/themes/<t>/meta.sh      COLOR_SCHEME (light/dark), MENU_NAME
  + bin/gen-vscode-themes.py                 the syntax inks (readable(): >= 4.5:1 on the paper)
                                             and the pj.letterpress-themes extension it writes
  + install/windows/upstream/                Notepad++ v8.9.8.1 DarkModeDefault.xml (GPL-2.0),
                                             Mumble v1.5.939 Dark.qss (Unlicense; its header names the WTFPL) and Wireshark
                                             v4.6.9 colorfilters (GPL-2.0-or-later), recoloured by name
  + dotfiles/.config/waybar/{config,modules}.jsonc  the masthead's layout, captions, intervals
  = install/windows/letterpress/
      theme                  the theme id the directory was generated from
      wt-schemes.json        Windows Terminal fragment: every dram theme as a colour scheme
      wt-settings.json       the keys look.ps1 owns in Windows Terminal's settings.json
      wsl/terminal-profile.json  profile template for the WSL Arch clone (scheme + font)
      psreadline.ps1         PSReadLine and $PSStyle in the inks; dot-sourced by the profile
      conhost.json           HKCU\Console ColorTable00-15 (the unit conhost-letterpress)
      accent.json            accent DWORDs + AccentPalette (the unit letterpress-look)
      vscodium-settings.json the keys look.ps1 pins in VSCodium's settings.json
      pj.letterpress-themes-<version>.vsix   the extension, packed for `codium --install-extension`
      powertoys.json         per utility, the colour keys of its PowerToys settings.json
      cmdpal.json            Command Palette's colour keys (washi paper behind the list)
      windirstat.json        WinDirStat's registry colours (tree bars, treemap highlight)
      runelite.json          RuneLite's overlay colour, for every profile
      vesktop/ obs/ notepad++/ mumble/ halloy/ qbittorrent/ calibre/ vortex/ mintty/
      teamspeak/ nomacs/ wireshark/
                             one theme (and the keys that select it) per app
      zebar/                 the masthead: Waybar's bar as a Zebar widget pack (letterpress/:
                             zpack.json, masthead.html/.css/.js) and settings.json starting it;
                             look.ps1 puts both in %USERPROFILE%\.glzr\zebar

Deterministic (no dates, fixed zip timestamps, a fixed @version: VERSION below, bumped by hand),
so --check can compare; bin/check.sh section 19 runs it. Every text output is ASCII, and every
ink the TeamSpeak, nomacs and Wireshark outputs set on a paper reads at 4.5:1 or better (the
build fails otherwise). Without a theme argument it regenerates the theme the directory was
made from (washi, the house theme, when there is none).

  theme         a theme dir id under dotfiles/.config/themes (default: the recorded one, else washi)
  --check       write nothing; exit 1 with a diff when the directory is stale
  -h, --help    this text

exit: 0 ok (or up to date) · 1 stale (--check) or an input failed · 2 bad usage
see: docs/design/themes/windows.md
"""
import colorsys
import difflib
import hashlib
import importlib.util
import io
import json
import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THEMES = os.path.join(ROOT, "dotfiles", ".config", "themes")
OUT = os.path.join(ROOT, "install", "windows", "letterpress")
UPSTREAM = os.path.join(ROOT, "install", "windows", "upstream")
REL_OUT = "install/windows/letterpress"
HOUSE = "washi"
VERSION = "2026.10.12"   # the themes' @version; bump by hand when the mapping changes
ZIP_TIME = (2026, 1, 1, 0, 0, 0)

# vendored inputs: path under install/windows/upstream -> (source, sha256). A bump: fetch the
# new tag's file, update the URL and the hash, regenerate, review the diff.
VENDORED = {
    "notepad++/DarkModeDefault.xml": (
        "https://raw.githubusercontent.com/notepad-plus-plus/notepad-plus-plus/v8.9.8.1/"
        "PowerEditor/installer/themes/DarkModeDefault.xml",
        "978b086b70368aee5e7f530103242485e581ae98b571a55217927ca56fff9a70"),
    "mumble/Dark.qss": (
        "https://raw.githubusercontent.com/mumble-voip/mumble/v1.5.939/themes/Default/Dark.qss",
        "2218e729c5f20162e875d29818643aa39e30200f903c475e069144f8cfc041c7"),
    "wireshark/colorfilters": (
        "https://raw.githubusercontent.com/wireshark/wireshark/v4.6.9/resources/share/wireshark/colorfilters",
        "0db519d9bb85865c4c7f4b5145af7b2ee47809c42b34e1d86b7c8cd7cdaa372b"),
}
NPP_TAG = "v8.9.8.1"
# stylers.model.xml's modelDate at NPP_TAG: a theme stamped with it is not merged into at
# startup (Parameters.cpp updateFromModelXml); DarkModeDefault.xml at that tag already has
# every lexer and style of the model (checked when the pin was set)
NPP_MODEL_DATE = "20260525"
MUMBLE_TAG = "v1.5.939"
WIRESHARK_TAG = "v4.6.9"
POWERTOYS_TAG = "v0.101.2362.0"   # the release whose settings classes powertoys() follows

PWSH_PROFILE = "{574e775e-4f2a-5b96-ac1e-a2962a402336}"   # Windows Terminal's PowerShell 7 profile
MONO = "Monaspace Xenon"
ICONS = "Symbols Nerd Font Mono"
SCHEME_NAMES = {"crt": "CRT"}   # Windows Terminal scheme names: the dir id in title case


class InputError(Exception):
    pass


def _load_vscode_generator():
    path = os.path.join(ROOT, "bin", "gen-vscode-themes.py")
    spec = importlib.util.spec_from_file_location("gen_vscode_themes", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


vs = _load_vscode_generator()   # colour maths, palette readers, syntax inks, the extension
mix, rgb = vs.mix, vs.rgb


# ---- inputs ------------------------------------------------------------------------
def kitty_keys(path):
    s = open(path, encoding="utf-8").read()
    return {k: v.lower() for k, v in re.findall(r"^([a-z_]+)\s+(#[0-9a-fA-F]{6})\b", s, re.M)}


class Theme:
    def __init__(self, tid):
        d = os.path.join(THEMES, tid)
        if not os.path.isfile(os.path.join(d, "waybar.css")):
            raise InputError("%s: no such theme (dotfiles/.config/themes/%s)" % (tid, tid))
        self.id = tid
        self.c = vs.define_colors(os.path.join(d, "waybar.css"))
        missing = [k for k in vs.NEEDED if not self.c.get(k)]
        if missing:
            raise InputError("%s: waybar.css lacks %s" % (tid, missing))
        pal = vs.palette_lua(os.path.join(d, "palette.lua"))
        self.meta = vs.meta(os.path.join(d, "meta.sh"))
        self.light = self.meta.get("COLOR_SCHEME") == "prefer-light"
        self.accent = pal.get("accent") or self.c.get("accent") or self.c["blue"]
        self.accent_dim = pal.get("accent_dim") or mix(self.accent, self.c["base"], 0.25)
        self.kitty = kitty_keys(os.path.join(d, "kitty.conf"))
        self.ansi = vs.kitty_ansi(os.path.join(d, "kitty.conf"))
        for k in ("foreground", "background"):
            if k not in self.kitty:
                raise InputError("%s: kitty.conf lacks %s" % (tid, k))
        if sorted(self.ansi) != list(range(16)):
            raise InputError("%s: kitty.conf lacks some of color0-15" % tid)
        _, _, self.ink = vs.syntax(self.c, self.accent, self.accent_dim, self.light)
        self.label = vs.LABEL + self.meta.get("MENU_NAME", tid)
        self.menu = self.meta.get("MENU_NAME", tid)
        # the derived shades every app below shares
        base, text = self.c["base"], self.c["text"]
        self.hair = mix(base, text, 0.18)       # the hairline: alpha(text, .18) on the paper
        self.wash = mix(base, text, 0.08)       # hover
        self.shade = mix(self.c["surface1"], text, 0.08)    # an active selection: a paper shade
        self.shade2 = mix(self.c["surface1"], text, 0.16)
        self.strong = mix(text, "#000000" if self.light else "#ffffff", 0.5)

    @property
    def mode(self):
        return "light" if self.light else "dark"


def every_theme():
    return sorted(t for t in os.listdir(THEMES)
                  if t != "current" and os.path.isfile(os.path.join(THEMES, t, "waybar.css")))


def vendored(rel):
    url, want = VENDORED[rel]
    path = os.path.join(UPSTREAM, rel)
    if not os.path.isfile(path):
        raise InputError("install/windows/upstream/%s is missing (from %s)" % (rel, url))
    data = open(path, "rb").read()
    got = hashlib.sha256(data).hexdigest()
    if got != want:
        raise InputError("install/windows/upstream/%s: sha256 %s, pinned %s (%s)" % (rel, got, want, url))
    return data.decode("ascii")


# ---- helpers ---------------------------------------------------------------------------
def dump(obj):
    s = json.dumps(obj, indent=2, ensure_ascii=True)
    # a list of numbers on one line (AccentPalette's 32 bytes)
    s = re.sub(r"\[\n\s+((?:-?\d+,\n\s+)*-?\d+)\n\s*\]",
               lambda m: "[" + ", ".join(v.strip() for v in m.group(1).split(",")) + "]", s)
    return s + "\n"


def hex6(h):        # "#c0442b" -> "C0442B" (Notepad++)
    return h.lstrip("#").upper()


def rgbcss(h):      # "#c0442b" -> "rgb(192,68,43)" (OBS)
    return "rgb(%d,%d,%d)" % rgb(h)


def triple(h):      # "#c0442b" -> "192,68,43" (mintty)
    return "%d,%d,%d" % rgb(h)


def colorref(h):    # Win32 COLORREF 0x00BBGGRR
    r, g, b = rgb(h)
    return (b << 16) | (g << 8) | r


def s32(u):         # a DWORD as the signed Int32 the registry provider reads back
    return u - (1 << 32) if u >= (1 << 31) else u


def ansi_index(t, h):
    for i in range(16):
        if t.ansi[i] == h.lower():
            return i
    return None


def sgr_fg(t, h, italic=False):
    i = ansi_index(t, h)
    code = ("%d" % (30 + i if i < 8 else 82 + i)) if i is not None else "38;2;%d;%d;%d" % rgb(h)
    return ("3;" if italic else "") + code


def sgr_bg(t, h):
    i = ansi_index(t, h)
    return ("%d" % (40 + i if i < 8 else 92 + i)) if i is not None else "48;2;%d;%d;%d" % rgb(h)


def scheme_name(tid):
    return SCHEME_NAMES.get(tid) or " ".join(w.capitalize() for w in tid.split("-"))


def gen_note(t, what):
    return "%s - GENERATED by bin/gen-windows-look.py from themes/%s (%s); do not edit." % (
        what, t.id, t.menu)


def ink_on(t, ink, paper):
    """`ink` as it reads on `paper`: mixed toward the body ink until 4.5:1 (readable())."""
    return vs.readable(ink, paper, t.c["text"])


def paper_under(t, paper, ink):
    """`paper` moved toward the base in 5 % steps until `ink` reads on it at 4.5:1: a theme whose
    selection or tint is too close to its ink keeps its hue, a little nearer the page."""
    out, k = paper, 0.0
    while vs.contrast(ink, out) < vs.MIN_CONTRAST and k < 1.0:
        k = min(1.0, k + 0.05)
        out = mix(paper, t.c["base"], k)
    return out


def gate(t, what, pairs):
    """The contrast gate: every (name, ink, paper) reads at 4.5:1 or the build fails, so a palette
    edit cannot leave a Windows app with text that does not read (ink_on and paper_under come
    first; only a theme whose body ink does not read on its own page can fail it)."""
    for name, ink, paper in pairs:
        if vs.contrast(ink, paper) < vs.MIN_CONTRAST:
            raise InputError("%s (%s): %s %s on %s reads at %.2f:1, under %.1f:1" % (
                what, t.id, name, ink, paper, vs.contrast(ink, paper), vs.MIN_CONTRAST))


# ---- Windows Terminal, the WSL profile, conhost ------------------------------------------
def wt_scheme(t):
    k, a = t.kitty, t.ansi
    s = {"name": scheme_name(t.id), "background": k["background"], "foreground": k["foreground"],
         "cursorColor": k.get("cursor", k["foreground"]),
         "selectionBackground": k.get("selection_background", t.c["surface0"])}
    names = ["black", "red", "green", "yellow", "blue", "purple", "cyan", "white"]
    for i, n in enumerate(names):
        s[n] = a[i]
    for i, n in enumerate(names):
        s["bright" + n[0].upper() + n[1:]] = a[i + 8]
    return s


def wt_defaults(t):
    # kitty.conf, item by item: font + symbol_map (a fallback list since WT 1.21), the
    # texture-healing features, the beam, padding 10, scrollback, the bell as a window alert;
    # opacity stays 100 until 92 % is tried with transparency effects off
    return {
        "colorScheme": scheme_name(t.id),
        "font": {"face": "%s, %s" % (MONO, ICONS), "size": 12,
                 "features": {"calt": 1, "liga": 1, "ss01": 1, "ss02": 1, "ss03": 1}},
        "cursorShape": "bar",
        "padding": "10",
        "opacity": 100,
        "useAcrylic": False,
        "bellStyle": ["window", "taskbar"],
        "historySize": 20000,
        "adjustIndistinguishableColors": "never",
    }


def wt_settings(t):
    page = t.kitty["background"] + "ff"
    return {
        "defaultProfile": PWSH_PROFILE,
        "theme": "letterpress",
        "themes": [{
            "name": "letterpress",
            "window": {"applicationTheme": t.mode, "useMica": False},
            "tabRow": {"background": page, "unfocusedBackground": page},
            "tab": {"background": "terminalBackground", "unfocusedBackground": page,
                    "showCloseButton": "hover"},
        }],
        "profiles": {"defaults": wt_defaults(t)},
    }


CONSOLE_ORDER = [0, 4, 2, 6, 1, 5, 3, 7, 8, 12, 10, 14, 9, 13, 11, 15]   # conhost index -> ANSI


def conhost(t):
    table = [t.ansi[CONSOLE_ORDER[i]] for i in range(16)]
    out = {"ColorTable%02d" % i: colorref(h) for i, h in enumerate(table)}

    def slot(h, fallback):
        return table.index(h) if h in table else fallback
    bg = slot(t.kitty["background"], 15 if t.light else 0)
    fg = slot(t.kitty["foreground"], 0 if t.light else 7)
    out["ScreenColors"] = (bg << 4) | fg
    out["DefaultForeground"] = -1   # INVALID_COLOR: the table decides
    out["DefaultBackground"] = -1
    return out


# ---- the accent -------------------------------------------------------------------------
def accent_steps(t):
    """Windows' AccentPalette: eight RGBA swatches, light to dark, the accent fourth and the
    paper last. HLS lightness steps at the accent's own hue and saturation."""
    a = rgb(t.accent)
    h, l, s = colorsys.rgb_to_hls(*(v / 255 for v in a))
    out = []
    for d in (0.30, 0.18, 0.09, 0.0, -0.09, -0.18, -0.28):
        if d == 0.0:
            out.append(a)
            continue
        r, g, b = colorsys.hls_to_rgb(h, min(0.95, max(0.05, l + d)), s)
        out.append(tuple(round(v * 255) for v in (r, g, b)))
    out.append(rgb(t.kitty["background"]))
    return out


def accent_json(t):
    steps = accent_steps(t)
    r, g, b = rgb(t.accent)
    dr, dg, db = steps[4]
    abgr = 0xff000000 | (b << 16) | (g << 8) | r
    argb = 0xc4000000 | (r << 16) | (g << 8) | b
    start = 0xff000000 | (db << 16) | (dg << 8) | dr
    light = 1 if t.light else 0
    return {
        "theme": t.id,
        "accent": t.accent,
        "AppsUseLightTheme": light,
        "SystemUsesLightTheme": light,
        "AccentColor": s32(abgr),
        "ColorizationColor": s32(argb),
        "ColorizationAfterglow": s32(argb),
        "AccentColorMenu": s32(abgr),
        "StartColorMenu": s32(start),
        "AccentPalette": [v for sw in steps for v in (sw[0], sw[1], sw[2], 0)],
        "hex": {"AccentColor": "0x%08x" % abgr, "ColorizationColor": "0x%08x" % argb,
                "StartColorMenu": "0x%08x" % start,
                "AccentPalette": " ".join("#%02x%02x%02x" % sw for sw in steps)},
    }


# ---- PowerShell -----------------------------------------------------------------------
def psreadline(t):
    ink, c = t.ink, t.c

    def fg(h, italic=False):
        return '"$e[%sm"' % sgr_fg(t, h, italic)

    def bg(h):
        return '"$e[%sm"' % sgr_bg(t, h)
    colors = [
        ("Default", fg(c["text"])), ("Variable", fg(c["text"])), ("Member", fg(c["text"])),
        ("Operator", fg(c["text"])), ("Command", fg(ink["support"])), ("Parameter", fg(c["subtext"])),
        ("Keyword", fg(t.accent)), ("String", fg(ink["string"])), ("Type", fg(ink["type"])),
        ("Number", fg(ink["numbers"])), ("Comment", fg(c["subtext"], True)), ("Emphasis", fg(t.accent)),
        ("Error", fg(t.ansi[9])), ("Selection", bg(c["surface1"])), ("ContinuationPrompt", fg(c["subtext"])),
    ]
    lines = [
        "# " + gen_note(t, "PSReadLine and $PSStyle in the Letterpress inks"),
        "# keywords the accent, strings ochre, types blue, commands teal, parameters subtext,",
        "# comments subtext italic, predictions overlay, the rest body ink (gen-vscode-themes.py's",
        "# inks); named ANSI where the ink is one of the scheme's 16 colours, 24-bit otherwise.",
        "# Dot-sourced by the profile dram-windows/look.ps1 writes; Windows PowerShell 5.1 and",
        "# PowerShell 7. ASCII only: [char]27, not the 7-only escape.",
        "& {",
        "  $e = [char]27",
        "  $m = Get-Module PSReadLine | Select-Object -First 1",
        "  if (-not $m) { $m = Import-Module PSReadLine -PassThru -ErrorAction SilentlyContinue | Select-Object -First 1 }",
        "  if ($m) {",
        "    $c = @{",
    ]
    lines += ["      %s = %s" % (k, v) for k, v in colors]
    lines += [
        "    }",
        "    if ($m.Version -ge [version]'2.1.0') { $c.InlinePrediction = %s }" % fg(c["overlay"]),
        "    if ($m.Version -ge [version]'2.2.0') { $c.ListPrediction = %s; $c.ListPredictionSelected = %s }" % (
            fg(ink["string"]), bg(c["surface0"])),
        "    Set-PSReadLineOption -Colors $c -BellStyle None",
        "  }",
        "  if ($PSVersionTable.PSVersion.Major -ge 7 -and (Get-Variable -Name PSStyle -ErrorAction SilentlyContinue)) {",
        '    $PSStyle.FileInfo.Directory = "$e[34m"',
        '    $PSStyle.FileInfo.SymbolicLink = "$e[36m"',
        '    $PSStyle.FileInfo.Executable = "$e[32m"',
        "    $PSStyle.Formatting.TableHeader = %s" % fg(c["subtext"], True),
        "    $PSStyle.Formatting.FormatAccent = %s" % fg(c["subtext"]),
        "    $PSStyle.Formatting.Warning = %s" % fg(c["yellow"]),
        "    $PSStyle.Formatting.Verbose = %s" % fg(c["overlay"]),
        "    $PSStyle.Progress.Style = %s" % fg(t.accent),
        "  }",
        "}",
    ]
    return "\n".join(lines) + "\n"


# ---- VSCodium ---------------------------------------------------------------------------
def vscodium_settings(t):
    mono = "'%s', '%s', monospace" % (MONO, ICONS)
    return {
        "workbench.colorTheme": t.label,
        "editor.fontFamily": mono,
        "editor.fontLigatures": "'calt', 'liga', 'ss01', 'ss02', 'ss03'",
        "terminal.integrated.fontFamily": mono,
        "workbench.experimental.fontFamily": "Literata",
        "terminal.integrated.defaultProfile.windows": "PowerShell",
    }


def xml_escape(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


def vsix():
    """pj.letterpress-themes as a VSIX: [Content_Types].xml, extension.vsixmanifest and the
    committed extension under extension/ (forward slashes, fixed timestamps, sorted)."""
    ext = vs.EXT
    pkg_path = os.path.join(ext, "package.json")
    if not os.path.isfile(pkg_path):
        raise InputError("dotfiles/.vscode/extensions/letterpress-themes/package.json is missing")
    pkg = json.load(open(pkg_path, encoding="utf-8"))
    members = [("extension/package.json", open(pkg_path, "rb").read())]
    tdir = os.path.join(ext, "themes")
    for name in sorted(os.listdir(tdir)):
        if name.endswith(".json"):
            members.append(("extension/themes/" + name, open(os.path.join(tdir, name), "rb").read()))
    manifest = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011"'
        ' xmlns:d="http://schemas.microsoft.com/developer/vsx-schema-design/2011">\n'
        '  <Metadata>\n'
        '    <Identity Language="en-US" Id="%s" Version="%s" Publisher="%s" />\n'
        '    <DisplayName>%s</DisplayName>\n'
        '    <Description xml:space="preserve">%s</Description>\n'
        '    <Tags>theme,color-theme</Tags>\n'
        '    <Categories>Themes</Categories>\n'
        '    <GalleryFlags>Public</GalleryFlags>\n'
        '    <Properties>\n'
        '      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="%s" />\n'
        '      <Property Id="Microsoft.VisualStudio.Code.ExtensionDependencies" Value="" />\n'
        '      <Property Id="Microsoft.VisualStudio.Code.ExtensionPack" Value="" />\n'
        '      <Property Id="Microsoft.VisualStudio.Code.ExtensionKind" Value="ui,workspace" />\n'
        '      <Property Id="Microsoft.VisualStudio.Code.LocalizedLanguages" Value="" />\n'
        '      <Property Id="Microsoft.VisualStudio.Services.Content.Pricing" Value="Free" />\n'
        '    </Properties>\n'
        '  </Metadata>\n'
        '  <Installation>\n'
        '    <InstallationTarget Id="Microsoft.VisualStudio.Code" />\n'
        '  </Installation>\n'
        '  <Dependencies />\n'
        '  <Assets>\n'
        '    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true" />\n'
        '  </Assets>\n'
        '</PackageManifest>\n'
    ) % (xml_escape(pkg["name"]), xml_escape(pkg["version"]), xml_escape(pkg["publisher"]),
         xml_escape(pkg.get("displayName", pkg["name"])), xml_escape(pkg.get("description", "")),
         xml_escape(pkg.get("engines", {}).get("vscode", "*")))
    types = ('<?xml version="1.0" encoding="utf-8"?>\n'
             '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
             '<Default Extension=".json" ContentType="application/json" />'
             '<Default Extension=".vsixmanifest" ContentType="text/xml" /></Types>\n')
    members = [("[Content_Types].xml", types.encode()), ("extension.vsixmanifest", manifest.encode())] + members
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for name, data in members:
            zi = zipfile.ZipInfo(name, date_time=ZIP_TIME)
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.create_system = 0
            zi.external_attr = 0
            z.writestr(zi, data, compresslevel=9)
    name = "%s.%s-%s.vsix" % (pkg["publisher"], pkg["name"], pkg["version"])
    return name, buf.getvalue()


def zip_members(data):
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        return [(i.filename, z.read(i.filename)) for i in z.infolist()]


# ---- Vesktop (Vencord) ------------------------------------------------------------------
def vesktop_css(t):
    c = t.c
    sel = ".theme-%s" % t.mode
    v = [
        ("--background-base-lowest", c["crust"]), ("--background-base-lower", c["mantle"]),
        ("--background-base-low", c["base"]), ("--background-surface-high", c["surface0"]),
        ("--background-surface-higher", c["surface0"]), ("--background-surface-highest", c["surface1"]),
        ("--bg-surface-raised", c["surface0"]), ("--app-frame-background", c["mantle"]),
        ("--chat-background", c["base"]), ("--chat-background-default", c["base"]),
        ("--modal-background", c["mantle"]), ("--input-background-default", c["mantle"]),
        ("--text-default", c["text"]), ("--text-strong", t.strong), ("--text-muted", c["subtext"]),
        ("--text-subtle", c["overlay"]), ("--text-link", c["blue"]),
        ("--interactive-text-default", c["subtext"]), ("--interactive-text-hover", c["text"]),
        ("--interactive-text-active", c["text"]), ("--channels-default", c["subtext"]),
        ("--border-subtle", t.hair), ("--border-normal", t.hair), ("--border-strong", c["overlay"]),
        ("--background-brand", t.accent), ("--brand-500", t.accent + " !important"),
    ]
    out = [
        "/**",
        " * @name Letterpress",
        " * @author pj",
        " * @description Paper, ink, one accent: the dram's %s palette (%s). GENERATED by bin/gen-windows-look.py; do not edit." % (t.id, t.menu),
        " * @version %s" % VERSION,
        " */",
        "/* Discord's post-2025 variables (catppuccin/discord, refact0r/midnight-discord, Oct 2026);",
        " * the accent stays a rule: brand colour, links and focus, never a panel. Chat keeps gg sans. */",
        ".visual-refresh%s," % sel,
        ".visual-refresh %s:not(.custom-user-profile-theme)," % sel,
        "%s:not(.custom-user-profile-theme) {" % sel,
    ]
    out += ["  %s: %s;" % (k, val) for k, val in v]
    out += ['  --font-code: "%s", "%s", monospace;' % (MONO, ICONS), "}"]
    return "\n".join(out) + "\n"


# ---- OBS Studio ---------------------------------------------------------------------------
def obs_ovt(t):
    c = t.c
    v = [
        ("--grey1", c["subtext"]), ("--grey2", c["overlay"]), ("--grey3", c["surface1"]),
        ("--grey4", c["surface0"]), ("--grey5", c["base"]), ("--grey6", c["mantle"]),
        ("--grey7", c["crust"]), ("--grey8", c["crust"]),
        ("--primary", t.accent), ("--primary_light", mix(t.accent, c["text"], 0.15)),
        ("--primary_lighter", t.ink["numbers"]), ("--primary_dark", t.accent_dim),
        ("--primary_darker", mix(t.accent_dim, c["base"], 0.4)),
        ("--text", c["text"]), ("--text_light", c["text"]), ("--text_muted", c["subtext"]),
        ("--text_disabled", c["overlay"]), ("--text_inactive", c["subtext"]),
        ("--input_border", t.hair), ("--palette_link", c["blue"]), ("--palette_linkVisited", c["blue"]),
    ]
    refs = [
        ("--bg_base", "var(--grey5)"), ("--bg_window", "var(--grey4)"), ("--bg_preview", "var(--grey6)"),
        ("--border_color", "var(--grey3)"), ("--input_bg", "var(--grey6)"),
        ("--list_item_bg_selected", "var(--grey3)"), ("--list_item_bg_hover", "var(--grey4)"),
        ("--input_border_focus", "var(--primary)"), ("--highlight_color", "var(--primary)"),
        ("--tab_bg_down", "var(--grey3)"), ("--tab_border_selected", "var(--primary)"),
        ("--palette_highlight", "var(--grey3)"), ("--palette_highlightedText", "var(--text)"),
        ("--scrollbar_handle", "var(--grey3)"), ("--scrollbar_hover", "var(--grey2)"),
    ]
    out = [
        "/* " + gen_note(t, "Letterpress for OBS Studio") + " */",
        "/* A variant over Yami, as upstream recommends: paper greys, ink, the accent as OBS's",
        " * primary (focus rings, the selected tab's rule, checked controls); list selection and",
        " * text highlight are paper shades. Select it: Settings > Appearance, or user.ini",
        " * [Appearance] Theme=com.pj.Yami.Letterpress (dram-windows/look.ps1). */",
        "",
        "@OBSThemeMeta {",
        "    name: 'Letterpress';",
        "    id: 'com.pj.Yami.Letterpress';",
        "    extends: 'com.obsproject.Yami';",
        "    author: 'pj';",
        "    dark: '%s';" % ("false" if t.light else "true"),
        "}",
        "",
        "@OBSThemeVars {",
    ]
    out += ["    %s: %s;" % (k, rgbcss(h)) for k, h in v]
    out += ["    %s: %s;" % (k, r) for k, r in refs]
    out += ["}"]
    return "\n".join(out) + "\n"


# ---- Notepad++ ----------------------------------------------------------------------------
NPP_RULES = [   # (regex on the upper-cased style name, ink, fontStyle); first match wins
    (r"^(DIFF ADDITION|ADDED|ADDED KEY)$", "green", 0),
    (r"^(DIFF DELETION|DELETED|REMOVED KEY)$", "red", 0),
    (r"^DIFF CHANGED$", "yellow", 0),
    (r"ERROR|ILLEGAL|^BAD |GARBAGE|_WRONG$|NOT CLOSED|^STRING EOL", "red", 0),
    (r"^HIT WORD$", "accent", 0),
    (r"COMMENT|^POD\b|^DSC COMMENT", "comment", 2),
    (r"ESCAPE", "numbers", 0),
    (r"BLOCKQUOTE", "comment", 2),
    (r"^H[1-6]$|^STRONG\b", "text", 1),
    (r"^EM[12]\b", "text", 2),
    (r"^LINK$|URL|^URI$|^EMAIL|^COMPACT IRI", "blue", 0),
    (r"^CODE|^CODEBLOCK|MATH (BLOCK|INLINE)", "string", 0),
    (r"STRING|CHARACTER|^CHARS?$|TRIPLE|HEREDOC|^HERE |VERBATIM|QUOTE|BACKTICK|CDATA|REGEX|LITERAL", "string", 0),
    (r"NUMBER|NUMERIC|^HEX|BINARY|BINNUMBER|^DATE|^TIME|MONEY|^BOOL|^NIL$|CONSTANT|DECORATOR|^ATOM$|^SYMBOL$", "numbers", 0),
    (r"KEYWORD|INSTRUCTION|^INSTR$|RESERVED|STATEMENT|PREPROC|DIRECTIVE|MACRO|^WORD\d*$|DEFWORDS|CMDLET|"
     r"OPCODE|^IMPORT$|^MODIF|^IFDEF|^IF DEFINE|PRAGMA|^LABEL", "accent", 0),
    (r"TYPE|CLASS|STRUCT|NAMESPACE|INTERFACE|^ENUM|^MODULE", "type", 0),
    (r"^TAG|TAGNAME|^ENTITY|^SGML|^XMLSTART$|^XMLEND$|PSEUDO|SPECIAL SELECTOR", "support", 0),
    (r"BUILT-?IN|BUILTINS|BUILIN|^STD (FUNCTION|PACKAGE|OPERATOR)|PREDEFINED|^SYSTEM|^CORE API|^PLUGIN", "support", 0),
    (r"DELIMITER|BRACE|PUNCT|^SEPARATOR|^HRULE$", "subtext", 0),
]
ANSI_NAMES = {"BLACK": 0, "RED": 1, "GREEN": 2, "YELLOW": 3, "BLUE": 4, "MAGENTA": 5, "CYAN": 6, "WHITE": 7}
ANSI_COLOR = {  # the errorlist lexer's "ANSI COLOR <name>": the DOS colour names
    "BLACK": 0, "RED": 1, "GREEN": 2, "BROWN": 3, "BLUE": 4, "MAGENTA": 5, "CYAN": 6, "GRAY": 7,
    "DARK GRAY": 8, "BRIGHT RED": 9, "BRIGHT GREEN": 10, "YELLOW": 11, "BRIGHT BLUE": 12,
    "BRIGHT MAGENTA": 13, "BRIGHT CYAN": 14, "WHITE": 15,
}


def npp_globals(t):
    c, a = t.c, t.accent
    tints = [c["yellow"], c["green"], c["blue"], c["red"], c["mauve"]]
    g = {
        "Default Style": (c["text"], c["base"]),
        "Indent guideline style": (t.hair, c["base"]),
        "Brace highlight style": (a, c["base"]),
        "Bad brace colour": (c["red"], c["base"]),
        "Current line background colour": (None, mix(c["base"], c["text"], 0.06)),
        "Selected text colour": (c["text"], mix(c["base"], c["text"], 0.16)),
        "Multi-selected text color": (None, mix(c["base"], c["text"], 0.12)),
        "Caret colour": (a, None),
        "Multi-edit carets color": (t.accent_dim, None),
        "Edge colour": (t.hair, None),
        "Line number margin": (c["subtext"], c["base"]),
        "Bookmark margin": (None, c["base"]),
        "Change History margin": (None, c["base"]),
        "Change History modified": (c["yellow"], c["yellow"]),
        "Change History revert modified": (c["blue"], c["blue"]),
        "Change History revert origin": (c["teal"], c["teal"]),
        "Change History saved": (c["green"], c["green"]),
        "Fold": (c["subtext"], c["base"]),
        "Fold active": (a, None),
        "Fold margin": (c["base"], c["base"]),
        "White space symbol": (c["overlay"], None),
        "Smart Highlighting": (None, mix(c["base"], a, 0.30)),
        "Find Mark Style": (None, mix(c["base"], a, 0.45)),
        "Find status: Not found": (c["red"], None),
        "Find status: Message": (c["text"], None),
        "Find status: Search end reached": (c["yellow"], None),
        "Incremental highlight all": (None, mix(c["base"], a, 0.30)),
        "Tags match highlighting": (None, mix(c["base"], c["blue"], 0.35)),
        "Tags attribute": (None, mix(c["base"], c["teal"], 0.35)),
        "Active tab focused indicator": (a, None),
        "Active tab unfocused indicator": (t.accent_dim, None),
        "Active tab text": (c["text"], None),
        "Inactive tabs": (c["subtext"], c["base"]),
        "URL hovered": (c["blue"], None),
        "Document map": (c["overlay"], c["surface1"]),
        "EOL custom color": (c["overlay"], None),
        "Non-printing characters custom color": (c["overlay"], None),
        "Global override": (c["text"], c["base"]),
    }
    for i, h in enumerate([c["blue"], c["yellow"], c["red"], c["green"], c["mauve"]]):
        g["Mark Style %d" % (i + 1)] = (None, mix(c["base"], h, 0.45))
    for i, h in enumerate(tints):
        g["Tab color %d" % (i + 1)] = (None, mix(c["base"], h, 0.35))
        g["Tab color dark mode %d" % (i + 1)] = (None, mix(c["base"], h, 0.35))
    return g


def npp_words(t, name):
    """(fg, bg, fontStyle) for a lexer style, by its name."""
    n = name.upper().strip()
    c, a = t.c, t.ansi
    m = re.match(r"^(BOLD )?(%s) ON (%s)$" % ("|".join(ANSI_NAMES) + "|DEFAULT", "|".join(ANSI_NAMES) + "|DEFAULT"), n)
    if m:   # escseq: what a terminal shows, bold included
        bold, f, b = m.groups()
        fg = c["text"] if f == "DEFAULT" else a[ANSI_NAMES[f] + (8 if bold else 0)]
        bg = c["base"] if b == "DEFAULT" else a[ANSI_NAMES[b]]
        return fg, bg, 1 if bold else 0
    if n == "CURRENT LINE BACKGROUND COLOUR":   # searchResult's: a paper shade, not the paper
        return None, mix(c["base"], c["text"], 0.10), 0
    m = re.match(r"^ANSI COLOR (.+)$", n)
    if m and m.group(1) in ANSI_COLOR:
        return a[ANSI_COLOR[m.group(1)]], c["base"], 0
    inks = {"text": c["text"], "comment": c["subtext"], "subtext": c["subtext"], "accent": t.accent,
            "string": t.ink["string"], "numbers": t.ink["numbers"], "type": t.ink["type"],
            "support": t.ink["support"], "blue": c["blue"], "green": t.ink["green"],
            "red": c["red"], "yellow": t.ink["yellow"]}
    for pat, ink, style in NPP_RULES:
        if re.search(pat, n):
            return inks[ink], c["base"], style
    return c["text"], c["base"], 0


def _set_attr(tag, name, value):
    pat = re.compile(r'(\b%s=")([^"]*)(")' % re.escape(name))
    return pat.sub(lambda m: m.group(1) + value + m.group(3), tag, count=1) if pat.search(tag) else tag


def npp_theme(t):
    src = vendored("notepad++/DarkModeDefault.xml")
    globals_ = npp_globals(t)
    lexer, section, out, seen = None, None, [], set()
    head_done = False
    lines = src.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        if not head_done and line.startswith("<!--"):
            # the upstream comment block -> ours (keeping its attribution)
            while not lines[i].rstrip().endswith("-->"):
                i += 1
            out += [
                "<!--",
                "Letterpress for Notepad++ - GENERATED by bin/gen-windows-look.py from themes/%s (%s);" % (t.id, t.menu),
                "do not edit. Every style of Notepad++ %s's DarkModeDefault.xml (\"based on Zenburn\"," % NPP_TAG,
                "License: GPL2) recoloured by style name into the dram's inks: paper, body ink, one accent;",
                "comments subtext italic, bold only for headings, strong text and bold escape sequences.",
                "modelDate is the model's at %s, so nothing is merged in." % NPP_TAG,
                "-->",
            ]
            head_done = True
            i += 1
            continue
        if line.startswith("<NotepadPlus"):
            out.append('<NotepadPlus modelDate="%s">' % NPP_MODEL_DATE)
            i += 1
            continue
        m = re.match(r'^\s*<LexerType name="([^"]*)"', line)
        if m:
            lexer, section = m.group(1), "lexer"
        if "<GlobalStyles>" in line:
            section, lexer = "global", None
        m = re.match(r'^(\s*)<(WordsStyle|WidgetStyle)((?:\s+[\w:]+="[^"]*")*)(\s*/?>)(.*)$', line)
        if m:
            indent, kind, attrs, close, rest = m.groups()
            name = re.search(r'\bname="([^"]*)"', attrs).group(1)
            if kind == "WordsStyle":
                fg, bg, style = npp_words(t, name)
                if fg:
                    attrs = _set_attr(attrs, "fgColor", hex6(fg))
                attrs = _set_attr(attrs, "bgColor", hex6(bg))
                attrs = _set_attr(attrs, "fontStyle", str(style))
            else:
                if name not in globals_:
                    raise InputError("Notepad++ GlobalStyles has %r, which npp_globals() does not map" % name)
                seen.add(name)
                fg, bg = globals_[name]
                if fg:
                    attrs = _set_attr(attrs, "fgColor", hex6(fg))
                if bg:
                    attrs = _set_attr(attrs, "bgColor", hex6(bg))
                attrs = _set_attr(attrs, "fontStyle", "0")
                if name in ("Default Style", "Global override"):
                    attrs = _set_attr(attrs, "fontName", MONO)
                    attrs = _set_attr(attrs, "fontSize", "11")
            line = "%s<%s%s%s%s" % (indent, kind, attrs, close, rest)
        elif "<WordsStyle" in line or "<WidgetStyle" in line:
            raise InputError("Notepad++: a style tag spans lines: %r" % line[:80])
        out.append(line)
        i += 1
    if not head_done:
        raise InputError("Notepad++: DarkModeDefault.xml has no header comment to replace")
    return "\n".join(out)


def npp_darkmode(t):
    def bgr(h):
        return str(colorref(h))
    c = t.c
    dm = {"enable": "no" if t.light else "yes", "enableWindowsMode": "no"}
    if t.light:
        dm["lightThemeName"] = "Letterpress.xml"
    else:
        dm.update({
            "colorTone": "32",   # customizedTone: the customColor* below
            "customColorTop": bgr(c["mantle"]), "customColorMenuHotTrack": bgr(c["surface1"]),
            "customColorActive": bgr(c["surface0"]), "customColorMain": bgr(c["base"]),
            "customColorError": bgr(t.accent), "customColorText": bgr(c["text"]),
            "customColorDarkText": bgr(c["subtext"]), "customColorDisabledText": bgr(c["overlay"]),
            "customColorLinkText": bgr(c["blue"]), "customColorEdge": bgr(c["surface1"]),
            "customColorHotEdge": bgr(c["overlay"]), "customColorDisabledEdge": bgr(c["surface0"]),
            "darkThemeName": "Letterpress.xml",
        })
    return {
        "DarkMode": dm,
        "globalOverride": {"font": "yes", "fontSize": "yes"},
        # winget updates it; the built-in updater was the 2025 hijack path (CVE-2025-15556)
        "noUpdate": {"autoUpdateMode": "0", "#text": "yes"},
    }


# ---- Mumble -------------------------------------------------------------------------------
def mumble_map(t):
    c = t.c
    return {
        "#2e2e2e": c["base"], "#1d1d1d": c["base"], "#1e1e1e": c["base"],
        "#191919": c["mantle"], "#2b2b2b": c["mantle"], "#282828": c["mantle"],
        "#2d2d2d": c["surface0"],
        "#444": c["surface1"], "#3b3b3b": c["surface1"], "#393939": c["surface1"],
        "#333": t.wash,
        "#298ce1": t.shade, "#3e4f5e": t.shade, "#595959": t.shade,
        "#485d6f": t.shade2, "#1979ca": t.shade2,
        "#1c1c1c": t.hair, "#555": t.hair,
        "#666": mix(c["base"], c["text"], 0.20), "#888": mix(c["base"], c["text"], 0.30),
        "#777": c["overlay"], "#999": c["subtext"], "#bbb": c["text"], "#ccc": c["subtext"],
        "#d8d8d8": c["text"], "#eee": c["text"], "#fff": c["text"], "#484848": c["overlay"],
        "#39a5dd": c["blue"], "#486d8d": t.accent, "#6d96ba": t.accent, "#226": t.accent_dim,
        "#222": c["crust"],
        "#95a5a6": c["subtext"], "#f9655d": t.accent, "#e67e22": t.ink["yellow"],
        "#c0392b": c["red"], "#27ae60": t.ink["green"],
    }


def mumble_qss(t):
    src = vendored("mumble/Dark.qss")
    cmap = mumble_map(t)
    body = src.split("*/", 2)
    if len(body) < 3 or not src.startswith("/*"):
        raise InputError("Mumble Dark.qss: the two header comments are not where expected")
    rest = re.sub(r"/\*# sourceMappingURL=[^*]*\*/\n?", "", body[2].lstrip("\n"))
    unknown = sorted({h.lower() for h in re.findall(r"#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{3}\b", rest)} - set(cmap))
    if unknown:
        raise InputError("Mumble Dark.qss has colours mumble_map() does not map: %s" % unknown)
    rest = re.sub(r"#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{3}\b", lambda m: cmap[m.group(0).lower()], rest)
    head = [
        "/*",
        " * Letterpress for Mumble - GENERATED by bin/gen-windows-look.py from themes/%s (%s);" % (t.id, t.menu),
        " * do not edit. Mumble %s's Dark.qss (mumble-voip/mumble-theme: \"Based on MetroMumble Theme" % MUMBLE_TAG,
        " * by xPoke\", \"forked from Flat Mumble Theme by xPaw\"; The Unlicense / WTFPL) recoloured into",
        " * the dram's paper and inks: selection and hover are paper shades, the focus ring and the",
        " * selected tab's rule the accent. Images resolve from Mumble's own skin (skin:controls/...).",
        " */",
    ]
    tail = [
        "",
        "/* Letterpress: the focus ring and the selected tab are the accent ink, as a rule */",
        "QCheckBox::indicator:focus,",
        "QTreeView::indicator:focus,",
        "QRadioButton::indicator:focus,",
        "QComboBox:focus,",
        "QLineEdit:focus,",
        "QTextEdit:focus,",
        "QPlainTextEdit:focus,",
        "QSpinBox:focus,",
        "QAbstractSpinBox:focus,",
        "QComboBox:editable:focus {",
        "  border-color: %s;" % t.accent,
        "}",
        "",
        "QTabBar::tab:top:selected {",
        "  border-bottom: 2px solid %s;" % t.accent,
        "}",
    ]
    return "\n".join(head) + "\n" + rest.rstrip("\n") + "\n" + "\n".join(tail) + "\n"


def mumble_ini(t):
    style = "Lite" if t.light else "Dark"
    return "[theme]\nname=Letterpress\nstyles=%s\n\n[%s]\nname=%s\nqss=Letterpress.qss\n" % (
        style.lower(), style.lower(), style)


# ---- Halloy -------------------------------------------------------------------------------
def halloy_toml(t):
    c, a, k = t.c, t.ansi, t.ink

    def q(h):
        return '"%s"' % h
    sections = [
        ("general", [("background", q(c["base"])), ("border", q(c["surface1"])),
                     ("horizontal_rule", q(c["surface1"])), ("horizontal_rule_text", q(c["subtext"])),
                     ("scrollbar", q(c["surface1"])), ("unread_indicator", q(t.accent)),
                     ("highlight_indicator", q(k["yellow"]))]),
        ("text", [("primary", q(c["text"])), ("secondary", q(c["subtext"])), ("tertiary", q(k["type"])),
                  ("success", q(k["green"])), ("error", q(c["red"])), ("warning", q(k["yellow"])),
                  ("info", q(k["type"])), ("debug", q(c["mauve"])), ("trace", q(c["overlay"]))]),
        ("buffer", [("action", q(k["support"])), ("background", q(c["base"])),
                    ("background_text_input", q(c["mantle"])), ("background_title_bar", q(c["mantle"])),
                    ("border", q(c["surface1"])), ("border_selected", q(t.accent)), ("code", q(k["string"])),
                    ("focus_border", q(t.accent)), ("focus_background", q(c["mantle"])),
                    ("highlight", q(mix(c["base"], c["yellow"], 0.18))), ("nickname", q(k["type"])),
                    ("nickname_offline", q(c["overlay"])), ("self_message", q(c["text"])),
                    ("selection", q(c["surface1"])), ("timestamp", q(c["overlay"])), ("topic", q(c["subtext"])),
                    ("url", q(c["blue"])), ("backlog_rule", q(t.accent)), ("backlog_rule_text", q(t.accent)),
                    ("date_rule", q(c["surface1"])), ("date_rule_text", q(c["subtext"]))]),
        ("buffer.server_messages", [("default", '{ color = "%s", font_style = "italic" }' % c["subtext"])]),
        ("buttons.primary", [("background", q(c["base"])), ("background_hover", q(c["surface0"])),
                             ("background_selected", q(c["surface1"])), ("background_selected_hover", q(t.shade)),
                             ("border_active", q(t.accent))]),
        ("buttons.secondary", [("background", q(c["surface0"])), ("background_hover", q(c["surface1"])),
                               ("background_selected", q(t.shade)), ("background_selected_hover", q(t.shade2)),
                               ("border_active", q(t.accent))]),
        ("formatting", [("white", q(a[15])), ("black", q(a[0])), ("blue", q(a[4])), ("green", q(a[2])),
                        ("red", q(a[1])), ("brown", q(c.get("maroon", a[1]))), ("magenta", q(a[5])),
                        ("orange", q(c["peach"])), ("yellow", q(a[11])), ("lightgreen", q(a[10])),
                        ("cyan", q(a[6])), ("lightcyan", q(a[14])), ("lightblue", q(a[12])), ("pink", q(a[13])),
                        ("grey", q(c["overlay"])), ("lightgrey", q(c["subtext"]))]),
    ]
    out = ["# " + gen_note(t, "Letterpress for Halloy"),
           "# Every key the theme format has (a missing one falls back to transparent). Selected by",
           '# the root key theme = "letterpress" in config.toml (dram-windows/look.ps1).']
    for name, kv in sections:
        out += ["", "[%s]" % name] + ["%s = %s" % kv_ for kv_ in kv]
    return "\n".join(out) + "\n"


# ---- qBittorrent, calibre, Vortex, mintty ---------------------------------------------------
def qbt_config(t):
    c, k = t.c, t.ink
    p = {
        "Palette.Window": c["base"], "Palette.WindowText": c["text"], "Palette.Base": c["mantle"],
        "Palette.AlternateBase": mix(c["mantle"], c["text"], 0.03), "Palette.Text": c["text"],
        "Palette.ToolTipBase": c["surface0"], "Palette.ToolTipText": c["text"], "Palette.BrightText": t.strong,
        "Palette.Highlight": c["surface1"], "Palette.HighlightedText": c["text"], "Palette.Button": c["surface0"],
        "Palette.ButtonText": c["text"], "Palette.Link": c["blue"], "Palette.LinkVisited": c["mauve"],
        "Palette.Light": c["surface1"], "Palette.Midlight": c["surface0"], "Palette.Mid": c["mantle"],
        "Palette.Dark": c["crust"], "Palette.Shadow": c["crust"],
        "Palette.WindowTextDisabled": c["overlay"], "Palette.TextDisabled": c["overlay"],
        "Palette.ToolTipTextDisabled": c["overlay"], "Palette.BrightTextDisabled": c["overlay"],
        "Palette.HighlightedTextDisabled": c["overlay"], "Palette.ButtonTextDisabled": c["overlay"],
        "Log.TimeStamp": c["overlay"], "Log.Normal": c["text"], "Log.Info": k["type"],
        "Log.Warning": k["yellow"], "Log.Critical": c["red"], "Log.BannedPeer": c["red"],
        "RSS.ReadArticle": c["subtext"], "RSS.UnreadArticle": c["text"],
        "TransferList.Downloading": k["green"], "TransferList.StalledDownloading": mix(k["green"], c["base"], 0.35),
        "TransferList.DownloadingMetadata": k["green"], "TransferList.ForcedDownloadingMetadata": k["green"],
        "TransferList.ForcedDownloading": k["green"], "TransferList.Uploading": k["type"],
        "TransferList.StalledUploading": mix(k["type"], c["base"], 0.35), "TransferList.ForcedUploading": k["type"],
        "TransferList.QueuedDownloading": k["yellow"], "TransferList.QueuedUploading": k["yellow"],
        "TransferList.CheckingDownloading": k["support"], "TransferList.CheckingUploading": k["support"],
        "TransferList.CheckingResumeData": k["support"], "TransferList.StoppedDownloading": c["overlay"],
        "TransferList.StoppedUploading": c["subtext"], "TransferList.Moving": k["support"],
        "TransferList.MissingFiles": c["red"], "TransferList.Error": c["red"],
        "PiecesBar.Border": c["surface1"], "PiecesBar.Piece": t.accent, "PiecesBar.PartialPiece": t.accent_dim,
        "PiecesBar.MissingPiece": c["mantle"], "ProgressBar": t.accent,
    }
    return {("colors" if t.light else "colors.dark"): p}


def calibre_palette(t):
    c = t.c
    p = {
        "Window": c["base"], "WindowText": c["text"], "Base": c["mantle"],
        "AlternateBase": mix(c["mantle"], c["text"], 0.03), "Text": c["text"], "PlaceholderText": c["overlay"],
        "ToolTipBase": c["surface0"], "ToolTipText": c["text"], "BrightText": t.strong,
        "Button": c["surface0"], "ButtonText": c["text"], "Highlight": c["surface1"],
        "HighlightedText": c["text"], "Accent": t.accent, "Link": c["blue"], "LinkVisited": c["mauve"],
    }
    for key in ("WindowText", "Text", "ButtonText", "PlaceholderText", "ToolTipText", "BrightText", "HighlightedText"):
        p[key + "-disabled"] = c["overlay"]
    which = "light" if t.light else "dark"
    return {"color_palette": which, "%s_palette_name" % which: "Letterpress",
            "%s_palettes" % which: {"Letterpress": p}}


def vortex_scss(t):
    c, k = t.c, t.ink
    v = [
        ("white", t.strong), ("black", c["crust"]), ("gray-darker", c["text"]), ("gray-dark", c["subtext"]),
        ("gray", c["overlay"]), ("gray-light", c["surface1"]), ("gray-lighter", c["base"]),
        ("brand-primary", t.accent), ("brand-highlight", k["type"]), ("brand-success", k["green"]),
        ("brand-info", k["type"]), ("brand-warning", k["yellow"]), ("brand-danger", c["red"]),
        ("border-color", c["surface1"]), ("brand-bg", c["base"]), ("brand-menu", c["mantle"]),
        ("brand-secondary", t.accent), ("brand-clickable", t.accent), ("text-color", c["text"]),
        ("text-color-disabled", c["overlay"]), ("link-color", c["blue"]),
        ("link-hover-color", mix(c["blue"], c["text"], 0.3)),
    ]
    out = ["// " + gen_note(t, "Letterpress for Vortex"),
           "// The variables of Vortex's bundled themes (theme-switcher/themes/classic). Vortex keeps",
           "// its choice in its own state: pick \"letterpress\" once in Settings > Theme."]
    out += ["$%s: %s;" % kv for kv in v]
    return "\n".join(out) + "\n"


def mintty_theme(t):
    k, a = t.kitty, t.ansi
    names = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]
    out = ["# " + gen_note(t, "Letterpress for mintty (Git Bash)"),
           "ForegroundColour=" + triple(k["foreground"]),
           "BackgroundColour=" + triple(k["background"]),
           "CursorColour=" + triple(k.get("cursor", k["foreground"])),
           # the selection is a paper shade under the text's own ink, as in Windows Terminal
           "HighlightBackgroundColour=" + triple(k.get("selection_background", t.c["surface0"]))]
    out += ["%s=%s" % (n, triple(a[i])) for i, n in enumerate(names)]
    out += ["Bold%s=%s" % (n, triple(a[i + 8])) for i, n in enumerate(names)]
    return "\n".join(out) + "\n"


# ---- PowerToys and Command Palette ------------------------------------------------------------
def argb(h, a):     # "#c0442b", 0xa6 -> "#A6C0442B" (PowerToys' #AARRGGBB keys)
    return "#%02X%s" % (a, hex6(h))


def powertoys(t):
    """Per utility (its folder under %LOCALAPPDATA%\\Microsoft\\PowerToys), the colour keys of its
    settings.json as Settings.UI.Library names them at POWERTOYS_TAG; look.ps1 sets each one's
    properties.<key>.value. The accent only as a line or a pointer: the zone borders, the
    always-on-top frame (2 px, Hyprland's border), the crosshairs, the ruler's cross, a left
    click. Zones at rest and the find-my-mouse veil are paper, the zone under a window a shade."""
    c = t.c

    def rgb6(h):
        return "#" + hex6(h)
    return {
        "FancyZones": {
            "fancyzones_systemTheme": False,
            "fancyzones_zoneColor": rgb6(c["base"]),
            "fancyzones_zoneBorderColor": rgb6(t.accent),
            "fancyzones_zoneHighlightColor": rgb6(c["surface1"]),
            "fancyzones_zoneNumberColor": rgb6(c["text"]),
            "fancyzones_highlight_opacity": 50,
        },
        "AlwaysOnTop": {"frame-enabled": True, "frame-thickness": 2, "frame-color": rgb6(t.accent),
                        "frame-accent-color": False, "frame-opacity": 100},
        "FindMyMouse": {"background_color": argb(c["base"], 0x80), "spotlight_color": argb(c["text"], 0x80)},
        "MouseHighlighter": {"left_button_click_color": argb(t.accent, 0xa6),
                             "right_button_click_color": argb(c["blue"], 0xa6)},
        "MousePointerCrosshairs": {"crosshairs_color": rgb6(t.accent), "crosshairs_border_color": rgb6(c["base"])},
        "Measure Tool": {"MeasureCrossColor": rgb6(t.accent)},
    }


def cmdpal(t):
    """Command Palette's settings.json keys (SettingsModel at POWERTOYS_TAG; enums as names): its
    light or dark follows Windows, and the list sits on the theme's paper, a custom colour at
    full strength."""
    r, g, b = rgb(t.c["base"])
    return {"Theme": "Default", "ColorizationMode": "CustomColor",
            "CustomThemeColor": {"A": 255, "R": r, "G": g, "B": b}, "CustomThemeColorIntensity": 100}


# ---- TeamSpeak 3 ------------------------------------------------------------------------------
def qss(blocks):
    """[(selectors, [(property, value)])] -> Qt stylesheet rules."""
    out = []
    for sels, props in blocks:
        out.append(",\n".join(sels) + " {")
        out += ["  %s: %s;" % kv for kv in props]
        out += ["}", ""]
    return "\n".join(out)


def ts3_head(t, what, lines):
    return "\n".join(["/*", " * " + gen_note(t, "Letterpress for TeamSpeak 3, " + what)] +
                     [(" * " + s) if s else " *" for s in lines] + [" */", "", ""])


def ts3_qss(t):
    c, a, ink = t.c, t.accent, t.c["text"]
    # every paper text sits on, and the quiet ink, held to 4.5:1 (no-ops for washi)
    sel, btn = paper_under(t, c["surface1"], ink), paper_under(t, c["surface0"], ink)
    press, hover = paper_under(t, t.shade, ink), paper_under(t, t.wash, ink)
    muted = ink_on(t, ink_on(t, c["subtext"], c["mantle"]), c["base"])
    gate(t, "TeamSpeak 3", [("text", ink, c["base"]), ("text", ink, c["mantle"]), ("selected", ink, sel),
                            ("button", ink, btn), ("pressed", ink, press), ("hover", ink, hover),
                            ("muted", muted, c["base"]), ("muted", muted, c["mantle"])])
    line = "1px solid " + t.hair
    arrow = [("width", "0"), ("height", "0"), ("border-left", "4px solid transparent"),
             ("border-right", "4px solid transparent")]
    blocks = [
        (["QWidget"], [("background-color", c["base"]), ("color", ink),
                       ("selection-background-color", sel), ("selection-color", ink),
                       ("alternate-background-color", c["mantle"])]),
        (["QWidget:disabled"], [("color", c["overlay"])]),
        (["QToolTip"], [("background-color", btn), ("color", ink), ("border", line),
                        ("padding", "3px")]),
        (["QMenuBar", "QMenu"], [("background-color", c["mantle"])]),
        (["QMenu"], [("border", line)]),
        (["QMenuBar::item:selected", "QMenu::item:selected"], [("background-color", sel), ("color", ink)]),
        (["QMenu::separator"], [("height", "1px"), ("background-color", t.hair), ("margin", "3px 6px")]),
        (["QAbstractItemView"], [("background-color", c["mantle"]), ("border", line), ("outline", "0")]),
        (["QAbstractItemView::item:hover"], [("background-color", hover)]),
        (["QAbstractItemView::item:selected"], [("background-color", sel), ("color", ink)]),
        (["QHeaderView::section"], [("background-color", c["mantle"]), ("color", muted), ("border", "0"),
                                    ("border-bottom", line), ("padding", "3px 6px")]),
        (["QLineEdit", "QTextEdit", "QPlainTextEdit", "QAbstractSpinBox", "QComboBox"],
         [("background-color", c["mantle"]), ("border", line), ("padding", "2px 4px")]),
        (["QLineEdit:focus", "QTextEdit:focus", "QPlainTextEdit:focus", "QAbstractSpinBox:focus", "QComboBox:focus"],
         [("border-color", a)]),
        (["QComboBox::drop-down"], [("border", "0"), ("width", "16px")]),
        (["QComboBox::down-arrow", "QAbstractSpinBox::down-arrow"], arrow + [("border-top", "5px solid " + muted)]),
        (["QAbstractSpinBox::up-arrow"], arrow + [("border-bottom", "5px solid " + muted)]),
        (["QAbstractSpinBox::up-button", "QAbstractSpinBox::down-button"], [("border", "0"), ("width", "14px")]),
        (["QPushButton"], [("background-color", btn), ("border", line), ("padding", "3px 12px")]),
        (["QPushButton:hover"], [("background-color", sel)]),
        (["QPushButton:pressed", "QPushButton:checked"], [("background-color", press)]),
        (["QPushButton:default"], [("border-color", a)]),
        (["QToolButton"], [("background-color", "transparent"), ("border", "1px solid transparent"),
                           ("padding", "2px")]),
        (["QToolButton:hover"], [("background-color", btn), ("border-color", t.hair)]),
        (["QToolButton:pressed", "QToolButton:checked"], [("background-color", sel)]),
        (["QTabWidget::pane"], [("border", line)]),
        (["QTabBar::tab"], [("background-color", c["base"]), ("color", muted), ("border", "0"),
                            ("border-bottom", "2px solid transparent"), ("padding", "4px 12px")]),
        (["QTabBar::tab:hover"], [("color", ink)]),
        (["QTabBar::tab:selected"], [("color", ink), ("border-bottom", "2px solid " + a)]),
        (["QScrollBar:vertical"], [("background-color", c["base"]), ("width", "10px"), ("margin", "0")]),
        (["QScrollBar:horizontal"], [("background-color", c["base"]), ("height", "10px"), ("margin", "0")]),
        (["QScrollBar::handle:vertical"], [("background-color", c["surface1"]), ("min-height", "24px")]),
        (["QScrollBar::handle:horizontal"], [("background-color", c["surface1"]), ("min-width", "24px")]),
        (["QScrollBar::handle:hover"], [("background-color", c["overlay"])]),
        (["QScrollBar::add-line", "QScrollBar::sub-line"], [("width", "0"), ("height", "0"), ("border", "0")]),
        (["QScrollBar::add-page", "QScrollBar::sub-page"], [("background", "none")]),
        (["QGroupBox"], [("border", line), ("margin-top", "14px"), ("padding-top", "4px")]),
        (["QGroupBox::title"], [("subcontrol-origin", "margin"), ("left", "8px"), ("padding", "0 4px"),
                                ("color", muted)]),
        (["QCheckBox", "QRadioButton"], [("background-color", "transparent")]),
        (["QProgressBar"], [("background-color", c["mantle"]), ("border", line), ("text-align", "center")]),
        (["QProgressBar::chunk"], [("background-color", a)]),
        (["QSlider::groove:horizontal"], [("height", "2px"), ("background-color", t.hair)]),
        (["QSlider::sub-page:horizontal"], [("background-color", a)]),
        (["QSlider::handle:horizontal"], [("background-color", ink), ("width", "8px"), ("margin", "-5px 0"),
                                          ("border-radius", "4px")]),
        (["QSplitter::handle", "QMainWindow::separator"], [("background-color", t.hair)]),
        (["QStatusBar"], [("background-color", c["mantle"]), ("color", muted)]),
        (["QStatusBar::item"], [("border", "0")]),
        (["QDockWidget"], [("color", muted)]),
        (["QDockWidget::title"], [("background-color", c["mantle"]), ("padding", "4px")]),
        (["TextBrowser", "InfoFrame", "ChatLineEdit"], [("background-color", c["base"])]),
    ]
    return ts3_head(t, "the window sheet", [
        "Written for this repo, not taken from TeamSpeak's own sheets: paper and ink, selection and",
        "hover as paper shades, the accent only as a rule (the focus ring, the selected tab, the",
        "default button, a slider's filled groove, the progress bar). Pick it once: Tools > Options >",
        "Design, \"Letterpress\"; dram-windows/look.ps1 keeps the files in %APPDATA%\\TS3Client\\styles.",
    ]), qss(blocks)


def ts3_chat_qss(t):
    c, k = t.c, t.ink
    paper = c["base"]
    link, ok, warn = ink_on(t, k["type"], paper), ink_on(t, k["green"], paper), ink_on(t, k["yellow"], paper)
    bad, alert, quiet = ink_on(t, c["red"], paper), ink_on(t, t.accent, paper), ink_on(t, c["subtext"], paper)
    gate(t, "TeamSpeak 3 chat", [("link", link, paper), ("welcome", ok, paper), ("unread", warn, paper),
                                 ("error", bad, paper), ("poke", alert, paper), ("quiet", quiet, paper)])
    blocks = [
        (["p"], [("margin", "0"), ("padding", "0")]),
        (["a", ".TextMessage_UserLink", ".TextMessage_ChannelLink", ".TextMessage_ServerLink",
          ".InfoFrame_Title .TextMessage_UserLink", ".InfoFrame_Title .TextMessage_ChannelLink",
          ".InfoFrame_Title .TextMessage_ServerLink", ".InfoFrame_Title .InfoFrame_CustomNick"],
         [("color", link), ("text-decoration", "none")]),
        (["a:hover"], [("text-decoration", "underline")]),
        ([".TextMessage_OfflineLink"], [("color", warn), ("text-decoration", "none")]),
        ([".TextMessage_Welcome", ".TextMessage_HostMessage", ".TextMessage_HostMsg"], [("color", ok)]),
        ([".TextMessage_Poke"], [("color", alert)]),
        ([".TextMessage_ChannelEdited", ".TextMessage_ChannelMoved", ".TextMessage_ServerEdited",
          ".TextMessage_ChannelCreated", ".TextMessage_ChannelDeleted", ".TextMessage_GroupAssigned",
          ".TextMessage_GroupRevoked", ".TextMessage_TalkPowerRequested", ".TextMessage_TalkPowerAssigned",
          ".TextMessage_TalkPowerRevoked"], [("color", link)]),
        ([".TextMessage_Normal", ".TextMessage_Connected", ".TextMessage_Disconnected",
          ".TextMessage_ClientConnected", ".TextMessage_ClientDisconnected", ".TextMessage_ClientJoined",
          ".TextMessage_ClientLeft", ".TextMessage_ClientSwitched", ".TextMessage_ClientDropped",
          ".TextMessage_Time"], [("color", quiet)]),
        ([".TextMessage_ClientKicked", ".TextMessage_ClientBanned", ".TextMessage_ServerError"], [("color", bad)]),
        ([".TextMessage_BeginHistory", ".TextMessage_EndHistory"], [("color", quiet), ("font-style", "italic")]),
        ([".InfoFrame_Title"], [("font-size", "x-large")]),
        ([".InfoFrame_Table"], [("border-collapse", "collapse"), ("border-spacing", "0px")]),
        ([".InfoFrame_Table td"], [("padding", "0px 4px 0px 1px")]),
        ([".InfoFrame_Table td.Label"], [("color", quiet)]),
        ([".InfoFrame_Table td.Bottom"], [("vertical-align", "bottom")]),
        ([".InfoFrame_Table td.List"], [("padding", "0px 1px 0px 8px")]),
        ([".InfoFrame_Table td.Space-Top"], [("padding", "10px 0px 0px 0px")]),
        ([".InfoFrame_Table td.Space-Bot"], [("padding", "0px 0px 10px 0px")]),
        ([".InfoFrame_Table.Space-Top"], [("margin", "10px 0px 0px 0px")]),
        ([".InfoFrame_Table.Space-Bot"], [("margin", "0px 0px 10px 0px")]),
        ([".Highlight", ".InfoFrame_Table td.Highlight"], [("color", link)]),
        ([".Important", ".InfoFrame_Table td.Important"], [("color", bad)]),
        ([".Active", ".InfoFrame_Table td.Active"], [("color", ok)]),
        ([".Inactive", ".InfoFrame_Table td.Inactive"], [("color", quiet)]),
    ]
    return ts3_head(t, "the chat and info frame sheet", [
        "The rich text of the chat log and the info frame, by the classes TeamSpeak documents in",
        "its default_chat.qss: names and links in the type ink, joins and leaves quiet, kicks and",
        "errors red, a poke the accent; no bold. Every ink reads at 4.5:1 on the paper.",
    ]), qss(blocks)


def ts3_sheets(t):
    """name -> text: each sheet, and its dark-mode twin with the same rules. TeamSpeak 3.6 adds
    <style>_darkmode.qss (and _chat_darkmode.qss) while Windows is dark; its changelog calls them
    extensions, layered over the sheet, but repeating the rules holds the theme either way, and
    a style without them may get the default style's dark sheets instead (as _chat.qss falls
    back to default_chat.qss)."""
    out = {}
    for name, (head, rules) in (("Letterpress", ts3_qss(t)), ("Letterpress_chat", ts3_chat_qss(t))):
        out[name + ".qss"] = head + rules
        out[name + "_darkmode.qss"] = ts3_head(t, "%s again for dark mode" % (name + ".qss"), [
            "TeamSpeak 3.6 and later add <style>_darkmode.qss (and _chat_darkmode.qss) while Windows",
            "is dark. This repeats %s.qss, so the theme holds whether TeamSpeak layers it" % name,
            "over that sheet or reads it alone.",
        ]) + rules
    return out


# ---- nomacs -----------------------------------------------------------------------------------
def nomacs_name(t):
    return "Letterpress-%s.css" % ("Light" if t.light else "Dark")


def nomacs_css(t):
    c = t.c
    stock = "Light-Theme.css" if t.light else "Dark-Theme.css"
    sel = paper_under(t, c["surface1"], c["text"])
    gate(t, "nomacs", [("foreground", c["text"], c["base"]), ("selection", c["text"], sel)])
    out = [
        "/* " + gen_note(t, "Letterpress for nomacs") + " */",
        "/* nomacs's own %s from the same themes folder, then the theme's paper and" % stock,
        " * ink: the colour lines below come after its own, so they win (DkThemeManager at 3.22.4).",
        " * Selection is a paper shade; HIGHLIGHT (the accent) keeps nomacs's own uses, the checked",
        " * tab's edge, a focused box, a pressed button. \"Dark\" in the name gives a dark title bar.",
        " * Selected by settings.ini [DisplaySettings] themeName312 (dram-windows/look.ps1). */",
        "",
        '/* nomacs-include "%s" */' % stock,
    ]
    colors = [("BACKGROUND_COLOR", c["base"]), ("FOREGROUND_COLOR", c["text"]), ("ICON_COLOR", c["text"]),
              ("HIGHLIGHT_COLOR", t.accent), ("HUD_BACKGROUND_COLOR", "#cc" + c["base"].lstrip("#")),
              ("HUD_FOREGROUND_COLOR", c["text"]), ("SLIDESHOW_COLOR", c["base"])]
    out += ["/* nomacs-color %-20s %s */" % kv for kv in colors]
    out += ["", "* {", "    selection-color: %s;" % c["text"],
            "    selection-background-color: %s;" % sel, "}"]
    return "\n".join(out) + "\n"


def nomacs_settings(t):
    """settings.ini keys (DkSettings at 3.22.4): the theme, and its colours not overridden by
    colours picked in nomacs's own preferences (default*Color true: the theme's are used)."""
    return {"DisplaySettings": {"themeName312": nomacs_name(t), "defaultBackgroundColor": "true",
                                "defaultForegroundColor": "true", "defaultIconColor": "true"},
            "SlideShowSettings": {"defaultBackgroundColor": "true"}}


# ---- WinDirStat, RuneLite -----------------------------------------------------------------------
def windirstat(t):
    """HKCU\\Software\\WinDirStat\\WinDirStat\\<section> values (Options.h at release/v2.9.3): the
    file tree's depth bars in the theme's inks, the treemap's selection frame in the accent (a
    rule), its grid a paper shade. A colour is a COLORREF as WinDirStat keeps it, REG_BINARY
    R, G, B, 0; the count a DWORD. Its dark palette itself is fixed and follows Windows."""
    c, k = t.c, t.ink

    def cref(h):
        return list(rgb(h)) + [0]
    bars = [t.accent, k["yellow"], c["blue"], c["teal"], k["green"], c["subtext"], c["overlay"], t.accent_dim]
    tree = {"FileTreeColor%d" % i: cref(h) for i, h in enumerate(bars)}
    tree["FileTreeColorCount"] = len(bars)
    return {"FileTreeView": tree,
            "TreeMapView": {"TreeMapHighlightColor": cref(t.accent), "TreeMapGridColor": cref(c["surface1"])}}


def runelite(t):
    """runelite.overlayBackgroundColor for every RuneLite profile (RuneLiteConfig): the paper at
    RuneLite's own overlay alpha (156, ComponentConstants), as Color.getRGB() writes it, a signed
    ARGB integer; the client's own look is fixed."""
    r, g, b = rgb(t.c["base"])
    return {"runelite.overlayBackgroundColor": str(s32((156 << 24) | (r << 16) | (g << 8) | b))}


# ---- Wireshark ----------------------------------------------------------------------------------
# Wireshark's stock colouring rules, by name: (the row's paper, its ink). A paper is a palette key,
# or (a hue, how much of it goes into the base). Errors keep upstream's look, coloured ink on the
# darkest paper; the rest are faint tints of the paper under the body ink. A rule upstream adds or
# drops fails the build until it is mapped here.
WS_RULES = {
    "Bad TCP": ("crust", "red"),
    "HSRP State Change": (("yellow", 0.22), "text"),
    "Spanning Tree Topology  Change": (("yellow", 0.22), "text"),
    "OSPF State Change": (("yellow", 0.22), "text"),
    "ICMP errors": ("crust", "green"),
    "ARP": (("yellow", 0.10), "text"),
    "ICMP": (("pink", 0.16), "text"),
    "TCP RST": (("red", 0.38), "text"),
    "SCTP ABORT": (("red", 0.38), "text"),
    "IPv4 TTL low or unexpected": (("red", 0.24), "text"),
    "IPv6 hop limit low or unexpected": (("red", 0.24), "text"),
    "Checksum Errors": ("crust", "red"),
    "SMB": (("yellow", 0.14), "text"),
    "HTTP": (("green", 0.20), "text"),
    "DCERPC": (("mauve", 0.20), "text"),
    "Routing": (("peach", 0.16), "text"),
    "TCP SYN/FIN": ("surface1", "text"),
    "TCP": (("blue", 0.14), "text"),
    "UDP": (("sky", 0.12), "text"),
    "Broadcast": ("base", "subtext"),
    "System Event": ("surface0", "blue"),
}


def ws16(h):        # "#c0442b" -> "49344,17476,11051" (the 16-bit components colorfilters keeps)
    return ",".join(str(v * 257) for v in rgb(h))


def wireshark_colorfilters(t):
    c = t.c
    out = ["# " + gen_note(t, "Letterpress colouring rules for Wireshark"),
           "# Wireshark %s's own rules (resources/share/wireshark/colorfilters, GPL-2.0-or-later), the filters" % WIRESHARK_TAG,
           "# as they are, recoloured by rule name (WS_RULES); every ink reads at 4.5:1 on its row. Kept",
           "# in Wireshark's profile folder by dram-windows/look.ps1, so a rule edited in Wireshark is",
           "# put back at the next converge."]
    pairs, seen = [], set()
    for line in vendored("wireshark/colorfilters").splitlines():
        if not line.startswith("@"):
            continue    # upstream's "DO NOT EDIT" comment
        m = re.match(r"^@([^@]*)@([^@]*)@\[[\d,]+\]\[[\d,]+\]$", line)
        if not m:
            raise InputError("Wireshark colorfilters: a rule not in @name@filter@[bg][fg] form: %r" % line[:60])
        name, flt = m.groups()
        if name not in WS_RULES:
            raise InputError("Wireshark colorfilters has rule %r, which WS_RULES does not map" % name)
        seen.add(name)
        spec, key = WS_RULES[name]
        paper = mix(c["base"], c[spec[0]], spec[1]) if isinstance(spec, tuple) else c[spec]
        # the ink first; the paper moves only where even the body ink would not read on it
        paper = paper_under(t, paper, ink_on(t, c[key], paper))
        ink = ink_on(t, c[key], paper)
        pairs.append((name, ink, paper))
        out.append("@%s@%s@[%s][%s]" % (name, flt, ws16(paper), ws16(ink)))
    gone = sorted(set(WS_RULES) - seen)
    if gone:
        raise InputError("WS_RULES maps rules Wireshark %s does not ship: %s" % (WIRESHARK_TAG, gone))
    gate(t, "Wireshark colouring rules", pairs)
    return "\n".join(out) + "\n"


def wireshark_prefs(t):
    """%APPDATA%\\Wireshark\\preferences keys (epan/prefs.c at WIRESHARK_TAG), each value as Wireshark
    writes it back (colours rrggbb, an enum by its description), so a converge after a save is
    quiet: the scheme follows Windows; the packet panes in Monaspace Xenon; the selected row a
    paper shade drawn FLAT (the style's default is the accent as a fill); a marked packet the
    accent in the paper; the Follow Stream pair; the filter bar's three states."""
    c, k = t.c, t.ink

    def h(x):
        return hex6(x).lower()
    ink = c["text"]
    sel, marked = paper_under(t, c["surface1"], ink), paper_under(t, mix(c["base"], t.accent, 0.45), ink)
    unfocused, ignored = ink_on(t, c["subtext"], c["surface0"]), ink_on(t, c["subtext"], c["mantle"])
    client_bg, server_bg = mix(c["base"], t.accent, 0.12), mix(c["base"], c["blue"], 0.14)
    client, server = ink_on(t, k["numbers"], client_bg), ink_on(t, c["blue"], server_bg)
    valid, invalid, deprecated = (paper_under(t, mix(c["base"], c[hue], k_), ink)
                                  for hue, k_ in (("green", 0.35), ("red", 0.40), ("yellow", 0.35)))
    gate(t, "Wireshark", [("selected", ink, sel), ("selected, unfocused", unfocused, c["surface0"]),
                          ("marked", ink, marked), ("ignored", ignored, c["mantle"]),
                          ("stream client", client, client_bg), ("stream server", server, server_bg),
                          ("filter valid", ink, valid), ("filter invalid", ink, invalid),
                          ("filter deprecated", ink, deprecated)])
    return {
        "gui.color_scheme": "System Default",
        "gui.qt.font_name": "%s,10" % MONO,
        "gui.active_frame.fg": h(ink), "gui.active_frame.bg": h(sel),
        "gui.active_frame.style": "FLAT",
        "gui.inactive_frame.fg": h(unfocused), "gui.inactive_frame.bg": h(c["surface0"]),
        "gui.inactive_frame.style": "FLAT",
        "gui.marked_frame.fg": h(ink), "gui.marked_frame.bg": h(marked),
        "gui.ignored_frame.fg": h(ignored), "gui.ignored_frame.bg": h(c["mantle"]),
        "gui.stream.client.fg": h(client), "gui.stream.client.bg": h(client_bg),
        "gui.stream.server.fg": h(server), "gui.stream.server.bg": h(server_bg),
        "gui.color_filter_fg.valid": h(c["text"]), "gui.color_filter_bg.valid": h(valid),
        "gui.color_filter_fg.invalid": h(c["text"]), "gui.color_filter_bg.invalid": h(invalid),
        "gui.color_filter_fg.deprecated": h(c["text"]), "gui.color_filter_bg.deprecated": h(deprecated),
    }


# ---- the masthead: Waybar's bar as a Zebar widget pack ------------------------------------------
# The masthead: a top bar over a hidden taskbar. Zebar (GPL-3.0, glzr.io) draws a widget per monitor
# in a WebView2 that its own asset server (127.0.0.1:6124, token-gated) serves from
# %USERPROFILE%\.glzr\zebar\<pack>\, so the bar is real HTML and CSS: Literata's small caps and
# tabular figures as in Waybar. Read from Zebar 3.3.1's source: a pack is <dir>\zpack.json, its id
# the pack's name (widget_pack.rs); settings.json's startupConfigs open it at start
# (app_settings.rs); dockToEdge reserves the edge through SHAppBarMessage (app_bar.rs); there is
# no fullscreen handling, so the bar sits in the normal z-order and a game covers it.
ZEBAR = "3.3.1"            # windows/packages.nix pins it: masthead.js speaks its IPC (npm zebar@3.3.1's client)
ZEBAR_PACK, ZEBAR_WIDGET, ZEBAR_PRESET = "letterpress", "masthead", "top"
ZEBAR_TRAY = True          # the tray icons: Zebar's spy window (a second Shell_TrayWnd; nothing injected)
WAYBAR = os.path.join(ROOT, "dotfiles", ".config", "waybar")
# Waybar's modules (config.jsonc's external bar, its groups) -> the masthead's; [] = no Windows
# source yet. A Waybar module missing here stops the generator, so the bars cannot drift apart.
WAYBAR_TO_MASTHEAD = {
    "custom/nameplate": ["seal", "host"],   # the nameplate: the "pj" seal and the PC's name
    "hyprland/workspaces": [],              # "No n": GlazeWM's provider, held (glzr-io/glazewm#1443)
    "hyprland/window": [],                  # the window title: no provider without a window manager
    "clock": ["clock"],
    "custom/date": ["date"],
    "custom/notification": [],              # the pilcrow: no notification provider
    "mpris": ["media"],
    "privacy": [],                          # no capture provider
    "hyprland/language": ["layout"],
    "cpu": ["cpu"],
    "memory": ["memory"],
    "custom/cputemp": [],                   # no sensor provider: the case panel shows it (decisions/log.md#d123)
    "network": ["network"],
    "bluetooth": [], "idle_inhibitor": [], "power-profiles-daemon": [], "custom/usb": [],
    "pulseaudio": ["volume"],
    "battery": ["battery"],
    "custom/updates": [],
}
# provider refresh (ms) where Waybar sets no interval of its own
MASTHEAD_EVERY = {"host": 3600000, "network": 10000, "layout": 1000, "battery": 60000}
MASTHEAD_FILES = ("masthead.html", "masthead.css", "masthead.js")
# the page reaches nothing but its own files and Zebar's IPC; the CSP and the check below hold it there
MASTHEAD_CSP = ("default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' blob: data:; "
                "font-src 'self'; connect-src 'self' ipc: http://ipc.localhost; object-src 'none'; "
                "base-uri 'none'; form-action 'none'")
REMOTE = re.compile(r"\b(?:https?|wss?|ftp)://[^\s\"'<>;)]*", re.I)


def load_jsonc(path):
    # Waybar's JSONC: // comments on their own lines (bin/check-waybar.py's rule)
    with open(path, encoding="utf-8") as f:
        return json.loads(re.sub(r"^\s*//.*$", "", f.read(), flags=re.M))


def waybar_masthead():
    """Waybar's external bar, read for the masthead: the layout (left/center/right; a group is
    {name: [modules]}), the caption words, the intervals, the date's locale."""
    rel = "dotfiles/.config/waybar/"
    try:
        bars = load_jsonc(os.path.join(WAYBAR, "config.jsonc"))
        mods = load_jsonc(os.path.join(WAYBAR, "modules.jsonc"))
    except (OSError, ValueError) as e:
        raise InputError("%s: %s" % (rel, e))
    bar = next((b for b in bars if b.get("name") == "external"), None)
    if bar is None:
        raise InputError(rel + "config.jsonc has no \"external\" bar")

    def mapped(name):
        if name.startswith("group/"):
            inner = [x for n in mods.get(name, {}).get("modules", []) for x in mapped(n)]
            return [{name[len("group/"):]: inner}] if inner else []
        if name not in WAYBAR_TO_MASTHEAD:
            raise InputError("waybar module %r has no masthead counterpart: map it in WAYBAR_TO_MASTHEAD" % name)
        return WAYBAR_TO_MASTHEAD[name]
    layout = {side: [x for n in bar.get("modules-" + side, []) for x in mapped(n)]
              for side in ("left", "center", "right")}
    if ZEBAR_TRAY:
        layout["right"].append("tray")

    def fmt(module, key):
        return mods.get(module, {}).get(key, "")

    def faded(module, key="format"):   # the caption word: <span alpha='55%'>word</span>
        m = re.search(r"<span alpha='55%'>([^<{]+)</span>", fmt(module, key))
        if not m:
            raise InputError("%smodules.jsonc: %s %s has no faded caption word" % (rel, module, key))
        return m.group(1)

    def state(module, key):            # a state word in full ink: нет сети, тихо
        m = re.search(r"<span font_features='smcp, lnum, tnum'>([^<{]+)</span>", fmt(module, key))
        if not m:
            raise InputError("%smodules.jsonc: %s %s has no state word" % (rel, module, key))
        return m.group(1)
    words = {"cpu": faded("cpu"), "memory": faded("memory"), "network": faded("network", "format-wifi"),
             "offline": state("network", "format-disconnected"), "volume": faded("pulseaudio"),
             "muted": state("pulseaudio", "format-muted"), "battery": faded("battery")}
    every = dict(MASTHEAD_EVERY)
    for module in ("cpu", "memory"):
        every[module] = int(mods.get(module, {}).get("interval", 5)) * 1000
    locale = mods.get("clock", {}).get("locale", "en_US").split(".")[0].replace("_", "-")
    mpris = mods.get("mpris", {})
    media = {"max": int(mpris.get("dynamic-len", 36)), "separator": mpris.get("dynamic-separator", " - ")}
    states = mods.get("battery", {}).get("states", {})
    battery = {"warning": int(states.get("warning", 30)), "critical": int(states.get("critical", 15))}
    return {"layout": layout, "words": words, "every": every, "locale": locale, "media": media,
            "battery": battery, "height": int(bar.get("height", 44))}


def zebar_settings():
    # byte for byte what Zebar writes itself (serde_json's pretty form), so it never rewrites it
    return {"$schema": "https://github.com/glzr-io/zebar/raw/v%s/resources/settings-schema.json" % ZEBAR,
            "startupConfigs": [{"pack": ZEBAR_PACK, "widget": ZEBAR_WIDGET, "preset": ZEBAR_PRESET}]}


def zebar_zpack(height):
    # zebar 3.3.1's WidgetPackConfig, its own field order; transparent: no white frame before the
    # page paints its paper; normal z-order: a fullscreen game covers the bar; nothing remote to
    # cache; no shell command the page may run; one bar per monitor, Waybar's height, the top
    # edge reserved
    return {
        "$schema": "https://github.com/glzr-io/zebar/raw/v%s/resources/zpack-schema.json" % ZEBAR,
        "name": ZEBAR_PACK,
        "version": VERSION,
        "description": "The Letterpress masthead: Waybar's bar on Windows, one per monitor. "
                       "GENERATED by bin/gen-windows-look.py; do not edit.",
        "tags": ["topbar", "letterpress"],
        "previewImages": [],
        "repositoryUrl": "",
        "widgets": [{
            "name": ZEBAR_WIDGET,
            "htmlPath": "./" + MASTHEAD_FILES[0],
            "zOrder": "normal",
            "shownInTaskbar": False,
            "focused": False,
            "resizable": False,
            "transparent": True,
            "includeFiles": list(MASTHEAD_FILES),
            "caching": {"defaultDuration": 0, "rules": []},
            "privileges": {"shellCommands": []},
            "presets": [{
                "name": ZEBAR_PRESET,
                "anchor": "top_left",
                "offsetX": "0px",
                "offsetY": "0px",
                "width": "100%",
                "height": "%dpx" % height,
                "monitorSelection": {"type": "all"},
                "dockToEdge": {"enabled": True, "edge": "top", "windowMargin": "0px"},
            }],
        }],
    }


def masthead_html(t):
    return "\n".join([
        "<!doctype html>",
        "<!-- " + gen_note(t, "masthead.html, the Letterpress masthead (Zebar)"),
        "     The CSP holds the page to its own files and Zebar's IPC: nothing comes from the network. -->",
        '<html lang="ru">',
        "<head>",
        '<meta charset="utf-8">',
        '<meta http-equiv="Content-Security-Policy" content="%s">' % MASTHEAD_CSP,
        "<title>Letterpress masthead</title>",
        '<link rel="stylesheet" href="%s">' % MASTHEAD_FILES[1],
        '<script type="module" src="%s"></script>' % MASTHEAD_FILES[2],
        "</head>",
        "<body>",
        '<div class="bar"><div class="left" id="left"></div><div class="center" id="center"></div>'
        '<div class="right" id="right"></div></div>',
        "</body>",
        "</html>",
    ]) + "\n"


MASTHEAD_CSS = r"""
/* Waybar's style.css in a WebView: the bar is the running head of a printed page, a strip of
   paper closed by ONE hairline; no islands, pills, blur or icons, type does the work. Literata
   sets the words (captions in its small caps, figures lining and tabular), EB Garamond the
   display (the host and the clock: Fraunces's roles; fonts.pin brings no Fraunces to Windows) and the
   italic voice (the date, now playing). The accent is a rule, never a fill: under a module that
   does something when hovered, and the seal's ring. Every gap is set here, as in Waybar. */

*, *::before, *::after { box-sizing: border-box; }
[hidden] { display: none !important; }

html, body {
  margin: 0;
  height: 100%;
  overflow: hidden;
  background: var(--base);
  color: var(--text);
  font-family: "Literata", "EB Garamond", serif;
  font-size: 16px;
  cursor: default;
  user-select: none;
}

.bar {
  display: grid;
  grid-template-columns: 1fr auto 1fr;
  height: 100%;
  border-bottom: 1px solid var(--rule);
}
.left, .center, .right { display: flex; min-width: 0; overflow: hidden; padding: 0 6px; }
.center { justify-content: center; }
.right { justify-content: flex-end; }
.g { display: flex; }

/* the shared rhythm: each module a run of type sitting on the masthead rule; margin 0 7px (14 px
   rail to rail), padding 0 6px (what the hover rule spans); the transparent border keeps the
   1 px the rule takes, so nothing moves on hover */
.m {
  display: flex;
  align-items: center;
  justify-content: center;
  margin: 0 7px;
  padding: 0 6px;
  border-bottom: 1px solid transparent;
  white-space: nowrap;
  transition: border-color 0.15s ease, color 0.15s ease;
}
.act:hover { border-bottom-color: var(--accent); }

/* the house caption span: small caps, lining tabular figures; the caption word faded; the
   figure keeps its leading space (a flex item would drop it) */
.cap { font-feature-settings: "smcp", "lnum", "tnum"; }
.w { color: var(--faint); }
.f { white-space: pre; }

/* section ticks: 20 px of hairline before a section's first module, drawn as a background so the
   box, and its hover rule, stays level with its neighbours */
.date, .layout, .readouts, .tools, .volume, .tray {
  background-image: linear-gradient(var(--rule), var(--rule));
  background-size: 1px 20px;
  background-repeat: no-repeat;
  background-position: left center;
  padding-left: 12px;
}
/* a group carries the tick; its first module keeps its own 7 + 6 */
.readouts, .tools, .tray { padding-left: 0; margin-left: 7px; }

/* LEFT: Waybar's nameplate on Windows - the seal, then the PC's name */
.seal { margin-left: 6px; margin-right: 0; padding-right: 4px; }
.seal .mark {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 26px;
  height: 26px;
  padding-bottom: 3px;
  border: 1.5px solid var(--accent);
  border-radius: 50%;
  color: var(--accent);
  font-family: "EB Garamond", serif;
  font-style: italic;
  font-weight: 500;
  font-size: 16px;
  line-height: 1;
}
.host { margin-left: 0; font-family: "EB Garamond", "Literata", serif; font-weight: 500; font-size: 17px; }

/* CENTRE: the clock is the headline, the date its dateline - one unit, 5 + 6 px apart with the
   date's tick between */
.clock {
  margin-right: 0;
  padding-right: 5px;
  font-family: "EB Garamond", "Literata", serif;
  font-weight: 600;
  font-size: 21px;
  font-feature-settings: "lnum", "tnum";
}
.date {
  margin-left: 0;
  padding-left: 6px;
  font-family: "EB Garamond", "Literata", serif;
  font-style: italic;
  font-size: 17px;
  color: var(--subtext);
}

/* RIGHT: now playing, the layout, readouts, tools, the device, the tray */
.media { font-family: "EB Garamond", "Literata", serif; font-style: italic; color: var(--subtext); }
.media.paused { opacity: 0.55; }
/* digits change width; the columns must not */
.cpu, .memory, .volume, .battery { min-width: 64px; }
/* the tray's icons in the ink until hovered */
.tray .m { margin: 0 3px; padding: 0 4px; }
.tray img { width: 16px; height: 16px; filter: grayscale(1); opacity: 0.7; transition: filter 0.15s ease, opacity 0.15s ease; }
.tray .m:hover img { filter: none; opacity: 1; }

/* alerts: the only colour besides the accent */
.alert { color: var(--red); }
.battery.warning { color: var(--yellow); }
.battery.critical { color: var(--red); }
.battery.charging { color: var(--green); }
@keyframes blink { to { color: var(--red); border-bottom-color: var(--red); } }
.battery.critical:not(.charging) { animation: blink 1s linear infinite alternate; }
"""


def masthead_css(t):
    c = t.c
    r, g, b = rgb(c["text"])
    root = [("--base", c["base"]), ("--text", c["text"]), ("--subtext", c["subtext"]),
            ("--accent", t.accent),
            ("--rule", "rgba(%d, %d, %d, 0.18)" % (r, g, b)),    # Waybar's @rule: alpha(@text, .18)
            ("--faint", "rgba(%d, %d, %d, 0.55)" % (r, g, b)),   # @faint: alpha(@text, .55)
            ("--red", c["red"]), ("--yellow", c["yellow"]), ("--green", c["green"])]
    head = ["/* " + gen_note(t, "masthead.css") + " */", ":root {"]
    head += ["  %s: %s;" % kv for kv in root]
    return "\n".join(head) + "\n}\n" + MASTHEAD_CSS


MASTHEAD_JS = r"""
const tauri = window.__TAURI_INTERNALS__;
const W = CONFIG.words;
const NNBSP = '\u202f';   // between a figure and its unit: "8 %"
const ELLIPSIS = '\u2026';
const MIDDOT = '\u00b7';
const UP = '\u2191';

function el(tag, cls, text) {
  const node = document.createElement(tag);
  if (cls) node.className = cls;
  if (text !== undefined) node.textContent = text;
  return node;
}

// a group (Waybar's group/readouts, group/tools; the tray) shows while one of its modules does
function fit(group) {
  group.hidden = !Array.prototype.some.call(group.children, function (c) { return !c.hidden; });
}

function show(node, on) {
  node.hidden = !on;
  const g = node.parentElement;
  if (g && g.classList.contains('g')) fit(g);
}

// ---- Zebar's IPC -------------------------------------------------------------------------------
// Zebar 3.3.1's own client (npm zebar@3.3.1, dist/index.js: desktopCommands, onProviderEmit) cut to
// the three calls the bar makes, over @tauri-apps/api 2.x's invoke() and event.listen(): Tauri puts
// window.__TAURI_INTERNALS__ into a page served from 127.0.0.1:6124 (Zebar's
// capabilities/widget.json). A provider is keyed by its config, so the bars on every monitor share
// one; an emission is {configHash, result: {output} or {error}}.
const handlers = new Map();
let listening = null;

function invoke(cmd, args) {
  return tauri.invoke(cmd, args || {});
}

function provider(config, render) {
  if (!tauri) return Promise.resolve();
  const hash = JSON.stringify([config]);
  handlers.set(hash, function (result) {
    render(result && 'output' in result ? result.output : null, hash);
  });
  if (!listening) {
    listening = invoke('plugin:event|listen', {
      event: 'provider-emit',
      target: { kind: 'Any' },
      handler: tauri.transformCallback(function (event) {
        const p = event && event.payload;
        const h = p && handlers.get(p.configHash);
        if (h) h(p.result);
      }),
    });
  }
  return listening
    .then(function () { return invoke('listen_provider', { configHash: hash, config: config }); })
    .catch(function (err) {
      console.warn('[masthead] ' + config.type + ': ' + err);
      render(null, hash);
    });
}

function call(hash, type, name, args) {
  return invoke('call_provider_function', { configHash: hash, function: { type: type, function: { name: name, args: args } } })
    .catch(function (err) { console.warn('[masthead] ' + type + ' ' + name + ': ' + err); });
}

// ---- readouts ----------------------------------------------------------------------------------
// the house caption: the word faded, the figure in full ink; an alert is the whole word in full
// ink, coloured (style: .alert)
function readout(cls) {
  const m = el('span', 'm cap ' + cls);
  const w = el('span', 'w');
  const f = el('span', 'f');
  m.append(w, f);
  m.hidden = true;
  return {
    m: m,
    figure: function (word, figure) {
      w.textContent = word;
      f.textContent = figure === undefined ? '' : ' ' + figure;
      m.classList.remove('alert');
      show(m, true);
    },
    alert: function (word) {
      w.textContent = '';
      f.textContent = word;
      m.classList.add('alert');
      show(m, true);
    },
    hide: function () { show(m, false); },
  };
}

function pct(n) { return Math.round(n) + NNBSP + '%'; }
function gib(b) { return (b / 1073741824).toFixed(1) + 'G'; }

// ---- the clock: local time, no provider ----------------------------------------------------------
let clock = null;
let date = null;
let timer = 0;
const DAY = new Intl.DateTimeFormat(CONFIG.locale, { weekday: 'long', day: 'numeric', month: 'long' });
const FULL = new Intl.DateTimeFormat(CONFIG.locale, { dateStyle: 'full' });

function two(n) { return (n < 10 ? '0' : '') + n; }

function tick() {
  const now = new Date();
  if (clock) clock.textContent = two(now.getHours()) + ':' + two(now.getMinutes());
  if (date) {
    date.textContent = DAY.format(now);
    date.title = FULL.format(now);
  }
  clearTimeout(timer);
  timer = setTimeout(tick, 60050 - now.getSeconds() * 1000 - now.getMilliseconds());
}

// ---- the tray: Zebar's systray provider ---------------------------------------------------------
function trayIcon(id, hash) {
  const m = el('span', 'm act');
  const img = el('img');
  img.alt = '';
  img.draggable = false;
  m.append(img);
  let moved = 0;
  function send(name) { call(hash, 'systray', name, { iconId: id }); }
  m.addEventListener('click', function () { send('icon_left_click'); });
  m.addEventListener('dblclick', function () { send('icon_left_double_click'); });
  m.addEventListener('contextmenu', function (e) { e.preventDefault(); send('icon_right_click'); });
  m.addEventListener('mousedown', function (e) { if (e.button === 1) e.preventDefault(); });
  m.addEventListener('auxclick', function (e) { if (e.button === 1) send('icon_middle_click'); });
  m.addEventListener('mouseenter', function () { send('icon_hover_enter'); });
  m.addEventListener('mouseleave', function () { send('icon_hover_leave'); });
  m.addEventListener('mousemove', function () {
    const now = Date.now();
    if (now - moved > 100) { moved = now; send('icon_hover_move'); }
  });
  return { m: m, img: img, hash: null, url: null };
}

// ---- the modules, by the names CONFIG.layout uses -----------------------------------------------
// A module is added here and mapped in the generator's WAYBAR_TO_MASTHEAD. The workspace numeral
// ("No n" in the accent: Waybar's hyprland/workspaces) waits for GlazeWM, held for its IPC
// (glzr-io/glazewm#1443): its builder would query GlazeWM on 127.0.0.1 port 6123 itself, and that
// origin would join the CSP's connect-src in masthead.html.
const BUILD = {
  seal: function () {
    const m = el('span', 'm seal');
    m.append(el('span', 'mark', 'pj'));
    m.title = CONFIG.label;
    return m;
  },
  host: function () {
    const m = el('span', 'm host');
    m.hidden = true;
    provider({ type: 'host', refreshInterval: CONFIG.every.host }, function (o) {
      if (o && o.hostname) {
        m.textContent = o.hostname.toLowerCase();
        show(m, true);
      }
    });
    return m;
  },
  clock: function () { return (clock = el('span', 'm clock')); },
  date: function () { return (date = el('span', 'm date')); },
  media: function () {
    const m = el('span', 'm media act');
    m.hidden = true;
    let hash = null;
    let session = null;
    provider({ type: 'media' }, function (o, h) {
      hash = h;
      const s = o && o.currentSession;
      const text = s ? [s.title, s.artist].filter(Boolean).join(CONFIG.media.separator) : '';
      session = s ? s.sessionId : null;
      if (!text) { show(m, false); return; }
      m.textContent = text.length > CONFIG.media.max ? text.slice(0, CONFIG.media.max - 1) + ELLIPSIS : text;
      m.title = text;
      m.classList.toggle('paused', !s.isPlaying);
      show(m, true);
    });
    function control(name) { if (hash) call(hash, 'media', name, { sessionId: session }); }
    m.addEventListener('click', function () { control('toggle_play_pause'); });
    m.addEventListener('mousedown', function (e) { if (e.button === 1) e.preventDefault(); });
    m.addEventListener('auxclick', function (e) { if (e.button === 1) control('previous'); });
    m.addEventListener('contextmenu', function (e) { e.preventDefault(); control('next'); });
    return m;
  },
  layout: function () {
    const m = el('span', 'm cap layout');
    m.hidden = true;
    provider({ type: 'keyboard', refreshInterval: CONFIG.every.layout }, function (o) {
      if (!o || !o.layout) return;   // keep the last one: no focused window is no news
      m.textContent = o.layout.split('-')[0].toLowerCase();
      m.title = o.layout;
      show(m, true);
    });
    return m;
  },
  cpu: function () {
    const r = readout('cpu');
    provider({ type: 'cpu', refreshInterval: CONFIG.every.cpu }, function (o) {
      if (o) r.figure(W.cpu, pct(o.usage)); else r.hide();
    });
    return r.m;
  },
  memory: function () {
    const r = readout('memory');
    provider({ type: 'memory', refreshInterval: CONFIG.every.memory }, function (o) {
      if (!o) { r.hide(); return; }
      r.figure(W.memory, pct(o.usage));
      r.m.title = gib(o.usedMemory) + ' / ' + gib(o.totalMemory);
    });
    return r.m;
  },
  network: function () {
    const r = readout('network');
    provider({ type: 'network', refreshInterval: CONFIG.every.network }, function (o) {
      if (!o) { r.hide(); return; }
      const i = o.defaultInterface;
      const gw = o.defaultGateway;
      if (!i) { r.alert(W.offline); r.m.title = ''; return; }
      if (i.type === 'wifi' && gw && gw.signalStrength != null) r.figure(W.network, pct(gw.signalStrength));
      else r.figure(W.network);
      r.m.title = [i.friendlyName || i.name, (i.ipv4Addresses || [])[0]].filter(Boolean).join(' ' + MIDDOT + ' ');
    });
    return r.m;
  },
  volume: function () {
    const r = readout('volume act');
    let hash = null;
    let dev = null;
    provider({ type: 'audio' }, function (o, h) {
      hash = h;
      dev = o && o.defaultPlaybackDevice;
      if (!dev) { r.hide(); return; }
      if (dev.isMuted) r.alert(W.muted); else r.figure(W.volume, pct(dev.volume));
      r.m.title = dev.name;
    });
    // as Waybar's pulseaudio: the wheel steps 5 %, a right click mutes
    r.m.addEventListener('wheel', function (e) {
      e.preventDefault();
      if (!hash || !dev) return;
      dev.volume = Math.max(0, Math.min(100, dev.volume + (e.deltaY < 0 ? 5 : -5)));
      call(hash, 'audio', 'set_volume', { volume: dev.volume, deviceId: dev.deviceId });
    }, { passive: false });
    r.m.addEventListener('contextmenu', function (e) {
      e.preventDefault();
      if (hash && dev) call(hash, 'audio', 'set_mute', { mute: !dev.isMuted, deviceId: dev.deviceId });
    });
    return r.m;
  },
  battery: function () {
    const r = readout('battery');
    provider({ type: 'battery', refreshInterval: CONFIG.every.battery }, function (o) {
      if (!o) { r.hide(); return; }   // a desktop: no battery
      const n = Math.round(o.chargePercent);
      r.figure(W.battery, pct(n) + (o.isCharging ? ' ' + UP : ''));
      r.m.classList.toggle('critical', n <= CONFIG.battery.critical);
      r.m.classList.toggle('warning', n > CONFIG.battery.critical && n <= CONFIG.battery.warning);
      r.m.classList.toggle('charging', !!o.isCharging);
    });
    return r.m;
  },
  tray: function () {
    const g = el('span', 'g tray');
    g.hidden = true;
    const icons = new Map();
    provider({ type: 'systray' }, function (o, hash) {
      const seen = new Set();
      ((o && o.icons) || []).forEach(function (icon) {
        seen.add(icon.id);
        let t = icons.get(icon.id);
        if (!t) {
          t = trayIcon(icon.id, hash);
          icons.set(icon.id, t);
        }
        if (t.hash !== icon.iconHash) {
          if (t.url) URL.revokeObjectURL(t.url);
          t.url = URL.createObjectURL(new Blob([new Uint8Array(icon.iconBytes)], { type: 'image/png' }));
          t.img.src = t.url;
          t.hash = icon.iconHash;
        }
        t.m.title = icon.tooltip || '';
        g.append(t.m);   // in the provider's order
      });
      icons.forEach(function (t, id) {
        if (seen.has(id)) return;
        if (t.url) URL.revokeObjectURL(t.url);
        t.m.remove();
        icons.delete(id);
      });
      fit(g);
    });
    return g;
  },
};

function place(side) {
  const box = document.getElementById(side);
  CONFIG.layout[side].forEach(function (item) {
    if (typeof item === 'string') {
      box.append(BUILD[item]());
      return;
    }
    const name = Object.keys(item)[0];
    const g = el('span', 'g ' + name);
    g.hidden = true;
    item[name].forEach(function (n) { g.append(BUILD[n]()); });
    box.append(g);
  });
}

['left', 'center', 'right'].forEach(place);
tick();
document.addEventListener('visibilitychange', function () { if (!document.hidden) tick(); });
if (!tauri) console.warn('[masthead] no Tauri IPC (not opened by Zebar): only the clock runs');
"""


def masthead_js(t, w):
    cfg = {"label": t.label, "locale": w["locale"], "layout": w["layout"], "words": w["words"],
           "every": w["every"], "media": w["media"], "battery": w["battery"]}
    names = [x for side in cfg["layout"].values() for item in side
             for x in ([item] if isinstance(item, str) else list(item.values())[0])]
    unknown = sorted(set(n for n in names if not re.search(r"^  %s: function" % re.escape(n), MASTHEAD_JS, re.M)))
    if unknown:
        raise InputError("masthead.js has no builder for %s (BUILD in MASTHEAD_JS)" % ", ".join(unknown))
    head = [
        "// " + gen_note(t, "masthead.js"),
        "// The Letterpress masthead: Waybar's external bar (dotfiles/.config/waybar/) as a Zebar %s" % ZEBAR,
        "// widget, one per monitor. CONFIG is Waybar's own layout, caption words and intervals, read",
        "// by the generator: no icons, a Russian caption and a figure per readout",
        "// (dotfiles/.config/waybar/README.md -> Captions and spacing), escaped so the file stays",
        "// ASCII. Nothing is fetched: the page talks to Zebar alone, over Tauri's IPC (masthead.html's",
        "// CSP), and may run no program (zpack.json grants no shellCommands). Not on Windows yet: the",
        "// workspace numeral, the window title, the temperature (no sensor provider: the case panel",
        "// shows it), notifications.",
        "const CONFIG = " + json.dumps(cfg, indent=2, ensure_ascii=True) + ";",
    ]
    return "\n".join(head) + "\n" + MASTHEAD_JS


def zebar_pack(t):
    """zebar/settings.json and zebar/letterpress/{zpack.json, masthead.*}, as text."""
    w = waybar_masthead()
    files = {
        "zebar/settings.json": dump(zebar_settings()),
        "zebar/%s/zpack.json" % ZEBAR_PACK: dump(zebar_zpack(w["height"])),
        "zebar/%s/%s" % (ZEBAR_PACK, MASTHEAD_FILES[0]): masthead_html(t),
        "zebar/%s/%s" % (ZEBAR_PACK, MASTHEAD_FILES[1]): masthead_css(t),
        "zebar/%s/%s" % (ZEBAR_PACK, MASTHEAD_FILES[2]): masthead_js(t, w),
    }
    for name in MASTHEAD_FILES:
        rel = "zebar/%s/%s" % (ZEBAR_PACK, name)
        bad = sorted(set(u for u in REMOTE.findall(files[rel]) if u != "http://ipc.localhost"))
        if bad:
            raise InputError("%s reaches past the page (%s): the masthead fetches nothing" % (rel, ", ".join(bad)))
    return files


# ---- the directory ----------------------------------------------------------------------------
def build(tid):
    t = Theme(tid)
    files = {}

    def text(rel, s):
        try:
            s.encode("ascii")
        except UnicodeEncodeError as e:
            raise InputError("%s: non-ASCII output (%s)" % (rel, e))
        files[rel] = s.encode("ascii")

    text("theme", tid + "\n")
    text("wt-schemes.json", dump({"schemes": [wt_scheme(Theme(x)) for x in every_theme()]}))
    text("wt-settings.json", dump(wt_settings(t)))
    text("wsl/terminal-profile.json", dump({"profiles": [wt_defaults(t)], "schemes": [wt_scheme(t)]}))
    text("psreadline.ps1", psreadline(t))
    text("conhost.json", dump(conhost(t)))
    text("accent.json", dump(accent_json(t)))
    text("vscodium-settings.json", dump(vscodium_settings(t)))
    name, data = vsix()
    files[name] = data
    text("vesktop/letterpress.theme.css", vesktop_css(t))
    text("obs/Letterpress.ovt", obs_ovt(t))
    text("notepad++/Letterpress.xml", npp_theme(t))
    text("notepad++/darkmode.json", dump(npp_darkmode(t)))
    text("mumble/Letterpress/theme.ini", mumble_ini(t))
    text("mumble/Letterpress/Letterpress.qss", mumble_qss(t))
    text("halloy/letterpress.toml", halloy_toml(t))
    text("qbittorrent/letterpress/config.json", dump(qbt_config(t)))
    text("calibre/palette.json", dump(calibre_palette(t)))
    text("vortex/letterpress/variables.scss", vortex_scss(t))
    text("mintty/letterpress", mintty_theme(t))
    text("powertoys.json", dump(powertoys(t)))
    text("cmdpal.json", dump(cmdpal(t)))
    for name, sheet in ts3_sheets(t).items():
        text("teamspeak/" + name, sheet)
    text("nomacs/" + nomacs_name(t), nomacs_css(t))
    text("nomacs/settings.json", dump(nomacs_settings(t)))
    text("windirstat.json", dump(windirstat(t)))
    text("wireshark/preferences.json", dump(wireshark_prefs(t)))
    text("wireshark/colorfilters", wireshark_colorfilters(t))
    text("runelite.json", dump(runelite(t)))
    for rel, s in zebar_pack(t).items():
        text(rel, s)
    return files


def on_disk():
    out = {}
    if not os.path.isdir(OUT):
        return out
    for d, _, names in os.walk(OUT):
        for n in names:
            p = os.path.join(d, n)
            out[os.path.relpath(p, OUT).replace(os.sep, "/")] = open(p, "rb").read()
    return out


def same(rel, old, new):
    if old is None:
        return False
    if rel.endswith(".vsix"):   # zlib builds differ in their bytes: compare what is inside
        try:
            return zip_members(old) == zip_members(new)
        except zipfile.BadZipFile:
            return False
    return old == new


def recorded_theme():
    p = os.path.join(OUT, "theme")
    if os.path.isfile(p):
        tid = open(p, encoding="ascii").read().strip()
        if re.fullmatch(r"[a-z0-9-]+", tid) and os.path.isdir(os.path.join(THEMES, tid)):
            return tid
    return None


def _parse_args():
    """argparse over the module docstring: usage line, description, hidden flags."""
    import argparse
    doc = (__doc__ or "").strip().splitlines()
    ap = argparse.ArgumentParser(
        prog=doc[0].split()[1], usage=doc[0][len("usage: "):],
        description="\n".join(doc[1:]).strip(), add_help=False,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-h", "--help", action="help", help=argparse.SUPPRESS)
    ap.add_argument("--check", action="store_true", help=argparse.SUPPRESS)
    ap.add_argument("theme", nargs="?", help=argparse.SUPPRESS)
    return ap.parse_args()


def main():
    args = _parse_args()
    tid = args.theme or recorded_theme() or HOUSE
    if not os.path.isfile(os.path.join(THEMES, tid, "waybar.css")):
        print("gen-windows-look.py: no theme %r under dotfiles/.config/themes" % tid, file=sys.stderr)
        return 2
    try:
        files = build(tid)
    except InputError as e:
        print("gen-windows-look.py: %s" % e, file=sys.stderr)
        return 1
    old = on_disk()
    changed = [r for r in sorted(files) if not same(r, old.get(r), files[r])]
    stale = sorted(set(old) - set(files))
    if args.check:
        if not changed and not stale:
            return 0
        for r in changed:
            if r.endswith(".vsix") or r not in old:
                print("%s/%s: %s" % (REL_OUT, r, "missing" if r not in old else "differs"))
                continue
            sys.stdout.writelines(list(difflib.unified_diff(
                old[r].decode("ascii", "replace").splitlines(True), files[r].decode("ascii").splitlines(True),
                "%s/%s" % (REL_OUT, r), "generated", n=1))[:40])
        for r in stale:
            print("%s/%s: not generated any more" % (REL_OUT, r))
        print("%s is stale: python3 bin/gen-windows-look.py" % REL_OUT, file=sys.stderr)
        return 1
    for r in changed:
        p = os.path.join(OUT, *r.split("/"))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "wb") as f:
            f.write(files[r])
        print("wrote %s/%s" % (REL_OUT, r))
    for r in stale:
        os.remove(os.path.join(OUT, *r.split("/")))
        print("removed %s/%s" % (REL_OUT, r))
    for d in sorted((w[0] for w in os.walk(OUT)), key=len, reverse=True):
        if d != OUT and not os.listdir(d):
            os.rmdir(d)
    return 0


if __name__ == "__main__":
    sys.exit(main())

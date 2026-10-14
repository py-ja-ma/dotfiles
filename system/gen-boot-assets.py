#!/usr/bin/env python3
"""usage: gen-boot-assets.py [--font PATH] [--check] [--icons-from DIR]

Renders the committed PNGs for the boot chain: Plymouth and rEFInd cannot load fonts, so the wordmark is pre-rendered here from system/house-palette.sh and committed. Re-run only when the palette or the wordmark changes; the outputs are deterministic (seeded grain), so a re-run with the same font produces byte-identical files. Needs Pillow.

Plymouth and rEFInd cannot load fonts, so the wordmark is pre-rendered here
and committed. Re-run only when the palette (system/house-palette.sh) or the
wordmark changes; the outputs are deterministic (seeded grain) so a re-run
with the same font produces byte-identical files.

    python3 system/gen-boot-assets.py --font /path/to/Fraunces.ttf
    python3 system/gen-boot-assets.py --check      # just report sizes

Outputs (all under system/):
  plymouth-letterpress/wordmark.png   "pj", ink, transparent  (Plymouth, 1:1)
  plymouth-letterpress/bar.png        240x1 accent strip      (progress rule)
  plymouth-letterpress/track.png      240x1 subtext strip     (rule track)
  refind-letterpress/background.png   2560x1440 paper + grain + wordmark
  refind-letterpress/selection_big.png    144x144 1px accent frame
  refind-letterpress/selection_small.png   64x64  1px accent frame
  refind-letterpress/icons/*.png      catppuccin mocha icons recoloured
                                      (os_* -> ink, the rest -> subtext)

Needs Pillow. Font: Fraunces (OFL) if given/found, else the first serif found
by fc-list from the FALLBACKS list. The chosen file is printed: note it in
docs/design/shell-and-bars/boot-screens.md when it changes.

  --font PATH       TTF/OTF to render the wordmark with (Fraunces preferred; else the first serif found)
  --check           only list the output files and their sizes
  --icons-from DIR  source icons (default: system/refind-catppuccin/assets/mocha/icons)
  -h, --help        this text

exit: 0 ok · 1 Pillow missing or a render failed · 2 bad usage
see: docs/design/shell-and-bars/boot-screens.md
"""
import argparse
import os
import random
import re
import subprocess
import sys

def _pil():  # imported after the arguments are parsed, so --help needs no Pillow
    global Image, ImageDraw, ImageFont
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        sys.exit("Pillow is required: pip install pillow (or pacman -S python-pillow)")

HERE = os.path.dirname(os.path.abspath(__file__))
FALLBACKS = ["Fraunces", "EB Garamond", "Hoefler Text", "Iowan Old Style",
             "Baskerville", "Charter", "Noto Serif", "DejaVu Serif"]


def palette():
    cols = {}
    with open(os.path.join(HERE, "house-palette.sh")) as fh:
        for ln in fh:
            m = re.match(r"^HP_([A-Z_]+)=([0-9a-fA-F]{6})", ln)
            if m:
                cols[m.group(1)] = tuple(int(m.group(2)[i:i + 2], 16) for i in (0, 2, 4))
    for k in ("PAPER", "PAPER_BOTTOM", "INK", "SUBTEXT", "ACCENT"):
        if k not in cols:
            sys.exit(f"house-palette.sh: HP_{k} missing")
    return cols


def find_font(explicit):
    if explicit:
        if not os.path.isfile(explicit):
            sys.exit(f"font not found: {explicit}")
        return explicit
    for fam in FALLBACKS:
        try:
            out = subprocess.run(["fc-list", f":family={fam}", "file"],
                                 capture_output=True, text=True, timeout=10).stdout
        except (OSError, subprocess.SubprocessError):
            out = ""
        files = [l.split(":")[0].strip() for l in out.splitlines() if l.strip()]
        files = [f for f in files if f.lower().endswith((".ttf", ".otf"))]
        if files:
            files.sort(key=lambda f: ("semibold" not in f.lower(), "regular" not in f.lower(), f))
            return files[0]
    return None


def load_font(path, size):
    """Fraunces is a variable font; pick a warm, heavy, large-optical-size cut."""
    if path is None:
        print("!! no serif font found — using Pillow's bitmap default (replace me)", file=sys.stderr)
        return ImageFont.load_default(size=size)
    font = ImageFont.truetype(path, size)
    try:
        axes = font.get_variation_axes()
    except OSError:
        return font
    want = {"opsz": 144, "wght": 600, "SOFT": 100, "WONK": 1}
    values = []
    for ax in axes:
        name = ax["name"].decode() if isinstance(ax["name"], bytes) else ax["name"]
        v = want.get(name, ax["default"])
        values.append(max(ax["minimum"], min(ax["maximum"], v)))
    try:
        font.set_variation_by_axes(values)
    except OSError:
        pass
    return font


def text_image(text, font, colour, pad=8):
    probe = Image.new("RGBA", (1, 1))
    bbox = ImageDraw.Draw(probe).textbbox((0, 0), text, font=font, anchor="ls")
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    im = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(im).text((pad - bbox[0], pad - bbox[1]), text, font=font,
                            fill=colour + (255,), anchor="ls")
    return im


def strip(width, colour):
    return Image.new("RGBA", (width, 1), colour + (255,))


def frame(size, colour):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(im).rectangle([0, 0, size - 1, size - 1], outline=colour + (255,), width=1)
    return im


def background(w, h, top, bottom, wordmark, seed=1, density=0.015):
    # vertical gradient, drawn as rows (compresses well)
    im = Image.new("RGB", (w, h))
    px = im.load()
    for y in range(h):
        t = y / (h - 1)
        col = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = col
    # faint grain: sparse single-pixel specks, +-6 levels, seeded. Sparse so
    # the PNG stays small (dense noise would be megabytes) and faint so the
    # top-left pixel - rEFInd's menu background colour - is still plain paper.
    rng = random.Random(seed)
    n = int(w * h * density)
    for _ in range(n):
        x, y = rng.randrange(w), rng.randrange(h)
        if x < 4 and y < 4:
            continue
        d = rng.choice((-6, -4, 4, 6))
        r, g, b = px[x, y]
        px[x, y] = (max(0, min(255, r + d)), max(0, min(255, g + d)), max(0, min(255, b + d)))
    px[0, 0] = top  # belt and braces: rEFInd samples this pixel
    # wordmark bottom-left
    margin = 96
    im = im.convert("RGBA")
    im.alpha_composite(wordmark, (margin, h - margin - wordmark.height))
    return im.convert("RGB")


def recolour(src, dst, colour, paper, ink):
    """Single-tone icons (the catppuccin-drawn ones: os_arch, func_*, ...) become
    flat `colour` with their alpha kept. The rest of the set is stock rEFInd
    full-colour art; those are printed monochrome: luminance mapped onto
    paper -> ink so nothing on the menu is ever a colour outside the palette."""
    im = Image.open(src).convert("RGBA")
    raw = im.tobytes()
    data = list(zip(raw[0::4], raw[1::4], raw[2::4], raw[3::4]))   # version-proof getdata()
    tones = {(r, g, b) for r, g, b, a in data if a > 128}
    out = []
    if len(tones) <= 3:
        for r, g, b, a in data:
            out.append(colour + (a,) if a else (0, 0, 0, 0))
    else:
        for r, g, b, a in data:
            if not a:
                out.append((0, 0, 0, 0)); continue
            k = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            out.append(tuple(round(paper[i] + (ink[i] - paper[i]) * k) for i in range(3)) + (a,))
    im.putdata(out)
    im.save(dst, optimize=True)


def main():
    doc = (__doc__ or "").strip().splitlines()
    ap = argparse.ArgumentParser(
        prog=doc[0].split()[1], usage=doc[0][len("usage: "):],
        description="\n".join(doc[1:]).strip(), add_help=False,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-h", "--help", action="help", help=argparse.SUPPRESS)
    ap.add_argument("--font", help=argparse.SUPPRESS)
    ap.add_argument("--check", action="store_true", help=argparse.SUPPRESS)
    ap.add_argument("--icons-from", default=os.path.join(HERE, "refind-catppuccin/assets/mocha/icons"), help=argparse.SUPPRESS)
    args = ap.parse_args()
    _pil()

    ply = os.path.join(HERE, "plymouth-letterpress")
    ref = os.path.join(HERE, "refind-letterpress")
    outputs = [os.path.join(ply, f) for f in ("wordmark.png", "bar.png", "track.png")] + \
              [os.path.join(ref, f) for f in ("background.png", "selection_big.png", "selection_small.png")]

    if not args.check:
        c = palette()
        font_path = find_font(args.font)
        print(f"font: {font_path or '(Pillow default)'}")
        big = load_font(font_path, 260)     # Plymouth wordmark (shown 1:1)
        small = load_font(font_path, 112)   # rEFInd background corner mark

        os.makedirs(ply, exist_ok=True)
        os.makedirs(os.path.join(ref, "icons"), exist_ok=True)
        text_image("pj", big, c["INK"]).save(os.path.join(ply, "wordmark.png"), optimize=True)
        strip(240, c["ACCENT"]).save(os.path.join(ply, "bar.png"), optimize=True)
        strip(240, c["SUBTEXT"]).save(os.path.join(ply, "track.png"), optimize=True)

        mark = text_image("pj", small, c["SUBTEXT"])
        background(2560, 1440, c["PAPER"], c["PAPER_BOTTOM"], mark).save(
            os.path.join(ref, "background.png"), optimize=True)
        frame(144, c["ACCENT"]).save(os.path.join(ref, "selection_big.png"), optimize=True)
        frame(64, c["ACCENT"]).save(os.path.join(ref, "selection_small.png"), optimize=True)

        if os.path.isdir(args.icons_from):
            for name in sorted(os.listdir(args.icons_from)):
                if not name.endswith(".png"):
                    continue
                colour = c["INK"] if name.startswith("os_") else c["SUBTEXT"]
                recolour(os.path.join(args.icons_from, name), os.path.join(ref, "icons", name),
                          colour, c["PAPER_BOTTOM"], c["INK"])
        else:
            print(f"!! icon source missing: {args.icons_from} — icons/ not written", file=sys.stderr)

    outputs += [os.path.join(ref, "icons", f) for f in sorted(os.listdir(os.path.join(ref, "icons")))
                if os.path.isdir(os.path.join(ref, "icons"))]
    bad = 0
    for p in outputs:
        if not os.path.exists(p):
            print(f"MISSING {os.path.relpath(p, HERE)}"); bad += 1; continue
        size = os.path.getsize(p)
        flag = "" if size < 300 * 1024 else "  <-- over 300 KB"
        if flag:
            bad += 1
        if flag or not p.endswith(os.path.join("icons", os.path.basename(p))):
            print(f"{size:8d}  {os.path.relpath(p, HERE)}{flag}")
    print(f"{len(outputs)} files checked, {bad} problems")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()

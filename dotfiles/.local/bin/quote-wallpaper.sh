#!/usr/bin/env bash
# usage: quote-wallpaper.sh [--en|--ru|--show]
#
# Renders a quote as the wallpaper (editorial layout): a random English quote
# from pyjama.sh (cached offline) and a random Russian proverb from
# ~/.config/quote-wallpaper/quotes-ru.txt, each rendered to a PNG by headless
# Chromium and shown through awww-daemon, in the active theme's colours
# (waybar.css). One output: the English quote. Two or more: English on the main
# (leftmost), the proverb on the second, English on any further one. A
# per-theme ~/.config/themes/current/wall.sh (executable) runs INSTEAD of all
# of this, with the same arguments. Run at login (hyprland.lua), by dram-theme
# and by wallpaper-hotplug.sh.
#
#   (no flag)     re-render and show everything
#   --en          re-render only the English quote
#   --ru          re-render only the Russian proverb
#   --show        re-display the cached renders, no render (login, hotplug: instant, no fade)
#   -h, --help    this text
#
# exit: 0 ok · 1 render or display failed · 2 bad usage
# see: docs/design/themes/wallpaper.md

set -euo pipefail

WALLDIR="$HOME/pictures/wallpapers"
OUT_EN="$WALLDIR/quote-wall.png" # name is load-bearing: wallpaper-hotplug.sh, hyprlock.conf
OUT_RU="$WALLDIR/quote-wall-ru.png"
QUOTES_URL="https://pyjama.sh/quotes.txt"
CORPUS_RU="${XDG_CONFIG_HOME:-$HOME/.config}/quote-wallpaper/quotes-ru.txt"
CACHE_DIR="$HOME/.local/share/quote-wallpaper"
CACHE_EN="$CACHE_DIR/quotes.txt"
HOOK="$HOME/.config/themes/current/wall.sh"

# --- arguments ---------------------------------------------------------------
MODE=all
case "${1:-}" in
  "") MODE=all ;;
  --en) MODE=en ;;
  --ru) MODE=ru ;;
  --show) MODE=show ;;
  -h | --help)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "quote-wallpaper: unknown argument '$1' (try --help)" >&2
    exit 2
    ;;
esac
# no Wayland session (a user manager started by an ssh login, a timer before the first
# graphical login): there is nothing to draw on, and awww-daemon aborts without a display
[ -n "${WAYLAND_DISPLAY:-}" ] || {
  echo "quote-wallpaper: no Wayland session — nothing to show" >&2
  exit 0
}

# --- per-theme override hook -------------------------------------------------
# A theme that wants its own wallpaper (a photo, a different generator) ships an
# executable wall.sh; it is responsible for displaying the image itself.
if [ -x "$HOOK" ]; then
  exec "$HOOK" "$@"
fi

mkdir -p "$WALLDIR" "$CACHE_DIR"

# --- monitors ----------------------------------------------------------------
# MONS: "name width height" per line, sorted left-to-right (x). Empty when
# hyprctl/jq are unavailable (pre-Hyprland, ssh) — then we paint all outputs.
MONS=""
if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  MONS="$(hyprctl monitors -j 2>/dev/null \
    | jq -r 'sort_by(.x, .y)[] | "\(.name) \(.width) \(.height)"' 2>/dev/null || true)"
fi
NMON=0
[ -n "$MONS" ] && NMON="$(printf '%s\n' "$MONS" | wc -l | tr -d ' ')"
mon_field() { printf '%s\n' "$MONS" | sed -n "${1}p" | cut -d' ' -f"$2"; } # mon_field <row> <col>
MAIN_W=2560
MAIN_H=1440 # fallback size offline / pre-Hyprland
SECOND_OUT=""
SECOND_W=2560
SECOND_H=1440
if [ "$NMON" -ge 1 ]; then
  MAIN_W="$(mon_field 1 2)"
  MAIN_H="$(mon_field 1 3)"
fi
if [ "$NMON" -ge 2 ]; then
  SECOND_OUT="$(mon_field 2 1)"
  SECOND_W="$(mon_field 2 2)"
  SECOND_H="$(mon_field 2 3)"
fi
# every output that is NOT the second one gets the English quote
EN_OUTS=""
if [ "$NMON" -ge 2 ]; then
  EN_OUTS="$(printf '%s\n' "$MONS" | cut -d' ' -f1 | grep -vx -- "$SECOND_OUT" | paste -sd, -)"
fi

# --- wallpaper backend --------------------------------------------------------
# awww (ex-swww, animated transitions) when installed, else the old swaybg.
# show_wall <file> [outputs-csv|""] [instant]
#   outputs "" = all outputs. The house transition is one soft fade.
show_wall() {
  local file="$1" outs="${2:-}" how="${3:-}"
  if command -v awww >/dev/null 2>&1; then
    pgrep -x awww-daemon >/dev/null 2>&1 || {
      setsid -f awww-daemon >/dev/null 2>&1
      sleep 0.4
    }
    local -a args=(img "$file")
    [ -n "$outs" ] && args+=(-o "$outs")
    if [ "$how" = instant ]; then
      args+=(--transition-type none)
    else
      args+=(--transition-type fade --transition-duration 0.9 --transition-bezier ".2,.8,.2,1")
    fi
    awww "${args[@]}" >/dev/null 2>&1
  elif command -v swaybg >/dev/null 2>&1; then
    # swaybg has no per-output targeting worth the complexity: one image everywhere.
    [ "$file" = "$OUT_RU" ] && return 0
    pkill -x swaybg 2>/dev/null || true
    sleep 0.3
    swaybg -i "$file" -m fill >/dev/null 2>&1 &
    disown
  else
    return 1
  fi
}

# display what exists: EN on main (+extras), RU on the second output.
# show_all [instant]
show_all() {
  local how="${1:-}" rc=1
  if [ "$NMON" -ge 2 ] && [ -f "$OUT_RU" ]; then
    show_wall "$OUT_RU" "$SECOND_OUT" "$how" && rc=0
    if [ -f "$OUT_EN" ]; then show_wall "$OUT_EN" "$EN_OUTS" "$how" && rc=0; fi
  elif [ -f "$OUT_EN" ]; then
    show_wall "$OUT_EN" "" "$how" && rc=0 # single output (or RU not rendered yet)
  fi
  return $rc
}

if [ "$MODE" = show ]; then
  show_all instant && exit 0
  echo "quote-wallpaper: nothing to show (no cached render / no backend)" >&2
  exit 1
fi

# Show the previous wallpaper INSTANTLY on login so there's no blank gap while we
# fetch + render the new quote (the fresh one fades in a few seconds later).
show_all instant || true

# --- helpers -----------------------------------------------------------------
trim() { printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//'; }
# Quote text comes from a remote URL / a corpus file and is dropped into an HTML
# doc that a full browser engine renders. HTML-escape it so a crafted line (or a
# compromised pyjama.sh / homelab DNS) can't inject markup/script. Ampersand first.
esc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }

# --- colours from the active theme (dram-theme) -------------------------------
# Pull base/crust/text/subtext/accent out of the theme's waybar palette so the
# wallpaper always matches the desktop. `accent` is the theme's own choice;
# older themes without one fall back to blue. Last resort: Catppuccin Mocha.
TW="$HOME/.config/themes/current/waybar.css"
col() { grep -oP "@define-color $1\s+\K#[0-9a-fA-F]{6}" "$TW" 2>/dev/null | head -1; }
BG="$(col base)"
BG="${BG:-#1e1e2e}"
BG2="$(col crust)"
BG2="${BG2:-#11111b}"
FG="$(col text)"
FG="${FG:-#cdd6f4}"
SUB="$(col subtext)"
SUB="${SUB:-#a6adc8}"
AC="$(col accent)"
AC="${AC:-$(col blue)}"
AC="${AC:-#89b4fa}"

# --- the page -----------------------------------------------------------------
# Editorial, not a centred poster: left-aligned block on a baseline grid, generous
# margins, paper grain + a soft vignette. Everything is in vw so the same sheet
# scales to 2560x1440 and 1920x1200 (the viewport IS the render size).
#   --u  baseline unit = 1.25vw (32px at 2560); every size is a multiple of it.
# Fraunces is the Latin display face (variable axes WONK/SOFT, with the static
# families as fallback); it has no Cyrillic, so the Russian sheet is EB Garamond.
page_css() { # page_css <W> <H>
  cat <<CSSEOF
  :root{ --u:1.25vw; --bg:${BG}; --bg2:${BG2}; --fg:${FG}; --sub:${SUB}; --ac:${AC}; }
  html,body{margin:0;padding:0;width:${1}px;height:${2}px;overflow:hidden;}
  body{
    position:relative;color:var(--fg);
    background:radial-gradient(130% 110% at 28% 36%, var(--bg) 0%, var(--bg2) 100%);
    font-family:"EB Garamond","Literata","Times New Roman",serif;
    -webkit-font-smoothing:antialiased;text-rendering:geometricPrecision;
    font-kerning:normal;font-feature-settings:"kern","liga","onum";
  }
  .sheet{
    position:absolute;left:calc(var(--u)*7.5);top:calc(var(--u)*11);
    width:calc(var(--u)*44);
  }
  .quote{
    margin:0;font-size:calc(var(--u)*1.75);line-height:calc(var(--u)*2);
    font-weight:500;text-indent:-0.42em;
    text-wrap:pretty;text-shadow:0 1px 14px rgba(0,0,0,0.25);
  }
  .quote.latin{
    font-family:"Fraunces","Fraunces 72pt Soft","Fraunces 72pt","Fraunces 9pt","EB Garamond",serif;
    font-variation-settings:"WONK" 1,"SOFT" 60,"opsz" 72;
    font-optical-sizing:auto;font-weight:400;
  }
  .quote::before{content:"\201C";} .quote::after{content:"\201D";}
  .gloss{
    margin:calc(var(--u)*1) 0 0 0;font-style:italic;font-weight:400;
    font-size:calc(var(--u)*0.95);line-height:calc(var(--u)*1.5);color:var(--sub);
    max-width:calc(var(--u)*36);
  }
  .rule{
    width:calc(var(--u)*5);height:1px;background:var(--ac);border:0;
    margin:calc(var(--u)*1.5) 0 calc(var(--u)*0.5) 0;opacity:0.9;
  }
  .author{
    margin:0;font-family:"EB Garamond","Literata","Times New Roman",serif;
    font-size:calc(var(--u)*0.75);line-height:calc(var(--u)*1);
    color:var(--ac);font-variant-caps:small-caps;letter-spacing:0.16em;font-weight:500;
  }
  /* paper: feTurbulence grain (~4%) + a soft vignette; both sit above the text */
  .grain{
    position:absolute;inset:0;pointer-events:none;opacity:0.04;mix-blend-mode:soft-light;
    background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='300' height='300'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='2' stitchTiles='stitch'/><feColorMatrix values='0 0 0 0 0.5  0 0 0 0 0.5  0 0 0 0 0.5  0 0 0 1 0'/></filter><rect width='100%' height='100%' filter='url(%23n)'/></svg>");
    background-size:300px 300px;
  }
  .vignette{
    position:absolute;inset:0;pointer-events:none;
    background:radial-gradient(120% 95% at 50% 45%, rgba(0,0,0,0) 55%, rgba(0,0,0,0.28) 100%);
  }
CSSEOF
}

# render_page <html-file> <out-png> <W> <H>
render_page() {
  local html="$1" out="$2" w="$3" h="$4"
  local chrome
  chrome="$(command -v chromium || command -v chromium-browser || command -v google-chrome || true)"
  if [ -z "$chrome" ]; then
    echo "No chromium found; cannot render." >&2
    return 1
  fi
  "$chrome" --headless=new --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=1 --window-size="${w},${h}" \
    --virtual-time-budget=3000 --screenshot="$out" "file://$html" >/dev/null 2>&1
  echo "Rendered: $out"
}

HTML="$(mktemp --suffix=.html)"
trap 'rm -f "$HTML"' EXIT # always clean up the temp render, even on early exit/failure

# --- English: pyjama.sh quote (works offline via local cache) -----------------
render_en() { # render_en <W> <H>
  local w="$1" h="$2" fetched line quote author
  fetched="$(curl -sfL --max-time 8 "$QUOTES_URL" 2>/dev/null || true)"
  if [ -n "$fetched" ]; then printf '%s\n' "$fetched" >"$CACHE_EN"; fi
  if [ -s "$CACHE_EN" ]; then
    line="$(shuf -n1 "$CACHE_EN")"
  else
    line='"Do not let what you cannot do interfere with what you can do." | John Wooden'
  fi
  quote="$(esc "$(trim "${line%%|*}")")"
  author="$(esc "$(trim "${line##*|}")")"
  cat >"$HTML" <<HTMLEOF
<!doctype html><html lang="en"><head><meta charset="utf-8"><style>
$(page_css "$w" "$h")
</style></head><body>
  <div class="sheet">
    <p class="quote latin">${quote}</p>
    <hr class="rule">
    <p class="author">${author}</p>
  </div>
  <div class="vignette"></div><div class="grain"></div>
</body></html>
HTMLEOF
  render_page "$HTML" "$OUT_EN" "$w" "$h"
}

# --- Russian: folk proverb + English gloss from the local corpus ---------------
render_ru() { # render_ru <W> <H>
  local w="$1" h="$2" line proverb gloss
  line=""
  if [ -s "$CORPUS_RU" ]; then
    line="$(grep -v '^[[:space:]]*#' "$CORPUS_RU" | grep '|' | shuf -n1 || true)"
  fi
  [ -n "$line" ] || line='Тише едешь — дальше будешь. | Ride slower, get further.'
  proverb="$(esc "$(trim "${line%%|*}")")"
  gloss="$(esc "$(trim "${line##*|}")")"
  cat >"$HTML" <<HTMLEOF
<!doctype html><html lang="ru"><head><meta charset="utf-8"><style>
$(page_css "$w" "$h")
</style></head><body>
  <div class="sheet">
    <p class="quote">${proverb}</p>
    <p class="gloss">${gloss}</p>
    <hr class="rule">
    <p class="author">Русская пословица</p>
  </div>
  <div class="vignette"></div><div class="grain"></div>
</body></html>
HTMLEOF
  render_page "$HTML" "$OUT_RU" "$w" "$h"
}

# --- render + display ---------------------------------------------------------
case "$MODE" in
  en) render_en "$MAIN_W" "$MAIN_H" ;;
  ru) render_ru "$SECOND_W" "$SECOND_H" ;;
  all)
    render_en "$MAIN_W" "$MAIN_H"
    if [ "$NMON" -ge 2 ]; then render_ru "$SECOND_W" "$SECOND_H"; fi
    ;;
esac

if show_all; then
  echo "Wallpaper set."
else
  echo "NOTE: install 'awww' (or 'swaybg') to display the wallpaper." >&2
fi

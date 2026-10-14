# Wallpaper

[Design](../README.md) › [Themes](README.md) › Wallpaper

On the Arch desktops the wallpaper is a quotation set as a printed page, in the colors of the active theme.
`quote-wallpaper.sh` writes an HTML page for each sheet, and headless Chromium renders it to a PNG at the output's size: an English quote on the leftmost output, a Russian proverb with an English gloss on the second.
The lock screen shows the English sheet too.

| | |
|---|---|
| Code | `dotfiles/.local/bin/quote-wallpaper.sh`, `dotfiles/.local/bin/wallpaper-hotplug.sh`, `dotfiles/.local/bin/wallpaper-menu.sh`, `dotfiles/.config/quote-wallpaper/quotes-ru.txt` |
| Runs on | the Arch hosts with the desktop role: cabin, lantern, campfire |
| Needs | Chromium 153, awww 0.12.1 or swaybg 1.2.2, Hyprland 0.56.2, jq 1.8.2, curl 8.22.0 and socat 1.8.1.3, tested 2026-10; the fonts Fraunces, EB Garamond and Literata ([Typography](../typography/README.md)) |
| Decided in | no record |

## How it works

Three callers run `quote-wallpaper.sh`:

| Caller | When | Argument | What shows |
|---|---|---|---|
| `hyprland.lua` | at login | none | the cached sheets at once, then fresh renders that fade in |
| `dram theme` | after each switch | none | fresh renders in the new colors, with a new quote |
| `wallpaper-hotplug.sh` | when an output is added | `--show` | the cached sheets, with no render and no fade |

Two neighbors have pages of their own.
The grain over the whole screen is Hyprland's [grain shader](../../../dotfiles/.config/hypr/README.md#grain-shader), and the change between washi and washi-day by the sun is under [Day and night](switcher.md#day-and-night).

### The page

The script writes a small HTML page and screenshots it with headless Chromium (`--headless=new --screenshot`), so the sheet gets real fonts, kerning and small caps without ImageMagick or Pillow.
Chromium runs with its sandbox.
The PNGs land in `~/pictures/wallpapers/`: `quote-wall.png` for English and `quote-wall-ru.png` for Russian.
`awww-daemon` shows them, or swaybg when awww is missing.

The colors come from `~/.config/themes/current/waybar.css`, so the wallpaper matches the bar.
`base` and `crust` make the paper, a radial gradient.
`text` sets the quote, `subtext` the gloss, and `accent` the rule and the attribution.
A theme without `accent` falls back to `blue`, and with no theme the colors are Catppuccin Mocha's.

The sheet is one left-aligned block on a baseline unit, `--u`, which is 1.25 % of the width: 32 px on a 2560 px panel.
Each size is a multiple of it, so one sheet fits a 2560×1440 panel and a 1920×1200 laptop.
The block starts 7.5 units from the left and 11 from the top, and is 44 units wide.
Over it sit an SVG `feTurbulence` grain at 4 % opacity and a soft vignette.

| Sheet | Text | Face | Under the rule |
|---|---|---|---|
| English, `quote-wall.png` | a quote from pyjama.sh | Fraunces with `"WONK" 1, "SOFT" 60, "opsz" 72`, and its static cuts and EB Garamond as fallbacks | the author, in EB Garamond small caps and the accent |
| Russian, `quote-wall-ru.png` | a proverb, with its English gloss in italic under it | EB Garamond, because Fraunces has no Cyrillic | Русская пословица, set the same way |

The rule is 1 px of the accent, 5 units long.
A new render fades in with the house transition, `--transition-type fade --transition-duration 0.9 --transition-bezier .2,.8,.2,1`.
Showing the cached sheets uses `--transition-type none`, so a login or a hotplug paints at once.
`hyprlock.conf` takes `quote-wall.png` as the lock screen's background, at 85 % brightness with a little noise and no blur ([hyprlock](../../../dotfiles/.config/hypr/README.md#hyprlock)).

### The corpora

The English quotes come from `https://pyjama.sh/quotes.txt`, one `"quote" | Author` per line.
Each English render fetches it with an 8-second timeout and keeps a copy at `~/.local/share/quote-wallpaper/quotes.txt`, so the sheet works offline.
With neither the network nor a copy, a built-in line by John Wooden stands in.

The Russian proverbs are `~/.config/quote-wallpaper/quotes-ru.txt`, tracked in the repo: 51 folk sayings with no named authors, one per line as `Пословица. | one-line English gloss`.
Lines that start with `#` are comments, and a line without `|` is skipped.
[quote-wallpaper](../../../dotfiles/.config/quote-wallpaper/README.md) has the format and how to add a proverb.

Both corpora are HTML-escaped before Chromium renders them, because the English one is remote content: a crafted line cannot inject markup into the page.

### Per output

The script lists the outputs with `hyprctl monitors -j` and sorts them left to right, by x and then y:

| Outputs | First | Second | Each further one |
|---|---|---|---|
| 1 | English | | |
| 2 or more | English | the Russian proverb | English |

The English sheet is rendered at the first output's size and the proverb at the second's.
Without `hyprctl` or `jq`, the English sheet is rendered at 2560×1440 and shown on each output.
Outside a Wayland session, an ssh login for example, the script prints `nothing to show` and exits 0.

### Hotplug

awww-daemon repaints an output it painted before from its cache.
An output it had not painted yet, a newly docked monitor or one after the cache was cleared, stayed black until something repainted it.
`wallpaper-hotplug.sh` closes that gap.
`hyprland.lua` starts it at login, and it reads Hyprland's event socket (`.socket2.sock`) with socat, `nc -U` or Python, idle until an event arrives.
One second after each `monitoradded`, it runs `quote-wallpaper.sh --show`, which sorts the outputs again, so the proverb moves to whichever output is second from the left.
If that fails, it paints `quote-wall.png` on the new output with `awww img -o <output>`.
It exits when Hyprland closes the socket, and the next login starts it again.

### A theme's own wallpaper

If `~/.config/themes/current/wall.sh` exists and is executable, `quote-wallpaper.sh` replaces itself with it (`exec`) and passes the same argument.
The hook's contract:

- It runs only inside a Wayland session, as the script does.
- It gets no argument (render and show), `--en`, `--ru` or `--show`: `quote-wallpaper.sh` rejects any other argument before it looks for the hook.
- `--show` comes on each hotplug, so it has to be quick and stay off the network.
- It shows the image on each output itself, with awww or swaybg.
- If it writes `~/pictures/wallpapers/quote-wall.png`, the hotplug fallback and the lock screen keep using that file.
- Its exit status is the script's.

No tracked theme has a `wall.sh` (2026-10-13).

## Use it

```sh
quote-wallpaper.sh            # render both sheets again and show them
quote-wallpaper.sh --en       # a new English quote
quote-wallpaper.sh --ru       # a new proverb, for the second output
quote-wallpaper.sh --show     # the cached sheets again: no render, no fade
ls -l ~/pictures/wallpapers/quote-wall*.png
```

A render prints `Rendered: <path>` for each sheet, and `Wallpaper set.` at the end.
SUPER+SHIFT+W runs `wallpaper-menu.sh`, which lists the other pictures in `~/pictures/wallpapers` in rofi and fades the chosen one in on the focused output.
It offers PNG, JPEG and WebP files and leaves out the two sheets.
The next theme switch, hotplug or login puts the quote back.

## When it breaks

| Symptom | Check | Fix |
|---|---|---|
| a docked output stays black | `pgrep -f wallpaper-hotplug.sh` | `quote-wallpaper.sh --show`; log in again to start the listener |
| `No chromium found; cannot render.` | `command -v chromium` | install `chromium`, listed in `packages/roles/desktop.txt` |
| `NOTE: install 'awww' (or 'swaybg') to display the wallpaper.` | `command -v awww swaybg` | install `awww`, listed in `packages/roles/desktop.txt` |
| `quote-wallpaper: nothing to show (no cached render / no backend)` after `--show` | `ls ~/pictures/wallpapers/` | run `quote-wallpaper.sh` once to render |
| John Wooden's quote at each render | `ls -l ~/.local/share/quote-wallpaper/quotes.txt` | the copy is missing and pyjama.sh did not answer: render again with the network up |

To watch the hotplug listener, run it by hand as `WALLPAPER_HOTPLUG_LOG=<file> wallpaper-hotplug.sh`, and it appends each event to that file.

## Limits

- Arch only: Windows shows the rEFInd theme's Letterpress art as its wallpaper and lock screen ([Windows look](windows.md)).
- The English quotes come from pyjama.sh at run time, and I have not recorded under what license it publishes them.
- swaybg shows the English sheet alone, on each output.
- A `wall.sh` in one theme's directory fails `bin/check.sh` §14, because `bin/check-themes.py` wants the same files in each theme.

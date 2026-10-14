# quote-wallpaper

[Design](../../../docs/design/README.md) › [Themes](../../../docs/design/themes/README.md) › Wallpaper

A wallpaper set like a page: a quote in Fraunces on the theme's paper, drawn by headless Chromium.
With two or more monitors, the second from the left shows a Russian proverb in EB Garamond with its English gloss.
Each render takes the active theme's colors, so the wallpaper follows `dram theme`.
[Wallpaper](../../../docs/design/themes/wallpaper.md) has the layout, the per-output rules and the hook a theme can use to replace it.

| | |
|---|---|
| Needs | Chromium 153, awww 0.12.1 or swaybg 1.2.2, curl, Hyprland 0.56.2 and jq for the monitor list, tested 2026-10; Fraunces, EB Garamond, Literata; a palette file |
| Copy alone | yes: the corpus and three scripts; without Hyprland it paints one quote on each output |
| License | MIT; the proverbs are traditional sayings |

## What it needs

- A Wayland session: `quote-wallpaper.sh` exits at once when `WAYLAND_DISPLAY` is unset.
- Chromium 153 as `chromium`, `chromium-browser` or `google-chrome` on the `PATH`, tested 2026-10.
  It renders each page headless and screenshots it at the output's size, so a browser engine sets the type, with its kerning and small caps.
- awww 0.12.1 to show the images, one per output, with a 0.9 s fade.
  swaybg 1.2.2 is the fallback: the English quote on each output, with no fade and no proverb.
- Hyprland 0.56.2 and jq 1.8.2 for the list of outputs, sorted left to right.
  Without them the script renders one English quote at 2560×1440 and paints each output with it.
- curl 8.22 for the English quotes, which come from `https://pyjama.sh/quotes.txt` and are cached in `~/.local/share/quote-wallpaper/quotes.txt` for offline runs.
  With neither the network nor the cache, the script uses one built-in quote.
- GNU grep for `grep -P`, and GNU coreutils for `shuf` and `mktemp --suffix`.
- The fonts ([Typography](../../../docs/design/typography/README.md)).
  Fraunces sets the English quote with its `WONK`, `SOFT` and `opsz` axes, and the static Fraunces 72pt and 9pt cuts stand in when the variable font is missing.
  Fraunces has no Cyrillic, so the proverb is set in EB Garamond, with its italic for the gloss.
  EB Garamond also sets each attribution in small caps, and Literata is its fallback.
- A palette at `~/.config/themes/current/waybar.css` whose `@define-color` lines give `base`, `crust`, `text`, `subtext` and `accent`.
  Each of the 17 themes in `dotfiles/.config/themes/` has one.
  A missing accent falls back to `blue`, and a missing file to Catppuccin Mocha's colors.
- For `wallpaper-hotplug.sh`: socat 1.8.1 to read Hyprland's event socket, with `nc -U` and Python 3 as fallbacks.
- For `wallpaper-menu.sh`: rofi 2.0.0, `notify-send` and awww.
- Not needed: ImageMagick, Nix, Home Manager or `dram`.

## Copy it alone

1. Copy `quotes-ru.txt` to `~/.config/quote-wallpaper/`.
2. Copy `quote-wallpaper.sh`, `wallpaper-hotplug.sh` and `wallpaper-menu.sh` from `dotfiles/.local/bin/` to `~/.local/bin/`, and make them executable.
   `wallpaper-hotplug.sh` calls `quote-wallpaper.sh` at that path.
3. Give it a palette: copy one theme's `waybar.css` to `~/.config/themes/current/waybar.css`, or write that file with the five colors above.
4. Start the first two at login.
   In a Lua config for Hyprland:

   ```lua
   hl.on("hyprland.start", function ()
     hl.exec_cmd("$HOME/.local/bin/quote-wallpaper.sh")
     hl.exec_cmd("$HOME/.local/bin/wallpaper-hotplug.sh")
   end)
   ```

   In a `hyprland.conf`:

   ```conf
   exec-once = ~/.local/bin/quote-wallpaper.sh
   exec-once = ~/.local/bin/wallpaper-hotplug.sh
   ```

   Set `force_default_wallpaper = 0` in Hyprland's `misc` section too, so its own wallpaper does not flash before the quote.
5. Bind `wallpaper-menu.sh` to a key if you want the picker for the images in `~/pictures/wallpapers/`.
6. Run `quote-wallpaper.sh`.
   It prints a `Rendered:` line for each image and `Wallpaper set.`, and the quote fades in.
   With two monitors, the second shows a proverb.
   When it cannot draw, it names what is missing: `No chromium found; cannot render.` or `NOTE: install 'awww' (or 'swaybg') to display the wallpaper.`

## How it is wired here

`modules/desktop.nix` links this folder to `~/.config/quote-wallpaper/` and the three scripts to `~/.local/bin/`, on hosts with the desktop role.
It also links `EBGaramond-Italic.ttf` from `dotfiles/.local/share/fonts/`, the italic that the nixpkgs `eb-garamond` package lacks.
awww, swaybg, chromium and socat come from `packages/roles/desktop.txt`, and jq from `packages/base.txt`.
`hyprland.lua` starts `quote-wallpaper.sh` and `wallpaper-hotplug.sh` at login, binds `wallpaper-menu.sh` to SUPER+SHIFT+W, and sets `force_default_wallpaper = 0`.
At login the script shows the last render at once, then renders new ones and fades them in.
`dram-theme` runs it in the background after each switch, and the new colors fade in about three seconds later.
A picture chosen with SUPER+SHIFT+W stays on its monitor until the next switch, hotplug or login repaints the quotes.
`hyprlock.conf` takes `quote-wall.png` as the lock screen's background ([hypr](../hypr/README.md#hyprlock)).

## Adding a proverb

Add a line to `quotes-ru.txt` with the proverb, a `|` and an English gloss:

```text
Утро вечера мудренее. | The morning is wiser than the evening.
```

Use one `|` per line: the proverb ends at the first and the gloss starts after the last, and a line without one is skipped.
A line that starts with `#` is a comment.
The gloss wraps under the proverb in italic, so keep it to one sentence.
With two or more monitors, `quote-wallpaper.sh --ru` renders a new proverb at once, picked at random.

## Files

| File | What it does |
|---|---|
| `quotes-ru.txt` | 51 Russian proverbs, one per line as `<proverb> \| <English gloss>`; a line starting with `#` is a comment |
| `dotfiles/.local/bin/quote-wallpaper.sh` | renders `~/pictures/wallpapers/quote-wall.png` and `quote-wall-ru.png` and shows them, one per output |
| `dotfiles/.local/bin/wallpaper-hotplug.sh` | follows Hyprland's events and repaints an output when it is added |
| `dotfiles/.local/bin/wallpaper-menu.sh` | a rofi picker that fades one image in on the focused monitor |
| `README.md` | this file; the script reads only `quotes-ru.txt` from this folder |

## License

MIT, Patrick Jordan, for the scripts and the English glosses.
The proverbs are traditional Russian sayings with no author.
The English quotes are not part of this repo: the script fetches them from pyjama.sh at run time.

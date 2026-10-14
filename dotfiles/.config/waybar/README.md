# waybar

[Design](../../../docs/design/README.md) › [Shell & bars](../../../docs/design/shell-and-bars/README.md) › Waybar

The Letterpress masthead for Waybar: a transparent bar closed by one hairline, with words in place of icons.
Readouts are captions and figures (`цп 8 %`, `бат 85 %`), set in Fraunces, Literata and EB Garamond Italic.
The external monitors get the full masthead, and a laptop's own panel gets a compact one.

| | |
|---|---|
| Needs | Waybar 0.15.0 under Hyprland, tested 2026-10; Fraunces, Literata, EB Garamond, Monaspace Xenon; a palette file; three scripts |
| Copy alone | yes, after giving `style.css` a palette and copying three scripts |
| License | MIT |

## What it needs

- Waybar 0.15.0 from Arch's `extra` repo, tested 2026-10.
- Hyprland 0.56.2, for the `hyprland/workspaces`, `hyprland/window` and `hyprland/language` modules.
- The fonts Fraunces, Literata and EB Garamond for the type, and Monaspace Xenon for the calendar tooltip ([Typography](../../../docs/design/typography/README.md)).
- A palette at `~/.config/themes/current/waybar.css` that defines the GTK colors `base`, `text`, `subtext`, `accent`, `red`, `yellow` and `green`.
  Each of the 17 themes in `dotfiles/.config/themes/` has one, with more names than the bar uses (`bin/check.sh` §14 keeps their file sets identical).
- Optionally the theme's `meta.sh` beside it: `custom/nameplate` reads `MENU_NAME` from it and shows "Letterpress" without it.
- Three scripts from `dotfiles/.local/bin/`: `waybar-date.sh` writes the dateline, `waybar-cputemp.sh` the CPU temperature, and `waybar-updates.sh` the pending updates.
- For the clicks, if you want them: gsimplecal with `gsimplecal-dram.sh` for the calendar, `kb-layout.sh` for the layout word, nwg-drawer, swaync, kitty with `nmtui`, blueman, Thunar, pavucontrol, `wpctl` and `brightnessctl`.
  A click whose program is missing does nothing.
- `waybar-updates.sh` counts with `checkupdates` from pacman-contrib and writes its JSON with Python 3.
  Without `checkupdates` the badge stays hidden.
- Not needed: Nix, Home Manager or `dram`.

## Copy it alone

1. Copy `config.jsonc`, `modules.jsonc` and `style.css` to `~/.config/waybar/`.
2. Give the bar a palette.
   Copy one theme's `waybar.css` and `meta.sh` to `~/.config/themes/current/`, for example from `dotfiles/.config/themes/washi/`.
   Or point the `@import` on line 1 of `style.css` at your own file with the seven colors above.
   The import is relative, so it resolves against `~/.config/waybar/`.
3. Copy `waybar-date.sh`, `waybar-cputemp.sh` and `waybar-updates.sh` to `~/.local/bin/` and make them executable.
   Or delete `custom/date`, `custom/date#compact`, `custom/cputemp` and `custom/updates` from `modules.jsonc` and from the bars in `config.jsonc`.
4. Match your outputs.
   The full bar takes every output except `eDP-1`, and the compact bar takes `eDP-1`.
   Change both `output` lines if your laptop panel has another name.
   On a desktop, delete `, "battery"` from the full bar's `modules-right`.
5. If your Hyprland reads `hyprland.conf` and not a Lua config, change the two scroll actions of `hyprland/workspaces` to `hyprctl dispatch workspace e-1` and `e+1`.
   The commands in `modules.jsonc` call the Lua dispatcher `hl.dsp.focus`.
6. Run `waybar`.
   The bar shows the theme's name, `№` and the workspace number, the window title, and the clock.
   A missing font shows as a fallback serif, and the date is English until the `ru_RU.UTF-8` locale is generated.

## How it is wired here

`modules/desktop.nix` links the three files into `~/.config/waybar/` one by one.
On a desktop host, `modules/laptop.nix` replaces `config.jsonc` with a copy whose `, "battery"` is gone, so the literal must stay spelled that way.
`hyprland.lua` starts `waybar` and `waybar-fullscreen.sh` at login.
`waybar-fullscreen.sh` hides the bar while the active window is fullscreen, and `waybar-toggle.sh` (SUPER+SHIFT+B) hides it by hand and pauses the auto-hide.
`dram theme` restarts Waybar after each switch, because a running Waybar keeps the colors of the old `@import`.
`dram update` sends signal 8 (`SIGRTMIN+8`) to refresh the updates badge.
`bin/check.sh` §10 runs `bin/check-waybar.py`, which fails on a private-use codepoint in `config.jsonc`, `modules.jsonc` or a `waybar-*` script, so no icon glyph creeps back in.
The same check holds the house span, `"spacing": 0` on both bars, and a `style.css` without a hex color.
`bin/gen-windows-look.py` reads `config.jsonc` and `modules.jsonc` to build the [Zebar masthead](../../../docs/design/shell-and-bars/zebar.md) for Windows, and stops on a module it has no mapping for.

## Captions and spacing

The bar has no icons.
Each readout is a Russian caption and a figure: `цп 8 %`, `озу 17 %`, `41 °`, `сеть 92 %`, `звук 35 %`, `бат 85 %`, `12 пакетов`.
Each state is a word: `сон` and `не спать`, `тихо`, `нет сети`, `макс` and `эко`, `usb`, `бт 1`.
The few marks (№ ¶ — · ° ↑) are ordinary characters of the text fonts.
The old bar set Nerd Font glyphs, and it needed a spacing rule per gap because glyph advances differ.
Words set in one face need none.

| Element | Face | Set in |
|---|---|---|
| nameplate, "№ 4", clock | Fraunces 17, 18 and 21, weights 500, 500 and 600 | `style.css`: `#custom-nameplate`, `#workspaces button`, `#clock` |
| window title, date, playing track | EB Garamond Italic 17, 17 and 16, in `@subtext` | `style.css`: `#window`, `#custom-date`, `#mpris` |
| captions and figures, `en` and `ru`, ¶, tooltips | Literata 16, 14 on the laptop and in tooltips | the house span in `modules.jsonc`, and `*` in `style.css` |

The house caption span is spelled exactly `<span font_features='smcp, lnum, tnum'>…</span>`, and it wraps each caption and figure.
`smcp` sets the word in Literata's small caps, which include Cyrillic.
EB Garamond has small caps for Latin only, which is why the upright face is Literata.
`lnum` and `tnum` make the figures lining and tabular, so a column keeps its width as digits change.
A nested `<span alpha='55%'>` fades the caption word, and the figure keeps the full ink.
A narrow no-break space (U+202F) sits between a figure and its unit: `8 %`, `41 °`.
OpenType features live only in that span.
GTK3 CSS has no reliable `font-feature-settings`, and Pango 1.58 has no `font_variations` attribute, so Fraunces's optical size follows the pixel size.

### The modules

| Module | Shows | Click or scroll |
|---|---|---|
| `custom/nameplate` | the theme's bar name, `MENU_NAME` from `themes/current/meta.sh`, read once per start | click: nwg-drawer, the app grid |
| `hyprland/workspaces` | "№ 4" for the monitor's own workspace | scroll: the previous or next workspace |
| `hyprland/window` | the window title, at most 48 characters (32 on the laptop), browser and editor suffixes removed | none |
| `clock` | `HH:MM`, with a month calendar in the tooltip | click: the calendar; right-click: month or year; scroll: shift the tooltip |
| `custom/date` | "вторник, 6 октября" from `waybar-date.sh`, lowercased by Pango | click: the calendar |
| `custom/notification` | ¶, faint when clear, `@yellow` when a note waits, at 40 % opacity under do-not-disturb | click: the swaync column; right-click: do-not-disturb |
| `mpris` | "title — artist", 36 characters, faded while paused, gone when stopped | click: play or pause; middle: previous; right: next |
| `privacy` | Waybar's own marks in `@red`, only while the screen or a microphone is captured | none |
| `hyprland/language` | `en` or `ru` in small caps | click: `kb-layout.sh toggle` |
| `group/readouts` | `цп`, `озу` and the CPU temperature, which `waybar-cputemp.sh` finds by sensor name and turns red above 82 °C | none |
| `group/tools` | `сеть` or `нет сети`, `бт 1` while a device is connected, `сон` or `не спать`, `макс` or `эко`, `usb` while removable media is mounted | the network picker, blueman, Thunar |
| `pulseaudio` | `звук 35 %`, or `тихо` when muted | click: pavucontrol; right-click: mute |
| `battery` | `бат 85 %`, with ↑ and `@green` while charging, `@yellow` from 30 %, `@red` and blinking from 15 % | none |
| `custom/updates` | "12 пакетов", with the Russian plural from `waybar-updates.sh`; hidden at zero | click: `dram update` in kitty |
| `backlight` | `ярк 40 %`, on the laptop bar only | scroll: brightness |

The power profile's resting state, balanced, shows nothing, and its box collapses through the `.balanced` class.
The laptop bar drops the nameplate, the playing track, the readouts, the updates and Bluetooth, adds the backlight, and sets its type 2 px smaller.
Its rules key on the bar's name: `window#waybar.laptop`.

### The rhythm

Both bars set `"spacing": 0` in `config.jsonc`, and the CSS owns each gap.

- Each module has `margin: 0 7px`, 14 px from rail to rail, and `padding: 0 6px`, the width the hover rule underlines.
- A transparent `border-bottom` holds the 1 px the hover rule uses, so hover does not move the bar.
- Hover is `border-bottom-color: @accent`, on modules that do something when clicked.
- The clock and the date read as one unit, with no margins between them: 5 px of the clock's padding, the date's tick, then 6 px of the date's.
- A section opens with a short vertical tick, 20 px of `@rule` and 16 px on the laptop, on its first module: the date, ¶, the layout, the readouts, the tools and the volume (on the laptop, the brightness).
- The tick is a 1 px `background-image` gradient and not a `border-left`, so the module's box and its hover rule stay level with their neighbors.
- `#cpu`, `#memory`, `#custom-cputemp`, `#pulseaudio` and `#battery` have `min-width: 64px`, so a column keeps its width as its digits change.

Two derived inks sit under the theme's `@import`: `@define-color rule alpha(@text, 0.18)` for the hairline, the ticks and the tooltip border, and `@define-color faint alpha(@text, 0.55)` for the quiet ¶.
`style.css` names no hex color, and `bin/check-waybar.py` reads it to make sure.

### Adding a module

1. For a caption and a figure, copy the outer span from a neighbor: `"format": "<span font_features='smcp, lnum, tnum'><span alpha='55%'>слово</span> {value} %</span>"`.
2. For a state word, use the same outer span, fade the quiet state, and set the alert state in full ink with a theme color in `style.css`.
3. Add the module's id to the shared rhythm selector in `style.css`, and to the hover list if it is clickable.
4. Run `python3 bin/check-waybar.py` from the repo, or `dram check`.

## Files

| File | What it does |
|---|---|
| `config.jsonc` | the two bars: which output, which modules in which order, height 44 px (36 on the laptop) |
| `modules.jsonc` | each module's format, interval and clicks, included by both bars |
| `style.css` | the palette import, the two derived inks, and the fonts, sizes, gaps and alert colors |
| `dotfiles/.local/bin/waybar-date.sh` | the dateline, Russian when the locale exists |
| `dotfiles/.local/bin/waybar-cputemp.sh` | the CPU package temperature as one line of JSON |
| `dotfiles/.local/bin/waybar-updates.sh` | the pending-updates badge, cached for 30 minutes |
| `dotfiles/.local/bin/waybar-fullscreen.sh` | hides the bar over a fullscreen window |
| `dotfiles/.local/bin/waybar-toggle.sh` | hides or shows the bar by hand |
| `dotfiles/.local/bin/gsimplecal-dram.sh` | opens the themed calendar under the clock ([gsimplecal](../gsimplecal/README.md)) |
| `bin/check-waybar.py` | the checks above, run by `bin/check.sh` §10 |

## License

MIT, Patrick Jordan.

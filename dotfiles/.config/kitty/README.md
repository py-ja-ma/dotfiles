# kitty

[Design](../../../docs/design/README.md) › [Shell & bars](../../../docs/design/shell-and-bars/README.md) › Terminal

The Letterpress terminal for kitty: Monaspace type on a faint paper grain, with the tabs set as a running head.
Each tab's title starts with its number, as in `№ 2  btop`, and the date in Russian closes the bar at the right.
The colors come from the active theme, and the shell, the prompt and the tools inside are on the [Terminal](../../../docs/design/shell-and-bars/terminal.md) page.

| | |
|---|---|
| Needs | kitty 0.49.2, tested 2026-10; Monaspace Xenon and Radon, Symbols Nerd Font Mono; a colors file |
| Copy alone | yes, after giving the `include` on its last line a colors file |
| License | MIT |

## What it needs

- kitty 0.49.2 from Arch's `extra` repo, tested 2026-10.
- Monaspace Xenon for the text and Monaspace Radon for italics, from `otf-monaspace` 1.400, and Symbols Nerd Font Mono from `ttf-nerd-fonts-symbols-mono` 3.5.1 ([Typography](../../../docs/design/typography/README.md)).
  Until Monaspace is installed, kitty gets fontconfig's next monospace face, JetBrainsMono Nerd Font here (`modules/desktop.nix`).
- A colors file at `~/.config/themes/current/kitty.conf`, which the last line of `kitty.conf` includes.
  It sets the paper and the inks, `color0` to `color15`, the cursor, the split borders, the five tab colors, `url_color` and `cursor_trail_color`.
  Each of the 17 themes in `dotfiles/.config/themes/` has one ([themes](../themes/README.md)).
- The `ru_RU.UTF-8` locale for a Russian date in the tab bar, which `system/locale-setup.sh` generates here.
  Without it the date is English.
- Python 3, only to write the five tab lines again with `bin/gen-kitty-tabs.py`.
- Not needed: Nix, Home Manager, `dram` or Hyprland.

## Copy it alone

1. Install kitty and the three fonts.
2. Copy `kitty.conf`, `tab_bar.py` and `grain.png` to `~/.config/kitty/`.
   kitty loads `tab_bar.py` from that directory, and `kitty.conf` names `~/.config/kitty/grain.png`.
3. Give it colors.
   Copy one theme's `kitty.conf` to `~/.config/themes/current/kitty.conf`, for example from `dotfiles/.config/themes/washi/`.
   Or point the `include` on the last line of `kitty.conf` at a colors file of your own, with the five tab colors set as the table under [The running head](#the-running-head) shows.
4. On a desktop that expects title bars, such as GNOME, delete `hide_window_decorations yes`.
   Hyprland draws the frame here.
5. For the Russian date, uncomment `ru_RU.UTF-8 UTF-8` in `/etc/locale.gen` and run `sudo locale-gen`.
   For a date in another language, change the locale in the `locale.setlocale` line of `tab_bar.py`.
6. Start kitty and open a second tab with ctrl+shift+t.
   It worked when the bar at the top shows `№ 1` and `№ 2` with a middle dot between them, the active title in italic in the accent, and the date at the right.
   The grain is a faint texture under the text.
   To compare, set `background_tint 1.0` and reload the configuration with ctrl+shift+F5.

## How it is wired here

`modules/desktop.nix` links `dotfiles/.config/kitty` whole to `~/.config/kitty` on hosts with the desktop role, and sets `TERMINAL=kitty`.
SUPER+Q opens it, and Hyprland floats its `cava-visualizer` and `nmtui` windows ([hypr](../hypr/README.md)).
`dram theme` repoints `themes/current` and sends `SIGUSR1` to each kitty, which reads `kitty.conf` and the new colors again.
`bin/check-themes.py`, which `bin/check.sh` §14 runs, holds each theme's `kitty.conf` to the same color keys and its `cursor_trail_color` to the theme's accent.
`bin/gen-kitty-tabs.py` writes the five tab lines, and no check compares them with their sources, so a palette change needs a run by hand.
On Windows, `bin/gen-windows-look.py` turns each theme's `kitty.conf` into a Windows Terminal color scheme.
It also repeats this file's font, features, cursor shape, padding and scrollback for Windows Terminal ([Terminal](../../../docs/design/shell-and-bars/terminal.md)).

## Type

| Setting | Value |
|---|---|
| `font_family` | Monaspace Xenon, the slab-serif mono, with `+calt +liga +ss01 +ss02 +ss03` |
| `italic_font` | Monaspace Radon, the handwritten member of the family |
| `bold_font`, `bold_italic_font` | `auto`: the bold faces of the same families |
| `font_size` | 12 pt |
| `modify_font cell_height` | 110 %: a slab serif wants more leading than a grotesk |
| `disable_ligatures` | `cursor`: the cell under the cursor shows the plain characters |
| `symbol_map` | `U+E000` to `U+F8FF` and `U+F0000` to `U+FFFFF` in Symbols Nerd Font Mono |

`calt` turns on Monaspace's texture healing, and `liga` with `ss01` to `ss03` its ligatures.
Monaspace has no private-use glyphs, so `symbol_map` sends the Nerd Font ranges to the one symbol font, and a program that prints an icon still gets one.
Italics are where Radon shows: the active tab's title, and what the shell and the editors set in italic.

## The running head

`tab_bar_style custom` hands the tab bar to `tab_bar.py`.
It draws each tab with kitty's own `draw_tab_with_separator`, the function behind the `separator` style, so the title template, `tab_separator " · "` and the theme's tab colors apply as usual.
After the last tab it sets the date flush right, in italic and in the inactive ink: "Вторник, 6 октября", or "Tuesday, 6 October" when `ru_RU.UTF-8` is missing.
It tries the locale once, when kitty loads the module, and works the date out once a day.
When the tabs need the room, the date gives way.

Each title is `№ {index}  {title}`, the bar's "№ 4" numeral again.
Monaspace 1.400 carries № (U+2116), so the numeral is set in the terminal's own face.
A bell and activity show as printer's marks in red before the numeral, `! ` and `* `, set by `bell_on_tab` and `tab_activity_symbol` and colored by `{fmt.fg.red}` in the template.
The active title is set in italic and in the accent, and the inactive ones in the upright face and the second ink.
The bar sits at the top, 6 pt below the window's edge and 2 pt above the text, and appears only with two tabs or more (`tab_bar_min_tabs 2`).

The five tab colors in each theme's `kitty.conf` are generated from colors the theme already states:

| kitty option | Value | Taken from |
|---|---|---|
| `active_tab_foreground` | the accent, as ink on the active title | the theme's `cursor_trail_color` |
| `active_tab_background` | the paper | its `background` |
| `inactive_tab_foreground` | the second ink, which the date uses too | `@subtext` in its `waybar.css` |
| `inactive_tab_background` | the paper | its `background` |
| `tab_bar_background` | the paper, so the bar is part of the sheet | its `background` |

`bin/gen-kitty-tabs.py` writes those five lines in each theme's `kitty.conf`, or in the themes it is given, and leaves the other lines alone.
It prints each file it rewrote, and is silent when the lines already match.
Commit what it writes.

```sh
python3 bin/gen-kitty-tabs.py          # each theme
python3 bin/gen-kitty-tabs.py washi    # one theme
```

`tab_bar_margin_width` stays unset.
kitty paints side margins opaque, which shows as a dark notch on the translucent sheet, and the separator's leading space is the gap.
If `tab_bar.py` fails to load, kitty logs it and draws its `fade` style with the same colors.
An error inside the running head is caught, and the tabs draw without the date.

## Paper grain

`grain.png` is a 256 × 256 tile of 8-bit gray noise around middle gray (mean 128, standard deviation 18), 39,816 bytes.
kitty repeats it across the window, as `background_image_layout tiled` asks.
`background_tint 0.97` tints it 97 % toward the theme's background, so 3 % of the texture survives under the text.
`background_tint_gaps 1.0` tints the padding the same way.
The tint takes the theme's own background, so the one tile works on dark and light paper.
`background_opacity` stays 0.92, and Hyprland's blur is off, so the wallpaper shows faintly through the paper with no frost ([Blur](../hypr/README.md#blur)).
`background_tint 1.0` turns the grain off and keeps the image in place.
The tile is a committed file, with no generator in the repo.
The grain over the whole screen is a separate shader: [Grain shader](../hypr/README.md#grain-shader).

## Window and cursor

- The cursor is a 1.6 px beam that blinks at 0.5 s intervals, and it leaves a trail in the accent when it jumps more than two cells (`cursor_trail_start_threshold 2`).
- Windows have 10 px of padding and no title bar, and a new window opens centered.
- The scrollback keeps 20,000 lines, and its pager reaches 32 MB back.
- A command that runs longer than 10 s in an unfocused window ends with a notification (`notify_on_cmd_finish`), which needs kitty's shell integration.
- The bell flags the window and makes no sound.
- A link under the pointer gets a curly underline, and a copied selection loses its trailing spaces.
- kitty arranges its splits in two layouts of its own, `splits` and `stack`, apart from Hyprland's tiling.

## Keys

`kitty_mod` is kitty's default, ctrl+shift, so these keys stay apart from Hyprland's SUPER keys.

| Keys | Action |
|---|---|
| ctrl+shift+enter | a new split in the current directory |
| ctrl+shift+`\` | a split to the side, in the current directory |
| ctrl+shift+minus | a split below, in the current directory |
| ctrl+shift+h, j, k, l | move between splits, as in vim |
| ctrl+shift+t | a new tab in the current directory |
| ctrl+shift+p, then f, l, w or h | copy a path, a line, a word or a hash from the screen |
| ctrl+shift+p, then o | open a path from the screen |
| ctrl+shift+u | type a character by its name or code point |
| ctrl+shift+delete | clear the screen and the scrollback |
| ctrl+shift+g | the scrollback in a pager, moved from ctrl+shift+h |
| ctrl+shift+z | the `stack` layout, moved from ctrl+shift+l |

## Files

| File | What it does |
|---|---|
| `kitty.conf` | type, cursor, window, grain, tab bar and keys, and the `include` of the theme's colors |
| `tab_bar.py` | the running head: kitty's separator tabs, then the date |
| `grain.png` | the paper-grain tile |
| `dotfiles/.config/themes/<id>/kitty.conf` | each theme's colors, with five generated tab lines |
| `bin/gen-kitty-tabs.py` | writes those five lines |

## License

MIT, Patrick Jordan, for `kitty.conf`, `tab_bar.py` and `grain.png`.
`tab_bar.py` is a kitty plugin: kitty loads it, and it calls kitty's tab-bar API at run time, `draw_tab_with_separator` and the drawing types from `kitty.tab_bar`, `kitty.fast_data_types` and `kitty.utils`.
It copies no kitty code.
kitty itself is GPL-3.0, Kovid Goyal.

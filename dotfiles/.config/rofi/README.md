# rofi

[Design](../../../docs/design/README.md) › [Shell & bars](../../../docs/design/shell-and-bars/README.md) › Launchers

The Letterpress launcher for rofi: a search line on one accent rule over a list of names, with no icons.
The entry is set in Fraunces and the results in Monaspace Xenon, and the selected result carries a 2 px accent rule on its left.
The same look serves the desktop's other lists: the windows, the clipboard, the power menu and the theme picker.

| | |
|---|---|
| Needs | rofi 2.0.0, tested 2026-10; Fraunces, EB Garamond, Literata, Monaspace Xenon; a theme file |
| Copy alone | yes, after giving `config.rasi` a theme file |
| License | MIT |

## What it needs

- rofi 2.0.0 from Arch's `extra` repo, tested 2026-10, which runs on Wayland natively.
- The fonts: Fraunces for the entry, EB Garamond Italic for the prompt and the placeholder, Monaspace Xenon for the list and Literata Italic for messages ([Typography](../../../docs/design/typography/README.md)).
  Fraunces has no Cyrillic, so typed Russian falls to Literata through `60-letterpress.conf`, the fontconfig rule that `modules/desktop.nix` writes.
- A theme file at `~/.config/themes/current/rofi.rasi`, which the last line of `config.rasi` loads.
  Each of the 17 themes in `dotfiles/.config/themes/` has one, written from `theme.rasi.tmpl` ([The generated theme](#the-generated-theme)).
- For the power menu, `power-menu.sh` from `dotfiles/.local/bin/`, with hyprlock, systemd and Hyprland's Lua dispatcher.
- Python 3, only to write the theme files again with `bin/gen-rofi-themes.py`.
- Not needed: Nix, Home Manager, `dram` or Hyprland, for the launcher itself.

## Copy it alone

1. Install rofi 2.0.0 and the four fonts.
2. Copy `config.rasi` to `~/.config/rofi/`.
3. Give it a theme file.
   Copy one theme's `rofi.rasi` to `~/.config/themes/current/rofi.rasi`, for example from `dotfiles/.config/themes/washi/`, or point the `@theme` line at the end of `config.rasi` at your copy.
   For colors of your own, copy `theme.rasi.tmpl` and replace each `{{...}}` token with a color as `#rrggbb`.
   The template appends `f5` to `{{BASE}}` for paper at 96 % and `2e` to `{{TEXT}}` for a hairline at 18 %, so each token takes six hex digits.
   Four tokens show: `{{BASE}}`, `{{TEXT}}`, `{{SUBTEXT}}` and `{{ACCENT}}`.
   The template turns the other three into `bg-alt`, `surface` and `red` and uses none of them (2026-10).
4. Optionally copy `dotfiles/.local/bin/power-menu.sh` to `~/.local/bin/`, make it executable and bind it to a key.
   Its `logout` runs `hyprctl dispatch 'hl.dsp.exit()'`, Hyprland's Lua dispatcher, so change that line for another compositor.
5. Run `rofi -show drun`.
   It worked when a 560 px card opens with the prompt `apps` in italic and `что ищем?` on an accent rule, over seven names without icons.
   The arrow keys move a 2 px accent rule down the left of the list, and the selected name turns to the accent.

## How it is wired here

`modules/desktop.nix` links `dotfiles/.config/rofi` whole to `~/.config/rofi` on hosts with the desktop role, and `power-menu.sh` into `~/.local/bin`.
rofi reads `config.rasi` and the theme file each time it starts, so a theme switch reaches the next list with no reload.
These lists are rofi, and each takes this theme:

| Key | List | Runs |
|---|---|---|
| SUPER+R, SUPER+SPACE | apps | `rofi -show drun` |
| SUPER+Tab | open windows, from each workspace | `rofi -show window -modes window` |
| SUPER+SHIFT+V | the clipboard history | `cliphist list`, then `rofi -dmenu` |
| SUPER+= | a calculator, where Enter copies the result | `rofi -show calc`, from rofi-calc 2.5.1 |
| SUPER+. | emoji | rofimoji 6.8.0 |
| SUPER+T | the themes | `dram-theme` |
| SUPER+/ | the keys, 780 px wide and 16 lines long | `keybind-cheatsheet.sh` |
| SUPER+X, SUPER+M | the power menu, five lines long | `power-menu.sh` |
| SUPER+SHIFT+W | the wallpapers | `wallpaper-menu.sh` |

`bin/gen-rofi-themes.py` writes the theme files, and `bin/check.sh` doesn't run it, so a palette change needs a run by hand.
`bin/check-themes.py`, which `bin/check.sh` §14 runs, holds each theme to the same file set, so each has a `rofi.rasi`.

## The search line

rofi on SUPER+R and nwg-drawer on SUPER+G share one search line: a Fraunces entry on a single 1 px accent rule, with no box and no icon.
The drawer's half is in [nwg-drawer](../nwg-drawer/README.md).
In rofi it is set like this:

| Part | Set in |
|---|---|
| prompt | EB Garamond Italic 15 in `@muted`, the theme's second ink: `apps`, `run`, `power` |
| entry | Fraunces 22, with a 2 px cursor in the accent |
| placeholder | `что ищем?` in EB Garamond Italic at 19 pt, in `@muted` |
| rule | the input bar's bottom border, 1 px in `@accent` |
| results | Monaspace Xenon 12, seven lines, 2 px apart |
| selected result | a 2 px accent rule on its left and the name in the accent, with no fill |
| message | Literata Italic 13 in `@muted`, over a hairline |
| window | 560 px wide, the paper at 96 %, a 1 px hairline at 18 % of the ink, 3 px corners |

Fraunces has no Cyrillic, so the placeholder is Pango markup (`placeholder-markup: true`) in the prompt's face.
Its size, `size='19456'`, is 19 pt in Pango's units of 1/1024, which matches Fraunces 22's x-height.
Typed Latin stays in Fraunces, and typed Russian falls to Literata through `60-letterpress.conf`.
rofi replaced wofi, which had gone unmaintained.
`show-icons: false` keeps the list to text: I dislike mismatched app icons, and the wofi setup had none either.
The apps appear by `{name}` alone, matched fuzzily and sorted the way fzf sorts.
`terminal: "kitty"` opens the apps that ask for a terminal in kitty.
The launcher and the drawer are flat paper, since Hyprland's blur is off ([Blur](../hypr/README.md#blur)).

## Power menu

SUPER+X and SUPER+M run `power-menu.sh`: a `rofi -dmenu` list of five words in the theme's rofi style.
Type a letter to filter, or pick with the arrow keys, then press Enter.
Esc closes the list with no action.
`-no-custom` accepts only the five words, and `-theme-str 'listview { lines: 5; }'` sizes the list to them.

| Word | Runs |
|---|---|
| `lock` | `hyprlock`, unless one is already running |
| `logout` | `hyprctl dispatch 'hl.dsp.exit()'` |
| `suspend` | `systemctl suspend` |
| `reboot` | `systemctl reboot` |
| `shutdown` | `systemctl poweroff` |

The menu has no icons, no cards and no file of its own in the themes.
It replaced wlogout and `wlogout-menu.sh` on 2026-10-10, when wlogout failed the community rule of [the software rules](../../../decisions/0013-software-rules-and-waivers.md).
wlogout's typeset columns and its margins per monitor went with it.
SUPER+M used to leave Hyprland at once with no question asked, and it opens this menu too, where `logout` does that.

## The generated theme

The 17 `rofi.rasi` files differ only in seven colors, so they come from one template.
`bin/gen-rofi-themes.py` fills `theme.rasi.tmpl` with the theme's colors and writes `dotfiles/.config/themes/<id>/rofi.rasi`:

| Token | Becomes | Taken from the theme's `waybar.css` |
|---|---|---|
| `{{BASE}}` | `bg` with `f5` appended, the paper at 96 % | `@define-color base` |
| `{{SURFACE0}}` | `bg-alt` | `surface0` |
| `{{SURFACE1}}` | `surface` | `surface1` |
| `{{TEXT}}` | `fg`, and `hairline` with `2e` appended, the ink at 18 % | `text` |
| `{{SUBTEXT}}` | `muted` | `subtext` |
| `{{RED}}` | `red` | `red` |
| `{{ACCENT}}` | `accent` | `accent`, else `accent` in the theme's `palette.lua`, else `blue` |

Each of the 17 `waybar.css` files defines its accent (2026-10), so the two fallbacks go unused.
`{{NAME}}` becomes the theme's id in the header comment.
The output is committed, and rofi reads it directly.
After changing the template or a palette, run the generator and commit both:

```sh
python3 bin/gen-rofi-themes.py          # each theme
python3 bin/gen-rofi-themes.py washi    # one theme
```

It prints each file it rewrote, and is silent when the files already match.
A `waybar.css` that lacks one of the colors stops it with the theme's id and the missing tokens.

## Files

| File | What it does |
|---|---|
| `config.rasi` | the modes, the list's font, no icons, fuzzy matching, and the `@theme` line |
| `theme.rasi.tmpl` | the layout, the fonts and the rules, with seven color tokens |
| `dotfiles/.config/themes/<id>/rofi.rasi` | each theme's generated file |
| `bin/gen-rofi-themes.py` | writes those files from the template |
| `dotfiles/.local/bin/power-menu.sh` | the power menu |

## License

MIT, Patrick Jordan.

# themes

[Design](../../../docs/design/README.md) › [Themes](../../../docs/design/themes/README.md) › Palettes

Seventeen color themes, one directory each, which the desktop's apps read through one symlink.
Each theme is a paper color, a body ink and one accent ink, written out in the format each app wants: CSS for Waybar and GTK, a block for `kitty.conf`, a Lua table for Hyprland.
The bar shows each theme under a drink name, and the [gallery](../../../docs/design/README.md) pictures all of them.
The directory name is the stable id that scripts and the `current` symlink use.

| | |
|---|---|
| Needs | the apps you theme, each with one include line; Python 3 to regenerate the six generated files |
| Copy alone | yes: copy the directory, link `current` to one theme, add one include line per app |
| License | MIT, except the ported palettes, which keep their upstream licenses (see the table below): the six from ryoku-arch are GPL-3.0 |

## What it needs

- The apps that read the files.
  Tested on cabin in 2026-10: Hyprland 0.56.2 with its Lua config, Waybar 0.15.0, kitty 0.49.2, rofi 2.0.0, swaync 0.12.6, swayosd 0.3.2, hyprlock 0.9.6, nwg-drawer 0.7.5, gsimplecal 2.5.3, cava 1.0.0, satty 0.22.0, LibreWolf and Thunderbird 157.
- GTK 3.24 and 4.24 with adw-gtk-theme 6.5 for `gtk.css` and `gtk3.css`.
  The two files recolor adw-gtk3 and libadwaita, so another GTK theme ignores most of them.
- btop 1.4 or later, which looks a theme up by name in its own themes directory.
- fzf with `FZF_DEFAULT_OPTS_FILE` support.
- Python 3 (3.14 tested) for the generators in `bin/` and for `bin/check-themes.py`.
- Not needed: Nix, Home Manager or `dram`.
  `dram-theme` switches themes and reloads the apps, and a symlink plus the reloads do the same by hand.

The files for apps you do not run do no harm: nothing reads them.

## Copy it alone

1. Copy `dotfiles/.config/themes/` to `~/.config/themes/`.
2. Pick a theme with a relative link: `ln -sfn washi ~/.config/themes/current`.
3. Add the line for each app you use, always through `current`:

   | App | Line | In |
   |---|---|---|
   | Waybar | `@import url("../themes/current/waybar.css");` | `~/.config/waybar/style.css` |
   | swaync | `@import url("../themes/current/swaync.css");` | `~/.config/swaync/style.css` |
   | swayosd | `@import url("../themes/current/swayosd.css");` | `~/.config/swayosd/style.css` |
   | nwg-drawer | `@import url("../themes/current/waybar.css");` | `~/.config/nwg-drawer/drawer.css` |
   | rofi | `@theme "~/.config/themes/current/rofi.rasi"` | `~/.config/rofi/config.rasi` |
   | kitty | `include ~/.config/themes/current/kitty.conf` | `~/.config/kitty/kitty.conf` |
   | hyprlock | `source = ~/.config/themes/current/hyprlock.conf` | `~/.config/hypr/hyprlock.conf` |
   | Hyprland | `local theme = dofile(os.getenv("HOME") .. "/.config/themes/current/palette.lua")` | `~/.config/hypr/hyprland.lua` |
   | GTK 4 | a symlink `~/.config/gtk-4.0/gtk.css` to `~/.config/themes/current/gtk.css` | |
   | GTK 3 | a symlink `~/.config/gtk-3.0/gtk.css` to `~/.config/themes/current/gtk3.css` | |
   | fzf | `export FZF_DEFAULT_OPTS_FILE=~/.config/themes/current/fzf.opts` | your shell's profile |
   | btop | a symlink `~/.config/btop/themes/dram.theme` to `~/.config/themes/current/btop.theme`, then `color_theme = "dram"` | `~/.config/btop/btop.conf` |

   The relative `@import` lines resolve against the app's own directory under `~/.config`, so they work only when the app loads its stylesheet from there.
4. Reload: `hyprctl reload`, `pkill -SIGUSR1 kitty`, and restart Waybar, which keeps an imported color file cached.
5. To switch later, repoint `current` and reload again.
   Or copy `dotfiles/.local/bin/dram-theme`, which also patches cava, satty, yazi and VSCodium and restarts the bar: see the [switcher](../../../docs/design/themes/switcher.md).

It worked when `readlink ~/.config/themes/current` prints the theme's id and kitty, Waybar and rofi show its paper and its accent.

## How it is wired here

`modules/cli.nix` links `dotfiles/.config/themes` whole to `~/.config/themes`.
On the first activation it also links `current` to washi, because Hyprland does not start while `palette.lua` is missing.
`dram theme`, which is `dotfiles/.local/bin/dram-theme`, repoints `current`, rewrites the machine-state files and reloads the apps: the [switcher](../../../docs/design/themes/switcher.md) page has the details.
Seven scripts in `bin/` write the generated files from the hand-written ones: the [generators](../../../docs/design/themes/generators.md) page lists them.
`bin/check.sh` §14 runs `bin/check-themes.py`, which fails when the 17 directories stop matching:

| Rule | What fails |
|---|---|
| 1 | a theme whose file set differs from the others |
| 2 | a hand-written file whose keys differ from the same file in another theme |
| 3 | a `meta.sh` that does not source under bash, lacks `MENU_NAME`, `VSCODIUM_THEME` or `YAZI_FLAVOR`, or repeats another theme's `MENU_NAME` |
| 4 | a `VSCODIUM_THEME` other than `Letterpress — <MENU_NAME>` |
| 5 | a `YAZI_FLAVOR` other than `letterpress-<id>`, or a flavor directory that does not exist |
| 6 | an accent that differs between the six places listed under [The accent contract](#the-accent-contract) |

Rule 1 is why this README sits here and never inside a theme's directory.
The boot chain does not follow the theme: rEFInd, Plymouth and ly keep a fixed house palette, explained under [boot screens](../../../docs/design/shell-and-bars/boot-screens.md).
Windows takes its look from washi's files through `bin/gen-windows-look.py`: see the [Windows look](../../../docs/design/themes/windows.md).
The steps for switching and for adding a theme on a host are in [handbook chapter 6](../../../docs/records/handbook/06-theme-and-look.md).

## The palette slots

`waybar.css` holds the master palette: 21 colors under Catppuccin's names, defined the same way in each theme.
Fill them from any palette and the generators do the rest.

| Slot | What it is | Read by |
|---|---|---|
| `base` | the paper: window, bar and editor background | the generators, Waybar, swaync, nwg-drawer, gsimplecal |
| `mantle` | one step off the paper: sidebars, inputs, the reading surface | GTK, the browser chrome, VSCodium, Windows |
| `crust` | the deepest step: the gradient's foot, the mail app's rail | GTK, the browser chrome, VSCodium, Windows |
| `text` | the body ink | the generators, Waybar, swaync, nwg-drawer, gsimplecal |
| `subtext` | the second ink: dates, captions, comments, inactive titles | Waybar, rofi, the kitty tab bar, btop, yazi, VSCodium, the browser chrome |
| `overlay` | the faint ink: disabled text and placeholders | btop, yazi, VSCodium, the browser chrome |
| `surface0` | a paper shade: the cursor row, cards, popovers on a dark page | GTK, rofi, btop, yazi, VSCodium, the browser chrome |
| `surface1` | a deeper shade: selected rows | rofi, btop, yazi, VSCodium, the browser chrome |
| `red`, `green`, `yellow` | error, success and warning | GTK, Waybar, the browser chrome, yazi, VSCodium, Windows |
| `blue`, `teal`, `peach`, `mauve` | syntax and file-type hues; `blue` is also the link color | VSCodium, yazi, Windows |
| `maroon`, `sky`, `pink` | extra hues for a few Windows apps | `bin/gen-windows-look.py` |
| `lavender`, `sapphire` | the rest of Catppuccin's set | nothing reads them (2026-10) |
| `accent` | the one accent ink | see [The accent contract](#the-accent-contract) |

The other hand-written files repeat part of that palette in their own syntax:

| File | Keys |
|---|---|
| `palette.lua` | `accent`, `accent_dim` (the accent's darker step), `active1`, `active2`, `angle`, `inactive`, `shadow`, as `rgba(rrggbbaa)` strings |
| `hyprlock.conf` | `$base`, `$base90`, `$text`, `$subtext`, `$accent`, `$check`, `$fail`, as `rgba(r, g, b, a)` |
| `swaync.css` | ten of the waybar names, from `base` to `accent` |
| `swayosd.css` | `osd-bg`, `osd-border`, `osd-fg`, `osd-progress`, `osd-trough` |
| `kitty.conf` | `foreground`, `background`, the selection and cursor colors, `color0` to `color15`, the window borders, `url_color`, `cursor_trail_color` |
| `fzf.opts` | fzf's `--color` lines |
| `satty.toml` | one `palette = [...]` line of four to six annotation colors |

## The accent contract

Each theme names its accent in six places, all with the same hex, and `bin/check-themes.py` rule 6 fails otherwise:

| Slot | File | Read by |
|---|---|---|
| `@define-color accent` | `waybar.css` | Waybar's workspace numeral and hover rules; nwg-drawer and gsimplecal import it |
| `@define-color accent` | `swaync.css` | the rule down a notification's edge, the do-not-disturb switch |
| `@define-color osd-progress` | `swayosd.css` | the volume and brightness bar |
| `$accent` | `hyprlock.conf` | the rule under the clock and `check_color` |
| `accent` | `palette.lua` | Hyprland's active border, a 45° gradient from `accent` to `accent_dim`. The generators read the accent here or from `waybar.css`, which `bin/check-themes.py` keeps equal |
| `cursor_trail_color` | `kitty.conf` | the cursor's trail; the generated tab-bar lines take it too |

`hyprland.lua` falls back to `active1` and `active2` when a theme has no `accent`.
One exception is written into the checker: solarized-paper's OSD bar is `#826200`, its darker yellow, in place of `#b58900`, so the bar reads on the light paper.
The accent is the color each theme already used for the active border: vermilion `#c0442b` for washi, ochre for cassette, amber `#b58900` for solarized-paper, blue for the two Catppuccin themes.

## What each theme file controls

Fifteen files, the same set in each theme (rule 1):

| File | Read by | How | Written by |
|---|---|---|---|
| `waybar.css` | Waybar, nwg-drawer, gsimplecal, `quote-wallpaper.sh`, the generators | `@import` through `current` | hand |
| `swaync.css` | swaync | `@import` | hand |
| `swayosd.css` | swayosd | `@import` | hand |
| `hyprlock.conf` | hyprlock | `source` | hand |
| `palette.lua` | `hyprland.lua` | `dofile()` at start and on `hyprctl reload` | hand |
| `kitty.conf` | kitty | `include`; kitty reloads on SIGUSR1 | hand, except five tab-bar lines from `bin/gen-kitty-tabs.py` |
| `fzf.opts` | fzf | `FZF_DEFAULT_OPTS_FILE` | hand |
| `satty.toml` | satty | `dram-theme` copies its `palette = [...]` line into `~/.config/satty/config.toml` | hand |
| `meta.sh` | `dram-theme`, the bar's nameplate, the generators | sourced as shell | hand |
| `rofi.rasi` | rofi | `@theme` | `bin/gen-rofi-themes.py`, from `dotfiles/.config/rofi/theme.rasi.tmpl` |
| `gtk.css` | GTK 4 and libadwaita apps | linked at `~/.config/gtk-4.0/gtk.css` | `bin/gen-gtk-css.py` |
| `gtk3.css` | GTK 3 apps through adw-gtk3 | linked at `~/.config/gtk-3.0/gtk.css` | `bin/gen-gtk-css.py` |
| `browser.css` | the LibreWolf and Thunderbird chrome | linked into each profile as `chrome/letterpress-colors.css` | `bin/gen-browser-css.py` |
| `btop.theme` | btop | linked at `~/.config/btop/themes/dram.theme` | `bin/gen-tui-themes.py` |
| `cava.theme` | cava | `dram-theme` splices it into the `[color]` block of cava's config | `bin/gen-tui-themes.py` |

`meta.sh` holds what is not a color:

| Key | Value |
|---|---|
| `GTK_THEME_NAME` | `adw-gtk3-dark` on a dark theme, `adw-gtk3` on a light one |
| `COLOR_SCHEME` | `prefer-dark` or `prefer-light`: the portal's color scheme, GTK's dark flag and the generators' light or dark derivations |
| `BAT_THEME` | the bat theme |
| `YAZI_FLAVOR` | `letterpress-<id>`, the theme's generated yazi flavor |
| `VSCODIUM_THEME` | `Letterpress — <MENU_NAME>`, the theme's generated VSCodium theme |
| `MENU_NAME` | the drink: what the picker, the notifications and the bar's nameplate show |

Icons and the pointer do not change with the theme: `dram-theme` sets GNOME's Adwaita for both.
Qt has no theme file and follows GTK through `QT_QPA_PLATFORMTHEME=gtk3`.

## Adding a theme

1. Copy the closest theme's directory, `washi` for a dark one or `washi-day` for a light one, to `themes/<id>/` with all 15 files.
2. Replace the colors in `waybar.css`, `swaync.css`, `swayosd.css`, `kitty.conf`, `hyprlock.conf`, `fzf.opts` and `satty.toml`.
   In `palette.lua` set `accent`, `accent_dim`, `active1`, `active2`, `inactive` and `shadow`.
   Put the same accent hex in each of the six places of the accent contract.
3. Fill `meta.sh`: the GTK theme and color scheme, the bat theme, `YAZI_FLAVOR="letterpress-<id>"`, a `MENU_NAME` that no other theme uses, and `VSCODIUM_THEME="Letterpress — <MENU_NAME>"`.
4. Run the generators for the new id:

   ```sh
   python3 bin/gen-rofi-themes.py <id>      # rofi.rasi
   python3 bin/gen-gtk-css.py <id>          # gtk.css and gtk3.css
   python3 bin/gen-kitty-tabs.py <id>       # the tab-bar lines of kitty.conf
   python3 bin/gen-tui-themes.py <id>       # btop.theme and cava.theme
   python3 bin/gen-browser-css.py <id>      # browser.css
   python3 bin/gen-yazi-flavors.py <id>     # dotfiles/.config/yazi/flavors/letterpress-<id>.yazi/
   python3 bin/gen-vscode-themes.py         # no argument: every theme, and package.json lists the new one
   python3 bin/check-themes.py              # the schema still holds
   ```

5. `dram theme <id>`, then look at the bar, a kitty window, rofi (SUPER+R), a notification (`notify-send hi`), hyprlock (SUPER+L), a GTK app and a Qt app.

## Where the palettes come from

Licenses checked on GitHub on 2026-10-13.

| Theme | Ported from | Upstream license |
|---|---|---|
| `aqua`, `cassette`, `crt`, `mountains`, `soft-color`, `washi` | ryoku-arch (github.com/neur0map/ryoku-arch) | GPL-3.0 for the repository |
| `catppuccin-latte`, `catppuccin-mocha` | Catppuccin | MIT |
| `everforest` | Everforest Dark Medium (sainnhe/everforest) | MIT |
| `gruvbox-dark` | Gruvbox (morhetz/gruvbox) | MIT/X11, as its README states |
| `kanagawa` | Kanagawa Wave (rebelot/kanagawa.nvim) | MIT |
| `nord` | Nord (nordtheme/nord) | MIT |
| `oxocarbon` | Oxocarbon (nyoom-engineering/oxocarbon.nvim) | MIT |
| `rose-pine` | Rosé Pine (rose-pine/kitty) | MIT |
| `solarized-paper` | Solarized Light's paper with darker accents (altercation/solarized) | MIT |
| `tokyo-night` | Tokyo Night (folke/tokyonight.nvim, its kitty extra) | Apache-2.0 |
| `washi-day` | mine: the light twin of washi, its hues darkened for paper | MIT |

The six ryoku-arch palettes are under its repository's GPL-3.0, and `REUSE.toml` marks their directories so.

## License

MIT, Patrick Jordan, for the theme files I wrote and the generated ones.
The ported palettes keep the licenses in the table above.

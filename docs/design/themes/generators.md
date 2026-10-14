# Generators

[Design](../README.md) › [Themes](README.md) › Generators

Eight Python scripts in `bin/` write the theme files that derive from each theme's hand-written palette, and `bin/check-themes.py` checks the palettes themselves.
The outputs are committed, so a host only reads them: change a palette on the Mac, run the generators, and commit what they wrote.
Only the Windows look has a check that fails while its output is stale.

| | |
|---|---|
| Code | `bin/gen-rofi-themes.py`, `bin/gen-gtk-css.py`, `bin/gen-kitty-tabs.py`, `bin/gen-tui-themes.py`, `bin/gen-browser-css.py`, `bin/gen-yazi-flavors.py`, `bin/gen-vscode-themes.py`, `bin/gen-windows-look.py`, `bin/check-themes.py` |
| Runs on | the Mac or a host with the repo, by hand; `bin/check.sh` runs the checker and the Windows check wherever it runs |
| Needs | Python 3 with its standard library (3.14.8 on cabin, tested 2026-10); bash, which `bin/check-themes.py` uses to source each `meta.sh` |
| Decided in | the Windows look from Arch's palettes ([decided 2026-10-12](../../../decisions/log.md#d84)); the Arch generators have no record |

## How it works

A theme is 15 files in `dotfiles/.config/themes/<id>/`.
Nine are written by hand: `waybar.css` holds the palette and `palette.lua` the accent.
The generators write the other six and five lines of `kitty.conf`, and the theme files that live elsewhere: the yazi flavors, the VSCodium themes and the Windows look.
[What each theme file controls](../../../dotfiles/.config/themes/README.md#what-each-theme-file-controls) says which file is which.

A generator takes theme ids as arguments and renders each theme when it gets none.
It writes a file only when the content changed and prints `wrote <path>` for it, so a second run is silent.
A palette that lacks a color the generator reads stops it with exit 1, and the message names the theme, the file and the missing names.
`--help` prints the script's inputs and its full color mapping.
How each output looks, and why, is on the app's own page, linked from the table.

| Script | Reads, from each theme | Writes | Check | Run |
|---|---|---|---|---|
| `gen-rofi-themes.py` | `waybar.css`: `base`, `surface0`, `surface1`, `text`, `subtext`, `red`, `accent`; the template `dotfiles/.config/rofi/theme.rasi.tmpl` | `rofi.rasi` ([rofi](../../../dotfiles/.config/rofi/README.md#the-generated-theme)) | none | `python3 bin/gen-rofi-themes.py [<id> ...]` |
| `gen-gtk-css.py` | `waybar.css`: eight colors; `palette.lua`: `accent`; `meta.sh`: `COLOR_SCHEME` | `gtk.css` and `gtk3.css` ([GTK](#gtk)) | none | `python3 bin/gen-gtk-css.py [<id> ...]` |
| `gen-kitty-tabs.py` | `kitty.conf`: `background`, `cursor_trail_color`; `waybar.css`: `subtext` | the five tab-bar lines of `kitty.conf`, in place ([kitty](../../../dotfiles/.config/kitty/README.md#the-running-head)) | none | `python3 bin/gen-kitty-tabs.py [<id> ...]` |
| `gen-tui-themes.py` | `waybar.css`: seven colors, and the theme's name from its first line; `palette.lua`: `accent` | `btop.theme` and `cava.theme` ([TUI monitors](../shell-and-bars/terminal.md#tui-monitors)) | none | `python3 bin/gen-tui-themes.py [<id> ...]` |
| `gen-browser-css.py` | `waybar.css`: twelve colors; `palette.lua`: `accent`, `accent_dim`; `meta.sh`: `COLOR_SCHEME` | `browser.css` ([librewolf](../../../dotfiles/.librewolf/README.md)) | none | `python3 bin/gen-browser-css.py [<id> ...]` |
| `gen-yazi-flavors.py` | `waybar.css`: thirteen colors and the name; `palette.lua`: `accent`, `accent_dim` | four files in `dotfiles/.config/yazi/flavors/letterpress-<id>.yazi/` ([yazi](../../../dotfiles/.config/yazi/README.md#the-flavors)) | none; it stops before writing a flavor that holds a private-use codepoint | `python3 bin/gen-yazi-flavors.py [<id> ...]` |
| `gen-vscode-themes.py` | `waybar.css`: fifteen colors; `palette.lua`: `accent`, `accent_dim`; `meta.sh`: `COLOR_SCHEME`, `MENU_NAME`; `kitty.conf`: `color0` to `color15` | `themes/letterpress-<id>-color-theme.json` in `dotfiles/.vscode/extensions/letterpress-themes/`, and its `package.json` on a run without ids ([letterpress-themes](../../../dotfiles/.vscode/extensions/letterpress-themes/README.md)) | none | `python3 bin/gen-vscode-themes.py [<id> ...]` |
| `gen-windows-look.py` | washi's `kitty.conf`, `waybar.css`, `palette.lua` and `meta.sh`; each theme's terminal colors; the extension above; `install/windows/upstream/`; Waybar's `config.jsonc` and `modules.jsonc` | `install/windows/letterpress/`, and it deletes what it no longer writes ([Windows look](windows.md)) | `--check` writes nothing and exits 1 with a diff while the directory is stale; `bin/check.sh` §19 runs it | `python3 bin/gen-windows-look.py [<id>] [--check]` |
| `check-themes.py` | each theme directory | nothing | it is the check, and `bin/check.sh` §14 runs it | `python3 bin/check-themes.py` |

`gen-rofi-themes.py` takes the accent from `waybar.css`, `gen-kitty-tabs.py` from `cursor_trail_color`, and the others from `palette.lua`.
`bin/check-themes.py` rule 6 keeps those slots on one hex, and [themes](../../../dotfiles/.config/themes/README.md#how-it-is-wired-here) lists its six rules.

`gen-windows-look.py` renders one theme, the id recorded in `install/windows/letterpress/theme`, which is washi.
Two of its outputs hold the 17 themes: `wt-schemes.json` has each theme's terminal scheme, and the packed extension has each editor theme.
A change to any theme's terminal colors or editor theme therefore makes §19 fail until it runs again.
It packs what `gen-vscode-themes.py` wrote, so it runs after that generator.

## GTK

One GTK theme serves the 17 themes: adw-gtk3, the GTK 3 port of libadwaita's stylesheet.
It comes from Arch's `adw-gtk-theme` package (6.5, tested 2026-10), listed in `packages/roles/desktop.txt`.
`GTK_THEME_NAME` in `meta.sh` is `adw-gtk3-dark` for a dark theme and `adw-gtk3` for a light one.
`COLOR_SCHEME` sets the portal's `color-scheme` and GTK's `gtk-application-prefer-dark-theme`.
Until 2026-10-06 the themes used seven GTK theme packages from the AUR, each made for one palette: catppuccin, everforest, gruvbox, kanagawa, nordic, rose-pine and tokyonight.

The colors are two user stylesheets per theme.
`bin/gen-gtk-css.py` writes them from eight colors of `waybar.css` (`base`, `mantle`, `crust`, `text`, `surface0`, `red`, `green`, `yellow`), the accent in `palette.lua`, and `COLOR_SCHEME` for light or dark.

| File | Linked at | Holds |
|---|---|---|
| `gtk.css` | `~/.config/gtk-4.0/gtk.css` | libadwaita's variables in `:root`, from `--accent-bg-color` to `--window-radius`; the same colors as `@define-color` aliases; the chrome rules below |
| `gtk3.css` | `~/.config/gtk-3.0/gtk.css` | the 46 `@define-color` names adw-gtk3 reads, from `accent_bg_color` and `window_bg_color` to `shade_color`, and no selector rules |

The chrome rules in `gtk.css` keep GTK 4 on the printed page:

- Buttons, entries, spin buttons, tooltips, popovers, drop-downs, menu buttons, cards, toasts and the search bar get a 3 px radius.
- Entries and plain buttons get a 1 px inset hairline in `alpha(@text, .18)`, and flat, suggested, destructive and circular buttons keep their own look.
- The same hairline runs under the header bar.
- Popovers, tooltips and a floating window's own decorations get a hairline ring and a light shadow.
- `--window-radius` is 4 px, Hyprland's `rounding`.

| Palette | GTK colors |
|---|---|
| `base` | the window and the header bar: the header bar is part of the page, and a hairline separates it |
| `mantle` | the sidebar, and the view on a dark theme |
| `base` mixed 45 % toward white | the view on a light theme |
| `mantle` and `base`, half and half | the secondary sidebar |
| `surface0` | cards, popovers, dialogs and thumbnails on a dark theme; a light theme gives them the view's color |
| `text` | each `*_fg_color`, the hairline at 18 % and the shade lines at 10 % |
| the accent | `accent_bg_color` and `accent_color`; `accent_fg_color` is whichever of white, `crust` and `text` has the most contrast on it |
| `red`, `green`, `yellow` | destructive and error, success, warning, each with a foreground picked the same way |

There are two files because GTK 3 cannot parse `:root { --var }` and would log a parse error in each GTK 3 app.
`gtk3.css` has no selector rules.
GTK loads the user stylesheet at priority 800 (`GTK_STYLE_PROVIDER_PRIORITY_USER`), above an application's own CSS at 600.
A `button {}` rule there would restyle Waybar and nwg-drawer, both GTK 3 apps with stylesheets of their own.
Named colors cannot do that, and libadwaita's names do not collide with the palette names in `waybar.css`.
From 1.6 on, libadwaita reads the variables (1.10.0 on cabin, tested 2026-10), and older apps and plain GTK 4 widgets read the aliases.

`dram theme` sets `gtk-theme` and `color-scheme` with `gsettings`, links both files through the stable `themes/current/` path, and removes the `assets` and `gtk-dark.css` links the per-palette themes needed ([Switcher](switcher.md)).
GTK reads the user stylesheet when an app starts, so an open GTK app keeps the old colors until it restarts, and the switch's notification says so.
After changing a palette, run `python3 bin/gen-gtk-css.py <id>` and commit both files.
Apps that bring their own colors keep them: Chromium, Electron apps, and LibreWolf and Thunderbird, whose chrome has sheets of its own ([librewolf](../../../dotfiles/.librewolf/README.md)).

## Use it

```sh
python3 bin/gen-gtk-css.py washi          # one theme
python3 bin/gen-gtk-css.py                # each theme; prints "wrote <path>" per changed file
python3 bin/check-themes.py               # what bin/check.sh §14 runs
python3 bin/gen-windows-look.py --check   # what bin/check.sh §19 runs
```

After editing a theme's palette, run the set in this order and commit the outputs with the palette:

```sh
python3 bin/gen-rofi-themes.py <id>
python3 bin/gen-gtk-css.py <id>
python3 bin/gen-kitty-tabs.py <id>
python3 bin/gen-tui-themes.py <id>
python3 bin/gen-browser-css.py <id>
python3 bin/gen-yazi-flavors.py <id>
python3 bin/gen-vscode-themes.py          # no id, so package.json lists each theme
python3 bin/gen-windows-look.py           # last: it packs the extension and holds each terminal scheme
python3 bin/check-themes.py
bin/render-windows.sh                     # install/windows/letterpress/ is a Windows render input
```

On a host, `dram theme <id>` shows the result ([Switcher](switcher.md)).
A new theme needs the same run, after the steps in [Adding a theme](../../../dotfiles/.config/themes/README.md#adding-a-theme).

## When it breaks

| Symptom | What it means | Fix |
|---|---|---|
| `<id>: waybar.css lacks [...]` and exit 1 | the palette misses a color that generator reads | define it in that theme's `waybar.css`, as the other themes do |
| §19 of `bin/check.sh` prints `install/windows/letterpress is stale` | a palette, an editor theme or Waybar's configuration changed after the last Windows run | `python3 bin/gen-windows-look.py`, then `bin/render-windows.sh`, and commit both |
| `gen-windows-look.py: <app> (<id>): <name> <ink> on <paper> reads at <n>:1, under 4.5:1` | an ink in a Windows app does not read on its paper | change the palette, or that app's mapping in the generator |
| §14 of `bin/check.sh` prints `theme schema (bin/check-themes.py):` | a theme breaks one of the six rules | the indented lines under it name the theme, the file and what is wrong |

## Limits

- The seven Arch generators have no `--check`, so `bin/check.sh` passes while a palette is newer than its outputs (2026-10-13).
- The generators read colors with regular expressions: `@define-color <name> #rrggbb;` in `waybar.css`, `<key> = "rgba(rrggbbaa)"` in `palette.lua`, `<key> #rrggbb` in `kitty.conf`.
  A color written another way, such as `rgb()` or three hex digits, is not seen.
- `bin/check-themes.py` measures no contrast: I have not decided about solarized-paper's accent (2026-10-07).
  Three outputs lift inks that do not read: the editor's syntax inks to 4.5:1, yazi's directories to 3:1, and the Windows apps' inks to 4.5:1, where a gate fails the run if one still does not read.
- `VERSION` in `gen-vscode-themes.py` is bumped by hand, and `look.ps1` on Windows installs the packed extension only when that version is new.

# Themes

[Design](../README.md) › Themes

Seventeen palettes share the Letterpress design, and one command switches each app in `$HOME` to the chosen one.
Each palette lives in four hand-written files, and generators turn them into the files each app reads.
The Arch hosts switch between all 17, Windows takes washi, the house theme, and the boot chain keeps a palette of its own.

| Branch | What it does | Code | Copy alone |
|---|---|---|---|
| [Palettes](../../../dotfiles/.config/themes/README.md) | the 17 themes, 15 files each, and the accent contract | `dotfiles/.config/themes/` | yes |
| [Generators](generators.md) | write the GTK, rofi, kitty, btop, cava, browser, VSCodium, yazi and Windows files from the palettes | `bin/gen-*.py`, `bin/check-themes.py` | yes, with Python 3 |
| [Switcher](switcher.md) | `dram theme`, day and night, the night light | `dotfiles/.local/bin/dram-theme`, `dram-theme-auto`, `nightlight.sh` | yes |
| [Wallpaper](wallpaper.md) | the quote wallpaper | `dotfiles/.local/bin/quote-wallpaper.sh`, [`dotfiles/.config/quote-wallpaper/`](../../../dotfiles/.config/quote-wallpaper/README.md) | yes |
| [Editor](../../../dotfiles/.vscode/extensions/letterpress-themes/README.md) | VSCodium's 17 Letterpress themes as one local extension | `dotfiles/.vscode/extensions/letterpress-themes/` | yes |
| [Browser and mail](../../../dotfiles/.librewolf/README.md) | LibreWolf's and Thunderbird's chrome on paper | `dotfiles/.librewolf/`, `dotfiles/.thunderbird-chrome/` | yes |
| [yazi](../../../dotfiles/.config/yazi/README.md) | the file manager's 17 flavors | `dotfiles/.config/yazi/` | yes |
| [Windows look](windows.md) | the shell, the terminal and each app on Windows that can take the look | `bin/gen-windows-look.py`, `install/windows/letterpress/`, `install/windows/dram-windows/look.ps1` | yes, on Windows 11 |

## How the branches fit

```text
themes/<id>/waybar.css, palette.lua, meta.sh, kitty.conf     hand-written
  └─► bin/gen-*.py ─► themes/<id>/gtk.css, gtk3.css, rofi.rasi, browser.css, btop.theme, cava.theme
                      the tab lines of themes/<id>/kitty.conf, the yazi flavors, the VSCodium extension
                      install/windows/letterpress/ (from washi only)
dram theme <id> ─► ~/.config/themes/current ─► each app reads current/*, and dram theme reloads it
```

The generators run on the Mac or on a host when a palette changes, and their output is committed: a host only reads it.
`dram theme` links and reloads, needs no root, and leaves the boot chain alone ([Boot screens](../shell-and-bars/boot-screens.md)).
`dram-theme-auto` moves between washi and washi-day with the sun, and leaves a theme picked by hand where it is.
Windows takes the house theme when its look is generated: the PC has no `dram theme`.
The typefaces are the same in every theme ([Typography](../typography/README.md)).

## Operating it

Switching, day and night, the wallpaper, adding a theme and changing one color everywhere: [handbook chapter 6](../../records/handbook/06-theme-and-look.md).

## Status

- 2026-10-07: contrast is not measured, and solarized-paper's OSD bar keeps a darker yellow than its accent until that is decided (`bin/check-themes.py`).
- 2026-10-13: only `bin/gen-windows-look.py` has a check, so the other generators' output can drift until they are run again.

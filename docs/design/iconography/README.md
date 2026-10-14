# Iconography

[Design](../README.md) › Iconography

Words take the place of icons wherever a surface allows it, and the icons that remain are tinted to the page.
The bar carries none, the terminal draws glyphs from one icon font, and on Windows each app's own icon is redrawn in the accent.
The pointer is GNOME's Adwaita on both systems, and a "pj" seal stands for me where a system wants a picture.

| Branch | What it does | Code | Copy alone |
|---|---|---|---|
| The icon rule | keeps icon glyphs out of the bar and down to one font in the terminal | `bin/check-waybar.py`, `dotfiles/.config/kitty/kitty.conf` | yes, the check is plain Python |
| Windows icons | redraws each app's icon in the accent's shades on a dark tile, tints the folders, quiets the Start menu | `install/windows/dram-windows/icons.ps1` | yes, after changing its colors |
| The pointer | Adwaita's cursors on Arch and Windows | `install/windows/cursors.pin`, `cursors.notice`, `windows/units/cursors-machine.ps1`, `pointer-adwaita.ps1` | yes, with the pin file |
| The seal | the "pj" mark as the account picture | [`dotfiles/.local/share/dram/`](../../../dotfiles/.local/share/dram/README.md), `bin/gen-avatar.sh`, `install/windows/dram-windows/account-picture.ps1` | yes, after replacing the letters |
| Boot icons | rEFInd's icons recolored to the house palette | [`system/refind-letterpress/icons/`](../../../system/refind-letterpress/README.md), `system/gen-boot-assets.py` | yes, with the icons' notices |

## The icon rule

The bar has no icons: each readout is a Russian caption and a figure, and each state is a word ([Captions and spacing](../../../dotfiles/.config/waybar/README.md#captions-and-spacing)).
`bin/check-waybar.py`, run by `bin/check.sh` §10, fails on a single private-use codepoint in Waybar's configuration or its scripts, so no Nerd Font glyph creeps back.
The prompt follows the same rule: `dotfiles/.config/starship.toml` holds no private-use glyph ([Prompt](../shell-and-bars/prompt.md)).
In the terminal, Symbols Nerd Font Mono is the only icon font, and kitty's `symbol_map` sends the private-use ranges to it, so each glyph is one cell wide.
The desktop icon theme is Adwaita in each of the 17 themes, set by `dram theme` through gsettings.
Papirus was the icon theme until it failed the software rules' Origin test and was swapped out ([decided 2026-10-10](../../../decisions/log.md#d7)).

## Windows icons

Windows has no icon theme for third-party apps, and patching an app's resources breaks on its next update.
So `icons.ps1` re-renders each app's own icon: its glyph in vermilion shades, from the dim accent `#8a311f` to a pale `#d5947f` by the glyph's own light and shade, on a dark rounded tile in washi's paper with a faint rule.
It writes each icon as a multi-size `.ico` under `C:\ProgramData\dram\icons` and sets it on the shortcuts Windows draws from: the Start menu for all users and for mine, the taskbar pins and the desktop.
That covers the apps, Windows' own tools and consoles, and Steam's `.url` game links.
A link that Windows Installer advertises is rewritten as a plain link to its program, which can then take an icon.
The known folders (Desktop, Documents, Downloads, Music, Pictures and Videos) get their own icons tinted the same way, without a tile, through their `desktop.ini`.
The Start menu keeps apps only: document, folder and web links move to `C:\ProgramData\dram\start-tidy`.

Windows' own items, the drives and the generic folder change through registry overrides only: `DefaultIcon` under each namespace item's CLSID for my account, `DriveIcons` and `Shell Icons` for the machine.
`icons.ps1` never touches a system file ([decided 2026-10-12](../../../decisions/log.md#d135)).
Most of Windows' own Start menu links under ProgramData are protected by Windows Resource Protection, so `sfc /scannow` would undo a tinted one: 27 of them on cabin-win on 2026-10-12.
The script asks `SfcIsFileProtected` before it changes a link, and leaves a protected one alone.

Each original is kept, as `icons\manifest.json` and a byte copy of each changed link in `icons\originals`, so `icons.ps1 -Revert` puts everything back.
App updates rewrite their shortcuts, so each converge applies the icons again; raising `$Version` in the script re-renders all of them.
The desktop role runs it in phase 30, elevated, as the user it themes:

```powershell
powershell -ExecutionPolicy Bypass -File icons.ps1 -DryRun   # what it would change
powershell -ExecutionPolicy Bypass -File icons.ps1 -Sample C:\Windows\System32\notepad.exe   # one icon to icons\sample.png
```

To copy it, change `$TileColor`, `$RuleColor` and the `$Dark` and `$Light` ramp at the top of the script to your own palette, and the paths under `C:\ProgramData\dram`.
It reads no palette file: the colors are washi's, written into the script.

### Limits

- A Store app's icon in Start cannot be replaced.
- Large folder icons stay yellow: from Medium up, Windows composes the folder itself, and `Shell Icons` applies at small sizes only.
- Title bars, Alt-Tab and the tray have no supported way to change an icon.

## The pointer

The pointer is Arch's on both systems: GNOME's Adwaita cursors ([decided 2026-10-12](../../../decisions/log.md#d132)).
On Arch, `dram theme` sets the `cursor-theme` gsetting to Adwaita, and `hyprland.lua` sets the cursor size to 24 px.
On Windows, the cursors come from GNOME's own Windows build, the `.cur` and `.ani` files of adwaita-icon-theme 51.0, the last tag that ships them.
`install/windows/cursors.pin` pins each file by sha256, like the fonts, and `install/windows/cursors.notice` carries GNOME's license notice beside them.
The `cursors-machine` unit checks each file again and copies it to `%SystemRoot%\Cursors\Adwaita`, and `pointer-adwaita` makes it my account's "Adwaita" scheme with a 2 px text caret.
Adwaita has no pen, up arrow, pin or person, so those four roles keep Windows Black's cursors.
Windows' smallest pointer is 32 px where Arch draws 24, and each `.cur` carries a 32 px image, so Windows draws it at that size without scaling.

The cursors are LGPL-3.0 or CC-BY-SA-3.0-US, at the user's choice, as GNOME publishes them.
They are downloaded when a release is staged, and they are not committed to this repo.

## The seal

The seal is "pj" in EB Garamond Italic on a vermilion disc ringed in paper.
`bin/gen-avatar.sh` renders it at each size Windows keeps for an account picture, and `account-picture.ps1` sets it ([decided 2026-10-12](../../../decisions/log.md#d91)).
The Zebar masthead draws its own copy of the seal in CSS, and the boot wordmark is a separate "pj" set in Fraunces ([Boot screens](../shell-and-bars/boot-screens.md)).
Its files and how to render it: [the seal's README](../../../dotfiles/.local/share/dram/README.md).

## Boot icons

rEFInd's icons are Catppuccin's mocha set from `system/refind-catppuccin/`, recolored by `system/gen-boot-assets.py`.
The operating systems' icons are printed in ink and the tools' icons in the subtext gray, and the full-color ones are printed in one tone onto paper.
Catppuccin drew 39 of the 90, under MIT.
The other 51 are rEFInd's own stock icons, mostly under CC-BY-SA-3.0, and [the rEFInd theme's README](../../../system/refind-letterpress/README.md) lists each icon's license.

## Operating it

The icons on Windows come back with each converge.
Changing the theme's colors on Arch: [handbook chapter 6](../../records/handbook/06-theme-and-look.md).

## Status

- 2026-10-12: the Windows icons, the folders and the system icons are in place on cabin-win.
- 2026-10-13: the 512 px seal meant for `~/.face` on the Linux hosts is rendered, and nothing installs it.

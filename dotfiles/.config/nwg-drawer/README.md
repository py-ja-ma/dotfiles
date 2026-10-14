# nwg-drawer

[Design](../../../docs/design/README.md) › [Shell & bars](../../../docs/design/shell-and-bars/README.md) › Launchers

The Letterpress app grid for nwg-drawer: a full-screen sheet of paper with the app names set in Literata.
Its search line is a Fraunces entry on one 1 px accent rule, with no box and no icon, the same line that [rofi](../rofi/README.md) draws.

| | |
|---|---|
| Needs | nwg-drawer 0.7.5, tested 2026-10; Fraunces, Literata; a palette file |
| Copy alone | yes, after giving `drawer.css` a palette |
| License | MIT |

## What it needs

- nwg-drawer 0.7.5 from Arch's `extra` repo, tested 2026-10.
  It is a GTK 3 program on the layer shell.
- adw-gtk3, from adw-gtk-theme 6.5, as the GTK 3 theme: `drawer.css` takes away the focus ring it draws around the search line.
  Under another GTK 3 theme those rules are harmless.
- The fonts Literata for the names and Fraunces for the search line ([Typography](../../../docs/design/typography/README.md)).
  Fraunces has no Cyrillic, and typed Russian falls back to Literata through `60-letterpress.conf` ([fontconfig](../../../docs/design/typography/README.md#fontconfig)).
- A palette at `~/.config/themes/current/waybar.css` that defines the GTK colors `base`, `text`, `subtext` and `accent`.
  The drawer reads the bar's palette file, and each theme has one.
- A file manager and a terminal for the drawer to open: the command line here names Thunar and kitty.
- Not needed: Nix, Home Manager or `dram`.

## Copy it alone

1. Copy `drawer.css` to `~/.config/nwg-drawer/`.
2. Give it a palette.
   Copy one theme's `waybar.css` to `~/.config/themes/current/`, or point the `@import` at the top of `drawer.css` at your own file with the four colors above.
   The import is relative, so it resolves against `~/.config/nwg-drawer/`.
3. Run `nwg-drawer -c 6 -is 64 -fm thunar -term kitty` for six columns of 64 px icons, with your own file manager and terminal if they differ.
4. The sheet opens on the theme's paper, with a Fraunces search line on an accent rule and no magnifier or pill around it.
   If GTK cannot parse the stylesheet, nwg-drawer logs `css file not found or erroneous` and keeps GTK's own styling.

To try a changed copy while the live file stays as it is, start the drawer with the copy's absolute path:

```sh
nwg-drawer -s "$HOME/.config/drawer-test/drawer.css"
```

A path that starts with `/` is used as it stands, and a bare name resolves inside `~/.config/nwg-drawer/`.
Keep the copy in a directory directly under `~/.config`, so its relative `@import` still reaches `themes/current/waybar.css`.

## How it is wired here

`modules/desktop.nix` links `dotfiles/.config/nwg-drawer` whole to `~/.config/nwg-drawer` on hosts with the desktop role, and `packages/roles/desktop.txt` installs nwg-drawer.
SUPER+G in `hyprland.lua` and a click on the bar's nameplate run `nwg-drawer -c 6 -is 64 -fm thunar -term kitty` ([Keybinds](../../../docs/design/shell-and-bars/keybinds.md)).
The command has no `-r`, so the drawer does not stay resident.
Each opening is a new process that reads `drawer.css` and the palette afresh, which is how the drawer follows a theme switch with no reload.
SUPER+G while the drawer is open closes it, because a second nwg-drawer signals the first to quit, and Escape on an empty search line closes it too.

`modules/desktop.nix` also puts Flatpak's export directories on `XDG_DATA_DIRS`, where nwg-drawer finds the Flatpak apps.
Hyprland's blur is off, so the sheet is near-solid paper, `@base` at 97 %, and the wallpaper hardly shows through the names ([Blur](../hypr/README.md#blur)).
`bin/check.sh` §14 fails on a hardcoded home directory under `dotfiles/.config`, which is why the `@import` is relative.

## The search line

The drawer's search line and rofi's are one design, and [rofi](../rofi/README.md) covers its side.

- The entry is Fraunces 20 px on a 1 px bottom border in the accent, over a transparent background, with the caret in the accent.
- nwg-drawer 0.7.5 gives its search entry no CSS name, so `drawer.css` targets `entry`.
- adw-gtk3 draws its own ring on `entry:focus`: an accent outline, a box-shadow and a pill radius.
  `drawer.css` removes the three on `entry:focus` as well.
- GTK 3's search entry puts an `edit-find` icon at its start.
  GTK 3 has no icon-size property, so `drawer.css` hides the icon with `-gtk-icon-transform: scale(0)` and zero opacity.
- The rule stays in the accent with focus or without it.
  Under layer-shell, GTK 3 does not reliably flag `:focus`, so an accent shown on focus alone would read as a hairline most of the time.

## The sheet

| Part | Selector | Look |
|---|---|---|
| the sheet | `window` | `@base` at 97 %, Literata 14 px in `@text` |
| an app | `button` | no frame until the pointer is over it, then a hairline; on keyboard focus, an accent frame and an accent name |
| the pinned row | `#pinned-box` | a hairline under it |
| file search results | `#files-box` | a hairline box with a 3 px radius |
| a category | `#category-button` | an italic word in `@subtext` over a hairline, in the accent on hover and focus |
| a sum | `#math-label` | Fraunces bold in the accent, for arithmetic typed into the search line, for example `2+2` |

**Do not** use percent units for margins in `drawer.css`: GTK 3 rejects the whole file, and nwg-drawer falls back to GTK's own styling.

## Files

| File | What it does |
|---|---|
| `drawer.css` | the palette import, the paper, the search line, the app tiles and the categories |
| `dotfiles/.config/hypr/hyprland.lua` | the SUPER+G bind and the drawer's command line |
| `dotfiles/.config/waybar/modules.jsonc` | the same command line on the nameplate's click |

## License

MIT, Patrick Jordan.

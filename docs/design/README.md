# Design

[Organization](../README.md) › Design

Letterpress styles the desktop like a printed page.
Each theme has a paper color, a body ink and one accent ink.
The accent appears only as a rule, a numeral or a cursor, and never fills a surface.
Chrome is flat and nearly square, with a 3 to 4 px radius, and 1 px hairlines in `alpha(@text, .18)` separate its parts.
Type does the work that pills, blur and icons do elsewhere: Fraunces for display, Literata for text and the interface, Monaspace for code, EB Garamond Italic for the large italic voice.
Hyprland keeps my `jiggle` spring and the jello drag.
Not used: Material You color extraction (matugen), neon or CRT effects, 20 px rounded bubbles, Nerd Font glyphs in the bar, all-caps labels, redaction bars.

The Arch hosts carry all of it.
The Windows PC takes the same palette wherever an app lets it, and the boot chain keeps one fixed house palette.

| Division | Covers |
|---|---|
| [Themes](themes/README.md) | the 17 palettes, their generators, `dram theme` with day and night, the wallpaper, the look on Windows |
| [Typography](typography/README.md) | the house fonts, the size of each surface, fontconfig, Russian text, the fonts on Windows |
| [Iconography](iconography/README.md) | the bar without icons, Windows' tinted icons, the pointer, the "pj" seal, the boot icons |
| [Shell & bars](shell-and-bars/README.md) | Hyprland, Waybar, the Zebar masthead, launchers and notifications, the terminal and the prompt, the boot screens, the keybinds |

## Signature

Four things mark a Letterpress desktop:

- a large Fraunces clock over a 1 px accent rule on the lock screen;
- the bar as a masthead, with the theme's name as its nameplate, the workspace as "№ 4" and a Russian date in EB Garamond Italic;
- readouts as small-cap captions and figures (`цп 8 %`, `бат 85 %`), with no icon in the bar;
- paper grain under the terminal's text and over the whole screen.

## Rules

1. The bar has no icons.
   `bin/check-waybar.py`, run by `bin/check.sh` §10, fails on a private-use codepoint in Waybar's configuration or its scripts.
2. The 17 theme directories hold the same files and the same color names, and each theme states its accent in each slot.
   `bin/check-themes.py`, run by `bin/check.sh` §14, fails otherwise.
3. Generated files are regenerated, never edited by hand.
   [Generators](themes/generators.md) lists each generator.
   Only the Windows look has a check of its own: `bin/gen-windows-look.py --check`, run by `bin/check.sh` §19.
4. The boot chain does not follow `dram theme`.
   rEFInd, Plymouth and ly keep the house palette, so the screen I debug a broken desktop from looks the same on each host ([Boot screens](shell-and-bars/boot-screens.md)).
   Nothing checks this.
5. Windows takes the look from the same palette files, and never through a patcher that injects code into other processes ([decided 2026-10-12](../../decisions/log.md#d87)).
   `bin/check.sh` §15 fails on Windhawk, which the software register lists as a fail.

## The themes

Each theme is named for a drink on the bar and keeps its palette's name as its id.
`dram theme` takes either; [Switcher](themes/switcher.md) has the details, and [the theme files](../../dotfiles/.config/themes/README.md) say where each palette came from.

| On the bar | id | Paper | Accent |
|---|---|---|---|
| Absinthe Drip | `crt` | dark, `#050a0a` | `#22dddd` |
| Aviation | `tokyo-night` | dark, `#1a1b26` | `#7aa2f7` |
| Bellini | `washi-day` | light, `#f3ead9` | `#c0442b` |
| Black Manhattan | `oxocarbon` | dark, `#161616` | `#33b1ff` |
| Boulevardier | `washi` | dark, `#1c140f` | `#c0442b` |
| Espresso Martini | `catppuccin-mocha` | dark, `#1e1e2e` | `#89b4fa` |
| Gold Rush | `solarized-paper` | light, `#fdf6e3` | `#b58900` |
| Hakushu Highball | `kanagawa` | dark, `#1f1f28` | `#7e9cd8` |
| Jack Rose | `rose-pine` | dark, `#191724` | `#c4a7e7` |
| Last Word | `everforest` | dark, `#2d353b` | `#a7c080` |
| Old Fashioned | `cassette` | dark, `#0b0906` | `#9a8a5a` |
| Pisco Sour | `soft-color` | dark, `#2b304d` | `#ff9a8b` |
| Rob Roy | `mountains` | dark, `#1a1814` | `#7c907a` |
| Rusty Nail | `gruvbox-dark` | dark, `#282828` | `#83a598` |
| Southside | `aqua` | dark, `#0d1117` | `#5ac8fa` |
| Vesper | `nord` | dark, `#2e3440` | `#88c0d0` |
| White Russian | `catppuccin-latte` | light, `#eff1f5` | `#1e66f5` |

washi is the house theme: the boot chain's palette and the Windows look both come from it.

## Decisions

| Decision | Date | Log |
|---|---|---|
| The Windows look is generated from Arch's palette files | 2026-10-12 | [log](../../decisions/log.md#d84) |
| The fonts are installed for each account on Windows, from `install/windows/fonts.pin` | 2026-10-12 | [log](../../decisions/log.md#d85) |
| The terminal and the prompt on Windows match Arch's | 2026-10-12 | [log](../../decisions/log.md#d86) |
| Each app that can take the look takes it, with no taskbar or Start patcher | 2026-10-12 | [log](../../decisions/log.md#d87) |
| No sounds and a clear sign-in screen on Windows | 2026-10-12 | [log](../../decisions/log.md#d88) |
| The Russian layout on Windows for my account, not the sign-in screen | 2026-10-12 | [log](../../decisions/log.md#d89) |
| The "pj" seal as the account picture | 2026-10-12 | [log](../../decisions/log.md#d91) |
| A Zebar masthead on each monitor, the taskbar hidden | 2026-10-12 | [log](../../decisions/log.md#d130) |
| GlazeWM held until its IPC checks who connects | 2026-10-12 | [log](../../decisions/log.md#d131) |
| The Adwaita pointer on Arch and Windows | 2026-10-12 | [log](../../decisions/log.md#d132) |
| Icons change through copies and registry overrides, never a system file | 2026-10-12 | [log](../../decisions/log.md#d135) |
| Each display runs at its highest refresh rate | 2026-10-12 | [log](../../decisions/log.md#d137) |

## Open

- 2026-10-07: contrast is not measured, and solarized-paper's accent waits on that (`bin/check-themes.py`).
- 2026-10-12: the work apps on Windows (LibreOffice, KiCad and the rest) are not themed.
- 2026-10-12: GlazeWM stays out, so the Windows masthead shows no workspace numeral.
- 2026-10-13: `dotfiles/.config/qutebrowser/config.py` hard-codes Catppuccin Mocha and ignores `dram theme`.
- 2026-10-13: no screenshots yet.

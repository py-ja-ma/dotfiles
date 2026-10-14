# Typography

[Design](../README.md) › Typography

Serif everywhere: one display face, one face for text and the interface, one mono, one icon font, and one italic voice that appears only large.
The faces are the same in every theme, on Arch and on Windows.

| Branch | What it does | Code | Copy alone |
|---|---|---|---|
| House fonts | the five faces and the surfaces each one sets | `modules/desktop.nix`, `packages/roles/desktop.txt`, [`dotfiles/.local/share/fonts/`](../../../dotfiles/.local/share/fonts/README.md) | yes: they are packages and one tracked file |
| fontconfig | the generic families, the Cyrillic fallback, libadwaita's names | `modules/desktop.nix` | yes, as the XML it writes |
| Russian | the dates and words in Russian, with English as the fallback, and the EN/RU keyboard | `dotfiles/.local/bin/waybar-date.sh`, `kb-layout.sh`, `windows/units/keyboard-us-ru.ps1` | yes |
| Fonts on Windows | the same faces installed for each account, pinned by sha256 | `install/windows/fonts.pin`, `fonts.lock`, `windows/units/fonts-machine.ps1` | yes, with the pin file |

## House fonts

| Face | Role | Package | Sets |
|---|---|---|---|
| Fraunces | display | nixpkgs `fraunces` (`modules/desktop.nix`) | the bar's nameplate, clock and "№ n", hyprlock's clock, swaync's title and calendar heading, the search lines of rofi and nwg-drawer, gsimplecal's month, satty's text tool |
| Literata | text and interface | nixpkgs `literata`, with optical sizes 7 to 72, Cyrillic and Greek | each word at 14 px or below, the bar's captions in small caps with lining tabular figures, the GTK and Qt interface, toast summaries, labels, the browser's page text |
| Monaspace Xenon and Radon | mono and readouts | pacman `otf-monaspace` (`packages/roles/desktop.txt`) | kitty (Xenon upright, Radon italic), VSCodium's editor and terminal, each readout: the calendar grid, rofi's list, swaync's body, swayosd, hyprlock's layout word |
| Symbols Nerd Font Mono | icons | pacman `ttf-nerd-fonts-symbols-mono` | the only icon font: kitty sends U+E000–F8FF and U+F0000–FFFFF to it through `symbol_map`; the bar uses none |
| EB Garamond Italic | the italic voice, 15 px and up | nixpkgs `eb-garamond` and the tracked [`EBGaramond-Italic.ttf`](../../../dotfiles/.local/share/fonts/README.md) | hyprlock's Russian date, rofi's prompt, the bar's window title, date and track, the quote wallpaper |
| Noto Sans | the plain `sans-serif` | pacman `noto-fonts` | nothing names it; pages and apps that ask for the sans generic get it |

Fraunces has no Cyrillic, so Russian text is never set in it, and it has no tabular figures, so it never sets a column of numbers.
EB Garamond's x-height is 0.41 em: below 15 px it thins to hairlines, which is why each smaller italic is Literata Italic.
`ttf-nerd-fonts-symbols` is the proportional sibling of the Symbols face, and nothing names it.

### Sizes

cabin is 1440p at scale 1, and the laptop runs the same pixel sizes at 1.5×: nothing is retuned per host.
If Literata's hairlines soften on the laptop's panel, raise its weight to 450 or 500 (`font-weight` in GTK CSS, `wght` in the browser) and keep the size.

| Surface | Face | Size in px | Weight |
|---|---|---|---|
| GTK and Qt interface | Literata | 11 | 400 |
| document and reader text | Literata | 12 in gsettings, 16 for browser pages with a floor of 11 | 400 |
| toast summary, widget labels | Literata, Literata Italic | 14, 13 to 14 | 600, 400 |
| power menu, the rofi list | Monaspace Xenon | 12 | 400 |
| nwg-drawer names | Literata | 14 | 400 |
| rofi prompt, entry, placeholder, list, message | EB Garamond Italic, Fraunces, EB Garamond Italic, Monaspace Xenon, Literata Italic | 15, 22, 19, 12, 13 | 400 |
| hyprlock clock, date, field, layout | Fraunces, EB Garamond Italic, Literata, Monaspace Xenon | 150, 24, default, 12 | 400 |
| kitty, VSCodium editor and terminal | Monaspace Xenon, Radon for italic | 13, 12 | 400 |

The bar's own sizes are in [the Waybar README](../../../dotfiles/.config/waybar/README.md#captions-and-spacing).

## fontconfig

`modules/desktop.nix` sets the generic families:

| Generic | Faces, in order |
|---|---|
| serif | Literata, EB Garamond, Noto Serif |
| monospace | Monaspace Xenon, JetBrainsMono Nerd Font |
| sans-serif | Noto Sans |
| emoji | Noto Color Emoji |

There is no alias from sans-serif to serif.

It also writes `~/.config/fontconfig/conf.d/60-letterpress.conf`, the Cyrillic safety net.
It appends Literata as a weak fallback to any pattern that names Fraunces or EB Garamond, so Latin stays in the named face and Russian falls to Literata.
It binds libadwaita's own names, Adwaita Sans and Adwaita Mono, to Literata and Monaspace Xenon.

On Wayland the interface font comes from gsettings, through the settings portal, and `settings.ini` has no say.
GTK3, GTK4 and libadwaita read `org.gnome.desktop.interface font-name`, and Chromium, Electron apps, VSCodium's workbench and the LibreWolf and Thunderbird chrome follow the same value.
`dram theme` sets `font-name 'Literata 11'`, `document-font-name 'Literata 12'` and `monospace-font-name 'Monaspace Xenon 11'` on each switch.
It writes `gtk-font-name=Literata 11` into `settings.ini` as well, only so the files agree.

If a face is missing, the fallbacks are JetBrainsMono Nerd Font for mono and EB Garamond, then Noto Serif, for serif.
The layout still holds.
Flatpak apps cannot see the fonts from the Nix profile and get Noto Serif from the sandbox's fontconfig.

### Check the fonts on a host

```sh
fc-list | grep -iE 'fraunces|literata|monaspace|garamond'   # all four families
fc-match "Symbols Nerd Font Mono"        # SymbolsNerdFontMono-Regular.ttf, not JetBrainsMono
fc-match -s serif | head -3              # Literata, EB Garamond, Noto Serif
fc-match -s "Fraunces:lang=ru" | head -3 # Fraunces first, Literata next
fc-match "Adwaita Sans"                  # Literata
gsettings get org.gnome.desktop.interface font-name   # 'Literata 11'
```

## Russian

Anything that prints a date that depends on the locale checks for the Russian locale when it runs, and falls back to English:

```sh
if locale -a 2>/dev/null | grep -qi '^ru_RU\.utf-\?8$'; then LC_TIME=ru_RU.UTF-8 date +"%A, %-d %B"; else date +"%A, %-d %B"; fi
```

The bar's date (`waybar-date.sh`), hyprlock, the login toast (`welcome.sh`) and kitty's running head use this test, and `bin/check-waybar.py` fails a bar date that skips it.
Fixed words such as "что ищем?", "пароль…" and "нет" need no fallback.
The Russian locale is a system setting: `system/locale-setup.sh` uncomments `ru_RU.UTF-8 UTF-8` in `/etc/locale.gen` and runs `locale-gen`.

The keyboard has two layouts, English (US) first and Russian second.
On Arch, left Alt with left Shift, `SUPER+ALT+SPACE` or a click on `en`/`ru` in the bar runs `kb-layout.sh`, which switches each keyboard at once ([Keybinds](../shell-and-bars/keybinds.md)).
On Windows, `keyboard-us-ru.ps1` sets the same pair for my account only, with Left Alt+Shift and Win+Space, so a stray switch never reaches a password typed at the sign-in screen ([decided 2026-10-12](../../../decisions/log.md#d89)).

## Fonts on Windows

`install/windows/fonts.pin` pins the faces Windows gets, each by URL and sha256: Monaspace 1.400 (the first release with Cyrillic), the Nerd Fonts 3.5.1 JetBrainsMono and Symbols pair, Literata 3.103, and EB Garamond with its italic from Google Fonts at a fixed commit.
`bin/render-windows.sh` writes `install/windows/fonts.lock` with each extracted file's sha256, `install/windows/apply-windows.sh` refuses a staged file that differs, and the `fonts-machine` unit installs them for each account into the Windows Fonts folder ([decided 2026-10-12](../../../decisions/log.md#d85)).
Fonts installed for one user vanish at sign-out on Windows, which is why they go machine-wide.
Windows gets no Fraunces: EB Garamond takes its roles in [the Zebar masthead](../shell-and-bars/zebar.md).

## Operating it

Changing a face or a size, step by step: [handbook chapter 6](../../records/handbook/06-theme-and-look.md), "Fonts".

## Status

2026-10-13: nothing open.

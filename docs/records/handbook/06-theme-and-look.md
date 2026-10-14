# 6. Theme and look

The desktop is "Letterpress": a printed page with one body ink and one accent
ink per theme, serif type, hairlines instead of pills, no icons in the bar.
Seventeen colour themes share that design and are named after drinks. One
command switches everything that lives in `$HOME`; the boot chain keeps a
fixed house palette on purpose.

Reference: `docs/design/README.md` (the design contract, every file, every size),
`docs/design/themes/wallpaper.md` (wallpaper, grain shader, day/night, night light),
`docs/commands.md` (`dram theme --help`, `dram-theme-auto --help`,
`quote-wallpaper.sh --help`, `wallpaper-menu.sh --help`, `nightlight.sh --help`).

## Before you start

- A host that has finished chapter 2: `dram switch` ran, Hyprland starts, the
  bar shows a drink name at the left.
- `~/.config/themes/current` resolves (`readlink -f ~/.config/themes/current`
  prints a directory under `~/git/dotfiles/dotfiles/.config/themes/`). If it
  does not, `dram theme washi` creates it; Hyprland needs it to start.
- The four font families present: `fc-list | grep -iE 'fraunces|literata|monaspace|garamond'`
  prints lines for all four. If one is missing, see "Fonts" below.

## The seventeen drinks

`dram theme --list` prints the bar name and the directory id of every theme.
Either form works on the command line (`dram theme "Old Fashioned"` and
`dram theme cassette` are the same); scripts and the `current` symlink use the
id.

| On the menu | id | light or dark |
|---|---|---|
| Absinthe Drip | `crt` | dark |
| Aviation | `tokyo-night` | dark |
| Bellini | `washi-day` | light |
| Black Manhattan | `oxocarbon` | dark |
| Boulevardier | `washi` | dark |
| Espresso Martini | `catppuccin-mocha` | dark |
| Gold Rush | `solarized-paper` | light |
| Hakushu Highball | `kanagawa` | dark |
| Jack Rose | `rose-pine` | dark |
| Last Word | `everforest` | dark |
| Old Fashioned | `cassette` | dark |
| Pisco Sour | `soft-color` | dark |
| Rob Roy | `mountains` | dark |
| Rusty Nail | `gruvbox-dark` | dark |
| Southside | `aqua` | dark |
| Vesper | `nord` | dark |
| White Russian | `catppuccin-latte` | light |

The name comes from `MENU_NAME` in `dotfiles/.config/themes/<id>/meta.sh`; the
light/dark column is that file's `COLOR_SCHEME`. `washi` (Boulevardier) is the
default seeded on a fresh host and the night half of the day/night pair;
`washi-day` (Bellini) is the day half.

## Switching

```sh
dram theme                 # rofi picker (same as SUPER+T); Esc cancels, nothing changes
dram theme washi-day       # by id
dram theme "Gold Rush"     # by bar name
dram theme --list          # "<bar name>  <id>" per line
dram theme --ids           # ids only
```

`dram theme` is `dram-theme`. A switch ends with a line
`switched to <bar name> (<id>)` and exit 0, and a toast with the drink's name
appears. `no such theme: <x> (try --list)` and exit 1 means a typo.

What a switch touches, all without sudo and all inside `$HOME`:

- `~/.config/themes/current` is repointed; everything that `@import`s,
  `include`s, `source`s or `dofile()`s a file under that path (waybar, swaync,
  swayosd, rofi (and so the power menu), kitty, hyprlock, Hyprland's border
  palette, fzf, the browser and mail chrome) sees the new theme. Qt apps follow
  the GTK theme (`QT_QPA_PLATFORMTHEME=gtk3`); there is no Qt theme file.
- gsettings: GTK theme (`adw-gtk3-dark` or `adw-gtk3`), `color-scheme`, icon
  theme and cursor (`Adwaita` for both, the same on every theme), and the UI fonts
  (`Literata 11`, `Literata 12`, `Monaspace Xenon 11`). `hyprctl setcursor`
  applies the cursor live.
- Machine-state files that cannot include a path are patched in place: bat,
  btop, cava, yazi's `theme.toml`, satty's palette line, GTK `settings.ini`,
  and `"workbench.colorTheme"` in VSCodium's `settings.json` (set to
  `Letterpress — <bar name>`). Files missing on a fresh host are seeded from
  their tracked `*.default` twin first.
- Reloads: the quote wallpaper re-renders in the new colours (about 3 s),
  `hyprctl reload`, waybar restarts, swaync reloads, kitty/cava/btop get their
  signals, swayosd restarts.

What it does not touch:

- Apps that read their style once at start: GTK and Qt apps already open,
  Chromium, LibreWolf, Thunderbird (restart them); rofi (the power menu too) and hyprlock
  pick the theme up on their next open. The toast says so.
- The greeter. ly uses the fixed house palette in `system/house-palette.sh` (dark paper
  `#1c140f`, ink `#e6d6cb`, vermilion `#c0442b`), identical on every host and independent
  of the desktop theme: it is what is left when the desktop is broken. Changing a value
  there is a deliberate act followed by `sudo bash system/apply-ly.sh`. The boot menu
  (rEFInd, `system/apply-refind.sh`) and the splash (Plymouth, `system/plymouth-setup.sh`)
  use the same palette (`docs/platforms/arch/boot-chain.md`); `dram apply` runs both through
  `system/system-dram.sh`.
- Flatpak apps (the sandbox has its own fontconfig and GTK) and Steam. There is
  no folder-icon accent any more: Papirus and `papirus-folders` left 2026-10-10
  (`decisions/0013`).

## Day and night, and the night light

`dram-theme-auto` runs every 10 minutes and at login (a systemd user timer in
`modules/desktop.nix`). It follows the sun between exactly two themes:
`washi-day` from sunrise to sunset, `washi` otherwise, and it switches only
when the current theme is one of those two, so a theme picked by hand is never
overridden. Any other theme opts out of the schedule by being chosen.

The same clock drives the night light: `hyprland.lua` starts `hyprsunset` at
login (identity, no colour shift), and `dram-theme-auto` sets `temperature
4000` after sunset and `identity` after sunrise over its IPC.

See today's decision without changing anything:

```sh
dram-theme-auto --print
```

prints two lines, for example:

```
location 42.36 -71.06  sunrise 06:46  sunset 18:16  now=night
current=washi  want=washi  action=none  night light=4000K
```

`action=switch` means the next timer tick would call `dram-theme`. Exit 1
means the wanted theme is not installed.

Location comes from `dram.location` in `modules/hosts/<host>.nix` (one string
`"LAT LON"`, decimal degrees, east positive; the default in
`modules/options.nix` is Boston, `42.36 -71.06`). `dram switch` writes it to
`~/.config/dram/location` and `~/.config/dram/facts.lua`. After a move: change
the option, commit, `dram switch`, `dram-theme-auto --print` shows the new
sunrise and sunset. Sun times are computed locally (NOAA approximation,
±2 min); nothing is fetched.

`SUPER+ALT+N` (`nightlight.sh`) is the manual override: it forces 4000 K now,
and the next press hands control back to the sun. The schedule has no fixed
clock times; `hyprsunset.conf` only caps gamma.

## Wallpaper

The wallpaper is a quote, rendered as a page in the active theme's colours:

- `quote-wallpaper.sh` builds an HTML page per output and screenshots it with
  headless Chromium (real fonts, real kerning), writes the PNGs to
  `~/pictures/wallpapers/` and shows them through `awww-daemon`. One output
  gets a random English quote (Fraunces, cached offline from pyjama.sh); a
  second output gets a Russian proverb from
  `~/.config/quote-wallpaper/quotes-ru.txt` (EB Garamond; Fraunces has no
  Cyrillic). Colours come from `~/.config/themes/current/waybar.css`, so the
  wallpaper never disagrees with the bar.
- It runs at login (`hyprland.lua`), after every `dram theme`, and on monitor
  hotplug. By hand: `quote-wallpaper.sh` (everything), `--en` or `--ru` (one
  new quote), `--show` (re-display the cached renders, no render).
- `SUPER+SHIFT+W` (`wallpaper-menu.sh`) lists the images in
  `~/pictures/wallpapers` in rofi and fades the chosen one onto the focused
  monitor. It is a manual override for one output; the next theme switch or
  hotplug repaints the quote.
- A theme can replace all of this: an executable
  `dotfiles/.config/themes/<id>/wall.sh` runs instead of the generator, with
  the same arguments. No shipped theme has one.
- The paper grain over the whole screen is a Hyprland screen shader
  (`dotfiles/.config/hypr/shaders/grain.frag`), cleared while gamemode runs.

`docs/design/themes/wallpaper.md` has the layout rules, the corpora and the host-side checks.

## Fonts

| Face | Role | Comes from |
|---|---|---|
| Fraunces | display: bar nameplate, clock, `№ n`, hyprlock time, search entries | nixpkgs `fraunces`, `home.packages` in `modules/desktop.nix` (`dram switch`) |
| Literata | text and UI: every word at 14 px and below, GTK/Qt UI font, captions, Cyrillic | nixpkgs `literata` (`dram switch`) |
| Monaspace Xenon / Radon | mono: kitty, the editor, every readout | pacman `otf-monaspace` (`packages/roles/desktop.txt`) |
| EB Garamond Italic | hero italic at 15 px and above: the Russian date, prompts, the quote wallpaper | nixpkgs `eb-garamond` plus the tracked `dotfiles/.local/share/fonts/EBGaramond-Italic.ttf` |
| Symbols Nerd Font Mono | the only icon source (never in the bar) | pacman `ttf-nerd-fonts-symbols-mono` (`packages/roles/desktop.txt`) |
| Noto Sans / Serif / Emoji | the honest generics for pages that ask for them | pacman `noto-fonts`, `noto-fonts-emoji` |

`fonts.fontconfig.defaultFonts` in `modules/desktop.nix` sets serif to
Literata, EB Garamond, Noto Serif; monospace to Monaspace Xenon, JetBrainsMono
Nerd Font; sans-serif stays Noto Sans. `~/.config/fontconfig/conf.d/60-letterpress.conf`
appends Literata as a weak Cyrillic fallback behind Fraunces and EB Garamond.
Fraunces is never used for Russian.

Check a host:

```sh
fc-list | grep -iE 'fraunces|literata|monaspace|garamond' | wc -l   # > 0 for each family
fc-match -s serif | head -2                                          # Literata, EB Garamond
fc-match "Symbols Nerd Font Mono"                                    # SymbolsNerdFontMono-Regular.ttf
gsettings get org.gnome.desktop.interface font-name                  # 'Literata 11'
```

A nixpkgs face missing means `dram switch` has not run since
`modules/desktop.nix` listed it; a pacman face missing means
`sudo pacman -S --needed otf-monaspace ttf-nerd-fonts-symbols-mono noto-fonts`.
With a face missing the layout still works in the fallbacks; it only looks
like last week.

## The design contract

Every theme is paper plus two inks. The body ink is `@text`; the accent is ONE
colour per theme, stated as the same hex in four places (`@define-color accent`
in `waybar.css` and `swaync.css`, `$accent` in `hyprlock.conf`,
`palette.accent` and `accent_dim` in `palette.lua`, `cursor_trail_color` in
`kitty.conf`) and used only as a rule, a numeral or a cursor, never as a fill.
Chrome is flat with 3–4 px radii and 1 px hairlines in `alpha(@text,.18)`; the
bar is a masthead with the drink's name in Fraunces, the workspace as `№ 4`, a
Russian date in EB Garamond italic and small-cap captions instead of icons.
Nothing in the dram uses Nerd glyphs as decoration, all-caps, 20 px bubbles,
neon or redaction bars. The full contract, per surface and per size, is
`docs/design/README.md`.

## Adding a theme

A theme is `dotfiles/.config/themes/<id>/` with the same 15 files as every
other theme; six of them are generated from the others. Steps, on the Mac or
a host:

1. Copy the closest theme (`washi` for dark, `washi-day` for light):

   ```sh
   cd ~/git/dotfiles
   cp -r dotfiles/.config/themes/washi dotfiles/.config/themes/<id>
   ```

2. Edit the hand-written files: `waybar.css` (the `@define-color` palette,
   which is also what the wallpaper and the generators read), `swaync.css`,
   `swayosd.css`, `kitty.conf` (all colours except the five tab
   lines), `hyprlock.conf`, `fzf.opts`, `satty.toml`, and
   `palette.lua` (`accent`, `accent_dim`, `active1/2`, `inactive`, `shadow`).
   Put the same accent hex in the four slots named above.

3. Fill `meta.sh`: `MENU_NAME="<a drink>"` (unique), `GTK_THEME_NAME`
   (`adw-gtk3-dark` or `adw-gtk3`), `COLOR_SCHEME` (`prefer-dark` or
   `prefer-light`), `BAT_THEME`,
   `YAZI_FLAVOR="letterpress-<id>"`, `VSCODIUM_THEME="Letterpress — <MENU_NAME>"`.

4. Generate the derived files. Each generator prints the files it wrote and
   exits 0:

   ```sh
   python3 bin/gen-rofi-themes.py <id>      # rofi.rasi
   python3 bin/gen-gtk-css.py <id>          # gtk.css, gtk3.css
   python3 bin/gen-kitty-tabs.py <id>       # the five tab lines in kitty.conf
   python3 bin/gen-tui-themes.py <id>       # btop.theme, cava.theme
   python3 bin/gen-browser-css.py <id>      # browser.css
   python3 bin/gen-yazi-flavors.py <id>     # dotfiles/.config/yazi/flavors/letterpress-<id>.yazi/
   python3 bin/gen-vscode-themes.py         # no argument: every theme plus the extension's package.json (which lists them); `<id>` writes that theme's JSON only and leaves package.json alone
   ```

5. Add the row to the table in `docs/design/README.md` ("The bar — theme names") and
   to the table above, then:

   ```sh
   bash bin/check.sh          # ends with: all checks passed, N warning(s)
   git add -A dotfiles/.config/themes/<id> dotfiles/.config/yazi/flavors/letterpress-<id>.yazi dotfiles/.vscode/extensions/letterpress-themes docs
   git commit -m "themes: <id> (<MENU_NAME>)"
   ```

   A `failure(s)` line from `check.sh` names the file; fix and re-run.

6. Push the commit to a host (`bin/push-host.sh pj@<ip>` on the Mac), then
   `dram theme <id>`, and look at: waybar, a kitty window, rofi (`SUPER+R`), a
   toast (`notify-send hi`), hyprlock (`SUPER+L`), a GTK app, a Qt app, yazi,
   btop, the editor, the wallpaper.

## Changing one colour everywhere

The accent is the usual case. For theme `<id>`:

1. Change the hex in the four slots: `waybar.css` and `swaync.css`
   (`@define-color accent`), `hyprlock.conf` (`$accent`), `palette.lua`
   (`accent`, and `accent_dim` to a darker step of it), `kitty.conf`
   (`cursor_trail_color`); and the same colour in `swayosd.css` (`@osd-progress`).
2. Re-run the generators for that theme (step 4 above, the six with `<id>`,
   plus `gen-vscode-themes.py <id>`); they derive the GTK, rofi, TUI, browser,
   yazi and editor colours from `waybar.css` and `palette.lua`.
3. `bash bin/check.sh`, commit, push to the host, `dram theme <id>` to reload.
   Running the generators a second time must produce no diff
   (`git status --short` is empty); if it does not, a hand-written file and a
   generated one disagree.

Any other palette slot (`@base`, `@text`, `@subtext`, …) is the same
procedure with a different `@define-color` line.

## The editor, browser and mail chrome

These three read their theme from the profile, which does not exist until the
app has been opened once:

- **VSCodium**: the themes are one local extension
  (`dotfiles/.vscode/extensions/letterpress-themes`, linked at
  `~/.vscode-oss/extensions/pj.letterpress-themes` by `modules/desktop.nix`), registered in
  `~/.vscode-oss/extensions/extensions.json` by `codium-themes-install`, which
  `dram theme` runs every time; `settings.json` is seeded from
  `settings.json.default` by `dram switch`. Nothing to launch first. A window
  that was open during the switch shows the new theme after a reload
  (`Developer: Reload Window`); the colour theme itself hot-reloads.
- **LibreWolf** and **Thunderbird**: `dram theme` links the tracked
  `userChrome.css` and `themes/current/browser.css` into every profile's
  `chrome/` directory, and seeds Thunderbird's `user.js` once. A profile exists
  only after the first launch, so on a new host: open the app once, close it,
  `dram theme <id>`, open it again. Both read the sheets at startup, so every
  later theme change needs a restart of the app.

## Done when

- [ ] `systemctl --user list-timers` lists `dram-theme-auto.timer`

- [ ] `dram theme <id>` prints `switched to <bar name> (<id>)` and the bar's
      nameplate shows that drink.
- [ ] `dram doctor` prints `[ok] theme: <id>` in the `dram` section and no
      `[!]` lines.
- [ ] `dram-theme-auto --print` shows the host's sunrise and sunset and
      `action=none` while a hand-picked theme is active.
- [ ] `SUPER+ALT+N` warms the screen and a second press returns it to the
      schedule.
- [ ] The four font checks above answer as listed.
- [ ] LibreWolf, Thunderbird and VSCodium show the theme's chrome after one
      restart.

# Switcher

[Design](../README.md) › [Themes](README.md) › Switcher

`dram theme` moves an Arch desktop to another of the 17 themes by repointing one symlink, `~/.config/themes/current`, and reloading the apps that read through it.
A theme can be named by its bar name or by its id.
A user timer switches between washi and washi-day at sunrise and sunset unless another theme was picked by hand, and it warms the screen at night.

| | |
|---|---|
| Code | `dotfiles/.local/bin/dram-theme`, `dotfiles/.local/bin/dram-theme-auto`, `dotfiles/.local/bin/nightlight.sh`, `dotfiles/.config/hypr/hyprsunset.conf`, `modules/theme.nix`, the user timer in `modules/desktop.nix`, `dram.location` in `modules/options.nix` |
| Runs on | the Arch hosts with the desktop role: cabin, lantern, campfire |
| Needs | Hyprland 0.56.2, hyprsunset 0.4.0, rofi 2.0.0, `gsettings` from glib2 2.90.1, libnotify 0.8.8, Python 3.14.8 and systemd 262, tested 2026-10; the theme directories in `dotfiles/.config/themes/` |
| Decided in | the switcher in the desktop role ([decision 0009](../../../decisions/0009-roles-and-host-shape.md)); Adwaita icons and pointer for each theme ([decision 0013](../../../decisions/0013-software-rules-and-waivers.md), [the pointer, 2026-10-12](../../../decisions/log.md#d132)) |

## How it works

`dram theme` runs `dotfiles/.local/bin/dram-theme`, which `modules/theme.nix` links into `~/.local/bin` on a host with the desktop role.
Most apps read their theme file through `~/.config/themes/current`, so repointing that symlink does the larger part of a switch.
Waybar, swaync, swayosd, nwg-drawer and gsimplecal import a CSS file from it, rofi and kitty include one, hyprlock sources one, Hyprland reads `palette.lua` with `dofile()`, and fzf reads `fzf.opts`.
[themes](../../../dotfiles/.config/themes/README.md#copy-it-alone) lists the include lines.

### Names and ids

Each theme has two names.
The id is its directory under `dotfiles/.config/themes/`, such as `washi`, and scripts, `dram-theme-auto` and the `current` symlink use it.
The bar name is a drink, `MENU_NAME` in the theme's `meta.sh`, such as Boulevardier, and the picker, the notification and the bar's nameplate show it.
`dram theme` takes either, and a bar name in any case.
The picker lists the bar names in alphabetical order and shows the current one in its prompt.
`bin/check-themes.py` rule 3 keeps each bar name unique and different from the other themes' ids, so a name cannot mean two themes.
`dram theme` refuses `current`, `.`, `..` and any name with a slash: a `current` that pointed at itself would stop Hyprland from starting.
[Design](../README.md#the-themes) lists the 17 pairs.

### What a switch changes

1. It waits up to 30 s for the lock `$XDG_RUNTIME_DIR/dram-theme.lock`, so the timer and a switch by hand cannot both restart Waybar.
2. It checks that the new theme's `meta.sh` parses, and reads it, before anything moves.
3. It repoints `current`.
4. It sets what no include line reaches, app by app.
5. It reloads the apps that can reload.

| App | What the switch does |
|---|---|
| GTK | `gsettings` sets `gtk-theme` from `GTK_THEME_NAME` and `color-scheme` from `COLOR_SCHEME`; `~/.config/gtk-3.0/gtk.css` and `~/.config/gtk-4.0/gtk.css` link to the theme's generated stylesheets ([GTK](generators.md#gtk)) |
| fonts | `gsettings` sets the interface font to Literata 11, the document font to Literata 12 and the monospace font to Monaspace Xenon 11 ([Typography](../typography/README.md)) |
| icons and pointer | Adwaita for both, with the pointer at 24 px, also through `hyprctl setcursor` |
| bat | `~/.config/bat/config` gets `--theme` from `BAT_THEME` |
| btop | `~/.config/btop/themes/dram.theme` links to `current/btop.theme` |
| cava | the theme's `cava.theme` replaces the `[color]` block of its config |
| yazi | `dark` and `light` in its `theme.toml` both name `YAZI_FLAVOR` |
| VSCodium | `"workbench.colorTheme"` in its `settings.json` becomes `VSCODIUM_THEME`, and `codium-themes-install` registers the Letterpress extension |
| satty | its `palette = [...]` line comes from the theme's `satty.toml` |
| LibreWolf, Thunderbird | each profile's `chrome/` gets a link to the tracked `userChrome.css` and a `letterpress-colors.css` link to `current/browser.css`; a Thunderbird profile without a `user.js` gets a copy of `user.js.default` |
| Qt | nothing: Qt apps follow GTK through `QT_QPA_PLATFORMTHEME=gtk3`, set in `hyprland.lua` |

Then the reloads.
`quote-wallpaper.sh` renders the wallpaper in the new colors in the background, with a new quote ([Wallpaper](wallpaper.md)).
`hyprctl reload` runs `hyprland.lua` again, which reads the new `palette.lua`.
Waybar restarts, swayosd-server restarts if it runs, swaync reloads its style, kitty gets SIGUSR1, and cava and btop get SIGUSR2.
Waybar restarts because a running Waybar keeps the colors of its old `@import`: GTK caches an imported file by its path, and the path through `current` stays the same.
The processes the switch starts close the lock's file descriptor (`9>&-`).
On 2026-10-11 on cabin, a Waybar that held it made each later switch wait 30 s and give up with `another dram-theme is still running`.

A notification titled with the bar name says what still needs a restart, and the terminal gets `switched to <bar name> (<id>)`.

## Machine-state files

A switch cannot edit tracked files without leaving git dirty, so the files it edits in place are machine state.
Each has a tracked template that is copied into place when the live file is missing, and a switch then rewrites a few of its keys.

| Live file | Template | Rewritten on each switch |
|---|---|---|
| `~/.config/gtk-3.0/settings.ini`, `~/.config/gtk-4.0/settings.ini` | `settings.ini.default` | `gtk-theme-name`, `gtk-application-prefer-dark-theme` from `COLOR_SCHEME`, `gtk-icon-theme-name` and `gtk-cursor-theme-name` as Adwaita, and `gtk-font-name=Literata 11` |
| `~/.config/satty/config.toml` | `config.toml.default` | the one `palette = [...]` line |
| `~/.config/cava/config` | `config.default` | the `[color]` block, and `bar_width = 1` |
| `~/.config/yazi/theme.toml` | `theme.toml.default` | `dark = "<YAZI_FLAVOR>"` and `light = "<YAZI_FLAVOR>"` |
| `~/.config/btop/btop.conf` | `btop.conf.default` | `color_theme = "dram"`, `rounded_corners = false`, `theme_background = false` |
| `~/.config/VSCodium/User/settings.json` | `settings.json.default` | `"workbench.colorTheme"`, and `editor.fontFamily`, `terminal.integrated.fontFamily` and `editor.fontLigatures` as the template has them |

The directories of GTK, satty and cava, and VSCodium's `settings.json`, are links into the repo.
Those live files sit in the repo's tree, and `.gitignore` lists them.
yazi and btop are linked file by file (`modules/cli.nix`), so their live files sit in `~/.config`, outside the repo.

- `gtk-font-name` has no effect on Wayland, where GTK reads the font from `gsettings` through the settings portal, and the line keeps the file in step.
- satty has no include and no palette option, so its live file takes the one line.
- yazi picks its `dark` or `light` flavor by sniffing the terminal's background, which the theme sets, so both lines name the theme's flavor.
- btop rewrites its whole `btop.conf` on exit, so each switch writes the three keys back and adds any that btop left out: `theme_background` defaults to true, which would paint over the terminal's grain.
- VSCodium's file is seeded by `modules/theme.nix` at the repo path when Home Manager activates.
  The switch cannot seed it, because the link exists before its target does and `cp` does not write through a link to a missing file.

## Day and night

`dram-theme-auto` follows the sun between the two washi themes: washi-day from sunrise to sunset, washi otherwise.
It switches only when the current theme is one of those two, so a theme picked by hand stays until washi or washi-day is picked again.
Picking washi by hand in daylight lasts until the next check, which moves it to washi-day.
When the right theme is already on, it leaves the theme as it is.

The same clock drives the night light: `hyprctl hyprsunset temperature 4000` after sunset, and `hyprctl hyprsunset identity` after sunrise.
The night light follows the sun under any theme.
It is left alone while `nightlight.sh` holds its manual override in `$XDG_RUNTIME_DIR/nightlight.state`, and when no hyprsunset runs.

Sunrise and sunset come from NOAA's solar approximation, computed in Python without a network, to within about 2 minutes.
Polar day counts as day and polar night as night.

### Location

The sun is computed for one line, `LAT LON` in decimal degrees with east positive, in `~/.config/dram/location`.
`modules/core.nix` writes that file from `dram.location`, an option in `modules/options.nix` whose default is Boston, `42.36 -71.06`.
Without the file, or with a line it cannot read, `dram-theme-auto` uses Boston as well.
To follow your own sun, set `dram.location` in your host's `modules/hosts/<host>.nix`, run `dram switch`, and check the times with `dram-theme-auto --print`.

### The timer

`modules/desktop.nix` declares two user units.
`dram-theme-auto.service` is a oneshot wanted by `graphical-session.target`, so it runs at login.
`dram-theme-auto.timer` starts it on `OnCalendar=*:0/10` with `Persistent=true`, so a switch lands within ten minutes of sunrise or sunset.
A run from the timer has no Hyprland environment.
`dram-theme-auto` takes the newest live Hyprland instance under `$XDG_RUNTIME_DIR/hypr/` and its Wayland display, so the switch's reloads reach the compositor.

### The night light

`hyprland.lua` starts `hyprsunset` with no arguments at login.
It idles at identity, with no color shift, until a client talks to it over IPC.
`~/.config/hypr/hyprsunset.conf` holds one setting, `max-gamma = 100`.
SUPER+ALT+N runs `nightlight.sh`, the manual override:

| Before the press | The press |
|---|---|
| the session's hyprsunset, on the sun's setting | sets 4000 K over IPC and writes `ipc` to the state file |
| 4000 K from an earlier press | removes the state file and runs `dram-theme-auto --nightlight`, which puts back the sun's setting |
| no hyprsunset running | starts one at 4000 K and writes `spawned`; the next press stops it |

Until 2026-10-06 the schedule was a set of fixed `profile { time = HH:MM }` blocks in `hyprsunset.conf`.
Fixed times cannot follow the sun or a move.
In hyprsunset 0.4 a profile's `gamma` is a fraction (`1.0`), and the old `gamma = 100` made the daemon exit at startup.

## Use it

```sh
dram theme                 # the rofi picker, as SUPER+T; Esc changes nothing
dram theme washi-day       # by id; prints "switched to Bellini (washi-day)"
dram theme "gold rush"     # by bar name, in any case
dram theme --list          # "<bar name>  <id>" per line, sorted by id
dram theme --ids           # the ids alone, which the shell completion reads
```

```sh
dram-theme-auto --print                              # what a check would do; changes nothing
systemctl --user list-timers dram-theme-auto.timer   # when the next check runs
systemctl --user start dram-theme-auto               # check at once
hyprctl hyprsunset identity get                      # true by day, false after sunset
```

`dram-theme-auto --print` prints two lines, for example:

```text
location 42.36 -71.06  sunrise 06:46  sunset 18:16  now=night
current=washi  want=washi  action=none  night light=4000K
```

`action=switch` means the next check runs `dram-theme`.
`hyprctl hyprsunset temperature` prints the last value set, 4000 even after `identity`, because hyprsunset 0.4.0 only flips a flag: `identity get` is the query that tells day from night.
The routine steps, with what to look at after a switch, are in handbook chapter 6, [Theme and look](../../records/handbook/06-theme-and-look.md).

## When it breaks

| Symptom | Check | Fix |
|---|---|---|
| Hyprland does not start, or `dram doctor` warns `themes/current (in ~/.config) does not resolve to a theme` | `readlink ~/.config/themes/current` | `dram switch`, which links `current` to washi when it is missing, or `dram theme washi` |
| `no such theme: <name> (try --list)` and exit 1 | `dram theme --list` | use a bar name or an id from the list |
| `<theme dir>/meta.sh does not parse — theme not switched` | `bash -n` on that file | fix its shell syntax; nothing else moved |
| `another dram-theme is still running` after 30 s | `pgrep -a dram-theme` | let the other switch finish, then run yours again |
| an app keeps the old colors | the notification names the apps that read their style at start | restart the GTK and Qt apps that were open, Chromium, LibreWolf and Thunderbird; rofi and hyprlock change on their next open |
| the timer does not move the theme | `dram-theme-auto --print` shows `action=none` | the current theme is neither washi nor washi-day: pick one of them |
| the screen stays warm by day | `cat "$XDG_RUNTIME_DIR/nightlight.state"` | press SUPER+ALT+N to hand the night light back to the sun |

## Limits

- Arch only: Windows keeps one look, washi's, and has no switcher ([Windows look](windows.md)).
- The boot menu, the splash and the ly greeter keep the fixed house palette ([Boot screens](../shell-and-bars/boot-screens.md)).
- The day and night cycle knows two themes, washi and washi-day.
- The night light has one warmth, 4000 K, for the sun's schedule and for the manual override.
- `dotfiles/.config/qutebrowser/config.py` sets Catppuccin Mocha's colors itself and does not follow `dram theme` (2026-10-13).

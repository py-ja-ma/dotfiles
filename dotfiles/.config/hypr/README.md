# hypr

[Design](../../../docs/design/README.md) › [Shell & bars](../../../docs/design/shell-and-bars/README.md) › Hyprland

My Hyprland session in Hyprland's Lua configuration, with its idle timer, lock screen and paper-grain shader.
Windows sit 18 px from the screen's edge, with a 2 px border in the theme's accent, a soft shadow and no blur.
The lock screen is the quote wallpaper under a large Fraunces clock and one accent rule.

| | |
|---|---|
| Needs | Hyprland 0.56.2 with its Lua configuration, hypridle 0.1.8, hyprlock 0.9.6, tested 2026-10; Fraunces, Literata, EB Garamond, Monaspace Xenon; two palette files |
| Copy alone | yes, after replacing my monitors and giving it a palette |
| License | MIT; `hyprland.lua` began as Hyprland's example configuration, which is BSD-3-Clause |

## What it needs

- Hyprland 0.56.2 from Arch's `extra` repo, tested 2026-10.
  `hyprland.lua` uses Hyprland's Lua API (`hl.config`, `hl.bind`, the `hl.dsp.*` dispatchers), so it needs a Hyprland with the Lua configuration.
- hypridle 0.1.8 and hyprlock 0.9.6, from `extra`.
- The lock screen's fonts: Fraunces for the clock, EB Garamond Italic for the date, Literata for the password field and Monaspace Xenon for the layout ([Typography](../../../docs/design/typography/README.md)).
- Two files from one theme in `~/.config/themes/current/`.
  `palette.lua` colors the borders and the shadow, and the theme's `hyprlock.conf` defines the lock screen's `$base`, `$text`, `$subtext`, `$accent` and `$fail`.
  Each of the 17 themes in `dotfiles/.config/themes/` has both ([themes](../themes/README.md)).
  While `palette.lua` is missing, Hyprland does not start with this configuration.
- Optionally `~/.config/dram/facts.lua`, a Lua table of facts about the host.
  `hyprland.lua` reads its `laptop` and `roles`, and without the file it treats a host with a battery as a laptop.
- The programs under [Autostart](#autostart), and the programs the keys run, which the [keybinds](../../../docs/design/shell-and-bars/keybinds.md) page lists.
  A key or an autostart line whose program is missing has no effect.
- The seven scripts under [Helper scripts](#helper-scripts), from `dotfiles/.local/bin/`.
- Optionally the plugins hyprtasking and hyprfocus, built for Hyprland 0.56.2 as `/usr/lib/hyprland/libhyprtasking.so` and `/usr/lib/hyprland/libhyprfocus.so`.
  The `[dram]` repo I build has them as `hyprland-plugin-hyprtasking` and `hyprland-plugin-hyprfocus`.
- Not needed: Nix, Home Manager or `dram`.

## Copy it alone

1. Install Hyprland 0.56.2, hypridle and hyprlock, and the four fonts.
2. Copy `hyprland.lua`, `hyprland-gui.lua`, `hypridle.conf` and `hyprlock.conf` to `~/.config/hypr/`, and `shaders/grain.frag` to `~/.config/hypr/shaders/`.
   Leave out `gaming.lua` and `hyprsunset.conf`, which belong to Gaming Mode and the night light.
3. Give it a palette.
   Copy `palette.lua` and `hyprlock.conf` from one theme to `~/.config/themes/current/`, for example from `dotfiles/.config/themes/washi/`.
   Or replace `local theme = dofile(...)` in `hyprland.lua` with a table of your own:

   ```lua
   local theme = { accent = "rgba(c0442bee)", accent_dim = "rgba(8a311fee)", angle = 45,
                   inactive = "rgba(3a2a22aa)", shadow = "rgba(0e0a08aa)" }
   ```

   Then replace the `source` line at the top of `hyprlock.conf` with your own five variables:

   ```ini
   $base    = rgba(28, 20, 15, 1.0)
   $text    = rgba(230, 214, 203, 1.0)
   $subtext = rgba(172, 156, 146, 1.0)
   $accent  = rgba(192, 68, 43, 1.0)
   $fail    = rgba(192, 68, 43, 1.0)
   ```

4. Replace my monitors.
   `MON_MAIN` and `MON_MID` name my two NZXT panels by their EDID description, and `MON_LAP` names my laptop's panel `eDP-1`.
   Run `hyprctl monitors` and put each monitor's `description` after `desc:`, or write its port name, such as `DP-1`.
   Set the modes in `MON_MODE_MAIN` and `MON_MODE_MID`, and the positions in the `hl.monitor` lines.
   A monitor that no line names takes its preferred mode from the last `hl.monitor` line.
5. Tell it whether the host is a laptop.
   Without `~/.config/dram/facts.lua`, a battery makes it one: the laptop's panel then takes workspaces 1 to 3, and the lid switch turns the panel off and on.
   To decide yourself, write `return { laptop = false, roles = {} }` into that file.
   `"gaming"` in `roles` starts Steam at login on a desktop and adds SUPER+CTRL+G, and `"creator"` adds the recording and zoom keys.
6. Delete what you don't have.
   Without the plugins, delete the two `hl.plugin.load` lines.
   The first autostart line starts `hyprland-session.target`, a user unit that `modules/desktop.nix` defines in this repo.
   Delete that line, or save this as `~/.config/systemd/user/hyprland-session.target`:

   ```ini
   [Unit]
   Description=Hyprland session
   BindsTo=graphical-session.target
   Wants=graphical-session-pre.target
   After=graphical-session-pre.target
   ```

7. Copy the helper scripts you want to `~/.local/bin/` and make them executable: `kb-layout.sh`, `layout-toggle.sh`, `screenshot.sh`, `ocr-copy.sh`, `welcome.sh`, `keybind-cheatsheet.sh`, and `lid.sh` on a laptop.
   Put your name in the title on the last line of `welcome.sh`: `"Welcome back, <name>"`.
   The other scripts the keys run come from their own modules, listed under [Files](#files).
8. Set your keyboard layouts.
   Change `kb_layout = "us,ru"` to your layouts, and `$LAYOUT[en,ru]` in `hyprlock.conf` to match.
   For layouts other than `us` and `ru`, add each code with the name Hyprland reports for it to the `names` map in `kb-layout.sh`, such as `"de": "German"`.
   Without that entry the toggle can't tell which layout is active, and it stays on the second.
9. Point the lock screen at a picture.
   `path` in `hyprlock.conf` names the quote wallpaper, `~/pictures/wallpapers/quote-wall.png`, which `quote-wallpaper.sh` writes.
   Name your own picture, or delete the line for plain paper in `$base`.
10. Log in to Hyprland.
    It worked when the focused window's 2 px border fades from the accent to its darker step, and SUPER+/ lists the keys.
    SUPER+L shows the clock over the accent rule, the date and the password field.
    `hyprctl getoption decoration:screen_shader` prints the path of `grain.frag`.

## How it is wired here

`modules/desktop.nix` links `dotfiles/.config/hypr` whole to `~/.config/hypr` on hosts with the desktop role, and links the helper scripts into `~/.local/bin` one by one.
`modules/laptop.nix` links `lid.sh` on laptops only, which are also the hosts where `hyprland.lua` binds the lid switch.
`modules/core.nix` writes `~/.config/dram/facts.lua` from the host's `dram.*` flags, as `return { backupPeer, gpu, host, laptop, location, roles }`.
`dram doctor` compares its `host` and `gpu` with `/etc/hostname` and `lspci`.
ly's Desktop entry starts Hyprland through `/usr/lib/dram/session-hyprland` from `pkgs/dram-gaming-mode`.
Its Gaming Mode entry starts Hyprland with `gaming.lua` in place of this file ([Gaming Mode](../../../decisions/0012-gaming-mode.md)).
ly starts Hyprland without uwsm, so the first autostart line hands the Wayland environment to the user manager and starts `hyprland-session.target`, which `modules/desktop.nix` defines.
That target binds `graphical-session.target`, and the user services that wait for it start with it: Proton Mail Bridge, the YubiKey touch notifier and the day and night theme check.
`dram theme` repoints `themes/current` and runs `hyprctl reload`, which runs `hyprland.lua` again with the new `palette.lua`.
`system/limits-hyprland.conf` becomes `/etc/security/limits.d/20-hyprland.conf` on desktop hosts, so Hyprland gets the realtime priority it asks for at start.
Its two lines name my user.
`dram doctor` warns when a plugin package was built for another Hyprland than the installed one.
`bin/check.sh` §16 parses each `hypr/*.lua` with `luac -p` when `luac` is installed.
`bin/gen-commands-doc.py` reads the keys and autostart lines that run a script into `docs/commands.md`, and `bin/check.sh` §13 fails while that page is stale.

## Monitors

`hyprland.lua` matches my monitors by EDID description, because the laptop's dock renumbers its DisplayPort outputs between dockings.
DP-6 and DP-4 have come back as DP-5 and DP-8, and a rule by port then misses.
The two panels are the same model, NZXT CANVAS 27Q, and differ only in the serial at the end of the description.
The descriptions stay on each host, in `~/.config/dram/monitors.lua`: `monitors-pin.sh` writes it from the panels as Hyprland places them, the leftmost as `main`, then `mid`, and `hyprctl reload` applies it.
Without the file the rules name cabin's ports, `DP-1` and `HDMI-A-1`.

| Name | Matches | cabin, the desktop | lantern, docked |
|---|---|---|---|
| `MON_MAIN` | the left panel, `main` in `monitors.lua` | 2560×1440 at 165 Hz over DisplayPort, at 0,0 | 2560×1440 at 59.95 Hz |
| `MON_MID` | the middle panel, `mid` in `monitors.lua` | 2560×1440 at 144 Hz over HDMI, at 2560,0 | 2560×1440 at 59.95 Hz |
| `MON_LAP` | `eDP-1`, the laptop's panel | none | 1920×1200 at 60 Hz, scale 1.5, at 5120,640: right of the panels, bottom edges level |
| any other | the last `hl.monitor` line | its preferred mode, placed and scaled automatically | the same |

The dock drives the panels at 60 Hz only, so lantern asks for 59.95.
Hyprland's `highrr` mode stays unused: it picks the highest rate at any resolution, and on 2026-10-05 it dropped cabin to 1920×1080 at 165 Hz.

| Workspaces | cabin | lantern |
|---|---|---|
| 1 to 3 | the left panel | the laptop's panel |
| 4 to 6 | the left panel | the left panel |
| 7 to 9 | the middle panel | the middle panel |

The nine workspaces are persistent.
Each monitor opens on the first of its own: 1 and 7 on cabin, and 1, 4 and 7 on lantern.
A workspace whose monitor is absent opens on a monitor that is connected.
Each monitor's bar shows the numeral of its own workspace ([waybar](../waybar/README.md)).

## Autostart

`hl.on("hyprland.start", …)` runs these lines once, when Hyprland starts, and `hyprctl reload` doesn't run them again.

| Line | Starts | From |
|---|---|---|
| `systemctl --user import-environment …` with `systemctl --user start hyprland-session.target` | the user services of the graphical session | [How it is wired here](#how-it-is-wired-here) |
| `systemctl --user start hyprpolkitagent` | Hyprland's polkit agent, which asks for the password for admin actions | hyprpolkitagent 0.2.0 |
| `quote-wallpaper.sh`, `wallpaper-hotplug.sh` | the quote wallpaper, painted again on a monitor plugged in later | [quote wallpaper](../../../docs/design/themes/wallpaper.md) |
| `waybar`, `waybar-fullscreen.sh` | the bar, hidden over a fullscreen window | [waybar](../waybar/README.md) |
| `env LANG=ru_RU.UTF-8 swaync` | notifications, with swaync's own words in Russian | [swaync](../swaync/README.md) |
| `welcome.sh` | the login toast | [Helper scripts](#helper-scripts) |
| `swayosd-server`, when installed | the volume and brightness bar | [swayosd](../swayosd/README.md) |
| `udiskie` | mounts removable drives, with no tray icon | udiskie 2.7.0 |
| `hyprsunset` | the night light, idle until asked over IPC | [switcher](../../../docs/design/themes/switcher.md) |
| `hypridle` | the idle timer | [Idle](#idle) |
| `wl-paste --type text --watch cliphist store`, and the same for images | the clipboard history behind SUPER+SHIFT+V | cliphist 0.7.0, wl-clipboard 2.3.0 |
| `wl-clip-persist --clipboard regular` | keeps the clipboard's contents after the program that copied them closes | wl-clip-persist 0.5.0 |
| `steam -silent`, gaming role, desktops only | Steam, minimized, so it works through the shader caches in the background | Steam |

`blueman-applet` stays commented out.
Its white tray icon vanished on light themes, and Waybar's own Bluetooth word took its place.

## Look and motion

| Setting | Value | Why |
|---|---|---|
| `gaps_in`, `gaps_out` | 6 and 18 px | a page has margins |
| `border_size` | 2 px, a gradient from `accent` to `accent_dim` at the palette's `angle`; an unfocused window takes `inactive` | the accent as a rule around the focused window |
| `rounding` | 4 px | a card's corner |
| `dim_inactive`, `dim_strength` | on, 0.08 | the focus cue, since each window stays fully opaque |
| `shadow` | range 24, `render_power` 4, the palette's `shadow` | lifts a window off the page, the work the blur used to do |
| `blur` | off | see [Blur](#blur) |
| `layout` | dwindle | SUPER+ALT+L swaps in scrolling until the next reload |
| `allow_tearing` | on | windows marked `immediate`, the games, tear for the lowest latency |
| `animate_mouse_windowdragging` | on | the jello drag: a dragged window trails the pointer through the `jiggle` spring |

VRR stays off: with tearing on, Hyprland bounces between the two modes (Hyprland discussion #13244).
Windows move on `jiggle`, a spring with the mass and stiffness of Hyprland's default `easy` and a dampening of 8.9 in place of 15.8.
That is about half of critical damping, so a moved window overshoots and settles.
8.9 gives about 40 % less overshoot than the 7.0 the spring had until 2026-10-05.
New windows pop in from 92 % on `md3Decel`, closing ones shrink to 90 % on `md3Accel`, and workspaces change with an 8 % slide and fade.
`hyprland-gui.lua` turns the `borderangle` animation off, so the border's gradient holds its angle.
HyprMod, a settings editor, wrote that file, and `hyprland.lua` loads it on its last line.
I dropped HyprMod on 2026-10-06, and the file keeps the one setting it last wrote.
The hyprfocus plugin dims a window that takes keyboard focus to 85 % for a moment, and mouse focus has no animation.

## Input and environment

`kb_layout` is `us,ru` with no XKB group option.
Such an option flips one keyboard and leaves the others behind, so `kb-layout.sh` switches the layout of each keyboard at once.
The pointer's acceleration profile is flat, which gives the same movement on the desktop and in XWayland games.
Touchpads scroll the traditional way, and a three-finger horizontal swipe changes workspace.
`XCURSOR_SIZE` and `HYPRCURSOR_SIZE` are 24, and `dram theme` sets the pointer's theme.
`QT_QPA_PLATFORMTHEME=gtk3` makes Qt apps follow the GTK theme, and `_JAVA_AWT_WM_NONREPARENTING=1` keeps Java windows from coming up blank under XWayland.
The update news and the donation request that Hyprland shows after a version change are off.

## Window rules

| Rule | Matches | Does |
|---|---|---|
| `suppress-maximize-events` | each window | ignores maximize requests |
| `fix-xwayland-drags` | XWayland floats with no class and no title | keeps them from taking focus, which fixes drags in XWayland apps |
| `games-fullscreen` | `cs2` and `steam_app_<id>` | real fullscreen, which covers the bar, and `immediate` for tearing |
| `no-idle-when-fullscreen` | each fullscreen window | keeps hypridle from locking or darkening the screen |
| `move-hyprland-run` | `hyprland-run` | floats Hyprland's run dialog near the bottom left |
| `float-cava` | `cava-visualizer` | floats the cava of SUPER+A at 900 × 380 |
| `float-pavucontrol` | pavucontrol | a centered 760 × 560 float, opened from the bar's volume |
| `float-nmtui` | `nmtui` | a centered 500 × 580 float at full opacity, opened from the bar's network word |
| `place-gsimplecal` | `gsimplecal` | floats the calendar under the bar's clock, with 4 px corners |

Games run "fullscreen windowed", which Hyprland treats as an ordinary window, so the bar stayed on top of them until `games-fullscreen`.
SUPER+F still takes a game out of fullscreen.
The calendar is 339 px wide in the house fonts (`hyprctl clients` on lantern, 2026-10-06), so `monitor_w/2-170` centers it on any monitor, 46 px from the top.
GTK3 can't round its own window, so the rule rounds it.

## Keys

The [keybinds](../../../docs/design/shell-and-bars/keybinds.md) page lists each key, and SUPER+/ shows the same list in rofi.
`keybind-cheatsheet.sh` builds both from the `hl.bind` lines of `hyprland.lua`.
Each bind stays on one line, with a `description` flag for `hyprctl binds` and a trailing `-- comment` for the cheatsheet.
The parser skips the workspace keys made in a loop and the lid switch, and adds four summary rows.
After changing a key, write the page again from the repo:

```sh
KEYBIND_CONF=dotfiles/.config/hypr/hyprland.lua dotfiles/.local/bin/keybind-cheatsheet.sh --markdown > docs/design/shell-and-bars/keybinds.md
```

No check compares the page with `hyprland.lua`.

`` SUPER+` `` opens hyprtasking's overview, a 3 × 3 grid of the workspaces, where a window can be dragged to another workspace.
A four-finger swipe opens it too, and without the plugin the same key shows a notice that names the package.
SUPER+ALT+L swaps in the scrolling layout, windows on a horizontal tape, until the next `hyprctl reload`.
SUPER+CTRL with the left and right arrows then scrolls the tape by a column, and on dwindle the same keys resize.
The gaming role adds SUPER+CTRL+G, which logs out into Gaming Mode.
The creator role adds SUPER+CTRL+R, which starts and stops a recording, and SUPER+CTRL with `=`, `-` and `0`, which zoom around the pointer.

## Helper scripts

Seven scripts in `dotfiles/.local/bin/` belong to the session, and each answers `--help`.

| Script | Started by | What it does | Needs |
|---|---|---|---|
| `kb-layout.sh` | SUPER+ALT+SPACE, left Alt with left Shift, the bar's `en` or `ru` | sets each keyboard to the same layout with `hyprctl switchxkblayout all`; `status` prints the active one | Python 3 |
| `layout-toggle.sh` | SUPER+ALT+L | flips dwindle and scrolling through `hyprctl eval`, and a notification lists the new layout's keys | `notify-send` |
| `lid.sh` | the lid switch, on a laptop | turns the first `eDP` panel off when the lid closes, and on at its preferred mode and scale 1.5 when it opens | `hyprctl` |
| `screenshot.sh` | Print, SUPER+Print, SUPER+SHIFT+Print, SUPER+CTRL+Print | a region or the active window opens in satty; the focused monitor or the whole desktop goes to a file and the clipboard | grim 1.5.0, slurp 1.5.0, jq 1.8.2, `wl-copy`; satty 0.22.0 optional |
| `ocr-copy.sh` | SUPER+SHIFT+X | reads a region's text into the clipboard with tesseract and shows its first 120 characters | grim, slurp, tesseract 5.5.3 with `tesseract-data-eng`, `wl-copy` |
| `welcome.sh` | autostart | one toast: the date, the battery, the boot time, pending updates, a newer `dram` release, a reboot an update asked for | a notification daemon; `checkupdates` and `dram` optional |
| `keybind-cheatsheet.sh` | SUPER+/ | the key list in rofi, or the keybinds page with `--markdown` | Python 3, rofi |

Screenshots are named `screenshot-YYYYMMDD-HHMMSS.png` in `~/pictures/screenshots/`, the pattern of satty's own `output-filename`, so annotated and plain shots sort together.
Without satty, a region or window shot goes to the clipboard only.
`welcome.sh` waits up to 10 s for swaync, so the toast lands in the theme, and gives `checkupdates` 2 s.
`lid.sh` doesn't lock the session, which is hypridle's job.

## Idle

`hypridle.conf` locks the session before it darkens the screens.

| After | What happens |
|---|---|
| 30 min | `loginctl lock-session`, which runs hyprlock through `lock_cmd` |
| 30 min, on battery | `systemctl suspend` |
| 45 min | the screens go off, and the next input turns them on |

`lock_cmd` is `pidof hyprlock || hyprlock`, so a second lock can't stack on the first.
Before a suspend, `before_sleep_cmd` locks the session, so the machine wakes to the lock screen, and `after_sleep_cmd` turns the screens on.
At 30 minutes the third listener suspends when any `/sys/class/power_supply/*/online` reads 0, which on a laptop means it is unplugged.
The screens go off through Hyprland's Lua dispatcher, `hl.dsp.dpms({ action = "off" })`.
A bare string there means toggle, and an earlier `after_sleep_cmd` darkened screens that had already woken.
The old timer turned the screens off at 10 min and left the desktop unlocked behind them until 30, which is why the lock comes first.
A fullscreen window holds the timer off through the `no-idle-when-fullscreen` rule.

## hyprlock

hyprlock is the title page: SUPER+L, hypridle after 30 minutes and each suspend start it.

| Element | Set in | Place |
|---|---|---|
| background | the quote wallpaper, no blur, noise 0.02, brightness 0.85 | the whole screen |
| clock | `$TIME` in Fraunces at size 150, `$text` | center, 110 px up |
| rule | a 160 × 1 px shape in `$accent`, square | under the clock |
| date | EB Garamond Italic 24, `$subtext` | under the rule |
| password field | 300 × 48, a 1 px `$subtext` outline, no fill, square corners, Literata, the placeholder `пароль…` in italic | below the date |
| layout | `$LAYOUT[en,ru]` in Monaspace Xenon 12, `$subtext` | bottom right |

The wallpaper, `~/pictures/wallpapers/quote-wall.png`, is already the printed quote, so the lock screen adds no quote of its own.
`quote-wallpaper.sh` writes it on each run, and `dram theme` renders it again in the new theme's colors.
The outline turns `$accent` while hyprlock checks the password.
After a wrong one it turns `$fail`, and the field reads `нет` with the number of attempts.
hyprlock ignores an empty Enter (`ignore_empty_input`) and hides the pointer.
The date is set again each minute, in Russian when `locale -a` lists `ru_RU.UTF-8` and in English otherwise ([Russian](../../../docs/design/typography/README.md#russian)).
Fraunces has no Cyrillic, so the date is set in EB Garamond, and the clock shows figures only.
The screen fades in on `decel`, the curve of Hyprland's `windowsIn` (`bezier = decel, 0.05, 0.7, 0.1, 1`), in hyprlock 0.9's syntax: `animation = fadeIn, 1, 4, decel`.

## Blur

Hyprland's blur is one global setting.
`decoration.blur.enabled = false` turns it off for layers too, and Hyprland has no blur size or passes per layer.
So the blur is off, and each surface is flat paper.
A wide, soft shadow lifts a window off the wallpaper, the work the blur used to do.
rofi and swaync set their popups as paper at 96 % in their own styles, and nwg-drawer at 97 %.
No window rule sets `opacity` below 1: without blur, a window's alpha only shows the wallpaper through its text, as the old network picker's rule did at 0.96.
`float-nmtui` sets `opacity = 1.0` for that reason.
kitty's `background_opacity` of 0.92 fades only its background, and its text keeps the full ink ([kitty](../kitty/README.md)).
Two layer rules, `paper-rofi` and `paper-swaync`, name the only layers that would frost if a theme turned blur back on.
Their `ignore_alpha = 0.2` keeps the hairlines and the shadow out of the blur.
While blur is off they have no effect.
The bar has no such rule: it is a transparent masthead.

## Grain shader

`shaders/grain.frag` is a screen shader: one `hl.config` near the end of `hyprland.lua` sets it as `decoration.screen_shader`, and it runs over each monitor's composited frame.
It multiplies ±2.5 % noise into the frame and darkens the corners by 1.5 % with a warm tint, so the screen reads as paper.
The noise is the common one-line sine hash of the integer pixel position.
It doesn't change between frames, so it holds still when part of the screen redraws.
The warm factor, `(1.00, 0.985, 0.955)`, takes more blue out of the corners than red.

The shader is GLSL ES 3.00, written against Hyprland 0.56's interface for screen shaders:

| Declaration | Why |
|---|---|
| `#version 300 es`, on line 1 | Hyprland reads the first bytes to pick the matching vertex shader |
| `in vec2 v_texcoord` | 0 to 1 across the output |
| `uniform sampler2D tex` | the composited frame |
| `uniform vec2 fullSize` | the output's size in pixels |
| `layout(location = 0) out vec4 fragColor` | the result |

It declares no `time` uniform.
For a shader that declares one, Hyprland turns damage tracking off and redraws the whole screen each frame, a constant load on cabin's NVIDIA card.
Keyed on position alone, the grain is static, damage tracking stays on, and a still screen draws no new frames.
`gamemode.sh` (SUPER+SHIFT+G) sets `screen_shader = ""` while performance mode is on, one less full-screen pass, and sets the path again when it goes off.
Screenshots and recordings capture the grain.
hyprsunset's night light is applied at the CRTC, and screenshots don't capture it.

```sh
hyprctl getoption decoration:screen_shader                              # the path of grain.frag
gamemode.sh; hyprctl getoption decoration:screen_shader; gamemode.sh   # empty while performance mode is on
```

## Files

| File | What it does |
|---|---|
| `hyprland.lua` | the session: monitors, autostart, environment, plugins, look, input, keys, window rules and the shader |
| `hyprland-gui.lua` | turns the `borderangle` animation off; HyprMod wrote it |
| `hypridle.conf` | the idle timer |
| `hyprlock.conf` | the lock screen, colored by the theme's `hyprlock.conf` |
| `shaders/grain.frag` | the paper-grain screen shader |
| `gaming.lua` | the Gaming Mode session, part of the gaming profile (`modules/gaming.nix`) |
| `hyprsunset.conf` | the night light's settings, part of the [theme switcher](../../../docs/design/themes/switcher.md) |
| `dotfiles/.local/bin/kb-layout.sh`, `layout-toggle.sh`, `lid.sh`, `screenshot.sh`, `ocr-copy.sh`, `welcome.sh`, `keybind-cheatsheet.sh` | the [helper scripts](#helper-scripts) |
| `dotfiles/.config/themes/<id>/palette.lua`, `hyprlock.conf` | each theme's colors for the borders, the shadow and the lock screen |
| `modules/desktop.nix`, `modules/laptop.nix`, `modules/core.nix` | the links, `hyprland-session.target` and `facts.lua` |
| `system/limits-hyprland.conf` | Hyprland's realtime priority |

The keys also run scripts that other modules own.
`power-menu.sh` belongs to [rofi](../rofi/README.md), `waybar-toggle.sh` to [waybar](../waybar/README.md), and `wallpaper-menu.sh` to the [quote wallpaper](../../../docs/design/themes/wallpaper.md).
`dram-theme` and `nightlight.sh` belong to the [theme switcher](../../../docs/design/themes/switcher.md), `gamemode.sh` to the gaming profile, and `record-toggle.sh` and `rec` to the creator profile.

## License

MIT, Patrick Jordan.
`hyprland.lua` began as Hyprland's example Lua configuration, and its section banners, the comments that point at the wiki, the default curves and the example rules are still in it.
Those parts are BSD-3-Clause, the Hyprland authors.

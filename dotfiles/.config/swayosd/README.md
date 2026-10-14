# swayosd

[Design](../../../docs/design/README.md) › [Shell & bars](../../../docs/design/shell-and-bars/README.md) › OSD

The Letterpress on-screen display for SwayOSD: a flat slip of paper with one hairline and a thin bar in the accent.
It shows the new level when a media key changes the volume, the microphone's mute or the screen's brightness.

| | |
|---|---|
| Needs | SwayOSD 0.3.2, tested 2026-10; a PulseAudio server; Monaspace Xenon; a palette file |
| Copy alone | yes, after giving `style.css` a palette |
| License | MIT |

## What it needs

- SwayOSD 0.3.2 from Arch's `extra` repo, tested 2026-10.
  `swayosd-server` draws the slip with GTK 4 on the layer shell, and `swayosd-client` tells it what changed.
- A PulseAudio server for the volume keys: pipewire-pulse 1.6.9 here.
- A backlight under `/sys/class/backlight` for the brightness keys, which a laptop's panel has.
- Monaspace Xenon for the label ([Typography](../../../docs/design/typography/README.md)).
- A palette at `~/.config/themes/current/swayosd.css` that defines the GTK colors `osd-bg`, `osd-fg` and `osd-progress`.
  Each theme's file also defines `osd-border` and `osd-trough`, which `style.css` does not use: it draws the border and the trough from `osd-fg`, at 18 % and 14 %.
- Optionally `wpctl` and `brightnessctl`, which the binds here call, with no slip, when `swayosd-client` is missing.
- Not needed: Nix, Home Manager or `dram`.

## Copy it alone

1. Copy `style.css` to `~/.config/swayosd/`.
2. Give it a palette.
   Copy one theme's `swayosd.css` to `~/.config/themes/current/`, or point the `@import` at the top of `style.css` at your own file with the three colors above.
   The import is relative, so it resolves against `~/.config/swayosd/`.
3. Start `swayosd-server` at login.
4. Bind the media keys to `swayosd-client` with the arguments in the table under [How it is wired here](#how-it-is-wired-here).
5. Press a volume key.
   A slip shows the level on the theme's paper, framed by a hairline, with a thin bar in the accent.

## How it is wired here

`modules/desktop.nix` links `dotfiles/.config/swayosd` whole to `~/.config/swayosd` on hosts with the desktop role, and `packages/roles/desktop.txt` installs swayosd.
`hyprland.lua` starts `swayosd-server` at login when it is installed, and binds six keys to `swayosd-client` ([Keybinds](../../../docs/design/shell-and-bars/keybinds.md)):

| Key | `swayosd-client` | Without it |
|---|---|---|
| `XF86AudioRaiseVolume` | `--output-volume raise --max-volume 100` | `wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+` |
| `XF86AudioLowerVolume` | `--output-volume lower` | `wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-` |
| `XF86AudioMute` | `--output-volume mute-toggle` | `wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle` |
| `XF86AudioMicMute` | `--input-volume mute-toggle` | `wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle` |
| `XF86MonBrightnessUp` | `--brightness raise` | `brightnessctl -e4 -n2 set 5%+` |
| `XF86MonBrightnessDown` | `--brightness lower` | `brightnessctl -e4 -n2 set 5%-` |

The binds work on the lock screen and repeat while a key is held.
Without `swayosd-client` each one runs the command in the last column, which changes the level and shows no slip.
The volume stops at 100 % either way.
Waybar's volume and brightness modules change the levels without SwayOSD, so a click or a scroll on the bar shows no slip.

`dram theme` restarts a running `swayosd-server` after each switch, so the slip takes the new palette.
The new server starts detached and without the switch's lock: on cabin on 2026-10-11, a server that held the lock made each later switch wait 30 s and give up.

`bin/check.sh` §14 runs `bin/check-themes.py`, which holds each theme's `swayosd.css` to the same five names and checks that `osd-progress` is the theme's accent.
The only exception is solarized-paper: its bar is `#826200`, its darker yellow, in place of the accent `#b58900`, so the bar reads on the light paper.
The same section fails on a hardcoded home directory under `dotfiles/.config`, which is why the `@import` is relative.

## The slip

| Node | Look |
|---|---|
| `window` | `osd-bg` at 97 %, a 1 px hairline of `osd-fg` at 18 %, a 3 px radius |
| `label` | Monaspace Xenon 12 px in `osd-fg` |
| `progressbar` | flat, at least 2 px tall, no radius |
| `progress` | `osd-progress`, the theme's accent |
| `trough` | `osd-fg` at 14 % |
| `image` | SwayOSD's own symbolic icon, in `osd-fg` |

## Files

| File | What it does |
|---|---|
| `style.css` | the palette import and the rules in the table above |
| `dotfiles/.config/themes/<theme>/swayosd.css` | the five colors of each theme |
| `dotfiles/.config/hypr/hyprland.lua` | starts the server and binds the six keys |

## License

MIT, Patrick Jordan.

# Keybinds

[Design](../README.md) › [Shell & bars](README.md) › Keybinds

`SUPER` is the mod key.
This table is generated from the `-- comment` on each `hl.bind(...)` line in `dotfiles/.config/hypr/hyprland.lua` by `keybind-cheatsheet.sh --markdown`, the same parser behind the live `SUPER+/` cheatsheet.
Do not edit it by hand: regenerate it after changing a bind.

```sh
KEYBIND_CONF=dotfiles/.config/hypr/hyprland.lua dotfiles/.local/bin/keybind-cheatsheet.sh --markdown > docs/design/shell-and-bars/keybinds.md
```

Each bind also carries a `description` flag, so `hyprctl binds` lists the same text live.
Scripts in the Runs column live in `dotfiles/.local/bin/`, which `modules/desktop.nix` links to `~/.local/bin`.
Dispatchers are `hl.dsp.*` from the [Hyprland Lua API](https://wiki.hypr.land/Configuring/).
The session itself is described in [the Hyprland README](../../../dotfiles/.config/hypr/README.md).

## Quick answers

| Topic | Answer |
|---|---|
| Fullscreen | `SUPER+F` toggles it. A window rule forces games matching `cs2\|steam_app_*` fullscreen, and `SUPER+F` still leaves it. |
| Layouts | dwindle is the default. `SUPER+ALT+L` swaps in the scrolling layout, windows on a horizontal tape, until the next config reload. There `SUPER+CTRL+←/→` scroll by a column, `+SHIFT` swaps columns, `SUPER+CTRL+F` fits and `SUPER+CTRL+P` gives a window its own column. On dwindle the same `SUPER+CTRL+←/→` keys resize. |
| Overview | `` SUPER+` `` needs the hyprtasking plugin: the `hyprland-plugin-hyprtasking` package from the `[dram]` repo I build, loaded by `hl.plugin.load` in `hyprland.lua`. `dram update` keeps it in step with Hyprland. |
| Keyboard EN/RU | Left `Alt`+left `Shift` in either order, `SUPER+ALT+SPACE`, or a click on the EN/RU word on the bar. Right Alt and Shift do nothing. `kb-layout.sh` switches each keyboard at once, and shortcuts keep working under RU. |
| Lock | `SUPER+L`; the layout toggle is `SUPER+ALT+L`. The power menu on `SUPER+X` can lock too. |
| Bar hidden | `SUPER+SHIFT+B` toggles waybar by hand and pauses the fullscreen auto-hide until it is pressed again. |

## Binds

| Key | Action | Runs |
|---|---|---|
| `SUPER + Q` | terminal | `exec_cmd(terminal)` |
| `SUPER + C` | close window | `window.close()` |
| `SUPER + M` | power menu (alias for SUPER+X) | `power-menu.sh` |
| `SUPER + E` | file manager | `exec_cmd(fileManager)` |
| `SUPER + V` | toggle floating | `window.float({ action = "toggle" })` |
| `SUPER + R` | app launcher | `exec_cmd(menu)` |
| `SUPER + SPACE` | launcher (alias for SUPER+R) | `exec_cmd(menu)` |
| `SUPER + ALT + SPACE` | keyboard layout en/ru | `kb-layout.sh toggle` |
| `ALT + SHIFT_L` | keyboard layout en/ru (Alt+Shift) | `kb-layout.sh toggle` |
| `SHIFT + ALT_L` | keyboard layout en/ru (Shift+Alt) | `kb-layout.sh toggle` |
| `SUPER + G` | GNOME-style app grid (browse all apps) | `exec_cmd(appgrid)` |
| `SUPER + B` | open browser | `exec_cmd(browser)` |
| `SUPER + X` | power menu | `power-menu.sh` |
| `SUPER + A` | audio visualizer (needs cava) | `kitty --class cava-visualizer -e cava` |
| `SUPER + L` | lock the screen | `pidof hyprlock \|\| hyprlock` |
| `SUPER + F` | fullscreen toggle (press again to leave) | `window.fullscreen()` |
| `SUPER + SHIFT + V` | clipboard history (ESC = no-op, clipboard untouched) | `sel="$(cliphist list \| rofi -dmenu -i -p clipboard)" && [ -n "$sel" ] && printf '%s\\n' "$sel" \| cliphist decode \| wl-copy` |
| `SUPER + slash` | searchable keybind cheatsheet | `keybind-cheatsheet.sh` |
| `SUPER + T` | theme switcher menu | `dram-theme` |
| `SUPER + SHIFT + G` | game mode: eye candy off/on | `gamemode.sh` |
| `SUPER + CTRL + G` | log out and straight into Gaming Mode (gaming hosts) | `steamos-session-select gaming` |
| `SUPER + CTRL + R` | start/stop OBS on the recorder + the local spare (creator hosts) | `rec toggle 2>&1 \| head -2 \| xargs -0 notify-send -a rec Recording` |
| `SUPER + CTRL + equal` | zoom in around the cursor (creator hosts) | `function() set_zoom(zoom + 0.5) end` |
| `SUPER + CTRL + minus` | zoom out | `function() set_zoom(zoom - 0.5) end` |
| `SUPER + CTRL + 0` | zoom off | `function() set_zoom(1.0) end` |
| `SUPER + SHIFT + X` | OCR region -> clipboard | `ocr-copy.sh` |
| `SUPER + SHIFT + C` | color picker -> clipboard | `hyprpicker -a` |
| `SUPER + P` | pseudo-tile window | `window.pseudo()` |
| `SUPER + SHIFT + P` | pin window: a floating window follows you to every workspace | `window.pin()` |
| `SUPER + ALT + C` | center the window on its monitor (floating) | `window.center()` |
| `SUPER + Tab` | window switcher (rofi, every workspace) | `rofi -show window -modes window` |
| `SUPER + SHIFT + Tab` | back to the previously focused window | `focus({ last = true })` |
| `SUPER + N` | notification center toggle | `swaync-client -t -sw` |
| `SUPER + SHIFT + N` | do-not-disturb toggle | `swaync-client -d -sw` |
| `SUPER + SHIFT + B` | hide/show waybar (manual; overrides the fullscreen auto-hide until pressed again) | `waybar-toggle.sh` |
| `SUPER + ALT + N` | blue-light filter toggle (4000K; IPC into a scheduled hyprsunset if one runs) | `nightlight.sh` |
| `SUPER + period` | emoji picker -> clipboard | `rofimoji --action copy --skin-tone neutral --prompt emoji` |
| `SUPER + equal` | calculator (rofi-calc on qalc): Enter copies the result | `rofi -show calc -modi calc -no-show-match -no-sort -calc-command "echo -n '{result}' \| wl-copy"` |
| `SUPER + SHIFT + W` | wallpaper picker (~/pictures/wallpapers, fades in on the focused monitor) | `wallpaper-menu.sh` |
| `Print` | region screenshot -> annotate (satty) | `screenshot.sh region` |
| `SUPER + Print` | all monitors -> file + clipboard | `screenshot.sh all` |
| `SUPER + SHIFT + Print` | active window -> annotate (satty) | `screenshot.sh window` |
| `SUPER + CTRL + Print` | focused monitor -> file + clipboard | `screenshot.sh output` |
| `SUPER + SHIFT + R` | start/stop recording the focused monitor -> ~/videos/recordings/rec-<stamp>.mp4 | `record-toggle.sh` |
| `SUPER + ALT + R` | instant-replay buffer on/off (needs gsr-ui running) | `gsr-ui-cli toggle-replay \|\| notify-send -a record 'Replay needs gsr-ui' 'Start GPU Screen Recorder (gsr-ui) first'` |
| `SUPER + ALT + L` | toggle layout dwindle <-> scrolling | `layout-toggle.sh` |
| `SUPER + J` | toggle split direction (dwindle) | `layout("togglesplit")` |
| `SUPER + CTRL + F` | scrolling: expand the column into the free space | `layout("fit expand")` |
| `SUPER + CTRL + P` | scrolling: promote the window to its own column | `layout("promote")` |
| `SUPER + CTRL + SHIFT + left` | scrolling: swap column with the one on the left | `layout("swapcol l")` |
| `SUPER + CTRL + SHIFT + right` | scrolling: swap column with the one on the right | `layout("swapcol r")` |
| `SUPER + left` | focus left | `focus({ direction = "left" })` |
| `SUPER + right` | focus right | `focus({ direction = "right" })` |
| `SUPER + up` | focus up | `focus({ direction = "up" })` |
| `SUPER + down` | focus down | `focus({ direction = "down" })` |
| `SUPER + SHIFT + left` | move window left | `window.move({ direction = "left" })` |
| `SUPER + SHIFT + right` | move window right | `window.move({ direction = "right" })` |
| `SUPER + SHIFT + up` | move window up | `window.move({ direction = "up" })` |
| `SUPER + SHIFT + down` | move window down | `window.move({ direction = "down" })` |
| `SUPER + CTRL + left` | resize narrower (scrolling: scroll one column left) | `whenScrolling(layout("move -col"), window.resize({ x = -40, y = 0, relative = true }))` |
| `SUPER + CTRL + right` | resize wider (scrolling: scroll one column right) | `whenScrolling(layout("move +col"), window.resize({ x = 40,  y = 0, relative = true }))` |
| `SUPER + CTRL + up` | resize shorter | `window.resize({ x = 0,   y = -40, relative = true })` |
| `SUPER + CTRL + down` | resize taller | `window.resize({ x = 0,   y = 40,  relative = true })` |
| `SUPER + bracketleft` | previous workspace | `focus({ workspace = "e-1" })` |
| `SUPER + bracketright` | next workspace | `focus({ workspace = "e+1" })` |
| `SUPER + SHIFT + bracketleft` | move window to the previous workspace (and follow) | `window.move({ workspace = "e-1", follow = true })` |
| `SUPER + SHIFT + bracketright` | move window to the next workspace (and follow) | `window.move({ workspace = "e+1", follow = true })` |
| `SUPER + grave` | workspace overview on this monitor (hyprtasking; press again or right-click a workspace to leave) | `overviewToggle` |
| `SUPER + S` | scratchpad workspace | `workspace.toggle_special("magic")` |
| `SUPER + SHIFT + S` | move window to scratchpad | `window.move({ workspace = "special:magic" })` |
| `SUPER + mouse_down` | next workspace | `focus({ workspace = "e+1" })` |
| `SUPER + mouse_up` | previous workspace | `focus({ workspace = "e-1" })` |
| `SUPER + mouse:272` | drag window | `window.drag()` |
| `SUPER + mouse:273` | resize window | `window.resize()` |
| `XF86AudioRaiseVolume` | volume up (OSD) | `command -v swayosd-client >/dev/null 2>&1 && swayosd-client --output-volume raise --max-volume 100 \|\| wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+` |
| `XF86AudioLowerVolume` | volume down (OSD) | `command -v swayosd-client >/dev/null 2>&1 && swayosd-client --output-volume lower \|\| wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-` |
| `XF86AudioMute` | mute toggle | `command -v swayosd-client >/dev/null 2>&1 && swayosd-client --output-volume mute-toggle \|\| wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle` |
| `XF86AudioMicMute` | mic mute toggle | `command -v swayosd-client >/dev/null 2>&1 && swayosd-client --input-volume mute-toggle \|\| wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle` |
| `XF86MonBrightnessUp` | brightness up (OSD) | `command -v swayosd-client >/dev/null 2>&1 && swayosd-client --brightness raise \|\| brightnessctl -e4 -n2 set 5%+` |
| `XF86MonBrightnessDown` | brightness down (OSD) | `command -v swayosd-client >/dev/null 2>&1 && swayosd-client --brightness lower \|\| brightnessctl -e4 -n2 set 5%-` |
| `XF86AudioNext` | media: next track | `playerctl next` |
| `XF86AudioPause` | media: play/pause | `playerctl play-pause` |
| `XF86AudioPlay` | media: play/pause | `playerctl play-pause` |
| `XF86AudioPrev` | media: previous track | `playerctl previous` |
| `SUPER + 1-9,0` | switch to workspace 1-10 | `focus({ workspace = i })` |
| `SUPER + SHIFT + 1-9,0` | move window to workspace 1-10 | `window.move({ workspace = i })` |
| `SUPER + drag LMB/RMB` | move / resize window | `window.drag() / window.resize()` |
| `SUPER + scroll` | cycle workspaces | `focus({ workspace = "e±1" })` |

# Zebar masthead

[Design](../README.md) › [Shell & bars](README.md) › Zebar masthead

On Windows the Waybar masthead runs as a Zebar widget: one bar across the top of each monitor, over an auto-hidden taskbar.
`bin/gen-windows-look.py` writes it from washi's palette and from Waybar's own configuration.
A Waybar module with no counterpart stops the generator, and `bin/check.sh` §19 fails while the committed pack differs from what the generator writes.

| | |
|---|---|
| Code | `install/windows/letterpress/zebar/` (generated), `bin/gen-windows-look.py`, `install/windows/dram-windows/look.ps1`, `install/windows/dram-windows/apply-live.ps1` |
| Runs on | cabin-win, with the desktop role |
| Needs | Zebar 3.3.1, pinned in `windows/packages.nix`; WebView2; Literata and EB Garamond; tested on Windows 11 26H2 in 2026-10 |
| Decided in | the bar and the hidden taskbar ([decided 2026-10-12](../../../decisions/log.md#d130)), GlazeWM held ([2026-10-12](../../../decisions/log.md#d131)), Windhawk kept out ([2026-10-12](../../../decisions/log.md#d133)) |

## How it works

Zebar is glzr.io's widget host, licensed GPL-3.0.
It draws each widget in a WebView2 page that its own asset server serves from `%USERPROFILE%\.glzr\zebar\<pack>\`.
Nothing is injected into Explorer or any other process.

The bar is real HTML and CSS, so it sets Waybar's type exactly: Literata's small caps and tabular figures for the captions, and EB Garamond in the roles Fraunces has on Arch.
`install/windows/fonts.pin` carries no Fraunces, so Windows has none.
Each bar reserves the top edge of its monitor, and maximized windows stop under it.
`apply-live.ps1` auto-hides the taskbar at the bottom, the only edge Windows 11 26H2 auto-hides.

| Side | What it shows |
|---|---|
| Left | the seal, "pj" in EB Garamond italic inside a vermilion ring, then the PC's name |
| Center | the clock and the Russian date, with the full date as its tooltip |
| Right | now playing, `en` or `ru`, `цп` and `озу`, `сеть`, `звук`, the battery where there is one, and the tray |

A module that does something when clicked shows the accent rule under it on hover.
Now playing toggles play and pause on a click, skips back on a middle click and forward on a right click.
The wheel over `звук` steps the volume by 5 %, and a right click mutes it, as Waybar's `pulseaudio` module does.
The tray's icons stay gray until the pointer is over one, and clicks go to the icon's own program.

### Waybar's modules on Windows

The generator reads the `external` bar of `dotfiles/.config/waybar/config.jsonc` for the layout and the 44 px height.
From `modules.jsonc` it takes the caption words, the intervals of `cpu` and `memory`, the clock's locale, the media title's length and the battery's thresholds.
Each module maps through `WAYBAR_TO_MASTHEAD` in the generator:

| Waybar module | On Windows |
|---|---|
| `custom/nameplate` | the seal and the PC's name |
| `clock`, `custom/date` | the clock and the date |
| `mpris` | now playing, cut at 36 characters |
| `hyprland/language` | the keyboard layout as `en` or `ru` |
| `cpu`, `memory` | `цп` and `озу`, with the used and total memory as a tooltip |
| `network` | `сеть` with the Wi-Fi signal, or `нет сети` |
| `pulseaudio` | `звук`, or `тихо` when muted |
| `battery` | `бат`, with `↑` while charging and colored at 30 % and 15 % |
| `hyprland/workspaces` | nothing yet: the numeral waits for GlazeWM |
| `hyprland/window` | nothing: there is no window title without a window manager |
| `custom/cputemp` | nothing: no sensor provider, and the case panel shows the temperature |
| `custom/notification`, `privacy` | nothing: Zebar has no provider for them |
| `bluetooth`, `idle_inhibitor`, `power-profiles-daemon`, `custom/usb`, `custom/updates` | nothing |

The tray comes from Zebar's own `systray` provider and sits after the last module.

### What the page may reach

`masthead.html` carries a Content-Security-Policy that admits the pack's own files and Zebar's IPC (`connect-src 'self' ipc: http://ipc.localhost`).
The generator refuses to write a file of the pack that names any other URL.
`zpack.json` grants no shell commands, so the page runs no program, and it caches nothing.
Zebar's starter pack loads its scripts from the web.
`look.ps1` writes this pack and `settings.json` before Zebar's first start, so the starter pack is never copied in.

## Use it

After changing washi's palette or Waybar's configuration, write the pack again and check it:

```sh
python3 bin/gen-windows-look.py           # rewrites install/windows/letterpress/, the pack included
python3 bin/gen-windows-look.py --check   # what bin/check.sh §19 runs; fails while the pack is stale
```

The pack is a Windows render input, so `bin/render-windows.sh` follows before a push to the PC.
On the PC, `look.ps1` replaces `%USERPROFILE%\.glzr\zebar\letterpress\` whole and puts `settings.json` back when Zebar's tray menu changed it.
`apply-live.ps1` then starts Zebar on the signed-in desktop, or restarts it when the pack on disk is newer than the running bar.
Before a restart it closes each widget window, so the edge that window reserved is handed back.
At sign-in the Run entry from the unit `zebar-autostart` starts it.
When Zebar does not start, `%USERPROFILE%\.glzr\zebar\errors.log` says why.

## Copy it alone

1. Install Zebar 3.3.1: `winget install --id glzr-io.zebar --version 3.3.1`.
   `masthead.js` speaks 3.3.1's IPC, and a later Zebar may change it.
2. Install Literata and EB Garamond for your account or the machine ([Typography](../typography/README.md) lists the files).
3. Before Zebar's first start, copy `install/windows/letterpress/zebar/letterpress\` to `%USERPROFILE%\.glzr\zebar\letterpress\`, and `settings.json` beside it to `%USERPROFILE%\.glzr\zebar\settings.json`.
   If Zebar has run before, replace its `settings.json` with this one.
4. Set your colors in the `:root` block at the top of `masthead.css`.
   Set the caption words and the date's locale in `CONFIG` at the top of `masthead.js`: `en-US` and English words give an English bar.
5. Turn on the taskbar's auto-hide in Settings › Personalization › Taskbar › Taskbar behaviors.
6. Start Zebar.
   A 44 px bar opens across the top of each monitor, with the clock in the middle and the readouts on the right.
   Opened in a browser instead of Zebar, the page shows the clock alone: the readouts need Zebar's IPC.

## Limits

- No workspace numeral: GlazeWM is held because its IPC accepts any WebSocket ([glzr-io/glazewm#1443](https://github.com/glzr-io/glazewm/issues/1443)).
  Its builder would ask GlazeWM on `127.0.0.1:6123`, and that origin would join the page's CSP.
- No window title, no temperature and no notification mark (¶).
- The bar sits in the normal z-order, and Zebar has no fullscreen handling, so a fullscreen game covers it.
- The tray watches `Shell_NotifyIcon` through a second window of the taskbar's class.
  Nothing is injected, but test it beside anti-cheat software like any new process.
- Nothing restyles the taskbar or Start themselves.
  Windhawk would, and it injects into every process, so it is a `fail` in `packages/register.tsv`.
  Start and Explorer are quieted by policy instead ([Windows look](../themes/windows.md)).

## License

The pack is my own code, generated, and MIT, Patrick Jordan, except `masthead.js`.
Its three IPC calls (`plugin:event|listen`, `listen_provider` and `call_provider_function`) follow the client in npm `zebar@3.3.1`, and Zebar is GPL-3.0, so `masthead.js` is GPL-3.0, and so is `bin/gen-windows-look.py`, which writes it, beside its MIT (`REUSE.toml`).

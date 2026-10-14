# 0025: One look on every OS, Windows themed from Arch's palettes

[Design › Themes](../docs/design/themes/README.md) · accepted 2026-10-12

Windows takes the Letterpress look from the palette files Arch already uses, through a generator whose output is committed; the cost is a generator to keep in step with every app it themes.

## Context

cabin dual-boots Windows, and thermos runs it.
I want the riced look to follow me there: the same palettes, fonts, pointer, prompt and terminal on both OSes.
Windows has no theme engine for third-party apps; each app keeps its own settings, some rewrite them on exit, and patching system files breaks on updates and sits badly beside anti-cheat drivers.

## Decision

- One generator and one script ([D84](log.md#d84)).
  `bin/gen-windows-look.py` reads Arch's theme files (washi by default) and writes `install/windows/letterpress/`, committed; `install/windows/dram-windows/look.ps1` puts the per-user files in place after `winget configure`, one line per app.
- The house fonts machine-wide from `install/windows/fonts.pin`, each file pinned by sha256 in `install/windows/fonts.lock` ([D85](log.md#d85)).
- The terminal and the prompt as on Arch: Windows Terminal with the 17 themes as schemes, starship from a byte-identical `starship.toml`, opacity 100 and no grain until tested ([D86](log.md#d86)).
- Every app that can take the look by its own files does; no taskbar or Start patchers ([D87](log.md#d87)).
- No system sounds, a clear sign-in background and a 2 px caret ([D88](log.md#d88)); the pointer is Adwaita on Arch and Windows alike, GNOME's own Windows build pinned by sha256 in `install/windows/cursors.pin` ([D132](log.md#d132), which replaced the Windows Black pointer of D88).
- The Russian layout for my account, not the sign-in screen, where a stray Alt+Shift would mangle a typed password ([D89](log.md#d89)).
- The "pj" seal as the account picture and `~/.face`: `bin/gen-avatar.sh` renders it, `account-picture.ps1` sets it ([D91](log.md#d91)).
- The bars: a Zebar top bar on each monitor, generated from washi and Waybar's layout, with Windows' taskbar auto-hidden and Start and Explorer decluttered by policy ([D130](log.md#d130)).
- Tiling with GlazeWM is held: its IPC on 127.0.0.1:6123 accepts any WebSocket and runs `shell-exec`, so a web page could start programs; it is checked again once glzr-io/glazewm#1443 ships ([D131](log.md#d131)).
- Icons: never a system file (`SfcIsFileProtected` before every write), system icons by registry overrides only, and each app shortcut re-rendered from its own glyph in the accent on a dark tile (`install/windows/dram-windows/icons.ps1`, [D135](log.md#d135)).
- Each display at its highest refresh rate at its resolution, as Arch's `hyprland.lua` declares, with G-SYNC Compatible ticked once by hand (`apply-live.ps1`, [D137](log.md#d137)).

## Alternatives

| Option | Why not |
|---|---|
| Taskbar and Start patchers (StartAllBack, ExplorerPatcher, Windhawk) | they patch Explorer or inject into every process beside the anti-cheat drivers; StartAllBack also fails the FOSS and Origin rules |
| Theme files written by hand per app | they drift from Arch's palettes at the first palette change |
| komorebi, FancyWM, Seelen UI for tiling | the first two fail the FOSS rule, and Seelen UI injects into Explorer |
| Spicetify and Millennium for Spotify and Steam | they break the apps' terms or their security |

## Consequences

- A palette change on Arch means a regenerate, a commit and a new render of the Windows build; `bin/check.sh` §19 fails until both are done.
- Apps that rewrite their settings on exit are themed only while closed: `look.ps1` defers them to the next converge.
- Store apps cannot be re-iconed in Start, large folders stay yellow, and title bars, Alt-Tab and the tray have no supported lever.
- Old Win32 dialogs stay light: SecureUxTheme fails under Memory Integrity.

## How it is checked

`bin/check.sh` §19 runs `bin/gen-windows-look.py --check`, which fails when `install/windows/letterpress/` differs from what the palettes give, and holds every Windows source to ASCII.
On the PC, `dram doctor` runs `look.ps1` and `icons.ps1` with `-DryRun` and warns on any change waiting, and its masthead section checks Zebar.
The fonts and cursors are sha256-pinned, checked on the Mac or Arch and again on the PC.

## History

- 2026-10-12: accepted ([D84](log.md#d84) to [D89](log.md#d89), [D91](log.md#d91)) and built.
- 2026-10-12: the bars, the pointer, the icons and the displays settled the same evening ([D130](log.md#d130), [D132](log.md#d132), [D135](log.md#d135), [D137](log.md#d137)); GlazeWM held ([D131](log.md#d131)).

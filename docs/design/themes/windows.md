# Windows look

[Design](../README.md) › [Themes](README.md) › Windows look

Windows takes the Letterpress look from the palette files Arch uses, wherever an app lets it.
`bin/gen-windows-look.py` writes `install/windows/letterpress/` from washi's files on the Mac.
On the PC, the desktop role's units set what lives in the registry, and `look.ps1` writes what lives in each app's own files.

| | |
|---|---|
| Code | `bin/gen-windows-look.py`, `install/windows/letterpress/` (generated), `install/windows/dram-windows/look.ps1`, `windows/roles/desktop.nix`, `windows/units/letterpress-look.ps1`, `windows/units/letterpress-wallpaper.ps1`, `windows/units/letterpress-lock-screen.ps1`, `windows/units/conhost-letterpress.ps1` |
| Runs on | cabin-win, with the desktop role |
| Needs | Windows 11 26H2 and Windows PowerShell 5.1, tested 2026-10; the apps in the lists of `packages/winget/`; Python 3 on the Mac for the generator |
| Decided in | the look from Arch's palettes ([decided 2026-10-12](../../../decisions/log.md#d84)); each app that can take it, with no taskbar or Start patcher ([2026-10-12](../../../decisions/log.md#d87)); Windhawk kept out ([2026-10-12](../../../decisions/log.md#d133)); Windows from the flake ([decision 0020](../../../decisions/0020-windows-from-the-flake.md)) |

## How it works

Five parts of the look have pages of their own.
[Iconography](../iconography/README.md#the-pointer) has the pointer, [Zebar masthead](../shell-and-bars/zebar.md) the bar, [Terminal](../shell-and-bars/terminal.md#windows) Windows Terminal, [Prompt](../shell-and-bars/prompt.md#on-windows) the prompt and PSReadLine, and [Typography](../typography/README.md) the fonts and the keyboards.

### The generator

`bin/gen-windows-look.py` renders one theme: the id in `install/windows/letterpress/theme`, washi, the house theme.
It reads that theme's `kitty.conf`, `waybar.css`, `palette.lua` and `meta.sh`.
It also reads each theme's terminal colors, the syntax inks of `bin/gen-vscode-themes.py` and the extension that script writes, three upstream theme files, and Waybar's `config.jsonc` and `modules.jsonc` for the masthead.

| Output | For |
|---|---|
| `wt-schemes.json` | Windows Terminal: the 17 themes as color schemes, named after their ids in title case, such as Washi Day |
| `wt-settings.json` | the Windows Terminal keys `look.ps1` owns: the scheme, Monaspace Xenon with the symbols font, the bar cursor, padding 10, 20 000 lines of scrollback, the bell as a window and taskbar alert, a dark window without Mica |
| `psreadline.ps1` | PSReadLine and `$PSStyle` in the theme's inks, for PowerShell 5.1 and 7 |
| `conhost.json` | the classic console's 16 colors |
| `accent.json` | dark or light, the accent, and Windows' eight-step `AccentPalette`, from light to dark |
| `pj.letterpress-themes-<version>.vsix`, `vscodium-settings.json` | VSCodium: the editor extension, packed, and the keys that pick its theme and fonts |
| `vesktop/`, `obs/`, `notepad++/`, `mumble/`, `halloy/`, `calibre/`, `vortex/`, `teamspeak/`, `nomacs/`, `wireshark/`, `powertoys.json`, `cmdpal.json`, `windirstat.json`, `runelite.json` | a theme, or the keys that set one, for each app in the table below |
| `qbittorrent/`, `mintty/` | apps that no list installs |
| `wsl/terminal-profile.json` | a Windows Terminal profile for the WSL clone |
| `zebar/` | the [Zebar masthead](../shell-and-bars/zebar.md) |
| `theme` | the id the directory was made from |

The output is deterministic, with no dates, fixed timestamps inside the VSIX and a version bumped by hand, so `--check` can compare it with the committed files.
`bin/check.sh` §19 runs `--check` and fails while they differ.
Each text file is ASCII, or the run fails: Windows PowerShell 5.1 reads a file without a byte-order mark in the ANSI code page.
Each ink that the TeamSpeak, nomacs and Wireshark files set on a paper reads at 4.5:1 or better.
The generator first moves a weak ink toward the body ink, or a paper toward the page, and fails the run if a pair still does not read.

Notepad++'s theme is its own `DarkModeDefault.xml` at v8.9.8.1, Mumble's is its `Dark.qss` at v1.5.939, and Wireshark's coloring rules are its own `colorfilters` at v4.6.9.
The generator recolors each by name and stops on a style, a color or a rule it does not map, so an upstream bump gets read before it ships ([upstream](../../../install/windows/upstream/README.md)).

### On the PC

`install/windows/letterpress/` is a Windows render input, so `bin/render-windows.sh` renders cabin-win's build again after it changes.
`bin/push-windows.sh` stages the release in `C:\ProgramData\dram`, with the directory as `letterpress\`.
The desktop role also reads the recorded id, to stage that theme's `browser.css` for LibreWolf and Thunderbird.
`dram apply` on the PC then converges in this order:

1. The desktop role's units run through `winget configure`, in phase 10 for machine values and phase 20 for the user's.
2. `look.ps1` runs after phase 30.
3. `apply-live.ps1` runs on the signed-in desktop, so dark mode, the accent, the pointer, the fonts, the taskbar's auto-hide and the masthead change without a sign-out.

### The desktop

The units in `windows/roles/desktop.nix` set the shell:

| Unit | Sets |
|---|---|
| `letterpress-look` | dark apps and system, the accent and its eight-step palette from `accent.json`, no transparency, and the accent on title bars and window borders, with the taskbar and Start left plain |
| `letterpress-look` | the taskbar on the left without the Task View and Copilot buttons, and Start without suggestions, recent files or account notices |
| `letterpress-look` | file extensions shown, Explorer opening on This PC, and no mouse acceleration, for games |
| `letterpress-wallpaper` | the Letterpress art of the rEFInd theme, `system/refind-letterpress/background.png`, as the wallpaper, set to fill |
| `letterpress-lock-screen` | the same art on the lock screen, through the elevated converge |
| `conhost-letterpress` | the classic console's 16 colors and its default pair, from `conhost.json`, for a console outside Windows Terminal |
| `signin-clear`, `startup-sound-off`, `sounds-off` | a sign-in screen without the acrylic blur, no startup sound, and the No Sounds scheme ([decided 2026-10-12](../../../decisions/log.md#d88)) |
| `cursors-machine`, `pointer-adwaita` | Arch's Adwaita pointer ([Iconography](../iconography/README.md#the-pointer)) |
| `taskbar-taskview-policy` and the four `start-` policies | no Task View button, and Start without the Recommended section, website suggestions, the Most used list or the list of new apps |
| `no-widgets`, `lock-widgets-off` | no widgets board, and no widgets on the lock screen |
| `explorer-quiet` | Explorer compact, its pane open to the current folder, without the Gallery or sync-provider ads, and End task on the taskbar's menu for a hung game |

### Inside the apps

`look.ps1` keeps to these rules:

- A file that is the look's alone, such as a theme or a stylesheet, is rewritten whenever it differs.
- Keys inside a file the app owns, or under its registry key, are merged only while the app is closed, because the app writes its settings back when it exits.
  PowerToys waits for its Settings window instead.
  Otherwise the line reads `[deferred]`, and the next converge tries again.
- An app whose settings do not exist yet is skipped until it has run once.
- The first time it changes a file of an app's, it keeps the original as `<file>.before-dram`, and replaced registry values go to `<app>.before-dram.json` beside the script.
- It writes UTF-8 without a byte-order mark, because Vesktop's `JSON.parse` rejects one, and an INI or XML file keeps the mark it had.

It prints one line per app:

| Line | Means |
|---|---|
| `[ok] <app>` | as declared, nothing written |
| `[themed] <app>: <what>` | written |
| `[would] <app>: <what>` | what `-DryRun` would write |
| `[deferred] <app>: <why>` | the app is running, and its keys wait |
| `[skip] <app>: <why>` | not installed, or not started once yet |
| `[follows] <app>: <how>` | the app follows Windows' dark mode or accent by itself |
| `[cannot] <app>: <why>` | the app has no hook for a theme |
| `[!] <app>: <error>` | the step failed, and the run exits 1 |

The last line counts them: `== look: <n> themed, <n> would change, <n> ok, <n> deferred, <n> skipped, <n> failed`.

| App | Result | How |
|---|---|---|
| Windows Terminal, and in it PowerShell 7 and 5.1, cmd and the WSL clone | themed | the schemes as a fragment in `%ProgramData%\Microsoft\Windows Terminal\Fragments\dram\`, and the keys of `wt-settings.json` in each Windows Terminal's `settings.json`; the base role makes Windows Terminal the host of each console app |
| PowerShell | themed | one profile for 5.1 and 7: starship with Arch's `starship.toml`, then `psreadline.ps1`; your own lines go in `profile.local.ps1` beside it |
| the classic console | themed | `HKCU\Console`, from `conhost-letterpress` |
| VSCodium | themed | the VSIX, installed when its version is new, and the keys of `vscodium-settings.json`: the theme, Monaspace Xenon with the symbols font, Literata in the workbench |
| LibreWolf, Thunderbird | themed; web pages stay light under `resistFingerprinting` ([librewolf](../../../dotfiles/.librewolf/README.md#dark-and-light-under-resistfingerprinting)) | Arch's `userChrome.css` sheets and washi's `browser.css` in each profile, `librewolf.overrides.cfg`, and Thunderbird's `user.js` seed |
| Vesktop | themed | a Vencord theme, switched on, and Vesktop's transparency off |
| OBS Studio | themed | a variant of its Yami theme, `Letterpress.ovt`, chosen in `user.ini` |
| Notepad++ | themed | its dark theme recolored, and `config.xml`: dark mode in the theme's colors, the theme's font, and its own updater off, since winget updates it |
| Mumble | themed | its Dark theme recolored, chosen in `mumble_settings.json` |
| Halloy | themed | a theme file and the `theme` key of `config.toml` |
| calibre | themed | a named palette in `gui.json` |
| Vortex | themed once "letterpress" is picked in Settings › Theme | a theme folder |
| PowerToys | themed | each utility's color keys: the accent on zone borders, the 2 px Always On Top frame, the crosshairs, a left click's highlight and Screen Ruler's cross, and paper behind the zones and Find My Mouse |
| Command Palette | themed from its next start; `[deferred]` while it runs, so quit it from the tray once | its list on the theme's paper, as a custom color |
| TeamSpeak 3 | themed once "Letterpress" is picked in Tools › Options › Design | four Qt style sheets in `%APPDATA%\TS3Client\styles` |
| nomacs | themed | `Letterpress-Dark.css` beside nomacs's own themes in Program Files, through the elevated converge, and `settings.ini` |
| WinDirStat | themed; its dark mode follows Windows | registry colors: the file tree's depth bars in the inks, the treemap's selection frame in the accent |
| Wireshark | themed | `preferences` keys, with the packet panes in Monaspace Xenon and the selected row a paper shade, and its stock coloring rules recolored |
| RuneLite | the overlays only: the client's look is fixed | `runelite.overlayBackgroundColor` in each profile |
| Zebar | themed | the [Zebar masthead](../shell-and-bars/zebar.md) pack |
| VLC | its dark palette, whose highlight is the Windows accent | `qt-dark-palette` in `vlcrc` |
| LocalSend | follows the Windows accent | its color setting, `system` |
| Proton Pass, Proton Mail Bridge, Transmission | follow Windows' dark mode | no file to write |
| the work apps: LibreOffice, Zettlr, KiCad, Octave, draw.io, Xournal++, Anki, PDF Arranger, PuTTY, Rufus | not themed on 2026-10-12; an app among them that follows Windows' dark mode does so by itself | nothing yet |
| WireGuard, OpenVPN GUI | cannot: they stay light | no hook for a theme |
| Steam, Spotify, Battle.net, EA app, Epic Games, Ubisoft Connect, Hytale, Jagex Launcher, NVIDIA App | left alone | each has its own dark interface, and skins and patchers stay out |

Two outputs serve apps that no list installs.
qBittorrent gave way to Transmission ([Transmission in its place](../../../decisions/log.md#d104)), and `look.ps1` keeps its qBittorrent step for a host that keeps the app, without running it.
mintty came with Git for Windows, which no list installs ([no Git for Windows](../../../decisions/log.md#d108)), so `look.ps1` reports `[skip] mintty: Git for Windows is not installed`.

## Use it

```sh
python3 bin/gen-windows-look.py            # rewrites install/windows/letterpress/ from washi
python3 bin/gen-windows-look.py --check    # what bin/check.sh §19 runs: a diff and exit 1 while stale
bin/render-windows.sh                      # the directory is a render input
bin/push-windows.sh cabin-win --apply      # stage the release on the PC, then dram apply
```

On the PC, a dry run lists what `look.ps1` would write, one line per app, and changes no file:

```powershell
powershell -ExecutionPolicy Bypass -File C:\ProgramData\dram\look.ps1 -DryRun
```

`look.log` beside the script keeps each line with its time.

## When it breaks

| Symptom | Check | Fix |
|---|---|---|
| §19 of `bin/check.sh` prints `install/windows/letterpress is stale` | `python3 bin/gen-windows-look.py --check` prints the diff | run the generator and `bin/render-windows.sh`, and commit both |
| the generator stops: `install/windows/upstream/<file>: sha256 <hash>, pinned <hash>` | the file differs from its pinned tag | fetch the pinned file again ([upstream](../../../install/windows/upstream/README.md)) |
| the generator stops on a pair that reads under 4.5:1 | the message names the app, the ink and the paper | change washi's palette, or that app's mapping in the generator |
| `[deferred] <app>` | the app is open | close it and run `dram apply` again |
| `[skip] <app>: start it once` | the app has no settings yet | start it once, then converge |
| `[!] nomacs: cannot write <dir>\themes` | the run was not elevated | run it through `dram apply`, which runs elevated |
| VSCodium on Windows keeps the old editor colors | `codium --list-extensions --show-versions` | bump `VERSION` in `bin/gen-vscode-themes.py` and run both generators: `look.ps1` installs the VSIX only when its version is new |

## Limits

- One theme: Windows has no `dram theme`.
  Windows Terminal offers the 17 schemes and VSCodium the 17 editor themes, to pick by hand.
- The taskbar and Start keep Windows' own look.
  Windhawk would restyle them, and it injects into each process, so `packages/register.tsv` lists it as a fail ([decided 2026-10-12](../../../decisions/log.md#d133)).
- The work apps were not themed on 2026-10-12.
- WireGuard and OpenVPN GUI stay light, and the games and their launchers keep their own interfaces.
- LibreWolf shows web pages light under `resistFingerprinting`.
- TeamSpeak 3 keeps its style choice in a SQLite database, so the choice is made by hand once, as it is for Vortex.
- A RuneLite profile synced to a RuneLite account can bring the server's copy back at login.
- `wsl/terminal-profile.json` is staged on the PC, and no script reads it (2026-10-13): the WSL tab takes the scheme from the profile defaults in `wt-settings.json`.
- `look.ps1` has not confirmed on cabin-win which folder holds Command Palette's settings, and uses the first of four that holds the app's own keys (2026-10-13).

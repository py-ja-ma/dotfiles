# Gaming

[Toolchain](../README.md) › [Profiles](README.md) › Gaming

cabin is the gaming host: Steam with CS2, and OSRS through the Jagex Launcher, on Hyprland and an NVIDIA RTX 3080 Ti.
Any host with the gaming role also gets Gaming Mode: SteamOS-style sessions in the ly login menu, and one way to move between them and the desktop.

| | |
|---|---|
| Code | `packages/roles/gaming.txt`, `packages/winget/gaming.txt`, [`pkgs/dram-gaming-mode/`](../../../pkgs/dram-gaming-mode/README.md), `pkgs/gamescope-session/`, `pkgs/gamescope-session-steam/`, `modules/gaming.nix`, `dotfiles/.config/hypr/gaming.lua`, `dotfiles/.config/gamemode.ini`, `system/gaming-setup.sh` |
| Runs on | cabin and lantern; cabin-win for the Windows launchers |
| Needs | Steam, gamescope, ly 1.4.1, polkit, a Vulkan GPU |
| Decided in | [decision 0012](../../../decisions/0012-gaming-mode.md), [D19](../../../decisions/log.md#d19) |

## Packages

`packages/roles/gaming.txt` installs `steam`, `gamemode` and `lib32-gamemode`, `mangohud` and `lib32-mangohud`, `gamescope`, `ntsync-autoload`, Wine with winetricks, Mono and Gecko, and PrismLauncher.
From `[dram]` it adds `gamescope-session`, `gamescope-session-steam`, `dram-gaming-mode`, `xpadneo-dkms`, `game-devices-udev` and `jagex-launcher`; a `[dram]` name in a role list installs with that role only.
`dotfiles/.config/gamemode.ini`, linked by `modules/gpu.nix` on an NVIDIA host, asks tuned-ppd for the performance profile and turns split-lock mitigation off for the game, because Source-engine titles trap on it.
It leaves the screensaver alone: `hyprland.lua` already has a fullscreen `idle_inhibit` rule.

On a laptop, `SUPER+SHIFT+G` (`dotfiles/.local/bin/gamemode.sh`) is a compositor toggle that drops animations, blur and gaps for the Iris Xe.
It has nothing to do with Feral's gamemode.

## Gaming Mode

A host whose `roles` list `"gaming"` gets three entries in the ly menu:

| ly menu entry | What runs | When to use it |
|---|---|---|
| Desktop | Hyprland with `hyprland.lua` | everyday work |
| Gaming Mode | Hyprland with `~/.config/hypr/gaming.lua`: Steam Big Picture fullscreen on the main monitor, no bar, no wallpaper, no idle lock | the default gaming entry |
| Gaming Mode (gamescope, experimental) | gamescope with Steam's Deck UI (`gamescope-session` and `gamescope-session-steam`, from OpenGamingCollective, pinned in `pkgs/`) | the real SteamOS shape; experimental on NVIDIA |

ly also lists Arch's own "Hyprland" and "Hyprland (uwsm-managed)".
Desktop is the same compositor under its own name, because ly matches an autologin session by file name, `Name=` or `DesktopNames=`, and each Hyprland entry carries `DesktopNames=Hyprland`.
A switch has to name a session nothing else can match.

| From | How | Lands in |
|---|---|---|
| Desktop | `SUPER+CTRL+G`, or "Switch to Gaming Mode" in the app menu | the default Gaming Mode |
| Gaming Mode (Hyprland) | `SUPER+CTRL+D` | Desktop |
| Gaming Mode (Hyprland) | `SUPER+SHIFT+Escape`, or quitting Steam | the ly menu |
| Gaming Mode (gamescope) | Steam › Power › Switch to Desktop | Desktop |
| a terminal | `steamos-session-select desktop`, `gaming`, `big-picture` or `gamescope` | that session |

`steamos-session-select` (from gamescope-session-steam) runs `/usr/lib/os-session-select` from `dram-gaming-mode`, which maps the name and calls `pkexec /usr/lib/dram/session-switch`.
polkit lets the person at the machine do that without a password, in the active local session only, so not over SSH.
The helper writes `/run/dram/ly-next-session`, ends the session and restarts `ly@tty2`.
Before ly starts, `/usr/lib/dram/ly-prepare` turns the request into ly's one-shot autologin, and clears it again on the next start.
There is no lasting autologin: a reboot shows the menu.

The login keyring stays locked after a switch, because no password reached PAM.
Apps that keep secrets in it, Proton Pass and the Electron apps, ask once; log out and in through the ly menu to unlock it from the start.
[Decision 0012](../../../decisions/0012-gaming-mode.md) accepts that.

The Hyprland Gaming Mode stays the default until cabin's hardware test shows gamescope clean on the current NVIDIA driver for a month.
Then, on that machine:

```sh
echo gamescope | sudo tee /etc/dram/gaming-mode   # "gaming" now means the gamescope session
```

`dram doctor` prints which one is the default.

The gamescope session reads `~/.config/gamescope-session-plus/sessions.d/steam`, which `modules/gaming.nix` writes from the host file:

```nix
dram.gaming = {
  output = "DP-1";          # connector from /sys/class/drm (card1-DP-1 -> DP-1)
  width = 2560; height = 1440;
  adaptiveSync = false;     # VRR: off until tested on this driver
  hdr = false;              # gamescope#1593 on NVIDIA
  forceComposition = false; # GAMESCOPE_COMPOSITE_FORCE=1: try first if overlays corrupt
};
```

Each value is unset by default, and gamescope picks; cabin's values come from its hardware test.
On NVIDIA, the fallbacks in order: `forceComposition = true` with HDR off, then the Hyprland Gaming Mode, then Big Picture inside the Desktop (`steam -gamepadui`), then a nested `gamescope -f -- %command%` as a game's launch option.

## Where the games live

`/data/games` is the `@games` subvolume on the data pool ([decision 0011](../../../decisions/0011-disk-boot-secure-boot-snapshots.md)): a reinstall keeps it, and the system pool's snapshots never carry it.
`system/gaming-setup.sh`, a `dram apply` hook, gives it to the main user and links `~/games` to it.
Steam owns its library files, so Steam is told once, by hand:

1. Steam › Settings › Storage › the drive menu › Add Drive › `/data/games` › Add. Steam makes `/data/games/SteamLibrary`.
2. With that drive selected: ⋯ › Make Default.
3. For a game already in the first library (`~/.local/share/Steam`, on the system pool): select it on the same page › Move › the new drive. Its shader cache moves with it.

`dram doctor` names the step while Steam has only its home-directory library.
`system/gaming-setup.sh` also opens Steam Remote Play and Steam Link to the LAN in the firewall (`/etc/nftables.d/steam.nft`).

## Shader pre-caching

Steam downloads a game's Vulkan pipeline cache (Fossilize; CS2's is 6.8 GB) and replays it into the driver's cache with `fossilize_replay`, the "Processing Vulkan shaders" step.
Out of the box Steam does that only when a game starts, so each launch waits for hours, or skips it and stutters, and the next launch starts over.
Three settings move the work into the background, once per game or driver update:

- Steam › Settings › Downloads › Shader Pre-Caching: *Enable Shader Pre-caching* and *Allow background processing of Vulkan shaders* both on. Steam keeps the second in `~/.local/share/Steam/config/config.vdf` (`EnableShaderBackgroundProcessing`), and `dram doctor` checks it.
- `modules/gaming.nix` writes `~/.local/share/Steam/steam_dev.cfg` at each switch: half the CPU threads for background processing (`unShaderBackgroundProcessingThreads`, 16 on cabin, where Steam's own default is a quarter), all of them when a launch waits (`unShaderHighPriorityProcessingThreads`). Steam reads it when it starts.
- On a gaming desktop Steam starts minimized at login (`hyprland.lua`; not on a laptop), so the processing runs after each boot instead of at the first launch. The bar has no tray: open Steam from the launcher, which brings up the running one.

The results stay in `steamapps/shadercache/<appid>/` in the game's library on `/data/games`, and the NVIDIA cache is capped at 10 GB with pruning off (`modules/gpu.nix`).
A driver update makes Steam process again, in the background.
A game started before processing finishes stops it; `shader_log.txt` then says "fossilize_replay wait() returned exit code -10 … Considering it killed", which is the launch, not a crash.
It starts again once no game runs.

```sh
grep -E 'Starting processing job|fossilize_replay|Destroyed compile job' ~/.local/share/Steam/logs/shader_log.txt | tail
pgrep -a fossilize_replay              # running now, with its thread count
```

## Controllers

- Steam Input: `steam` pulls `steam-devices` (Valve's udev rules), and `uinput` loads at boot (`/usr/lib/modules-load.d/dram-uinput.conf`), so Steam can make virtual pads.
- Xbox pads over Bluetooth: `xpadneo-dkms` from `[dram]`, built by DKMS for each kernel. Pair once in the Desktop with blueman, and it reconnects by itself afterwards.
- PlayStation and Switch Pro pads: the kernel's `hid-playstation` and `hid-nintendo`.
- Other pads (8BitDo, Hori, PowerA, Razer): `game-devices-udev` from `[dram]` gives the logged-in user access.

## CS2

Steam › CS2 › Properties › Launch options, set per game:

```text
SDL_VIDEO_DRIVER=wayland gamemoderun mangohud %command%
```

- Drop `mangohud` once the numbers are known.
- Drop `SDL_VIDEO_DRIVER=wayland` if the Steam overlay or monitor placement matters: the X11 path still tears through the `immediate` window rule, so the latency is the same.
- Compatibility tool: none, or Steam Linux Runtime. CS2 is native and Vulkan, so it never needs Proton.
- In the gamescope Gaming Mode use `gamemoderun %command%` only: Steam's own performance overlay drives MangoHud there through mangoapp, and `mangohud` would draw a second one.

In the game: `fps_max 0` (or 400 and up), V-Sync off, NVIDIA Reflex on.

`input.accel_profile = "flat"` and `sensitivity = 0` in `hyprland.lua` give the same deltas on the desktop and in XWayland games, so in-game sensitivity does not change between them.
`force_no_accel` is off: the flat profile already removes acceleration, and `force_no_accel` would also bypass libinput's scaling.

| Setting | Value | Why |
|---|---|---|
| `general.allow_tearing` | `true` | lets `immediate` windows tear, for the lowest latency |
| window rule `games-fullscreen` | `fullscreen + immediate` for `cs2` and `steam_app_*` | real fullscreen, frames presented at once |
| `misc:vrr` | `0`, the default | tearing wins over VRR here: Hyprland bounces between the two modes (discussion #13244) |
| `render:direct_scanout` | `0`, the default | the 0.56 black-screen regression; to try: `direct_scanout = 2` with `render.quirks.skip_non_kms_dmabuf_formats = true`, reverted if fullscreen goes black |
| `__GL_THREADED_OPTIMIZATIONS`, `__GL_SYNC_TO_VBLANK`, `__GL_YIELD` | not set | GL-only knobs; CS2 is Vulkan |
| `__GL_SHADER_DISK_CACHE*` | set in `modules/gpu.nix` for NVIDIA | a 10 GB cache with no pruning, so CS2 does not recompile its pipelines at each launch |

To see that tearing happens:

```sh
hyprctl monitors | grep -E 'activelyTearing|tearingBlockedBy'
```

`activelyTearing: true` with CS2 fullscreen means the `immediate` rule and `allow_tearing = true` are both in effect; `tearingBlockedBy` names the reason when not.

## OSRS

Recorded on 2026-10-06, so the setup survives a reinstall.

| Piece | Where | Detail |
|---|---|---|
| Launcher | `jagex-launcher` 0.1.8 from `[dram]` (`pkgs/jagex-launcher/`, the official Linux AppImage, pinned by sha256) | installs `/opt/jagex-launcher/jagex-launcher.AppImage` and `/usr/bin/jagex-launcher`; the desktop entry runs `env DESKTOPINTEGRATION=false /usr/bin/jagex-launcher %U` and owns the `rshub:` URL scheme; window class `Jagex Launcher` |
| Launcher data | `~/.local/share/Jagex Launcher/games/runelite/RuneLite.AppImage` (43 MB) | the launcher downloads RuneLite itself, so nothing needs a backup |
| Login | the Jagex account session in the launcher, kept in gnome-keyring's `login.keyring` | the beta caps a session at about two weeks; log in again after a reinstall |
| RuneLite config | `~/.runelite/` (278 MB; `profiles2/` holds `profiles.json` and one profile, `default`) | in cabin's Borg set through `dram.backup.extraSources` (`modules/hosts/cabin.nix`); to restore, copy `profiles2/` and `plugins/` back |
| Plugin Hub jars | `~/.runelite/plugins/`: 117 HD, Quest Helper, Equipment Inspector, Sailing | RuneLite downloads them again on first start if the profile lists them |
| Settings | GPU plugin off; 117 HD renders with vsync off, an fps target of 60, HYBRID UI scaling, anisotropic 1, expanded map chunks 3, no fog; game size 765×503, `KEEP_GAME_SIZE`, custom chrome and stretched mode off | RuneLite is windowed, so the `games-fullscreen` rule does not apply and nothing tears |
| Compositor | class `net-runelite-launcher-Launcher`, a normal tiled window | `SUPER+F` for fullscreen |
| gamemode | not used: RuneLite is Java with no launch options | `gamemoderun jagex-launcher` from a terminal works if wanted |

Flathub has no Jagex Launcher (checked 2026-10-06).
`com.jagex.RuneScape` there is the RS3 client, unverified and X11-only, and the "Jagex Launcher" Flatpak projects wrap the Windows launcher in Wine outside Flathub.

## On Windows

cabin-win takes the gaming role from `packages/winget/gaming.txt`, and nothing starts at sign-in (`install/windows/dram-windows/autostart.ps1`).

| Launcher | How | Verdict |
|---|---|---|
| Steam | winget | waived ([D102](../../../decisions/log.md#d102)) |
| Epic Games Launcher | winget | accepted with an Origin flag ([D94](../../../decisions/log.md#d94)) |
| EA app | winget | waived ([D97](../../../decisions/log.md#d97)) |
| Hytale | winget | waived ([D99](../../../decisions/log.md#d99)) |
| Battle.net | the `battle-net` unit, because winget's package needs an install location | waived ([D98](../../../decisions/log.md#d98)) |
| Ubisoft Connect | the `ubisoft-connect` unit, Ubisoft's own signed installer | accepted with a flag ([D96](../../../decisions/log.md#d96)) |
| Jagex Launcher | the `jagex-launcher` unit opens its signed installer on the desktop | waived ([D102](../../../decisions/log.md#d102)) |
| Marvel Rivals | through Steam | waived, cabin-win only ([D138](../../../decisions/log.md#d138)) |
| RuneLite | winget | accepted with an Origin flag ([D103](../../../decisions/log.md#d103)) |
| Vortex | winget | pass |
| PrismLauncher | winget; it fetches the Java each Minecraft version needs | pass |

League of Legends, with the Riot Client and Vanguard, and Blitz left cabin-win on 2026-10-19 ([D149](../../../decisions/log.md#d149)).
Emulation stays on Arch ([D62](../../../decisions/log.md#d62)).

## Opt-in, not installed

- Proton-GE through ProtonUp-Qt (Flathub `net.davidotek.pupgui2`, an Origin pass): follow "To add an app" on the [Flatpak](../packaging/flatpak.md) page with a new gaming list in `packages/flatpak/` and a register row. CS2 is native and OSRS is Java, so neither needs it.
- Decky Loader: not used. It is a root daemon that patches Steam through its debug port.
- steamos-manager: not used, so Steam's Bluetooth and update pages in the gamescope session show less than on a Deck. Updates come from `dram update`.

## When it breaks

```sh
dram doctor                         # "gaming mode": packages, the hook, ly's drop-in, uinput, modeset
journalctl -b -u ly@tty2            # ly-prepare's lines: "one-shot autologin pj -> dram-gaming"
journalctl --user -b -u gamescope-session-plus@steam    # the gamescope session
```

A switch that shows only the ly menu means the request was older than five minutes, or ly is not on tty2.
The session menu is always there as the way back.
If gamescope exits at once with "Failed to connect to wayland socket", it started nested in a dead session; `modules/gaming.nix` unsets the old display variables for its unit, so `dram switch` and log in again.

## Tests

- `tests/gaming-switch.sh`, in `bin/check.sh` §16 on any machine: the name mapping, `ly-prepare` against ini and Lua configs, and `system/apply-ly.sh` keeping the keys.
- `tests/gaming-vm.sh`, a VM on the Mac's QEMU: a real ly 1.4.1, polkit and the switch chain, with a stand-in for Hyprland, because a VM has no GPU.
- The hardware test on cabin, by hand.
  The driver version and `gamescope --version` go with the results in `hosts/cabin/README.md`.
  - both Gaming Modes from a cold boot
  - 30 minutes of Steam UI with the overlay and notifications (gamescope#1964), then again with `forceComposition`
  - ten round trips between Desktop and Gaming through each switch path, and Steam's Shutdown and Restart
  - CS2, OSRS through the Jagex Launcher as a non-Steam shortcut, and one Proton game
  - VRR on the DP panel, and the second monitor in both modes
  - Xbox pads over USB and Bluetooth, a DualSense and a Switch Pro, after a reboot
  - the keyring after a switch

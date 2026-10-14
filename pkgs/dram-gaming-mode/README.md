# dram-gaming-mode

[Toolchain](../../docs/toolchain/README.md) › [Profiles](../../docs/toolchain/profiles/README.md) › [Gaming](../../docs/toolchain/profiles/gaming.md)

SteamOS-style sessions in the ly login menu, and a switch between them that needs no password at the machine.
It adds Desktop and Gaming Mode, both Hyprland, beside the gamescope session, and maps Steam's "Switch to Desktop" onto ly's one-shot autologin.

| | |
|---|---|
| Needs | ly 1.4.1, polkit, Hyprland 0.56 with `start-hyprland`, systemd, gamescope-session-steam; tested 2026-10 |
| Copy alone | yes, after writing your own `~/.config/hypr/gaming.lua` |
| License | MIT |

## What it needs

- ly as the display manager on `tty2`. `ly-prepare` writes ly's `auto_login_session` and `auto_login_user` keys before each start.
- polkit, for the one action `org.dram.session-select`.
- Hyprland with its `start-hyprland` launcher, and a config at `~/.config/hypr/gaming.lua` for the Gaming Mode session. This repo's is `dotfiles/.config/hypr/gaming.lua`: Steam Big Picture fullscreen on the main monitor, no bar.
- `gamescope-session-steam`, which ships `steamos-session-select` and the third menu entry; it lives in `pkgs/gamescope-session-steam/`.
- Steam, for anything to play.
- Not needed: Nix, Home Manager or the `dram` command.

## Copy it alone

1. Copy this directory onto an Arch machine with ly on `tty2`.
2. Build and install it: `makepkg -si` in the directory. It needs `gamescope-session-steam` first; build that from `pkgs/gamescope-session/` and `pkgs/gamescope-session-steam/` the same way.
3. Write `~/.config/hypr/gaming.lua`, or copy `dotfiles/.config/hypr/gaming.lua` and change its monitor names.
4. Log out. The ly menu shows Desktop, Gaming Mode and Gaming Mode (gamescope, experimental).
5. In a terminal, `steamos-session-select gaming` ends the session and logs straight into Gaming Mode. `journalctl -b -u ly@tty2` shows `ly-prepare`'s line for the one-shot autologin.

## How it is wired here

`packages/roles/gaming.txt` lists it, so `dram apply` installs it from `[dram]` on each host with the gaming role.
`system/apply-ly.sh` keeps ly's autologin keys when it rewrites ly's config.
`modules/gaming.nix` writes the gamescope session's per-host settings, and `hyprland.lua` binds `SUPER+CTRL+G` to the switch.
`bin/check.sh` §16 runs `tests/gaming-switch.sh` against these files, and `tests/gaming-vm.sh` runs the switch chain in a VM.
`dram doctor` checks the package, ly's drop-in, `uinput` and which session is the default.
Why two gaming modes, and why Hyprland's is the default: [decision 0012](../../decisions/0012-gaming-mode.md).
[Gaming](../../docs/toolchain/profiles/gaming.md) is the page for using it.

## Files

| File | Installed as | What it does |
|---|---|---|
| `os-session-select` | `/usr/lib/os-session-select` | the hook `steamos-session-select` runs: maps a SteamOS or dram session name to one of three sessions and calls the switch through `pkexec` |
| `session-switch` | `/usr/lib/dram/session-switch` | root, through polkit: writes `/run/dram/ly-next-session`, then a transient unit ends the caller's ly session and restarts `ly@ttyN` |
| `ly-prepare` | `/usr/lib/dram/ly-prepare` | before each ly start: a request younger than five minutes becomes ly's one-shot autologin; otherwise both keys go |
| `session-hyprland` | `/usr/lib/dram/session-hyprland` | what Desktop and Gaming Mode run: Hyprland with the normal config, or with `gaming.lua` |
| `dram-session.conf` | `/usr/lib/systemd/system/ly@.service.d/dram-session.conf` | runs `ly-prepare` as `ExecStartPre` |
| `org.dram.session-select.policy` | `/usr/share/polkit-1/actions/` | lets the active local user switch, with no password, and nobody else |
| `dram-desktop.desktop`, `dram-gaming.desktop` | `/usr/share/wayland-sessions/` | the Desktop and Gaming Mode menu entries, without `DesktopNames=` so ly can tell them apart |
| `dram-gaming-mode.desktop` | `/usr/share/applications/` | "Switch to Gaming Mode" in the app menu |
| `uinput.conf` | `/usr/lib/modules-load.d/dram-uinput.conf` | loads `uinput` at boot, for Steam Input's virtual pads |
| `PKGBUILD`, `.SRCINFO`, `UPSTREAM`, `PIN`, `REVIEW.md` | — | the recipe, how to bump it, and its review |

## License

MIT, Patrick Jordan.

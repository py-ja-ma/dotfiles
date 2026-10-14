# .local/bin

[Operations](../../../docs/operations/README.md) › [dram CLI](../../../docs/operations/dram/README.md) › dram on Arch

The `dram` command, its two shims, and the other user scripts each host links into `~/.local/bin`.
`dram` updates, applies, themes and checks a host.
The other scripts belong to the divisions in the table below, and each one's header is its documentation and its `--help`.

| | |
|---|---|
| Needs | bash, git, Nix with Home Manager, pacman and pacman-contrib, tested on Arch Linux in 2026-10; this repo checked out at `~/git/dotfiles` |
| Copy alone | no: `dram` reads this repo's host files, package lists and `system/` tables; the shims and most other scripts copy alone with the needs in their headers |
| License | MIT |

## What it needs

`dram` runs on Arch Linux and in a WSL 2 clone of it, tested in October 2026.

- bash, git and coreutils; `nix` and `home-manager`, for the flake's `<user>@<host>` configuration.
- `pacman`, `pacman-contrib` (`paccache`, `pacdiff`, `checkupdates`), `arch-audit` and `rebuild-detector`, for `update` and `doctor`.
- By command: `flatpak`, `borgmatic`, `snapper`, `efibootmgr`, `sbctl`, `vim` for `pacnew`, `rofi` for the theme picker.
- From this repo: `modules/hosts/<host>.nix`, `install/lib/detect.sh` and `install/lib/roles.sh`, the lists in `packages/`, `packages/register.tsv`, `pkgs/manifest.txt` and `pkgs/dram.asc`, the tables in `system/` and their scripts, `keys/`, `CHANGELOG.md` and `flake.lock`.
- It runs `bin/check.sh`, `bin/pkgs.sh`, `bin/yubikey.sh` and `dram-theme` from the same checkout.
- `bash-completion`, from `packages/base.txt`, loads the completion.

## Copy it alone

`dram` is not built to leave this repo: nearly each command reads one of the files above.
To take the idea, read [Releases and pushes](../../../docs/operations/releases/README.md) for the model, then copy the functions you need.
`cmd_boot_to` needs `efibootmgr` and util-linux, and the two shims are one `exec` line each.
Set `DRAM_REPO` when your checkout is not at `~/git/dotfiles`.

## How it is wired here

- `modules/cli.nix` links `dram`, `dram-switch` and `sysupdate` on every host, desktop or not.
- `modules/desktop.nix`, `theme.nix`, `laptop.nix`, `creator.nix`, `office.nix` and `dev.nix` link the other scripts file by file, so this README stays in the repo.
- `modules/shell.nix` links the completion, `dotfiles/.local/share/bash-completion/completions/dram`.
- `bin/check.sh` §4 lints each bash script here, and §13 runs each script's `--help` and each `dram` subcommand's.
- `bin/gen-commands-doc.py` copies each header into [Commands](../../../docs/commands.md).

## Files

| File | What it does | Branch |
|---|---|---|
| `dram` | updates, applies, themes and checks the host | [dram CLI](../../../docs/operations/dram/README.md) |
| `dram-switch` | shim for `dram switch` | [dram CLI](../../../docs/operations/dram/README.md) |
| `sysupdate` | shim for `dram update` | [dram CLI](../../../docs/operations/dram/README.md) |
| `dram-theme` | switches the desktop between the themes | [Design › Themes](../../../docs/design/themes/README.md) |
| `dram-theme-auto` | follows the sun between `washi` and `washi-day`, and the night light | [Design › Themes](../../../docs/design/themes/README.md) |
| `codium-themes-install` | registers the Letterpress themes with the editor | [Design › Themes](../../../docs/design/themes/README.md) |
| `nightlight.sh` | the blue-light filter, by hand | [Design › Themes](../../../docs/design/themes/README.md) |
| `quote-wallpaper.sh` | renders a quote as the wallpaper | [Design › Themes](../../../docs/design/themes/README.md) |
| `wallpaper-hotplug.sh` | repaints the wallpaper when a monitor arrives | [Design › Themes](../../../docs/design/themes/README.md) |
| `wallpaper-menu.sh` | picks a wallpaper for the focused monitor | [Design › Themes](../../../docs/design/themes/README.md) |
| `gsimplecal-dram.sh` | the calendar under the bar's clock, in the theme | [Design › Shell and bars](../../../docs/design/shell-and-bars/README.md) |
| `waybar-cputemp.sh` | the bar's CPU temperature | [Design › Shell and bars](../../../docs/design/shell-and-bars/README.md) |
| `waybar-date.sh` | the dateline under the bar's clock | [Design › Shell and bars](../../../docs/design/shell-and-bars/README.md) |
| `waybar-fullscreen.sh` | hides the bar over a fullscreen window | [Design › Shell and bars](../../../docs/design/shell-and-bars/README.md) |
| `waybar-toggle.sh` | hides or shows the bar by hand | [Design › Shell and bars](../../../docs/design/shell-and-bars/README.md) |
| `waybar-updates.sh` | the bar's pending-updates badge | [Design › Shell and bars](../../../docs/design/shell-and-bars/README.md) |
| `kb-layout.sh` | keeps the keyboards on one layout | [Design › Shell and bars](../../../docs/design/shell-and-bars/README.md) |
| `keybind-cheatsheet.sh` | the searchable keybind sheet | [Design › Shell and bars](../../../docs/design/shell-and-bars/README.md) |
| `layout-toggle.sh` | flips the window layout | [Design › Shell and bars](../../../docs/design/shell-and-bars/README.md) |
| `monitors-pin.sh` | names this host's panels by description for the monitor rules | [Hyprland](../../.config/hypr/README.md#monitors) |
| `lid.sh` | turns the laptop's panel off and on with the lid while docked | [Design › Shell and bars](../../../docs/design/shell-and-bars/README.md) |
| `ocr-copy.sh` | reads the text in a screen region to the clipboard | [Design › Shell and bars](../../../docs/design/shell-and-bars/README.md) |
| `power-menu.sh` | lock, log out, suspend, reboot, shut down | [Design › Shell and bars](../../../docs/design/shell-and-bars/README.md) |
| `screenshot.sh` | each screenshot bind, with one naming scheme | [Design › Shell and bars](../../../docs/design/shell-and-bars/README.md) |
| `welcome.sh` | the login toast | [Design › Shell and bars](../../../docs/design/shell-and-bars/README.md) |
| `gamemode.sh` | turns the desktop's effects off for a game | [Toolchain › Profiles](../../../docs/toolchain/profiles/README.md) |
| `office-init` | the office role's first run: the vault and the ledger | [Toolchain › Profiles](../../../docs/toolchain/profiles/README.md) |
| `re-lab-tools` | the re-lab role's per-user tools | [Toolchain › Profiles](../../../docs/toolchain/profiles/README.md) |
| `rec` | OBS recording on the recorder, over obs-websocket | [Toolchain › Profiles](../../../docs/toolchain/profiles/README.md) |
| `record-toggle.sh` | a screen recording, by hand | [Toolchain › Profiles](../../../docs/toolchain/profiles/README.md) |

## License

MIT, Patrick Jordan.

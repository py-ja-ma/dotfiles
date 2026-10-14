# flatpak

[Toolchain](../../docs/toolchain/README.md) › [Packaging](../../docs/toolchain/packaging/README.md) › [Flatpak](../../docs/toolchain/packaging/flatpak.md)

Flathub apps per role, each in a sandbox narrowed by a least-privilege override, for the programs Arch cannot provide.
The lists here name the apps, `system/flatpak-setup.sh` installs them, and `dotfiles/.local/share/flatpak/overrides/` holds one override per app.

| | |
|---|---|
| Needs | flatpak, `xdg-desktop-portal-gtk` and a portal for the compositor; Flathub; tested 2026-10 |
| Copy alone | yes, with `install/lib/roles.sh`; without a host file it installs the desktop list |
| License | MIT |

## What it needs

- `flatpak` and `xdg-desktop-portal-gtk` from pacman; screen sharing also needs the compositor's portal, `xdg-desktop-portal-hyprland` here.
- `system/flatpak-setup.sh`, root: it adds the Flathub remote at system scope, installs the ids for the host's roles, and copies each override to `/var/lib/flatpak/overrides/`.
- The override files in `dotfiles/.local/share/flatpak/overrides/`, one per app id. They cannot hold a README: Flatpak reads each file in that directory as an override.
- `install/lib/roles.sh`, which the installer sources to read the host's roles from `modules/hosts/<host>.nix`. A host without a host file gets the desktop list.
- Not needed: Nix or Home Manager to install the apps. Home Manager only links the overrides directory for the user scope.

## Copy it alone

1. Copy `packages/flatpak/`, `system/flatpak-setup.sh`, `install/lib/roles.sh` and the override files you want from `dotfiles/.local/share/flatpak/overrides/`, keeping their paths: the installer finds the others from its own location.
2. Keep the lists for the roles you want. With no host file, only `desktop.txt` is read.
3. Run `sudo bash system/flatpak-setup.sh --dry-run` to read what it would do, then without `--dry-run`. `DRAM_HOST=<host>` picks `modules/hosts/<host>.nix` when the hostname differs.
4. `flatpak info --show-permissions <id>` shows each sandbox with its override applied.

## How it is wired here

`system/apply-hooks.tsv` runs `system/flatpak-setup.sh` on each `dram apply` of a desktop host, after the packages.
`modules/desktop.nix` links `~/.local/share/flatpak/overrides` to the overrides directory, so Flatseal's edits land in the repo, and adds the Flatpak export directories to `XDG_DATA_DIRS`.
`dram update` runs `sudo flatpak update` after `pacman -Syu`.
`bin/check.sh` §15 fails on an id without a `packages/register.tsv` row, and `dram doctor` warns about an emulation id that is not installed.
Why Flatpak at all, and why only these apps: [decision 0016](../../decisions/0016-emulation-set-and-flatpak.md) and the [Flatpak](../../docs/toolchain/packaging/flatpak.md) page.

## Files

| File | What it lists |
|---|---|
| `desktop.txt` | Vesktop (Discord), LocalSend, Flatseal: vendor binaries that cannot be built here and need no theming |
| `emulation.txt` | PCSX2, xemu, shadPS4, Cemu, melonDS, Azahar, Rosalie's Mupen GUI, Steam ROM Manager: emulators with no Arch package and a Flathub-verified publisher |

Each file holds one Flathub id per line, with comments on their own lines only.

## License

MIT, Patrick Jordan.

# roles

[Toolchain](../../docs/toolchain/README.md) › [Packaging](../../docs/toolchain/packaging/README.md) › Role lists

One pacman package list per role: a host takes a role by naming it in its host file, and gets the role's packages.
The same role name also names the role's lists for Flatpak, winget and uv, so one word in a host file installs everything a job needs.

| | |
|---|---|
| Needs | pacman; a reader such as `install/lib/roles.sh` that turns a host's roles into list paths; tested 2026-10 |
| Copy alone | yes: each list is plain text, one package name per line |
| License | MIT |

## What it needs

- pacman, to install a list: `grep -vE '^[[:space:]]*(#|$)' packages/roles/<role>.txt | sudo pacman -S --needed -`.
- Something that knows a host's roles. Here, `install/lib/roles.sh` reads the `roles = [ … ];` line of `modules/hosts/<host>.nix` and prints the matching list paths.
- A few names come from `[dram]`, this repo's own pacman repo: they are marked in the lists, and need [`pkgs/`](../../pkgs/README.md) or the AUR.
- Not needed: Nix or Home Manager to install the pacman lists.

## Copy it alone

1. Copy the lists you want from `packages/roles/`.
2. Drop the `[dram]` names you do not build yourself, or build them from `pkgs/`.
3. Install a list with the pacman line above; `pacman -Q <name>` shows each one afterwards.

## How it is wired here

A host file's `roles` line names its roles, on one line, because `install/lib/roles.sh` reads it with grep ([decision 0009](../../decisions/0009-roles-and-host-shape.md)).
`install/bootstrap.sh` and `dram apply` install `packages/base.txt`, the hardware lists and each role's list.
`modules/options.nix` builds the list of valid roles from the `*.txt` files here, so a role exists for Home Manager exactly when its pacman list exists.
A role with a setup script also has a row in `system/apply-hooks.tsv`, which `dram apply` runs.
`system/flatpak-setup.sh` installs `packages/flatpak/<role>.txt` for each role a host has ([Flatpak](../flatpak/README.md)).
A Windows host installs `packages/winget/<role>.txt` for each role in its `windows/hosts/<host>.nix`, through the render (`bin/render-windows.sh`).

The checks:

- `bin/check.sh` §3 fails on an inline comment, a duplicate name or an AUR name in a list here.
- `bin/check.sh` §11 fails on a host that names a role without a list.
- `bin/check.sh` §15 fails on a name without a verdict in `packages/register.tsv`, for the pacman, Flatpak and winget lists alike.

## The roles

| Role | For | pacman | Flatpak | winget | Hosts | Page |
|---|---|---|---|---|---|---|
| `builder` | the `[dram]` builder | `builder.txt` | | | cabin | [Packaging](../../docs/toolchain/packaging/README.md) |
| `chat` | voice and IRC | planned | | `chat.txt` | cabin-win | [Profiles](../../docs/toolchain/profiles/README.md) |
| `college` | coursework | `college.txt` | | `college.txt` | cabin, lantern, cabin-wsl, thermos-wsl, cabin-win | [College](../../docs/toolchain/profiles/college.md) |
| `creator` | OBS and the virtual camera | `creator.txt` | | `creator.txt` | cabin, campfire, cabin-win | [Creator](../../docs/toolchain/profiles/creator.md) |
| `desktop` | Hyprland, the look, browser, mail, files | `desktop.txt` | `desktop.txt` | `desktop.txt` | cabin, lantern, campfire, cabin-win | [Toolchain](../../docs/toolchain/README.md) |
| `dev` | the programmer's kit | `dev.txt` | | `dev.txt` | cabin, lantern, cabin-wsl, thermos-wsl, cabin-win | [Development](../../docs/toolchain/development/README.md) |
| `docker` | Docker, by opt-in | `docker.txt` | | | cabin | [Development](../../docs/toolchain/development/README.md) |
| `dump-kit` | reading discs and images | `dump-kit.txt` | | | cabin, lantern | [Emulation](../../docs/toolchain/profiles/emulation.md) |
| `emulation` | emulators | `emulation.txt` | `emulation.txt` | | cabin | [Emulation](../../docs/toolchain/profiles/emulation.md) |
| `gaming` | Steam and Gaming Mode | `gaming.txt` | | `gaming.txt` | cabin, lantern, cabin-win | [Gaming](../../docs/toolchain/profiles/gaming.md) |
| `ml` | local models | `ml.txt` | | | cabin | [Development](../../docs/toolchain/development/README.md) |
| `ml-cuda` | the CUDA toolkit, by opt-in | `ml-cuda.txt` | | | none | [Development](../../docs/toolchain/development/README.md) |
| `office` | tasks, notes, money | `office.txt` | | `office.txt` | cabin, lantern, cabin-wsl, thermos-wsl, cabin-win | [Office](../../docs/toolchain/profiles/office.md) |
| `re-lab` | reverse engineering | `re-lab.txt` | | `re-lab.txt` | cabin, lantern, thermos-wsl | [Re-lab](../../docs/toolchain/profiles/re-lab.md) |
| `recording` | editing on the recorder | `recording.txt` | | | cabin, campfire | [Creator](../../docs/toolchain/profiles/creator.md) |
| `sysadmin` | the homelab kit | `sysadmin.txt` | | `sysadmin.txt` | cabin, lantern, campfire, cabin-wsl, thermos-wsl, cabin-win | [Development](../../docs/toolchain/development/README.md) |
| `telephony` | the Yate lab | `telephony.txt` | | | cabin, lantern | [Development](../../docs/toolchain/development/README.md) |

The re-lab role also has per-user lists, which `re-lab-tools` installs: `packages/uv/re-lab.txt` (uv tools, `name==version`) and `packages/ghidra-extensions.tsv` (Ghidra extensions, with their sha256).
base is no role: each host reads `packages/base.txt`, and a metal host its hardware lists too (`packages/metal.txt`, `cpu-*.txt`, `gpu-*.txt`, `laptop.txt`, `host-<host>.txt`).
A WSL clone skips the names in `packages/wsl-skip.tsv`.

## List format

The pacman lists here, and `packages/flatpak/*.txt`, hold one name per line, with comments on their own lines only.
A name lives in one list.

The winget lists in `packages/winget/` hold one name per line with a prefix: `winget:<id>`, `msstore:<id>` for the Microsoft Store, or `manual:<name>` for a program a Script unit installs, or that is installed by hand.
Each name lives in one winget list and has a `packages/register.tsv` row; a name that matches an Arch package carries that row's verdict through a `= <name> (Arch)` note.
A Windows host installs each name of its roles' lists unless its host file holds one back.
`packages/winget/` is an input of the Windows render, so a file added there changes the build: no README goes in it, and this page describes it.

## License

MIT, Patrick Jordan.

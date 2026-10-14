# windows

[Platforms](../docs/platforms/README.md) › [Windows](../docs/platforms/windows/README.md) › [Renderer](../docs/platforms/windows/renderer.md)

Windows PCs declared in Nix: a host file names its roles, the roles carry registry values, Script units and staged files, and a render turns them into winget configuration documents and a manifest of every file the PC needs.
The build is committed in `build/<host>/`, so neither the Mac nor the PC needs Nix to read it.

| | |
|---|---|
| Needs | Nix with flakes and nixpkgs' `lib` (or Docker and Colima on the Mac), python3, curl, bsdtar; on the PC, winget 1.28 or later with Microsoft.WinGet.DSC and PSDscResources; tested 2026-10 |
| Copy alone | yes, with Nix: this directory, `bin/render-windows.sh`, `install/lib/windows-stage.sh`, the `packages/winget/` lists and the flake's `windowsConfigurations` lines; write your own host file |
| License | MIT |

## What it needs

- `flake.nix`, which evaluates each host file as `windowsConfigurations.<host>` and checks the committed build against a fresh render.
- `packages/winget/<role>.txt` for every role a host names: the role exists when its list does.
- The files the roles stage: the fonts and pointer pinned in `install/windows/fonts.pin` and `cursors.pin`, the generated themes in `install/windows/letterpress/`, the scripts in `install/windows/dram-windows/`, and a few files Arch shares.
- A row in `packages/register.tsv` for every listed name ([decision 0013](../decisions/0013-software-rules-and-waivers.md)).
- Not needed on the PC: Nix, git or PowerShell 7.

## Copy it alone

1. Copy this directory, `bin/render-windows.sh`, `install/lib/windows-stage.sh` and the `packages/winget/` lists you want, and add the `windowsConfigurations` output from `flake.nix`.
2. Write `hosts/<host>.nix`: `host`, `roles` on one line, `address` and `user` for the push, and the host's own settings as `windows.role.host-<host>`.
3. Delete the roles and units you don't want; a role is a list in `packages/winget/` and, if it has settings, a file in `roles/`.
4. Render: `bin/render-windows.sh <host>` writes `build/<host>/`; `bin/render-windows.sh --check` then prints "current".
5. Apply the documents on the PC with `winget configure -f <document> --accept-configuration-agreements`, machine documents elevated, in the manifest's order, or stage the build with `install/windows/apply-windows.sh`.

## How it is wired here

| File | What it holds |
|---|---|
| `default.nix` | the flake's `windowsConfigurations`: one `lib.evalModules` per host file, and which committed files are stale |
| `options.nix` | every `windows.*` option, declared once |
| `lib.nix` | the lists, the pins and the directories staged whole |
| `lower.nix` | turns the host's roles, their lists and its own settings into units, and refuses what it can't trust |
| `render.nix` | writes the units as documents, one per phase and scope, plus `manifest.json` and `inputs.json` |
| `packages.nix` | what a list line can't say: unit id, description, pinned version, how a manual app arrives |
| `roles/<role>.nix` | a role's settings: base, desktop, creator, dev, gaming |
| `hosts/<host>.nix` | a PC: its roles, address, held and unmanaged apps, and its own settings beside Arch |
| `units/<id>.ps1` | each Script unit's PowerShell, with Get, Test and Set |
| `build/<host>/` | the committed render: six documents, `manifest.json`, `inputs.json` |

`bin/check.sh` §19 runs `bin/render-windows.sh --check`, which hashes every file `inputs.json` lists and lists the directories it read again, without Nix; `nix flake check` compares the build with a fresh render.
Markdown files are never render inputs, so this README doesn't make the build stale.
`bin/push-windows.sh` stages the build for `dram.ps1` on the PC ([dram.ps1](../docs/platforms/windows/dram-ps1.md)).
What each phase and document holds, the manifest's format and how to add an app: [Renderer](../docs/platforms/windows/renderer.md).

## License

MIT, Patrick Jordan.

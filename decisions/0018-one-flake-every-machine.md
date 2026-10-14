# 0018: One flake for every machine

[Platforms](../docs/platforms/README.md) · proposed 2026-10-11 · amended 2026-10-12

One repository and one flake describe every machine I own, each OS taking what Nix can declare there; the cost is a module tree that grows one OS family at a time.

## Context

I want Nix to apply to all my machines, while the core of this repo stays my Arch Linux, declared and riced.
The question was whether the other machines belong in projects of their own.
The fleet (docs/platforms/README.md): cabin (Arch + a bench of Windows, Debian,
Fedora, NixOS), lantern (Arch, travel), thermos (Windows, travel), lodge (macOS), campfire
(the recorder, Arch, later), a Steam Deck (SteamOS, much later).

## Decision (proposed)

Keep it **one repository and one flake**. Nix flakes are built to describe many machines;
splitting into repos would duplicate the shared modules (shell, git, editor, themes) that
are the point of having one config. The Arch system layer stays as it is.

| Machine / OS | What Nix can declare | Output in flake.nix |
|---|---|---|
| Arch (cabin, lantern, campfire) | the user layer (Home Manager) | `homeConfigurations."<user>@<host>"` |
| Arch in WSL 2 on the Windows PCs (cabin-wsl, thermos-wsl) | the same user layer and the CLI roles, as an Arch host with `form = "wsl"` (`decisions/0021-wsl-clone.md`, built 2026-10-12) | `homeConfigurations."pj@<host>-wsl"` |
| Debian, Fedora on cabin's bench | the same user layer | `homeConfigurations."pj@cabin-debian"` … |
| NixOS on cabin's bench | the whole system + Home Manager | `nixosConfigurations.cabin-nixos` |
| macOS (lodge) | system settings (nix-darwin) + Home Manager | `darwinConfigurations.lodge` |
| SteamOS (the Deck) | the user layer in /home (Nix installs on SteamOS's read-only root) | `homeConfigurations."deck@smores"` |
| Windows (cabin's Windows disk, cabin-win; thermos when it is rebuilt) | its settings, apps and rice: one `windows/hosts/<host>.nix` with its roles on one line, the roles' settings and `packages/winget` lists, rendered to `winget configure` documents and a manifest of every staged file (`decisions/0020-windows-from-the-flake.md`; amended 2026-10-12: was "nothing - WinUtil's exported settings and a setup script as data") | `windowsConfigurations.<host>` |

Shared modules (shell, git, editors, the theme palette) would move into a common
subfolder of modules, with one subfolder per OS family beside it (Arch, macOS, NixOS). The Arch rice
stays the reference; the others take what applies.
NixOS-WSL is not part of this: it was struck on 2026-10-12 ([D139](log.md#d139)), and the WSL clone of 0021 takes its place.

## Consequences

- lodge would get Nix (and nix-darwin): a change to the Mac I approve when this starts; until
  then the Mac only edits and releases.
- `bin/check.sh` and the nixos/nix container check would evaluate every output.
- Not started until Arch runs on cabin and lantern.

## How it is checked

`nix flake check --all-systems --no-build` evaluates every output that exists: the Arch homes, the two WSL clones and `windowsConfigurations.cabin-win`.
Nothing checks the outputs that are not built yet.

## History

- 2026-10-11: proposed, for after the Arch rollout.
- 2026-10-12: amended: the Windows row built by [0020](0020-windows-from-the-flake.md) (accepted 2026-10-12) and the WSL row by [0021](0021-wsl-clone.md); NixOS-WSL struck ([D139](log.md#d139)).

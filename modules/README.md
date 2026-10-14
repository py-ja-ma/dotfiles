# modules

[Platforms](../docs/platforms/README.md) › [Arch Linux](../docs/platforms/arch/README.md) › User layer

The Home Manager modules every host's configuration is built from: one module per concern, switched on by the flags and roles in the host's file.
`flake.nix` builds one configuration per file in `modules/hosts/`, named `<user>@<host>`, and `dram switch` activates it.

| | |
|---|---|
| Needs | Nix with flakes; nixpkgs (nixos-unstable), Home Manager and sops-nix as `flake.lock` pins them; tested on Arch 2026-10 |
| Copy alone | yes, after replacing the login, the location and the git identity, and writing your own host file |
| License | MIT |

## What it needs

- `flake.nix` at the repo root, which imports `./modules` and each host file, and `flake.lock`.
- The files the modules link from `dotfiles/`: every `link "…"` target exists there (`bin/check.sh` §1).
- `packages/roles/`: `options.nix` builds the list of allowed roles from that directory's file names.
- `keys/ssh.pub` for `dev.nix`'s allowed signers, and `secrets/pj.yaml` for `secrets.nix` once a host enables secrets.
- The repo cloned at `~/git/dotfiles`: the links point there, so edits to a dotfile are live and tracked.
- Not needed: NixOS. The modules run on Arch with Home Manager's `genericLinux`; GUI programs come from pacman ([decision 0003](../decisions/0003-gui-apps-from-pacman-over-nixpkgs.md)), and the modules only configure them.

## Copy it alone

1. Copy `flake.nix`, `flake.lock`, `modules/` and the parts of `dotfiles/` you want; drop the `./windows` import from `flake.nix` if you don't render Windows.
2. In `modules/options.nix`, set the default `user`, the `location` used for day and night, and `repo` if your clone lives elsewhere.
3. In `modules/dev.nix`, replace the git name, email and allowed signers.
4. Write `modules/hosts/<host>.nix` with `hostName`, `user`, `roles`, `isLaptop` and `gpu`, and give each role a `packages/roles/<role>.txt`, even an empty one.
5. Build and activate: `nix run home-manager -- switch --flake .#<user>@<host>`.
   `ls -l ~/.config/hypr` then shows links into your clone.
   Never run `home-manager switch` without `--flake`: it reads `~/.config/home-manager/home.nix` instead and tore down every link once.

## How it is wired here

A host file sets flags only ([decision 0004](../decisions/0004-module-split.md)); `laptop.nix` and `gpu.nix` turn the flags into configuration with `lib.mkIf`, and a role's module applies only when the host has the role.
`bin/check.sh` §11 checks the host files without Nix, and `nix flake check` builds every host's configuration as the `home-<host>` check.
`dram switch` on a host builds the generation from the flake and activates it; `dram doctor` warns when `modules/` changed after the last switch.

| Module | What it does | Documented on |
|---|---|---|
| `options.nix` | every `dram.*` option, and the `link` helper that points a file at the repo | [Arch Linux](../docs/platforms/arch/README.md#the-user-layer) |
| `core.nix` | identity, `home.stateVersion`, `nix.conf`, `genericLinux`, `PATH` | [Arch Linux](../docs/platforms/arch/README.md#the-user-layer) |
| `laptop.nix` | `isLaptop`: the lid and brightness scripts, or Waybar without its battery module | [Roles](../docs/platforms/arch/roles.md#hardware-lists) |
| `gpu.nix` | `gpu`: the NVIDIA session environment, shader cache and gamemode, or Intel's VA-API driver | [Roles](../docs/platforms/arch/roles.md#hardware-lists) |
| `hosts/*.nix` | one file per host: its flags, roles and form | [Roles](../docs/platforms/arch/roles.md), [WSL](../docs/platforms/wsl/README.md) |
| `shell.nix` | bash, atuin, starship, fzf, eza, zoxide, bat, btop, the aliases | [Terminal](../docs/design/shell-and-bars/terminal.md) |
| `cli.nix` | every host, with or without a session: `dram` and its shims, `~/.ssh/config`, the prompt, yazi, the themes' seed | [the dram page](../docs/operations/dram/README.md) |
| `desktop.nix` | every GUI dotfile and script link, fonts, dconf, the user services, the default applications | [Shell & bars](../docs/design/shell-and-bars/README.md) |
| `theme.nix` | `dram-theme`, the editor's themes and their first-switch seed | [Themes](../docs/design/themes/README.md) |
| `dev.nix` | git signed with SSH, delta, lazygit, direnv, ripgrep, the homelab command-line kit | [Development](../docs/toolchain/development/README.md) |
| `ml.nix` | role ml: llama-server on loopback | [Development](../docs/toolchain/development/README.md) |
| `gaming.nix` | role gaming: the Gaming Mode settings | [Profiles](../docs/toolchain/profiles/README.md) |
| `creator.nix` | roles creator and recording: `rec`, the OBS templates | [Profiles](../docs/toolchain/profiles/README.md) |
| `office.nix` | role office: `office-init`, the vault and the ledger | [Profiles](../docs/toolchain/profiles/README.md) |
| `secrets.nix` | sops-nix, behind `dram.secrets.enable` | [Secrets](../docs/security/identity/secrets.md) |
| `backup.nix` | borgmatic between hosts, paused until the NAS | [Backups](../docs/operations/backups/README.md) |
| `default.nix` | imports every module above | this page |

Keep a host's `roles = [ … ];` on one line and quoted: `install/lib/roles.sh` reads it with grep, so shell scripts and Nix agree on the roles.

## License

MIT, Patrick Jordan.

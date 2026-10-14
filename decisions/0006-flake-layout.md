# 0006: The flake finds hosts in their directory and builds per system

[Platforms › Arch Linux](../docs/platforms/arch/README.md) · accepted 2026-10-06

Hosts come from `modules/hosts/`, outputs exist for Linux and the Mac, and the lints are flake checks; the cost is a binary-cache fetch for the lint tools.

## Context

`flake.nix` named each host twice (`homeConfigurations."pj@<h>"` and
`checks.x86_64-linux.home-<h>`) next to the file that already defines it,
`modules/hosts/<h>.nix`; `bin/check.sh` §2 existed largely to keep the three in
step. Every output was hard-wired to `x86_64-linux`, so `nix fmt` and `nix
develop` did not exist on the Mac the repo is edited from, and the lints the
roadmap wanted (statix, deadnix, shellcheck) ran only through `bin/check.sh`.
CI ran `nix flake check` and then a hand-written loop evaluating each host's
`drvPath`, and its actions floated on `@main`.

## Decision

1. **Hosts are enumerated once, by the filesystem.** `hosts` =
   `builtins.readDir ./modules/hosts` filtered to `*.nix`; `homeConfigurations`
   and `checks.x86_64-linux.home-<h>` are generated from that list. A new host is
   `modules/hosts/<h>.nix` and nothing else (plus `hosts/<h>/` from `dram harvest`).
2. **Per-system outputs.** `systems = [ "x86_64-linux" "aarch64-darwin" ]`,
   `forAll = lib.genAttrs systems`; `checks`, `formatter` (`nixfmt-tree`) and
   `devShells.default` exist for both. The `home-<h>` checks stay under
   `x86_64-linux` only: that is the hosts' system and `activationPackage` is not
   meaningful elsewhere. `config.allowUnfree` was dropped after `nix flake check`
   instantiated both hosts without it (nothing in the user layer is unfree).
3. **Lints are a check.** `github:cachix/git-hooks.nix` (nixpkgs follows this flake's)
   provides `checks.<system>.pre-commit` with statix (`statix.toml` disables
   `repeated_keys` and `empty_pattern`, which are this tree's Home Manager style),
   deadnix, and shellcheck at `bin/check.sh` §4's severity and file rule (`-S
   warning -s bash`, bash-shebang files only; `hosts/`, the vendored theme
   directories and `pkgs/` excluded). `nix develop` installs the same hooks into `.git`
   (it writes `.pre-commit-config.yaml`, gitignored). nixfmt, shfmt and stylua
   are **not** hooks: the tree is not formatted (`treefmt.toml` says so; nixfmt
   alone would rewrite ~530 lines) and that reformat is a commit of its own.
4. **CI is `nix flake check --all-systems --no-build -L`**: every derivation of
   every system is instantiated (which is what the old `drvPath` loop did by
   hand), nothing is built. `flake-checker-action`, `update-flake-lock` and
   `determinate-nix-action` are pinned to a commit with the tag in a comment.
5. **No flake-parts.** The whole flake is ~110 lines with two `let` helpers
   (`forAll`, `forHosts`); a framework would add an input, a `perSystem`
   indirection and a second place to learn, to save the one `genAttrs` call.
   Revisit only if a third kind of output (NixOS, darwin) ever lands here.

## Consequences

- `bin/check.sh` §2 can no longer grep `flake.nix` for host names; it derives
  the list from `modules/hosts/*.nix` and checks `hosts/<h>/` against that.
  `install/bootstrap.sh` likewise tests for `modules/hosts/$HOST.nix`, not a
  `flake.nix` line.
- `nix flake check` on a host now needs the binary cache for statix/deadnix/
  shellcheck once (a few MB); offline it still evaluates, the `pre-commit`
  build just fails to fetch.
- The host facts the flags encode are also written to `~/.config/dram/facts.lua`
  (`modules/core.nix`) for `hyprland.lua` and `dram doctor`, which closed two roadmap
  items in the same change (not a flake decision, recorded here because it landed with it).

## How it is checked

`nix flake check --all-systems --no-build` evaluates every output: in CI (`.github/workflows/check.yml`, once the repo has a remote) and in the `nixos/nix` container on the Mac ([D26](log.md#d26)).
`bin/check.sh` §2 fails a host module without its `hosts/<h>/` directory and the reverse, and §4 runs shellcheck at the hooks' severity.

## History

- 2026-10-06: accepted and built.
- 2026-10-12: the flake gained `windowsConfigurations` ([0020](0020-windows-from-the-flake.md)) and the WSL clones as ordinary hosts ([0021](0021-wsl-clone.md)).

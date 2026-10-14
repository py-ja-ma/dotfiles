# 0004: Host flags over per-host copies, one module per concern

[Platforms › Arch Linux](../docs/platforms/arch/README.md) · accepted 2026-10-06

A host file sets flags and nothing else, and each shared concern lives in one module; the cost is a new flag whenever a host needs something the flags cannot say.

## Context

The old `common.nix` had grown to ~400 lines holding everything from `stateVersion`
to the Proton Mail unit, and the two host files each re-declared a `repo`/`link`
helper and carried hand-copied blocks: cabin's NVIDIA env + waybar battery strip,
panasonic's lid/brightness links + Intel VA-API. `docs/platforms/arch/install.md` told a third
host to "copy the closest host". That is how two machines drift: the copy is edited
on one and not the other, and `nix flake check` cannot tell, because both are valid.

## Decision

1. **A host file sets flags, nothing else.** `modules/hosts/<h>.nix` is
   `{ dram = { hostName; backupPeer; backupPeerAddr; isLaptop; gpu; }; }` (plus
   `address` / `secrets.enable` / `backup.extraSources`, added later the same way;
   `location` keeps its default on both hosts — nine options in all) plus its
   hardware header comment. If a host needs something the flags cannot express, the
   answer is a new flag (or a new branch on an existing one), not a block in the host file.
2. **Every `dram.*` option is declared in `modules/options.nix`** — one place to read
   the host contract, and the only place a type or default changes. `isLaptop` and `gpu`
   have no default: `nix flake check` fails a host that forgets one, and
   `bin/check.sh` §11 catches it without nix.
3. **Flags become config with `lib.mkIf`** in `modules/laptop.nix` (lid/brightness
   links vs the waybar `config.jsonc` with `, "battery"` stripped) and `modules/gpu.nix`
   (NVIDIA env + shader cache + `gamemode.ini`, Intel `LIBVA_DRIVER_NAME`, AMD empty).
   The values are the ones the host files carried, moved verbatim with their comments.
4. **`link` is defined once**, as `_module.args.dram.link` in `options.nix`, built from
   the string `"${config.home.homeDirectory}/git/dotfiles"` (not a path literal — with
   flakes `mkOutOfStoreSymlink` on a path silently points at a stale store copy,
   home-manager#2660). Modules take `{ dram, ... }` and call `dram.link`; three
   private copies of the same two lines are gone.
5. **The shared layer is split by concern** (`core`, `shell`, `dev`, `desktop`, `theme`,
   `backup`, `secrets`), imported by `modules/default.nix`. Option *values* did not
   change: this was a move, verified by diffing every `link "..."` target and every
   string-valued leaf against the previous tree. Two side effects were accepted:
   `home.packages` now concatenates three lists (same set, module order), and the
   waybar `readFile` path is one directory shallower (`../dotfiles/...`).

## Consequences

- Adding a desktop or a laptop is a five-line file (`docs/platforms/arch/install.md`); adding a
  *kind* of host (AMD GPU, a box without a backup peer) is a change in one shared module.
- `hyprland.lua` keeps its own runtime laptop detection (battery present); `dram.isLaptop`
  is the Nix-side statement of the same fact. If they ever disagree, the Lua side is what
  the running session believes — `DRAM_LAPTOP=0/1` overrides it.
- `dram.gpu` must agree with `install/lib/detect.sh` and `packages/gpu-<vendor>.txt` for
  the same machine; nothing enforces that yet.
- Four roadmap items closed with this change: a CI evaluation matrix, feature flags, the
  sops-nix scaffold and `flake-checker-action`.

## How it is checked

`bin/check.sh` §11 fails a host file that does not set `hostName`, `roles` (on one line, each with its list), `isLaptop` and `gpu`.
`bin/check.sh` §1 fails a `link` target that does not exist under `dotfiles/`.
`nix flake check` fails a host that leaves an option without a default unset.

## History

- 2026-10-06: accepted and built; option values unchanged, checked by diffing every link target and string leaf.
- 2026-10-10: host files gained `roles` ([0009](0009-roles-and-host-shape.md)).

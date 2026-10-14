# 0001: Documented manifests, not a NixOS rebuild

[Platforms › Arch Linux](../docs/platforms/arch/README.md) · accepted 2026-10-05

The system layer is plain text manifests and idempotent scripts, and Home Manager owns only `~/.config` and the user tools; the cost is a layer that no Nix evaluation checks.

## Context

I want the same Nix flake and setup on every Arch Linux PC, with the packages firmly
documented. Two facts constrain how to get there:

1. These are **Arch** machines, not NixOS. Nix on Arch manages user packages and
   dotfiles (via home-manager); it does not manage the kernel, the bootloader,
   DKMS modules, or the 17 hand-built AUR packages.
2. Nix was not installed on `cabin` on 2026-10-05. There was a stray `/nix` directory
   but no `nix` binary and `nix-daemon` was inactive. The only `flake.nix` on the
   machine was `~/Tools/Waybar-master/flake.nix`, which is upstream Waybar source.

The reference flake was believed to live on the second PC, which had not been
reachable yet.

## Decision

Start with **plain, diffable text manifests** per host (`pacman -Qqe`, `-Qqm`, a
pinned `pacman -Q` lock, enabled units, `/etc` copies) plus scripts to harvest,
diff, and apply them. Treat this as the substrate.

Layer home-manager on top **only after** seeing the second PC's actual flake, and
only for what Nix is good at here: `~/.config` and user tooling.

## Why not go straight to a flake

- Writing a flake to match a reference config nobody has read yet would be guesswork.
- A flake cannot own GRUB, the ESP layout, DKMS, or version-pinned AUR builds -
  the exact things that broke this machine. Those need to be documented regardless.
- Text manifests are reviewable and survivable. If the tooling rots, the lists
  still tell you what the machine is supposed to be.

## How it is checked

`dram doctor`'s declared-state section shows the drift between a host and its manifests ([0008](0008-system-layer-converge.md)).
`bin/check.sh` §2 keeps `hosts/` and `modules/hosts/` in step, and §3 keeps the package lists to one valid name per line.
Nothing checks the boundary itself: no module asks Home Manager to own the system layer, and `modules/default.nix` says so at its top.

## History

- 2026-10-05: accepted, with Home Manager deferred until the second PC had been harvested and its flake read.
- 2026-10-06: revisited. panasonic was harvested the same day and its flake became this repo's.
  Home Manager is canonical for `~/.config` and the user CLI tools on both hosts (`modules/*.nix`, [0004](0004-module-split.md)).
  The system layer stayed as decided here: manifests (`packages/*.txt`, `hosts/<h>/`) plus idempotent scripts (`system/`, `install/bootstrap.sh`).
  The 17 hand-built AUR packages became vendored, reviewed PKGBUILDs built once into the signed `[dram]` repo ([0005](0005-own-package-repo.md)).

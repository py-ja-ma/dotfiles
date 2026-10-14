# game-devices-udev review

[Toolchain](../../docs/toolchain/README.md) › [Packaging](../../docs/toolchain/packaging/README.md) › [The `[dram]` repo](../README.md) › game-devices-udev

udev rules that give the logged-in user third-party game controllers, so Steam Input and emulators can read them.

| | |
|---|---|
| Needs | Arch with makepkg, meson and git; udev; tested 2026-10 |
| Copy alone | yes: `makepkg -si` in this directory |
| License | the rules: MIT; the recipe: its AUR repository's terms, unstated |

## What it is

The rules cover 8BitDo, Sony, Microsoft, Nintendo, Razer, Hori, PowerA and others, and the package loads `uinput` at boot.
Tag `1.1` is signed by its author, Fabian Bornschein (`fabiscafe`, an Arch Linux staff member).
His public key is in `pkgs/game-devices-udev/keys/pgp/6E58E886A8E07538A2485FAED6A4F386B4881229.asc`, from keys.openpgp.org, so the chroot checks the tag without a keyserver.

## Runs at build and install time

`meson` installs the rule files.
The `.install` file loads `uinput` if it is not loaded, and reloads the udev rules, nothing else.

## Changed from the AUR

At AUR commit `0dcd1d6` (2026-10-10): the header comments only.
`dram-gaming-mode` also loads `uinput`, and two modules-load entries for one module are harmless.

## Origin and community

I ruled on its Origin on 2026-10-11: accepted.
The upstream is on Codeberg, with 186 commits, the last in 2026-04, when Valve's rules were merged.

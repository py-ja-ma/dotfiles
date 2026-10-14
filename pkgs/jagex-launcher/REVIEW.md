# jagex-launcher review

[Toolchain](../../docs/toolchain/README.md) › [Packaging](../../docs/toolchain/packaging/README.md) › [The `[dram]` repo](../README.md) › jagex-launcher

Jagex's official Linux launcher, a beta AppImage, for OSRS through RuneLite.

| | |
|---|---|
| Needs | Arch with makepkg, squashfs-tools and binutils; `fuse2` at run time; tested 2026-10 |
| Copy alone | yes: `makepkg -si` here; Jagex's EULA applies |
| License | Jagex's EULA (`JAGEX-EULA`), proprietary and waived in `packages/register.tsv`; the recipe: its AUR repository's terms, unstated |

## What it is

The AppImage comes from Jagex's CDN and is installed whole to `/opt`, run through `fuse2` at launch.
Only the `.desktop` file, the icons and the licenses are taken out of it.
The sha256 is computed from my download on 2026-10-06 and equals the AUR's (pajlada, 0.1.8, published 2026-10-05).
`JAGEX-EULA` is the AUR's copy of the EULA text, its sha256 checked.

## Runs at build and install time

The AUR runs the AppImage itself (`--appimage-extract`); this copy does not.
`prepare()` computes the squashfs offset from the ELF header with `readelf` and unpacks it with `unsquashfs`, so no vendor code runs in the chroot.
Then a `sed` on the `.desktop` file and a `chmod`.
There is no `.install`.
At run time the launcher updates games under `~/.local`, not itself: `/opt` is pacman's.

## Changed from the AUR

At AUR commit `5e7ae4e`: the unsquashfs `prepare()`, with `squashfs-tools` and `binutils` in `makedepends`; otherwise identical.
`pkgver` and `pkgrel` are the AUR's.

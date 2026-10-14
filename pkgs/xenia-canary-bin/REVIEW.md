# xenia-canary-bin review

[Toolchain](../../docs/toolchain/README.md) › [Packaging](../../docs/toolchain/packaging/README.md) › [The `[dram]` repo](../README.md) › xenia-canary-bin

Xenia Canary build `103257c` (2026-10-11), the Xbox 360 emulator's Linux AppImage, which upstream calls experimental.

| | |
|---|---|
| Needs | Arch with makepkg, squashfs-tools and binutils; SDL2, GTK 3 and the Vulkan loader at run time; tested 2026-10 |
| Copy alone | yes: `makepkg -si` in this directory |
| License | BSD-3-Clause; the recipe: its AUR repository's terms, unstated |

## What it is

It comes from the `xenia-canary/xenia-canary` releases, BSD-3-Clause.
The release names end in `…_canary_experimental`, and the README still asks for someone to port it to Linux.
It is pinned by the asset's published sha256.

The AppImage's squashfs is unpacked with `unsquashfs` at the offset its ELF header gives, as `pkgs/jagex-launcher` does.
The binary goes to `/opt/xenia_canary/bin` and its bundled libraries to `/opt/xenia_canary/lib`.
The AUR's launcher `xenia-canary-bin`, which changes to `~/.xenia-canary` and runs it, and its desktop file are kept.

## Runs at build and install time

`prepare()` reads the ELF header and runs `unsquashfs`; nothing from upstream runs.
There is no `.install`: the AUR's only printed notes.

## Changed from the AUR

At AUR commit `3c15ba6` (2026-08-11): the AUR sets `pkgver=$(curl …/releases/latest)` when the PKGBUILD is read, so any build with a `SKIP` checksum, and runs `--appimage-extract`.
This copy pins build `103257c` and unpacks it without running it.
The icons come from the AppImage instead of eight separate downloads, the license from the repository at the build's commit, and `vulkan-icd-loader` is added to `depends`.

## Origin and community

My emulator group ruling of 2026-10-10 covers it: the second to fourth committers are in Poland, London and California.
It releases per commit, and the register holds it as `pass-flag`.

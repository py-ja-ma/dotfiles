# xdvdfs review

[Toolchain](../../docs/toolchain/README.md) › [Packaging](../../docs/toolchain/packaging/README.md) › [The `[dram]` repo](../README.md) › xdvdfs

xdvdfs 0.8.3, the tool xemu's documentation recommends to pack and unpack original Xbox XISO images.

| | |
|---|---|
| Needs | Arch with makepkg, cargo and git; tested 2026-10 |
| Copy alone | yes: `makepkg -si` in this directory |
| License | MIT; the recipe: its AUR repository's terms, unstated |

## What it is

Redump's ISOs must be repacked as XISO for xemu.
The release tarball is pinned by sha256.

## Runs at build and install time

`cargo fetch --locked` and `cargo build --frozen` of the `xdvdfs-cli` crate; nothing runs at install.

## Changed from the AUR

At AUR commit `003b93d` (2024-11-24): the AUR runs `cargo update` in `prepare()`, which resolves each crate to the newest at build time.
This copy builds exactly what upstream's `Cargo.lock` says.

## Origin and community

I ruled on 2026-10-11 to accept one of extract-xiso and xdvdfs: this is the maintained one.
It is antangelo's, with low activity; the last push was in 2026-07.

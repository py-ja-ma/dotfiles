# uefitool-ng review

[Toolchain](../../docs/toolchain/README.md) › [Packaging](../../docs/toolchain/packaging/README.md) › [The `[dram]` repo](../README.md) › uefitool-ng

UEFITool A75 from LongSoft: a Qt 6 viewer for PC firmware images, with UEFIExtract and UEFIFind.

| | |
|---|---|
| Needs | Arch with makepkg and cmake; `qt6-base` at run time; tested 2026-10 |
| Copy alone | yes: `makepkg -si` in this directory |
| License | BSD-2-Clause; the recipe: its AUR repository's terms, unstated |

## What it is

The three tools read PC firmware images: cabin's and lantern's BIOS dumps, and firmware for reverse engineering.
The release tarball `A75` (2026-07-10) is pinned by sha256.

## Runs at build and install time

CMake builds the three tools; nothing runs at install.

## Changed from the AUR

At AUR commit `b4073a9` (2026-07-04): bumped from A74 to A75, the current upstream release, and x86_64 only.

## Origin and community

I ruled on its Origin on 2026-10-11: accepted.
Nikolaj Schlej, who gives no location, maintains it alone, with regular releases.

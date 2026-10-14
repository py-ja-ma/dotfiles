# redumper review

[Toolchain](../../docs/toolchain/README.md) › [Packaging](../../docs/toolchain/packaging/README.md) › [The `[dram]` repo](../README.md) › redumper

redumper b760, the low-level CD and DVD dumper the Redump project uses.

| | |
|---|---|
| Needs | Arch with makepkg, cmake, ninja, clang, lld and llvm; libc++ at run time; a disc drive; tested 2026-10 |
| Copy alone | yes: `makepkg -si` in this directory |
| License | GPL-3.0-only; the recipe: its AUR repository's terms, unstated |

## What it is

It reads raw sectors, subchannels and C2 errors: PS2 CD games, and Kreon- or OmniDrive-flashed drives for Xbox, GameCube and Wii discs.
The release tarball `b760` is pinned by sha256.
It needs raw access to the drive (`/dev/sg*`): run it with sudo, or join the `optical` group.
How each console's discs are read: [Emulation](../../docs/toolchain/profiles/emulation.md#your-own-consoles).

## Runs at build and install time

CMake and Ninja with clang, lld and libc++, as upstream builds it.
`package()` installs the binary, the README and the license; there is no `.install`.

## Changed from the AUR

At AUR commit `7adde15` (2026-10-08): the header comments only.

## Origin and community

I ruled on its Origin on 2026-10-11: accepted.
superg (`@NVIDIA` on GitHub, no location given) works with Redump, and releases come every few weeks.

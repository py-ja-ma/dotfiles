# imhex-bin review

[Toolchain](../../docs/toolchain/README.md) › [Packaging](../../docs/toolchain/packaging/README.md) › [The `[dram]` repo](../README.md) › imhex-bin

ImHex 1.38.1, a hex editor with a pattern language, from upstream's own CI-built Arch package.

| | |
|---|---|
| Needs | Arch with makepkg; `mbedtls3`, glfw, GTK 3, yara and the other libraries in `depends`; tested 2026-10 |
| Copy alone | yes: `makepkg -si` in this directory |
| License | GPL-2.0; the recipe: its AUR repository's terms, unstated |

## What it is

Upstream's release ships a `.pkg.tar.zst` already, and the PKGBUILD copies the files it wants out of it.
The sha256 is GitHub's digest of the release asset; my download on 2026-10-06 (14,554,070 bytes) matched it and the AUR's md5.
There is no `extra/imhex`, so it comes from `[dram]`, and this build links `mbedtls3`.

## Runs at build and install time

`install` and `cp` only; there is no `.install` and no hook.
It ships `imhex-updater`, upstream's updater, which cannot replace anything under `/usr`, because pacman owns it: ignore its prompts.

## Changed from the AUR

At AUR commit `5b7838f`: `md5sums` became `sha256sums`, because md5 alone is too weak, and the unused `makedepends=(git nlohmann-json)` went, since nothing is built.
`pkgver` and `pkgrel` are the AUR's.

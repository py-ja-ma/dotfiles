# rpcs3-bin review

[Toolchain](../../docs/toolchain/README.md) › [Packaging](../../docs/toolchain/packaging/README.md) › [The `[dram]` repo](../README.md) › rpcs3-bin

RPCS3 0.0.43-20284, the PS3 emulator's official Linux AppImage.

| | |
|---|---|
| Needs | Arch with makepkg; `fuse3`, the Vulkan loader, GL and ALSA at run time; tested 2026-10 |
| Copy alone | yes: `makepkg -si` in this directory |
| License | GPL-2.0-only; the recipe: its AUR repository's terms, unstated |

## What it is

Build `2ba2f75b` (2026-10-11), from `RPCS3/rpcs3-binaries-linux`.
It is pinned by the sha256 GitHub publishes for that release asset (`21aa550a…95cb`), which my own download matched.
The AppImage is installed as it is, to `/opt/rpcs3/rpcs3.AppImage`, and `/usr/bin/rpcs3` runs it.
Its runtime is uruntime with a DwarFS image, and no Arch repo package unpacks DwarFS, so it stays packed and mounts itself through FUSE (`fuse3`) at start.
The icon and the license come from the RPCS3 repository at the build's commit.

## Runs at build and install time

Nothing from upstream: `package()` copies files only, with no `prepare()` and no `.install`.

## Changed from the AUR

At AUR commit `fb6b3c5` (2026-08-12): the AUR asks the GitHub API for the latest release in `pkgver()` and downloads the AppImage with curl in `prepare()`, unpinned, with a `SKIP` checksum.
It then runs the AppImage (`--appimage-extract`) during the build and patches its `AppRun`.
This copy pins one build by its hash, never runs it while building, and ships it whole.
`depends` is trimmed to what the AppImage does not bundle: FUSE, the Vulkan loader, GL and ALSA.

## Origin and community

My emulator group ruling of 2026-10-10 covers it: the second committer is in Munich, and the others give no location.
Releases come several times a day, with 995 open and 8,771 closed issues.
The register holds it as `pass-flag`.

# vita3k-bin review

[Toolchain](../../docs/toolchain/README.md) › [Packaging](../../docs/toolchain/packaging/README.md) › [The `[dram]` repo](../README.md) › vita3k-bin

Vita3K build 4168, the PS Vita emulator's x86_64 AppImage.

| | |
|---|---|
| Needs | Arch with makepkg, squashfs-tools and binutils; the Vulkan loader, GL and the desktop portal at run time; tested 2026-10 |
| Copy alone | yes, while upstream still serves this build; otherwise pin the current one per `PIN` |
| License | GPL-2.0-only; the recipe: its AUR repository's terms, unstated |

## What it is

Build 4168 is commit `46602447` (2026-10-11).
Vita3K publishes only a moving `continuous` release: the same URL serves each new CI build.
The PKGBUILD pins build 4168's sha256 (`62ac9979…888c`, the digest GitHub showed), so a rebuild after upstream moves fails the checksum and has to be pinned again per `PIN`, never with `SKIP`.
I pinned it again from build 4166 when cabin's first build met the moved asset, on 2026-10-11.
An older build's asset cannot be fetched again, so the built package in `[dram]` is the copy.

The squashfs is unpacked with `unsquashfs` at the ELF header's offset.
The linuxdeploy tree, with Qt and its other libraries bundled, goes to `/opt/vita3k`, and `/usr/bin/vita3k` runs `/opt/vita3k/AppRun`, which finds its tree from its own path.

## Runs at build and install time

`unsquashfs` only; nothing from upstream runs.

## Changed from the AUR

At AUR commit `0d31bcf` (2026-07-24): the AUR downloads `ubuntu-latest.zip` with a `SKIP` checksum, computes `pkgver()` from the GitHub API at build time, and depends on the system's Qt 6, SDL3 and GTK 3.
This copy takes the self-contained AppImage, pins its hash and version, and keeps only the `depends` the AppImage leaves to the system: the Vulkan loader, GL and the portal.
`unzip`, inherited from the AUR's zip route, went in `-2`: the register forbids it since 2026-10-10, and nothing here unpacks a zip; cabin's `dram doctor` flagged it on 2026-10-11.

## Origin and community

The emulator group's Origin check passed: the first committer is in Tokyo, the second in France, the fourth in Japan.
Builds roll continuously, with 177 open and 933 closed issues.
The register holds it as `pass`.

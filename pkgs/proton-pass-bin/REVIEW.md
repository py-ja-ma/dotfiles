# proton-pass-bin review

[Toolchain](../../docs/toolchain/README.md) › [Packaging](../../docs/toolchain/packaging/README.md) › [The `[dram]` repo](../README.md) › proton-pass-bin

The Proton Pass desktop app, repackaged from Proton's own Linux `.deb`.

| | |
|---|---|
| Needs | Arch with makepkg; GTK 3, nss and the other Electron libraries in `depends`; tested 2026-10 |
| Copy alone | yes: `makepkg -si` in this directory |
| License | MIT and GPL-3.0-or-later, with Electron bundled; the recipe: its AUR repository's terms, unstated |

## What it is

Nothing is built.
The URL and the sha512 come from Proton's release manifest (`version.json`, Stable 1.41.1, 2026-09-24).
The `.deb` I downloaded on 2026-10-06 (103,838,612 bytes) hashed to exactly that sha512, so the file is what Proton publishes, not what an AUR maintainer uploaded.

## Runs at build and install time

`tar -xf data.tar.xz` and file moves in `package()`; there is no `.install` and no hook.
At run time the app updates nothing itself, because pacman owns `/opt/proton-pass`.

## Changed from the AUR

At AUR commit `c567314` (1.40.0, flagged out of date):

- bumped to 1.41.1 with the vendor's hash
- the source URL is the manifest's (`download/pass/linux/`) instead of `PassDesktop/linux/x64/`
- `chmod u-s chrome-sandbox`: no setuid-root binary, so Electron falls back to user namespaces, as VSCodium's package does
- `tar -xf` instead of `-xvf`

`pkgrel` stays 1.

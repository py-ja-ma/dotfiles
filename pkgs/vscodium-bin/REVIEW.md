# vscodium-bin review

[Toolchain](../../docs/toolchain/README.md) › [Packaging](../../docs/toolchain/packaging/README.md) › [The `[dram]` repo](../README.md) › vscodium-bin

VSCodium 1.135.06055, the community build of Microsoft's MIT-licensed `vscode` sources without Microsoft's branding, telemetry or proprietary license.

| | |
|---|---|
| Needs | Arch with makepkg; GTK 3, nss and the other Electron libraries in `depends`; tested 2026-10 |
| Copy alone | yes: `makepkg -si` in this directory |
| License | MIT (`LICENSE` here is VSCodium's own); the recipe: its AUR repository's terms, unstated |

## What it is

Upstream is github.com/VSCodium/vscodium, MIT, with 33.6k stars; the organization was created on 2018-06-17.
It replaced `visual-studio-code-bin`, Microsoft's proprietary build, under the FOSS rule of [decision 0013](../../decisions/0013-software-rules-and-waivers.md) ([D4](../../decisions/log.md#d4)).

The x86_64 tarball's sha256, `c09d8ac8…e1f2`, equals the `VSCodium-linux-x64-1.135.06055.tar.gz.sha256` published on the GitHub release, fetched on 2026-10-10, and the asset digest GitHub reports.
My own download (243,185,899 bytes) hashed to it.
`code.svg`, the raw file at the release tag, hashed to the pinned `e622e6bd…d347`, and the `.desktop`, `.install`, `.sh` and `LICENSE` files hash to their pinned values.
The tarball is not signed: its only integrity anchor is the sha256 from the same GitHub release.

The launcher `vscodium-bin.sh` (13 lines) reads `~/.config/codium-flags.conf`, skipping `#` lines, and runs `/opt/vscodium-bin/bin/codium`.
The binary is `/usr/bin/codium`, with a `/usr/bin/vscodium` link, and the desktop files are `codium.desktop` and `codium-url-handler.desktop` (`x-scheme-handler/vscode` and `/vscodium`).

## Runs at build and install time

There is no `prepare()` or `build()`.
`package()` copies the tarball to `/opt/vscodium-bin`, deletes the source links, and installs the launcher, two `.desktop` files, the icons (the png from the tarball, the svg from the tag), the `LICENSE` and links to the shell completions.
It installs `chrome-sandbox` without setuid, mode 0755, where the AUR installs it 4755.
Arch kernels have unprivileged user namespaces, which Electron's sandbox uses instead, so a setuid-root helper would be attack surface with no use.
The `.install` only prints a note on install and upgrade.
There are no hooks, and no upstream script runs.

## Changed from the AUR

At AUR commit `13bee17` (2026-09-09):

- `aarch64` dropped (`arch`, `source_aarch64`, `sha256sums_aarch64`), because only x86_64 is built
- `conflicts` extended from `vscodium` to `vscodium code visual-studio-code-bin`, so the swap removes Microsoft's package, with `provides` unchanged (`vscode codium vscodium`)
- header comments added
- `chrome-sandbox` installed 0755 instead of 4755, as above

`.SRCINFO` was edited by hand to match, because the Mac has no makepkg; `dram pkgs update` writes it again on cabin.
Not vendored: the AUR's unused `vscodium-bin-wayland.desktop`, which is not in `source=`, and its `.gitignore`.
`pkgver` and `pkgrel` are the AUR's, and each checksum is the AUR's, checked again.

## Origin and community

From the GitHub API on 2026-10-10.
`github.com/VSCodium` is an organization with 16 public repositories and no location set; its public members are `daiyam` and `stripedpajamas`.
Of the 257 commits since 2025-10-10 the leaders are `daiyam` with 187 (profile name "Baptiste Augrain", no location), `dependabot[bot]` with 36 and `lex-ibm` with 7 (location "Austin, TX", company "@IBM").
Then come `xiaolai`, `ThadHouse`, `DetachHead` and `bhaskarvilles` with 3 each (locations "beijing", "Sultan, WA", "your walls", "India"), and `darkyzhou` with 2 (none listed).
The top contributors of all time: `daiyam` 1160, `stripedpajamas` 346, `dependabot[bot]` 53, `lex-ibm` 16, `paulcarroty` 14.
The main maintainer's location is not documented, and nothing is inferred from names.

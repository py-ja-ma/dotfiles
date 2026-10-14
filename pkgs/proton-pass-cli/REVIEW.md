# proton-pass-cli review

[Toolchain](../../docs/toolchain/README.md) › [Packaging](../../docs/toolchain/packaging/README.md) › [The `[dram]` repo](../README.md) › proton-pass-cli

Proton's official `pass-cli`, the Proton Pass command line, built from source in Rust.

| | |
|---|---|
| Needs | Arch with makepkg, cargo and git; `sqlcipher` at run time; tested 2026-10 |
| Copy alone | yes: `makepkg -si` in this directory |
| License | GPL-3.0-or-later; the recipe: its AUR repository's terms, unstated |

## What it is

Built from the upstream git tag 2.4.2, which is commit `7ae51e5` (2026-10-01) and the latest GitHub release.
The b2sum is the AUR maintainer's checksum of that checkout, not `SKIP`, so the content is pinned even if the tag moves.
The AUR package, with four votes, only wraps upstream's own repository.

## Runs at build and install time

`prepare()` runs `cargo fetch` without `--locked`, so it needs the network and resolves the crate tree at build time: upstream's `Cargo.lock` lags its `Cargo.toml` at the tag.
A two-line `sed` raises `recursion_limit`, a rustc workaround I read.
Then `cargo build --offline` and `cargo test --offline`; there is no `.install`.

## Changed from the AUR

At AUR commit `fbf9906`:

- x86_64 only
- `cargo fetch --target <host>`, taking the host triple from `rustc -vV`
- the `RUSTUP_TOOLCHAIN=stable` exports dropped, because Arch's `rust` package has no rustup

`pkgver` and `pkgrel` are the AUR's.

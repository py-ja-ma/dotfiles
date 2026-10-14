# hyprland-plugin-hyprtasking review

[Toolchain](../../docs/toolchain/README.md) › [Packaging](../../docs/toolchain/packaging/README.md) › [The `[dram]` repo](../README.md) › hyprland-plugin-hyprtasking

raybbian's workspace overview for Hyprland, on `SUPER+grave` in `hyprland.lua`.

| | |
|---|---|
| Needs | Arch with makepkg, meson and git; the exact Hyprland version it was built against (0.56.2); tested 2026-10 |
| Copy alone | yes: `makepkg -si` here, against the Hyprland you run |
| License | BSD-3-Clause; the recipe is mine, MIT |

## What it is

There is no AUR package, so the PKGBUILD is mine.
It is pinned to commit `4d3c395` (2026-08-30, the merge of PR #129, "blur cache").
That is newer than the `commit_pins` row of upstream's `hyprpm.toml` for Hyprland v0.56.1 (`e68897e`), so the first build on cabin was the ABI proof; if it fails to load, set `_commit` back to `e68897e`.
About 4,000 lines of C++ in `src/`, loaded into the compositor: read once.

## Runs at build and install time

`arch-meson` and `meson compile`; `meson.build` runs `find` to glob the sources, which I read.
There is no `.install` and no hook.
At run time: `hl.plugin.load("/usr/lib/hyprland/libhyprtasking.so")`.

## Changed from upstream

Against the hyprpm build it replaced: Arch's CFLAGS and `buildtype=plain` instead of hyprpm's `--buildtype=debug`, LTO off, installed under `/usr/lib/hyprland/`, versioned by the Hyprland ABI.

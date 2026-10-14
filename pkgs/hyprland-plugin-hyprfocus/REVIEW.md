# hyprland-plugin-hyprfocus review

[Toolchain](../../docs/toolchain/README.md) › [Packaging](../../docs/toolchain/packaging/README.md) › [The `[dram]` repo](../README.md) › hyprland-plugin-hyprfocus

hyprwm's official `hyprfocus` plugin, which flashes the window that takes focus.

| | |
|---|---|
| Needs | Arch with makepkg and git; the exact Hyprland version it was built against (0.56.2); tested 2026-10 |
| Copy alone | yes: `makepkg -si` here, against the Hyprland you run |
| License | BSD-3-Clause; the recipe: its AUR repository's terms, unstated |

## What it is

It comes from the hyprland-plugins repository at commit `7644cec` (2026-07-15, "chase hyprland"), the commit the AUR split package `hyprland-plugins` 0.56.2-3.1 pins.
One `main.cpp`, compiled with `g++` against the installed `hyprland` headers through pkg-config.
It replaces the hyprpm build of the same plugin: a signed package instead of a root-owned clone built as my user.

## Runs at build and install time

`make -C hyprfocus all`, one `g++` line, read in `hyprfocus/Makefile` at that commit.
There is no `.install` and no hook.
At run time Hyprland loads it into the compositor with `hl.plugin.load("/usr/lib/hyprland/libhyprfocus.so")`, which is the trust decision; the source is 200 lines.

## Changed from the AUR

At AUR commit `f9b2ff8`:

- one package instead of the four-way split: borders-plus-plus, csgo-vulkan-fix and hyprbars are not built
- `depends=('hyprland=0.56.2')`, exact, instead of `>=0.56.0 <0.57.0`
- installed to `/usr/lib/hyprland/` instead of `/usr/lib/`, so both plugins live in one directory
- `cmake` dropped from `makedepends`, because the Makefile does not use it

`pkgver` and `pkgrel` are the AUR's.

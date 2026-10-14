# gamescope-session review

[Toolchain](../../docs/toolchain/README.md) › [Packaging](../../docs/toolchain/packaging/README.md) › [The `[dram]` repo](../README.md) › gamescope-session

The "session plus" launcher for the gamescope Gaming Mode, as OpenGamingCollective (OGC) maintains it.

| | |
|---|---|
| Needs | Arch with makepkg and git; gamescope, bash and systemd at run time; tested 2026-10 |
| Copy alone | yes: `makepkg -si` in this directory |
| License | MIT; the recipe: its AUR repository's terms, unstated |

## What it is

OGC's fork of ChimeraOS's session, whose own repositories went quiet; MIT.
It is pinned to OGC commit `08e65a6` (2026-10-02, 390 commits, no upstream tags).

| File | What it does |
|---|---|
| `/usr/bin/gamescope-session-plus <client>` | starts the user unit and waits |
| `/usr/share/gamescope-session-plus/gamescope-session-plus` | builds gamescope's command line from `OUTPUT_CONNECTOR`, `SCREEN_WIDTH` and `SCREEN_HEIGHT`, `ADAPTIVE_SYNC`, `ENABLE_GAMESCOPE_HDR`, `BACKEND`, `VULKAN_ADAPTER` and others; starts gamescope, mangoapp and the client; falls back after five short sessions |
| `device-quirks` | 306 lines of per-handheld variables keyed on the DMI product name, with nothing for a desktop |
| `gamescope-session-plus@.service`, `gamescope-session.target` | the user units |
| `export-gpu` | an interactive helper that writes `~/.config/environment.d/00-vulkan-device.conf` |
| one gamescope Lua script | turns explicit sync off when `GAMESCOPE_DISABLE_EXPLICIT_SYNC=1` |

## Runs at build and install time

Nothing: `package()` copies `usr/` and the license.

At session time it runs the scripts above as the user, never as root.
The launcher sources, as shell, `/usr/share/…/sessions.d/<client>`, `/etc/gamescope-session-plus/sessions.d/<client>`, `~/.config/gamescope-session-plus/sessions.d/<client>` and each `~/.config/environment.d/*.conf`.
So the per-host values go in the user's `sessions.d/steam` (`modules/gaming.nix`), not in `environment.d`, and do not leak into the desktop session.
It also keeps a fallback counter in `/tmp/chimeraos-short-session-tracker`.

## Changed from the AUR

At AUR `gamescope-session-git` commit `57f121d` (2026-02-09):

- a fixed `#commit=` and `pkgver` instead of the floating HEAD and `pkgver()`, and the name without `-git`, which it `provides` and `conflicts` with;
- no `.install`. The AUR's `post_install` runs `setcap cap_sys_nice=eip /usr/bin/gamescope` on a file the `gamescope` package owns, so the capability disappears at each gamescope update. A capability on the binary also makes the loader drop `LD_PRELOAD` and friends (secure-execution mode). gamescope runs without real-time scheduling here, and the hardware test on cabin says whether that matters.
- `depends` adds `bash` and `systemd`, which it uses directly, and `cp -r --no-preserve=ownership`.

## Origin and community

The commit leaders are KyleGospo ("San Francisco Bay Area") and justradical ("Norway").
OGC is a working group of Universal Blue and Bazzite, ASUS Linux, ShadowBlip, PikaOS and Fyra Labs.
Its community is borderline: several active maintainers and a steward group, but no tags or releases, and it is not in the Arch repos.
The register holds it as `pass-flag` with a six-month re-check, and each bump reads the diff (`PIN`).

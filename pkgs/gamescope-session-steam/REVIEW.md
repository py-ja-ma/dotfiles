# gamescope-session-steam review

[Toolchain](../../docs/toolchain/README.md) › [Packaging](../../docs/toolchain/packaging/README.md) › [The `[dram]` repo](../README.md) › gamescope-session-steam

The Steam half of the gamescope Gaming Mode, OpenGamingCollective's fork of ChimeraOS's.

| | |
|---|---|
| Needs | Arch with makepkg and git; gamescope, `gamescope-session` and bash at run time; Steam; tested 2026-10 |
| Copy alone | yes: `makepkg -si` here, after `gamescope-session` |
| License | MIT; the recipe: its AUR repository's terms, unstated |

## What it is

MIT, pinned to OGC commit `82c45fc` (2026-09-19, 23 commits, no tags).

| File | What it does |
|---|---|
| `sessions.d/steam` | the environment Steam's Deck UI expects, `CLIENTCMD="steam -gamepadui -steamos3 -steampal -steamdeck"`, and a fallback that repairs the bootstrap |
| `gamescope-session-steam.desktop` | the ly session, `Exec=gamescope-session-plus steam` |
| `steamos-session-select` | runs `/usr/lib/os-session-select` from `dram-gaming-mode`, or else `steam -shutdown` |
| `steamos-update`, `steamos-select-branch`, `jupiter-biosupdate` | the shims Steam calls, without root: `steamos-update` exits 7 ("no update") unless `/usr/libexec/ogc/os-update` exists, and the other two do nothing here |
| `steam-http-loader` and its `.desktop` | a Python URL forwarder to `steam://openurl_external/…` |
| `gamescope-mimeapps.list` | the MIME defaults inside gamescope only |

## Runs at build and install time

`prepare()` makes two `sed` edits, listed below.
A `grep` after each makes a moved upstream line fail the build instead of shipping unedited.

## Changed from the AUR

At AUR `gamescope-session-steam-git` commit `11f7efd` (2026-02-09):

1. a fixed `#commit=` and `pkgver`, and the name without `-git`, which it `provides` and `conflicts` with.
2. Not shipped: `/usr/bin/steamos-polkit-helpers/*` and `org.chimeraos.update.policy`.
   The policy grants `allow_any=yes` to run three helpers as root with no password: any user, local or remote, active or not.
   They only forward to OS-update and BIOS hooks this system does not have, so Steam's update, branch and BIOS pages in Gaming Mode report nothing to do; updates come from `dram update`.
3. Upstream's 2026-09-19 commit makes the fallback after five crashes call `steamosctl switch-to-desktop-mode`, from Valve's steamos-manager, which is not installed here.
   This copy calls `steamos-session-select desktop` when `steamosctl` is missing.
4. The session's `Name=` reads "Gaming Mode (gamescope, experimental)", so the ly menu matches [decision 0012](../../decisions/0012-gaming-mode.md).
5. `optdepends` names `steam`, `ttf-dejavu` and `dram-gaming-mode`.

## Origin and community

As `gamescope-session`: KyleGospo leads, with OGC as the steward group.
The register holds it as `pass-flag` with a six-month re-check.

# 0012: Two gaming modes at the login screen, Big Picture in Hyprland by default

[Toolchain › Profiles](../docs/toolchain/profiles/README.md) · accepted 2026-10-11

ly offers a Hyprland Gaming Mode by default and gamescope's as experimental, switched by a polkit helper of my own; the cost is a vendored session pair and a switch to maintain.

## Context

I want the machines to mimic SteamOS: a Gaming Mode beside the desktop. SteamOS builds
Gaming Mode on gamescope + Steam's `-gamepadui`.
As of October 2026, Valve supports AMD only and says NVIDIA support will not arrive before the end of 2026.
gamescope's DRM backend has open bugs on NVIDIA (overlay artifacts #1964, HDR/modeset corruption #1593,
4K corruption #2309), cause acknowledged, no fix. cabin has an RTX 3080 Ti.

## Decision

- ly offers three sessions ([D19](log.md#d19)): **Desktop** (Hyprland), **Gaming Mode** (a Hyprland session
  that launches Steam Big Picture fullscreen — the default gaming entry), and **Gaming
  Mode (experimental)** (gamescope-session + gamescope-session-steam).
- gamescope from extra; the session pair from the OpenGamingCollective forks (active;
  the ChimeraOS originals are stale), vendored and pinned in `pkgs/`.
- Switching is an `os-session-select` of my own (the upstream hook is LightDM/SDDM-only): a
  polkit helper writes a one-shot autologin drop-in for `ly@tty2` and restarts it. No
  permanent autologin; the login keyring stays locked after a switch (accepted).
- Controllers through Steam Input with `game-devices-udev`; xpadneo for Xbox controllers
  over Bluetooth. MangoHud and gamemode stay. Proton-GE / ProtonUp-Qt are opt-in.
- **No Decky Loader** (root daemon, patches Steam through its debug port, AUR-only).
- The NVIDIA driver is not pinned; `steamos-manager` is not used.

## Alternatives weighed

| Option | Why not |
|---|---|
| gamescope Gaming Mode as the default | closest to SteamOS, but the open NVIDIA bugs make it unsafe as the only mode (October 2026) |
| Bazzite / ChimeraOS | not Arch-from-this-repo; ChimeraOS's session repos are stale |
| Big Picture only | loses the gamescope path entirely; it stays, to test as drivers improve |

## Consequences

- Promotion rule: when cabin's T4 test shows gamescope clean on the current driver for
  a month, the experimental session becomes the default.
- The `gaming` role carries Steam (waived, `decisions/0013`) and the NVIDIA userspace
  (waived).

## As built

- **Packages** (`packages/roles/gaming.txt`): `gamescope`, `ntsync-autoload` from the Arch
  repos; from `[dram]`: `gamescope-session` (OGC `08e65a6`) and
  `gamescope-session-steam` (OGC `82c45fc`), pinned commits with real b2sums;
  `dram-gaming-mode`, a package of my own; `xpadneo-dkms` 0.10.4; `jagex-launcher` moved here from every host.
  A `[dram]` name a role lists now installs only with that role (`pkgs/README.md`).
- **Changes to the vendored session pair** (their `REVIEW.md`): no `setcap` on gamescope;
  the ChimeraOS polkit policy that let *any* user run three root helpers is not shipped;
  the five-crashes fallback uses `steamos-session-select desktop` when steamos-manager's
  `steamosctl` is absent; the session is named "Gaming Mode (gamescope, experimental)".
- **Sessions**: ly lists "Desktop" (`dram-desktop`), "Gaming Mode" (`dram-gaming`,
  Hyprland + `~/.config/hypr/gaming.lua`) and the gamescope entry. The two from this repo carry no
  `DesktopNames=`: ly 1.4.1 matches an autologin session by file name, `Name=` or
  `DesktopNames=` (first hit, any case), and Arch ships two entries with
  `DesktopNames=Hyprland`.
- **Switching**: `steamos-session-select` → `/usr/lib/os-session-select` →
  `pkexec /usr/lib/dram/session-switch` (polkit `org.dram.session-select`, active local
  session only) → `/run/dram/ly-next-session` + a transient unit that ends the session and
  restarts `ly@tty2` → `ly-prepare` (an `ExecStartPre` drop-in) sets ly's
  `auto_login_session`/`auto_login_user` for that one start and clears them on the next.
  `/etc/dram/gaming-mode` = `gamescope` is the promotion switch. `system/apply-ly.sh`
  carries the two keys over. Keys: `SUPER+CTRL+G` (desktop, gaming hosts only),
  `SUPER+CTRL+D` / `SUPER+SHIFT+Escape` (Gaming Mode).
- **Per-host gamescope settings**: `dram.gaming.*` → `modules/gaming.nix` →
  `~/.config/gamescope-session-plus/sessions.d/steam` (not environment.d, which would
  leak into the desktop's user units).
- **Checks**: `dram doctor` "gaming mode"; `bin/check.sh` §16 runs
  `tests/gaming-switch.sh` and parses `hypr/*.lua`; `tests/gaming-vm.sh` drives the real
  ly/polkit chain in QEMU with a stand-in compositor. `game-devices-udev` was accepted
  by an Origin ruling on 2026-10-11. Guide: `docs/toolchain/profiles/gaming.md`.

## How it is checked

`bin/check.sh` §16 runs `tests/gaming-switch.sh` (T0: the switch chain against stand-ins) and parses `hypr/*.lua`.
`tests/gaming-vm.sh` drives the real ly and polkit chain in QEMU, by hand.
`dram doctor`'s "gaming mode" section checks the sessions and the switch on a host.

## History

- 2026-10-10: proposed ([D19](log.md#d19)).
- 2026-10-11: accepted and built; the switch test passes, and the switching drill in the VM passes 13 of 13.
- Revisit after cabin's hardware test, under the promotion rule above.

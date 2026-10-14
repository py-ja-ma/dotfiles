# 0016: An EmuDeck-equivalent emulator set, compliant, mostly from Flathub

[Toolchain › Profiles](../docs/toolchain/profiles/README.md) · accepted 2026-10-11 · amended 2026-10-11

The emulators EmuDeck offers, minus the non-free ones, come from Arch, Flathub-verified Flatpaks or `[dram]`; the cost is a Flatpak channel beside pacman.

## Context

I want what EmuDeck includes, so I can emulate every major gaming machine, from dumps of
my own consoles (GameCube, Wii, PS2, PSP, original Xbox, Switch Lite).
EmuDeck itself is a SteamOS installer script; this repo copies its emulator choice and folder
layout, not the script. I scored all 29 EmuDeck entries against the three rules of `decisions/0013`.
About 14 emulators are not in Arch's official repos, and `docs/toolchain/packaging/flatpak.md` limited Flatpak to
three vendor apps.

## Decision

- **Set** ([D28](log.md#d28)): RetroArch with free cores only (Mesen, Nestopia, bsnes, Gambatte,
  SameBoy, Beetle PSX HW, Beetle PCE, BlastEm, Kronos/Yabause, mupen64plus-next…), mGBA,
  Dolphin, PPSSPP, MAME (arcade + Sega Model 2), ScummVM, DOSBox, ares, Stella,
  PCSX2, RPCS3, shadPS4, Vita3K, xemu, Xenia Canary (experimental), Cemu, melonDS,
  Azahar, Flycast, Supermodel, RMG; Steam ROM Manager as the frontend (ES-DE not for now, below).
- **Left out:** DuckStation (CC BY-NC-ND), BigPEmu and Model 2 Emulator (proprietary),
  the non-commercial libretro cores (Snes9x, Genesis Plus GX, PicoDrive, FBNeo,
  FBAlpha2012, MAME 2003-Plus, Opera, Mu, PX68k, QUASI88 — Arch mislabels two of them
  BSD-3, so `dram doctor` uses an allow-list of cores, not license strings), PrimeHack,
  Pegasus, EmuDeck itself, Decky plugins.
- **Switch:** no modchip on the Switch Lite and no Switch emulator for now ([D8](log.md#d8)); console-side homebrew is outside the rules, since it never runs on these PCs ([D20](log.md#d20)).
- **Packaging:** emulators not in extra come from **Flathub-verified** Flatpaks — the
  Flatpak carve-out in `docs/toolchain/packaging/flatpak.md` widens to "vendor binaries + emulators" ([D29](log.md#d29)). Where an
  emulator has no verified Flathub build (Vita3K, Xenia, RPCS3 on 2026-10-11), it is built into
  `[dram]`.
- **Layout:** EmuDeck's tree on the data pool: `/data/emulation/{roms,bios,saves,storage}`
  per `decisions/0011`.
- **Origin:** I accepted the emulators with no published maintainer location (Dolphin, PCSX2, xemu,
  RetroArch, RPCS3, shadPS4, Cemu, melonDS, mGBA, Flycast, MAME, ares, Supermodel, Xenia,
  PrimeHack) as a group on 2026-10-10 (pass-with-flag); the free libretro cores fall under the
  same ruling ([D33](log.md#d33)).

## Consequences

- Dumping uses only my own hardware. Reading unencrypted discs is clean; exploit,
  CFW and modchip steps are a legal grey area under US §1201: documented, and my call.
- Flatpak emulators update outside `dram update`'s pacman step; `dram update` already
  runs `flatpak update`.
- Systems I own no console for get emulators but no BIOS until I have a dump.

## As built

- **Roles**: `emulation` (cabin) and `dump-kit` (cabin, panasonic) added to the host
  files. `packages/roles/emulation.txt`: RetroArch + 14 free cores (the allow-list), Dolphin,
  PPSSPP, MAME, ares, mGBA, ScummVM from `extra`; `[dram]` `rpcs3-bin`, `vita3k-bin`,
  `xenia-canary-bin`. `packages/flatpak/emulation.txt`: the eight Flathub-verified apps
  (PCSX2, xemu, shadPS4, Cemu, melonDS, Azahar, RMG, Steam ROM Manager), verified through
  Flathub's API on 2026-10-11. `dump-kit`: ddrescue, libcdio, mame-tools (chdman),
  dolphin-emu-tool.
- **Flatpak per role**: the app list moved from `APPS=` in `system/flatpak-setup.sh` to
  `packages/flatpak/<role>.txt`; the register reads it. Each emulator gets an override:
  `/data/emulation` granted; host, home, removable media, desktop-entry creation and the
  Discord sockets removed; `devices=all` kept for controllers.
- **`[dram]` packaging**: all three AUR recipes fetched "latest" at build time (one also ran
  the AppImage during the build). The vendored ones pin one release by the sha256 GitHub publishes.
  RPCS3's AppImage carries a DwarFS image that nothing in Arch unpacks, so it is installed
  whole and mounts itself through FUSE. Xenia's and Vita3K's are unpacked with
  `unsquashfs`. Vita3K has only a moving `continuous` release, so its pin breaks on every
  upstream build.
- **ES-DE not for now** ([D32](log.md#d32)): it needs FreeImage, which Arch dropped to the AUR and whose upstream
  has not released since 2018 (open CVEs). Vendoring it, or using ES-DE's AppImage that
  bundles it, fails the Community rule. Steam ROM Manager's emulator parsers put games
  into Steam instead; revisit if ES-DE drops FreeImage.
- **Allow-list**: `dram doctor` ("emulation") warns about any `libretro-*` package not in the
  role, anything with a register `fail` verdict that is installed, and cores RetroArch's
  updater downloaded into `~/.config/retroarch/cores`.
- **Tree**: the desktop preset's `@roms:/data/roms` became `@emulation:/data/emulation`;
  `system/emulation-setup.sh` (role hook) makes EmuDeck's folders, 37 system folders and
  `~/ROMs` (ES-DE's default) owned by the user.
- **Docs**: `docs/toolchain/profiles/emulation.md`, `docs/toolchain/profiles/emulation.md` (PS2, GameCube + Wii, PSP, Xbox, Switch
  Lite), `docs/toolchain/packaging/flatpak.md` widened.
- **Not installed until ruled or decided**: Stella, DOSBox, mednafen and the home-computer
  emulators (not scored); maxcso (no release since 2021; chdman covers it); the Switch ([D8](log.md#d8)).
  redumper and xdvdfs waited on Origin rulings, accepted on 2026-10-11, and are in `[dram]`.

## How it is checked

`bin/check.sh` §15 fails an emulator name without a register verdict and a declared `fail` (DuckStation and the non-commercial cores are `fail` rows).
`dram doctor`'s "emulation" section warns about a libretro core off the allow-list, an installed `fail` name, cores RetroArch downloaded by itself, and a missing `/data/emulation` tree.

## History

- 2026-10-10: proposed ([D28](log.md#d28), [D29](log.md#d29)); the emulator group ruling made.
- 2026-10-11: accepted and built.
- 2026-10-11: amended: no ES-DE for now ([D32](log.md#d32)); the free libretro cores confirmed under the group ruling ([D33](log.md#d33)); redumper and xdvdfs accepted.

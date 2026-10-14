# Emulation

[Toolchain](../README.md) › [Profiles](README.md) › Emulation

EmuDeck's choice of emulators and its folder layout, without EmuDeck's script, and only software that passes the FOSS, Origin and Community rules.
The `emulation` role installs the emulators on cabin; the `dump-kit` role installs the disc tools on cabin and lantern, the machine with the disc drive.

| | |
|---|---|
| Code | `packages/roles/emulation.txt`, `packages/roles/dump-kit.txt`, [`packages/flatpak/emulation.txt`](../../../packages/flatpak/README.md), `dotfiles/.local/share/flatpak/overrides/`, `system/emulation-setup.sh`, `pkgs/rpcs3-bin/`, `pkgs/vita3k-bin/`, `pkgs/xenia-canary-bin/`, `pkgs/redumper/`, `pkgs/xdvdfs/` |
| Runs on | cabin; `dump-kit` on lantern too |
| Needs | the data pool's `@emulation` subvolume, or any directory at `/data/emulation` |
| Decided in | [decision 0016](../../../decisions/0016-emulation-set-and-flatpak.md), [D8](../../../decisions/log.md#d8), [D29](../../../decisions/log.md#d29), [D32](../../../decisions/log.md#d32), [D33](../../../decisions/log.md#d33) |

## What is installed

| System | Emulator | Source |
|---|---|---|
| NES, SNES, Game Boy and Color, PS1, PC Engine, Mega Drive, Saturn, Dreamcast and NAOMI | RetroArch with free cores: Mesen, Nestopia, bsnes, Mesen-S, Gambatte, SameBoy, Beetle PSX HW, Beetle PCE Fast, Beetle SuperGrafx, BlastEm, Kronos, Yabause, Flycast | `extra` |
| N64 | Rosalie's Mupen GUI; the Mupen64Plus-Next core as a fallback | Flathub, verified |
| GBA | mGBA | `extra` |
| GameCube, Wii | Dolphin | `extra` |
| Wii U | Cemu | Flathub, verified |
| DS | melonDS | Flathub, verified |
| 3DS | Azahar | Flathub, verified |
| PSP | PPSSPP | `extra` |
| PS2 | PCSX2 | Flathub, verified |
| PS3 | RPCS3 | `[dram]`: `pkgs/rpcs3-bin`, the official AppImage, pinned |
| PS4 | shadPS4 | Flathub, verified |
| PS Vita | Vita3K | `[dram]`: `pkgs/vita3k-bin`, a pinned CI build |
| original Xbox | xemu | Flathub, verified |
| Xbox 360 | Xenia Canary, experimental on Linux | `[dram]`: `pkgs/xenia-canary-bin` |
| Master System, Game Gear, SG-1000, Mega CD, 32X | ares | `extra` |
| arcade, Neo Geo, Sega Model 2 | MAME | `extra` |
| point-and-click adventures | ScummVM | `extra` |
| Steam shortcuts for all of it | Steam ROM Manager | Flathub, verified |

Flatpak is used only where Arch has no package and Flathub's publisher is verified as the upstream project ([Flatpak](../packaging/flatpak.md)); `packages/flatpak/emulation.txt` lists the ids.
Each emulator Flatpak sees `/data/emulation` and none of the home directory, through its override in `dotfiles/.local/share/flatpak/overrides/`.

| Left out | Why | Instead |
|---|---|---|
| DuckStation (PS1) | a CC BY-NC-ND license, not free software | Beetle PSX HW |
| the Snes9x, Genesis Plus GX, PicoDrive, FBNeo, FBAlpha2012, MAME 2003-Plus, Opera, Mu, PX68k and QUASI88 cores | non-commercial licenses | bsnes or Mesen-S, BlastEm, ares, MAME |
| BigPEmu (Jaguar), Model 2 Emulator | closed source | none, or MAME |
| a Switch emulator | no Switch modchip, decided 2026-10-10 ([D8](../../../decisions/log.md#d8)), and Nintendo's 2026 takedowns | — |
| ES-DE, the frontend | it needs FreeImage, which Arch dropped and whose upstream has had no release since 2018, with unpatched CVEs; I left it out on 2026-10-11 until ES-DE drops FreeImage ([D32](../../../decisions/log.md#d32)) | Steam ROM Manager's emulator parsers and each emulator's own library |
| EmuDeck, Pegasus, Decky plugins, PrimeHack | an installer script, a thin project, a root daemon, and a Dolphin fork that Dolphin covers | — |
| Stella, DOSBox, mednafen, VICE, Hatari, FS-UAE | not scored for Origin yet; each needs my ruling first | — |

Arch's own package metadata calls Genesis Plus GX and PicoDrive "BSD-3", while their upstream licenses forbid commercial use, so a package's license string is not enough.
Only the cores in `packages/roles/emulation.txt` are allowed.
`dram doctor` ("emulation") warns about any other installed `libretro-*` package, anything the register forbids, and cores that RetroArch's online updater downloaded into `~/.config/retroarch/cores`, which are unverified buildbot builds.
Keep RetroArch's core directory at `/usr/lib/libretro`, and do not use its core downloader.

## The ROM tree

`/data/emulation` is the `@emulation` subvolume of the data pool on a desktop install, so a reinstall of the system pool keeps it.
`system/emulation-setup.sh`, a `dram apply` hook, makes EmuDeck's layout, owned by the main user:

```text
/data/emulation/
  roms/<system>/   nes snes gb gbc gba n64 gc wii wiiu nds n3ds psx ps2 ps3 ps4 psp psvita
                   xbox xbox360 mastersystem gamegear sg-1000 megadrive segacd sega32x saturn
                   dreamcast naomi atomiswave model2 model3 arcade neogeo pcengine pcenginecd
                   supergrafx scummvm
  bios/            system files, one folder per emulator where it wants one
  saves/  storage/  tools/
~/roms -> /data/emulation/roms
```

Point each emulator at it once, at its first start:

| Emulator | Setting |
|---|---|
| RetroArch | Settings › Directory: System/BIOS `/data/emulation/bios`, Saves `/data/emulation/saves/retroarch`, Core `/usr/lib/libretro` |
| PCSX2 | Settings › BIOS › folder `/data/emulation/bios/ps2`; Game list › add `/data/emulation/roms/ps2` |
| xemu | Settings › System: the MCPX boot ROM, flash ROM and HDD image under `/data/emulation/bios/xbox` |
| Dolphin, PPSSPP, RPCS3, Vita3K, Xenia, Cemu, melonDS, Azahar, RMG, shadPS4 | the matching `roms/<system>` folder as a game directory; system files under `bios/<emulator>` |

## Into Steam and Gaming Mode

Steam ROM Manager, in the app menu, adds games as non-Steam shortcuts with artwork, so they show up in Big Picture and in both Gaming Modes ([Gaming](gaming.md)).
Use its per-emulator parsers, with the ROM folder `/data/emulation/roms/<system>`.
Its override lets it write Steam's shortcut file and read the ROM tree, nothing else.
For a gamepad, keep Steam Input on unless an emulator maps the pad itself, as Dolphin does with the GameCube adapter.

## Your own consoles

Each console I own needs its own route to the files an emulator wants and to the games.
The cheapest and cleanest come first: PS2, then Wii and GameCube, PSP, Xbox, and the Switch Lite last, not planned ([D8](../../../decisions/log.md#d8)).

| Console | Emulator | Needs from the console | Hardware beyond the console |
|---|---|---|---|
| PS2 | PCSX2 | the BIOS | a FreeMcBoot card or a burned DVD-R; lantern's disc drive |
| GameCube and Wii | Dolphin | nothing | an SD card or USB disk on the Wii |
| PSP | PPSSPP | nothing | a Memory Stick, a USB cable |
| original Xbox | xemu | the MCPX boot ROM, a flash BIOS, an HDD image | a modchip, with soldering |
| Switch Lite | none | keys and firmware | a Picofly modchip, not planned |

The legal line in the US, as fact and not legal advice: reading an unencrypted disc on a PC drive and keeping the copy private is the clean case.
Anything that first defeats a protection is a gray area under 17 U.S.C. §1201, which has no exemption for personal backups.
That covers running unsigned code on the console (FreeMcBoot, a Wii softmod, PSP custom firmware, a modchip) and decrypting with extracted keys.
**Never** share BIOS files, keys or dumps.

### PS2

PCSX2 (Flathub `net.pcsx2.PCSX2`, verified) needs the BIOS from your own PS2, because it has no free replacement.
PS2 discs are unencrypted CDs and DVDs, so a normal PC drive reads them.

To dump the BIOS, run homebrew on the PS2 once, then *biosdrain* writes it to a USB stick (MBR and FAT32) or over the network.
Homebrew starts from FreeMcBoot on a memory card (about $15 pre-made, for fat and most slim models), from FreeDVDBoot on a burned DVD-R (free, for many slims and some fats), or from Fortuna or OpenTuna on slims.
Switch an installed modchip off first: it can corrupt the dump.
biosdrain writes `.rom0`, `.rom1`, `.nvm` and others.
Check them against the Redump SHA-1 list, copy them to `/data/emulation/bios/ps2`, and point PCSX2's BIOS folder there.
`nvm` is unique to the console, so keep a copy offline.

Discs, on lantern:

```sh
ddrescue -b 2048 -r3 /dev/sr0 game.iso game.map                 # a DVD: retries bad sectors, resumable
sudo redumper cd --drive=/dev/sr0 --image-name=game            # a CD game: raw sectors and subchannels, Redump-grade
chdman createdvd -i game.iso -o game.chd                        # smaller; createcd from a .cue
```

The library is `/data/emulation/roms/ps2`.

### GameCube and Wii

Dolphin (`dolphin-emu` from `extra`) needs nothing from the console: its DSP ROMs and fonts ship with it, and the GameCube IPL (`IPL.bin`) only adds the boot animation.
A PC drive cannot read these discs, so they are read on the Wii with CleanRip.

1. Softmod the Wii with the Nintendo Homebrew guide, wii.hacks.guide: HackMii, then the Homebrew Channel and BootMii, then Priiloader.
   Make the NAND backup it asks for and keep it offline, because it is unique to the Wii.
   The SD card needs 2 GB or more, FAT32.
2. Rip with CleanRip from the Homebrew Channel to the SD card or to a USB hard disk or SSD, FAT32, because flash sticks are unreliable.
   A single-layer Wii disc needs 4.4 GiB free, a dual-layer one 7.9 GiB.
   GameCube discs rip the same way on a Wii with GameCube ports, so not on a Wii Mini, a Family Edition or a Wii U.
3. Shrink to RVZ, Dolphin's lossless format: right-click › Convert in Dolphin, or `dolphin-tool convert -f rvz -c zstd -l 5 -i game.iso -o game.rvz` from the dump-kit role.

The libraries are `/data/emulation/roms/gc` and `/data/emulation/roms/wii`.
The `dolphin-emu` package ships the udev rule for the official GameCube USB adapter and the DolphinBar.
With Steam running, turn Steam Input off for Dolphin while the adapter is in use, or both read it.
A Wii Remote pairs over Bluetooth.

### PSP

PPSSPP (`ppsspp` and `ppsspp-assets` from `extra`) needs nothing from the console: it emulates at a high level, and free replacement fonts ship with it.
Games come from UMDs, copied over USB from a PSP running custom firmware.

Update the PSP to official firmware 6.61, then install ARK-5 (GPL-3.0), the successor of ARK-4, which was archived on 2026-08-02.
A PSP Go has no UMD drive.
You need a working battery, a Memory Stick Pro Duo or a microSD adapter, and a mini-USB cable.
In the custom firmware's menu set USB Device to UMD Disc, connect USB, and copy the ISO that appears.
PPSSPP reads ISO, CSO and CHD; `chdman createdvd -i game.iso -o game.chd` from the dump-kit role makes the smaller CHD.
The library is `/data/emulation/roms/psp`.

### Original Xbox

xemu (Flathub `app.xemu.xemu`, verified) needs three files:

- the MCPX boot ROM, `mcpx_1.0.bin`, MD5 `d49c52a4102f6df7bcf8d0617ac475ed`
- a flash BIOS: an unmodified retail BIOS does not boot games, so a modified retail or debug BIOS, commonly "COMPLEX 4627", from a 1.0 Xbox
- an HDD image: xemu ships a clean 8 GB one, or `dd` your own unlocked disk

The MCPX ROM comes from hardware only.
A modchip flashed with a Cromwell payload built by `mcpx-attack`, with the stock BIOS, boots and shows the ROM on screen (Xbox-Scene write-up, 2023).
That needs soldering or a clip-on LPC adapter, and it is the hardest file of all six consoles.
xemu's project does not explain dumping, and the modified BIOS derives from Microsoft code: you supply it yourself, and it stays out of any package and any share.

Games come off over FTP from an Xbox running a custom dashboard, or from a Kreon- or OmniDrive-flashed PC drive with redumper.
Then repack to XISO with `xdvdfs pack game.iso game.xiso.iso`.
redumper and xdvdfs are both in the dump-kit role.
xemu does not read CHD.
The files go to `/data/emulation/bios/xbox`, the games to `/data/emulation/roms/xbox`.

### Switch Lite

No software exploit exists for the Lite (Mariko).
It needs a Picofly modchip soldered to the board, then Atmosphère and hekate, Lockpick_RCM for `prod.keys`, and nxdumptool for games and firmware.
On 2026-10-10 I decided against a modchip ([D8](../../../decisions/log.md#d8)), so no Switch emulator is installed.
Each current one (Eden, Ryubing, Citron NEO) was named in Nintendo's 2026 DMCA notices, their Origin is unclear, and Picofly's firmware license could not be confirmed.
If that changes, the decision comes back with a waiver row.
**Never** download keys or firmware: they must come from your own console.

## Keep the irreplaceable files

BIOS images, keys and dumps unique to a console (a PS2's `nvm`, an Xbox's MCPX ROM, a Wii's NAND backup) cannot be dumped again if the console dies.
Backups are paused until the NAS ([decision 0014](../../../decisions/0014-backups-paused-until-nas.md)), so copy `/data/emulation/bios` and each console's NAND and keys backup to the offline drive yourself.
**Never** put them in git or any shared place.

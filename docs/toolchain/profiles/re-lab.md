# Reverse-engineering lab

[Toolchain](../README.md) › [Profiles](README.md) › Re-lab

The tools to take apart console software and firmware, read and write flash chips, and watch buses, each scored against the three rules of [decision 0013](../../../decisions/0013-software-rules-and-waivers.md).

| | |
|---|---|
| Code | `packages/roles/re-lab.txt`, `packages/uv/re-lab.txt`, `packages/ghidra-extensions.tsv`, `dotfiles/.local/bin/re-lab-tools`, `system/re-lab-setup.sh`, `system/udev/70-dram-re-lab.rules`, `pkgs/imhex-bin/`, `pkgs/uefitool-ng/` |
| Runs on | cabin and lantern; thermos-wsl; on Windows a list for thermos, not rendered yet |
| Needs | Ghidra 12.1 with JDK 21, uv, the `uucp` group |
| Decided in | [D21](../../../decisions/log.md#d21) |

| Job | Tools | From |
|---|---|---|
| Disassemble, decompile | Ghidra with JDK 21, radare2, ImHex | `extra`; ImHex from `[dram]` |
| Debug, trace | gdb with pwndbg, strace, qemu-user, qemu-system-ppc for the Gekko and Broadway | `extra` |
| Exploits, CPU emulation, Java and Android | pwntools, unicorn with its Python bindings, jadx | `extra` |
| Firmware images | UEFITool, UEFIExtract and UEFIFind, release A75 | `[dram]` |
| JTAG, SWD, serial | OpenOCD, minicom | `extra` |
| Binaries and firmware | binwalk, YARA, capstone | `extra` |
| Flash chips, buses | flashrom, sigrok-cli, PulseView, the fx2lafw firmware | `extra` |
| Instrumentation, symbolic execution | frida-tools 14.11.0, angr 10.0.3 | `uv tool`, per user |
| Console loaders for Ghidra | GameCube and Wii (Cuyler36), the PS2's Emotion Engine (chaoticgd, built for 12.1.2), the PSP's Allegrex (kotcrab), each Apache-2.0 | per user |

radare2 replaced Rizin and Cutter on 2026-10-10, when both failed the Origin rule ([D21](../../../decisions/log.md#d21)).
Arch's `extra/cutter` is a TCP connection cutter, unrelated to Rizin's GUI.

## Use it

The per-user half runs once per machine, and again after each Ghidra update:

```sh
re-lab-tools   # uv tools from packages/uv/re-lab.txt, Ghidra extensions from packages/ghidra-extensions.tsv
```

It checks each extension's sha256 before unpacking it into `~/.config/ghidra/ghidra_<version>_PUBLIC/Extensions`; enable it in Ghidra under *File › Install Extensions*.
An extension built for another Ghidra major.minor is skipped with a note: bump its row once upstream publishes a matching build.
The GameCube and PSP loaders are built for 12.1, and Arch ships Ghidra 12.1.2, so Ghidra may ask before loading them, or refuse.
The Xbox loader (`ghidra-xbe`) states no license, so it stays out until it does.

A serial console: `minicom -D /dev/ttyUSB0 -b 115200`.

| Need | How |
|---|---|
| Serial ports (`/dev/ttyUSB*`, `/dev/ttyACM*`: UART consoles, the Tigard's UART, a Pico running serprog) | the main user is in `uucp`, added by `system/re-lab-setup.sh` and in effect from the next login; Arch has no `dialout` |
| USB flash programmers (Tigard or FT2232H, FT232H, CH341A, CH347) | `uaccess` in `/etc/udev/rules.d/70-dram-re-lab.rules`, from `system/udev/`: the user at the machine gets the device, not a user over SSH |
| Logic analyzers | libsigrok's own `uaccess` rules |
| `flashrom -p internal`, the machine's own BIOS chip | root, and Secure Boot's lockdown may refuse it: read the chip with an external clip instead |

**Never** create a `plugdev` group: Arch has none, and udev ignores a rule that names an unknown group.

## Hardware

What I buy for the bench:

| Tier | Item | Notes |
|---|---|---|
| Must | Tigard (FT2232H; 1.8, 3.3 and 5 V; UART, SPI, JTAG, SWD and I2C) | flashrom's `ft2232_spi`; open hardware |
| Must | a SOIC-8 test clip with a 1.8 V adapter | check the chip's voltage on its datasheet first |
| Should | a Raspberry Pi Pico running `pico-serprog` | 3.3 V chips only |
| Should | an FX2 8-channel logic analyzer at 24 MHz | sigrok's `fx2lafw`; usually unbranded clones |
| Could | a CH341A, revision 1.6 or later with a voltage selector | older black boards put 5 V on 3.3 V chips |

Not every console uses SPI NOR flash: the Xbox (LPC, TSOP), the GameCube and Wii, and the PS2 each have their own route ([Emulation](emulation.md#your-own-consoles)).

## Console SDKs

Homebrew toolchains run in containers, rootless Podman by default ([Development](../development/README.md#containers)): `pspdev/pspdev`, the ps2dev image, devkitPro's images.
Do not add devkitPro's pacman repositories to a host: they put a third-party signing key on the system package manager, and libogc's license is unclear.

## Learning

- pwn.college, which is free.
- The *Nightmare* course, with open-source tools only: Ghidra, gdb, pwntools, angr.
- Ghidra's own `GhidraClass` material, in `/opt/ghidra/docs`.
- WiiBrew's "Using Ghidra with the Wii".
- *Hacking the Xbox* by Andrew Huang, which No Starch released free.

Malware samples belong in a homelab VM, never on cabin.

## Limits

- On Windows the lab lives in thermos' WSL clone, which reaches the USB programmers through usbipd-win; that waits for a Community waiver ([D118](../../../decisions/log.md#d118)).
- System Informer stands in for Sysinternals' Process Explorer and TCPView on Windows ([D111](../../../decisions/log.md#d111)).

# Platforms

[Organization](../README.md) › Platforms

The operating systems this repo installs and keeps in step.
Arch Linux runs on the machines themselves, and Windows 11 is rendered from the same flake.
Each Windows PC carries an Arch clone in WSL 2, the Mac is where I edit and release, and cabin's bench disk holds the test systems.
Arch is the primary OS.
Every other system on a machine boots from its own firmware entry and leaves Arch's boot order alone.

| Division | Covers |
|---|---|
| [Arch Linux](arch/README.md) | the disk installer and first-boot bootstrap, roles and package lists, the system hooks `dram apply` runs, the boot chain, the host records |
| [Windows](windows/README.md) | the flake's Windows renderer, `dram.ps1` on the PC, debloat and autostart, the boot guard, the case display, installing a Windows PC |
| [WSL](wsl/README.md) | the Arch clone in WSL 2 on cabin's Windows and on thermos |
| [macOS](macos/README.md) | lodge, the Mac where I edit, check and release |
| [Bench OSes](bench/README.md) | cabin's test-system disk, the systems on it and `dram boot-to` |

## The fleet

The names are warm cabin things: a cabin, a campfire, a lantern, a thermos, a lodge.
A machine this repo manages has a host file, and its login is that file's `dram.user`.

| Name | Machine | OS | Login | Job | State (2026-10-13) |
|---|---|---|---|---|---|
| cabin | desktop: MSI B550 (MS-7C56), Ryzen 9 5950X, RTX 3080 Ti; two 2 TB NVMe disks, a 2 TB and a 1 TB SATA SSD | Arch on the NVMe disks; Windows 11 alone on the 1 TB SSD; the bench disk for Debian, Fedora and NixOS | pj | every role; builds the `[dram]` package repo; the test bench for every OS | Arch reinstalled from a blank disk on 2026-10-11; Windows converged from the flake on 2026-10-12 |
| cabin-win | cabin's Windows 11 | Windows 11 Pro | pj | gaming, the Windows look, the native half of the work roles | rendered from `windows/hosts/cabin-win.nix` |
| cabin-wsl | Arch in WSL 2 on cabin-win | Arch (the clone) | pj | the terminal half of coding, homelab, work and college | converged 2026-10-12 |
| lantern | travel laptop, Intel TigerLake (it was called panasonic) | Arch (LUKS2 + TPM2) | ranger | desktop, gaming, dump-kit, re-lab, sysadmin, dev, office, telephony | waiting for its reinstall; `hosts/lantern/` still holds the old install's records |
| thermos | Lenovo ThinkPad L14 Gen 1 AMD, travel | Windows 11 Pro | pj | the travel Windows PC | reviewed 2026-10-12; its reset from this repo is planned |
| thermos-wsl | Arch in WSL 2 on thermos | Arch (the clone) | pj | coding, homelab, re-lab, work and college in a terminal | planned, after thermos' reset |
| lodge | MacBook Pro | macOS | pj | edits, checks and releases this repo; runs the VM tests | managed by hand |
| campfire | the recorder: 32 GB RAM, RTX 3060, a capture card | Arch | pj | records what cabin shows | not installed yet |
| smores (proposed) | Steam Deck | SteamOS | deck | as much of SteamOS as Home Manager can declare | much later |

Spare names for the next machines: kindling, ember, flannel, quilt, cocoa.
Each Arch host's hardware, disks and quirks are in its README: [cabin](../../hosts/cabin/README.md), [lantern](../../hosts/lantern/README.md), [campfire](../../hosts/campfire/README.md).
The clones have theirs too: [cabin-wsl](../../hosts/cabin-wsl/README.md), [thermos-wsl](../../hosts/thermos-wsl/README.md).
What `dram harvest` writes into those directories is in [hosts/README.md](../../hosts/README.md).

## Rules

- Arch owns the boot order.
  Windows and the bench systems start from their own firmware entries, and rEFInd goes back to the front of the boot order at every boot of Arch and of Windows ([decision 0017](../../decisions/0017-cabin-bench-layout.md), [decision log](../../decisions/log.md#d67)).
  `dram doctor --boot` warns when rEFInd is not first, and `dram doctor` on the PC checks the boot guard's task.
- A host is a host file with its roles on one line, and its hardware is detected ([decision 0009](../../decisions/0009-roles-and-host-shape.md)).
  `bin/check.sh` §11 fails a host file without `hostName`, `roles`, `isLaptop` and `gpu`, and §2 fails a host file without its `hosts/<host>/` directory.
- The Mac edits, checks and releases.
  The hosts apply what a release brings: `dram update` on Arch and in the clones, `dram apply` through `dram.ps1` on Windows ([decision 0001](../../decisions/0001-approach.md)).
  Nothing checks this rule; the Mac has no Nix and no pacman, so it cannot break it by accident.
- Windows is rendered from the flake, and the committed build matches its inputs ([decision 0020](../../decisions/0020-windows-from-the-flake.md)).
  `bin/check.sh` §19 fails a stale build, and `nix flake check` compares the build with a fresh render.
- A WSL clone gets the user layer and the command-line roles, never the system layer ([decision 0021](../../decisions/0021-wsl-clone.md)).
  `bin/check.sh` §21 fails a clone whose plan holds a hardware or `[dram]` package.

## Decisions

| Record | Decision | Status |
|---|---|---|
| [0001](../../decisions/0001-approach.md) | Documented manifests on Arch, not a NixOS rebuild | accepted 2026-10-05 |
| [0004](../../decisions/0004-module-split.md) | Host flags over per-host copies; one module per concern | accepted 2026-10-06 |
| [0006](../../decisions/0006-flake-layout.md) | Hosts come from the directory; outputs per system; lints as checks | accepted 2026-10-06 |
| [0008](../../decisions/0008-system-layer-converge.md) | `dram apply` converges the system layer | accepted 2026-10-10 |
| [0009](../../decisions/0009-roles-and-host-shape.md) | A host is a hostname, detected hardware and a list of roles | accepted 2026-10-10 |
| [0010](../../decisions/0010-install-path.md) | Install with this repo's own pacstrap script, not archinstall | proposed; built 2026-10-11 |
| [0011](../../decisions/0011-disk-boot-secure-boot-snapshots.md) | btrfs and snapper, systemd-boot with signed UKIs, Secure Boot with sbctl | accepted 2026-10-11 |
| [0017](../../decisions/0017-cabin-bench-layout.md) | cabin is the bench: one operating system per disk | accepted 2026-10-11 |
| [0018](../../decisions/0018-one-flake-every-machine.md) | One flake for every machine, later | proposed 2026-10-11 |
| [0020](../../decisions/0020-windows-from-the-flake.md) | Windows from the flake | accepted 2026-10-12 |
| [0021](../../decisions/0021-wsl-clone.md) | Arch in WSL 2: a clone of the user layer and the command-line roles | proposed; built 2026-10-12 |

The smaller decisions behind each division are rows of the [decision log](../../decisions/log.md).

## Open

- lantern: the reinstall from this repo (2026-10-13).
- thermos: the reset from this repo, then thermos-wsl ([Windows](windows/README.md#thermos)).
- campfire: not installed (2026-10-13).
- The bench disk: one ESP per system and the three installs ([Bench OSes](bench/README.md)).
- Windows: DSC 3's own resources instead of `PSDscResources`, and apps installed only after a VM proof ([renderer](windows/renderer.md#not-yet)).
- lodge: nix-darwin, if [decision 0018](../../decisions/0018-one-flake-every-machine.md) is accepted.

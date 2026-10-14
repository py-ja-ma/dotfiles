# Bench OSes

[Platforms](../README.md) › Bench OSes

cabin is the bench: one operating system per disk, so no installer is ever pointed at another system's boot partition.
Arch has the two NVMe disks and Windows 11 the 1 TB SATA SSD; the 2 TB SATA SSD holds the test systems: Debian, Fedora and NixOS, with a spare slot for the next one.
This repo manages Arch and Windows; the test systems stay stock, which is the point of a test bench.

| | |
|---|---|
| Code | `system/bench-disk.sh`; `install/presets/bench.env` is Arch's own layout ([Install](../arch/install.md)) |
| Runs on | cabin |
| Needs | sgdisk and mkfs.fat from Arch, each system's own installer on a USB stick |
| Decided in | [decision 0017](../../../decisions/0017-cabin-bench-layout.md) |

| Disk | Holds |
|---|---|
| NVMe, the CPU's slot (PCIe 4), Samsung 990 PRO 2 TB | Arch: the ESP, the system pool, the data pool |
| NVMe, the chipset's slot (PCIe 3), Samsung 990 EVO Plus 2 TB | Arch's work pool |
| SATA, Samsung 870 EVO 2 TB | the bench: Debian, Fedora, NixOS, a spare slot |
| SATA, Crucial MX500 1 TB | Windows 11 alone, with its own ESP ([Windows](../windows/README.md)) |

`cat /sys/class/nvme/nvme*/device/current_link_speed` tells the NVMe slots apart: 16.0 GT/s is the CPU's.
`lsblk -do NAME,SIZE,MODEL,SERIAL,TRAN` and `ls -l /dev/disk/by-id/ | grep -v part` give the names to type into an installer.

## Lay out the bench disk

From Arch:

```sh
sudo bash ~/git/dotfiles/system/bench-disk.sh --dry-run --disk /dev/disk/by-id/ata-<2 TB SSD>
sudo bash ~/git/dotfiles/system/bench-disk.sh --disk /dev/disk/by-id/ata-<2 TB SSD>
```

It writes a GPT with `bench-esp` (2 GiB, FAT32, label BENCH-ESP), then `bench-debian`, `bench-fedora` and `bench-nixos` (500 GiB each, `--slot-gib` changes that) and `bench-spare` with the rest.
It lists the disks first, refuses Arch's or Windows' disk, and asks for the disk's serial number.

## Install the systems

Boot each installer from USB and choose manual partitioning on the 2 TB SATA SSD only:

| OS | Root | EFI |
|---|---|---|
| Debian | `bench-debian`, ext4 or btrfs, mounted at `/` | `bench-esp`: "use as EFI System Partition", don't format |
| Fedora | `bench-fedora`, btrfs, mounted at `/` | `bench-esp` mounted at `/boot/efi`, reformat unchecked |
| NixOS | `bench-nixos`, mounted at `/mnt` | `bench-esp` mounted at `/mnt/boot`; systemd-boot or lanzaboote in `configuration.nix` |

Each registers its own firmware boot entry.
Debian and Fedora boot with Secure Boot on, through Microsoft's signed shim.
NixOS has no signed path of its own: lanzaboote with a key enrolled from Arch, or Secure Boot off while it boots; try lanzaboote in a VM first.

## Switching

```sh
dram boot-to list          # the firmware's entries; "(this Arch)" marks home
dram boot-to fedora        # reboot once into Fedora; the next boot is Arch again
dram boot-to windows
```

Or the firmware's boot menu at power-on: F11 on cabin.

## What lives where

Arch's data pool (`/data/games`, `/data/emulation`, `/data/recordings`) and work pool (`/data/vm`, `/data/ml`, `/data/scratch`, containers) are separate filesystems, so an Arch reinstall could keep them.
`install/arch-install.sh` still wipes every disk it is given, so copy what matters off first ([handbook chapter 5](../../records/handbook/05-backup-restore.md)).
The test systems keep their files on their own partitions; to share files between them, use `bench-spare` or the network, never Arch's pools.

## Planned

None of this is built yet ([decision log](../../../decisions/log.md#d81), open):

- one ESP per test system instead of the shared BENCH-ESP, since Fedora's shim rewrites `\EFI\BOOT\BOOTX64.EFI` on every update and the NixOS installer clears the ESP it is given;
- Arch owns the boot order on the bench too: each system runs the same guard that puts rEFInd first, and rEFInd gets a tile for each;
- the installs rehearsed in a KVM VM on Arch with the disk passed through;
- NixOS signing with its own db key, appended from Arch ([decision log](../../../decisions/log.md#d82));
- Home Manager on each test system, the first step of [decision 0018](../../../decisions/0018-one-flake-every-machine.md).

## Status

As of 2026-10-13 the bench disk is blank: Arch and Windows are installed, and the test systems wait for the per-system ESPs.
The case display stays dark on the test systems: they would need its program too.

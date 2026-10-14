# 0017: cabin is the bench, one operating system per disk

[Platforms › Bench OSes](../docs/platforms/bench/README.md) · accepted 2026-10-11 · amended 2026-10-12

Each operating system on cabin owns a disk and boots from its own ESP, and this repo manages only Arch there; the cost is four disks and the firmware menu or rEFInd to switch.

## Context

I started both machines fresh on 2026-10-11. cabin becomes the big mother bench: every role, and a
bare-metal machine to learn every OS and to test products and tutorials on Windows, Arch,
Debian, Fedora and NixOS. It has two 2 TB NVMe disks, a 2 TB SATA SSD and a 1 TB SATA SSD.
Windows is waived (FOSS rule) because not everything runs on Linux ([D148](log.md#d148)).

## Decision

| Disk | Holds |
|---|---|
| NVMe 1 (2 TB) | Arch: its own ESP (4 GiB at /efi), a 512 GiB btrfs system pool with snapshots, a data pool on the rest (games, the emulation tree, recordings) |
| NVMe 2 (2 TB) | Arch's work pool: VM images (nocow), ML models and datasets, containers, scratch for product tests |
| SATA 2 TB | the test bench: one shared 2 GiB ESP (`BENCH-ESP`), Debian, Fedora, NixOS (~500 GiB each), a spare slot for the next distro |
| SATA 1 TB | Windows 11 alone, with its own ESP |

- **No shared ESP with Arch.** Arch's boot partition, systemd-boot, signed UKIs and snapshot
  entries live on NVMe 1 and no other installer is ever pointed at it.
- **Switching:** Arch's menu shows Arch and its snapshots. Every other OS boots from the
  firmware menu or `dram boot-to windows|debian|fedora|nixos` (a one-time `BootNext`).
- **Install order:** Windows first, on its disk alone (Windows Setup puts its boot files on
  any ESP it finds); Arch with `install/arch-install.sh --preset bench --disk <NVMe 1>
  --work-disk <NVMe 2>`; then `system/bench-disk.sh` lays out the SATA 2 TB disk from Arch;
  then Debian, Fedora, NixOS onto their labelled partitions, each mounting `BENCH-ESP`
  unformatted.
- **Secure Boot** stays on: Debian and Fedora boot through Microsoft-signed shim (the
  enrolment keeps Microsoft's keys), Windows likewise. NixOS has no signed path of its own:
  lanzaboote signs with a copy of my db key, or Secure Boot is switched off to boot it —
  decided when NixOS goes on (docs/platforms/bench/README.md).
- **What this repo manages** on cabin: Arch only. The other systems stay stock — that is
  the point of a test bench. One flake for every machine is a later step (`decisions/0018`).

## Alternatives weighed

| Option | Why not |
|---|---|
| All Linuxes on NVMe 1 sharing Arch's ESP (the first sketch) | three installers would each have to be told not to touch Arch's boot loader; one mistake breaks Arch's boot |
| Windows on an NVMe | faster Windows, but Windows here is for testing, not gaming; it keeps the work pool on fast storage |
| A boot manager that scans every ESP (rEFInd) | the firmware menu and `BootNext` do the job without scanning; rEFInd came back on 2026-10-12 as the themed front menu, with fixed entries and Windows started through its firmware entry |

## Consequences

- `install/arch-install.sh` takes `--work-disk` (same safety: listed, Windows refused, the
  serial typed); `install/presets/bench.env`; `tests/t2-vm.sh --bench` installs both disks.
- The data that must survive an Arch reinstall lives on the data and work pools; the test
  bench OSes keep their own data on their own partitions.

## Amendments

Windows Setup did put its boot files on Arch's ESP after all.
On 2026-10-12 Windows got its own ESP on its own disk, made in place without a reinstall, and its old files left Arch's ESP ([D65](log.md#d65), [0023](0023-windows-own-esp-and-boot-order.md)).
rEFInd is the front menu again since 2026-10-12, in front of systemd-boot ([0011](0011-disk-boot-secure-boot-snapshots.md)): Arch, Arch LTS, Windows by its firmware entry, and the snapshots.

Proposed for the bench, open: one ESP per OS instead of the shared `BENCH-ESP`, Arch owning NVRAM, installs done in a VM, in the order Debian, NixOS, Fedora 45 ([D81](log.md#d81)); NixOS signing with its own db key ([D82](log.md#d82)).
Decided: the bench starts on the open-source nouveau GPU driver ([D83](log.md#d83)).

## How it is checked

`install/arch-install.sh` refuses a disk carrying NTFS, BitLocker or a Windows ESP and wants its serial typed; `tests/t2-vm.sh --bench` installs across two disks in QEMU, by hand.
`dram doctor --boot` warns when Windows' boot files reappear on Arch's ESP or no NVRAM entry starts Windows' own ESP.

## History

- 2026-10-11: accepted: I chose the layout; the Arch half passes the VM install test with `--bench`.
- 2026-10-12: amended: Windows' own ESP made in place ([0023](0023-windows-own-esp-and-boot-order.md)); rEFInd in front again ([0011](0011-disk-boot-secure-boot-snapshots.md)); the bench changes above proposed.

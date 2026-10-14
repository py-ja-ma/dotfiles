# 0011: btrfs with bootable snapshots, signed UKIs, and Secure Boot with my keys and Microsoft's

[Security › Boot trust](../docs/security/boot-trust/README.md) · accepted 2026-10-11 · amended 2026-10-12

Every Arch host gets btrfs with snapshots it can boot, signed UKIs, and Secure Boot with my own keys beside Microsoft's, and only the laptop is encrypted; the cost is new code on the boot path and keys that have to be kept.

## Context

I want SteamOS-like safety on every machine: a snapshot before every update, and a way back from the boot menu.
I also want Secure Boot on every machine, with cabin dual-booting Windows.
In 2026-10 the hosts ran ext4 (cabin) and LVM with ext4 (the laptop), rEFInd with a GRUB fallback, and no Secure Boot.
What I read on Secure Boot and on filesystems pointed to one design.
Its main problem: kernels on the ESP are not inside a root snapshot, so a rolled-back root can boot a mismatched kernel.

## Decision

| Part | Decision |
|---|---|
| Filesystem | btrfs everywhere, with flat subvolumes: `@`, `@home`, `@snapshots`, `@home_snapshots`, `@var_log`, the pacman cache, `@flatpak`, `@sbctl`, and `@containers` and `@swap` where used. `noatime,compress=zstd:1,discard=async`, no quotas, a monthly scrub. Desktops get two pools, about 256 GiB for the system and a data pool for games, ROMs, ML data, VM images and recordings, so a reinstall keeps the data. |
| Snapshots | snapper: root keeps 12 plus 6 "important" and no timeline; `/home` a light daily and weekly config. |
| Boot | a 4 GiB ESP at `/efi`, systemd-boot, signed UKIs. A hook in the repo builds a signed UKI for each kept snapshot from that snapshot's own kernel and initramfs, and `dram rollback --system N` restores a snapshot. |
| Secure Boot | keys made with sbctl and enrolled with Microsoft's and the firmware vendor's. cabin's 5950X has no integrated GPU, and a rejected GPU option ROM means no display, so never `--yolo`. `/var/lib/sbctl` is its own subvolume and is exported offline. |
| Encryption | LUKS2 on the laptop only, unlocked by the TPM2 (PCR 7) and a PIN, with the recovery key in Proton Pass ([D3](log.md#d3)); the desktops unencrypted. Hibernation on the laptop; Arch sets no lockdown, so never set `lockdown=`. |
| Windows on cabin | on its own disk with its own ESP, started from its firmware entry and never chain-loaded; BitLocker suspended around any key change. |
| NVIDIA | the prebuilt `nvidia-open` for each kernel instead of DKMS ([D18](log.md#d18)). |

## Alternatives

| Option | Why not |
|---|---|
| Limine with limine-snapper-sync | the runner-up: snapshot boot out of the box, but AUR-only tooling with one maintainer, and fragile reports under Secure Boot |
| GRUB with grub-btrfs | snapshot menus work, but no signed per-snapshot UKIs, and `/boot` inside btrfs complicates Secure Boot |
| rEFInd with refind-btrfs | the same gap; refind-btrfs is thinly maintained |
| Timeshift | GUI-first, with no pacman integration worth having; btrbk stays the choice for the NAS |
| one pool on the desktops | simpler, but a reinstall or a full disk takes the games and datasets with it |

## Consequences

- The per-snapshot UKI hook is new code on the boot path, so the VM install and rollback tests had to pass before a real machine depended on it.
- fwupd's db and dbx updates are applied by hand, never automatically.
- The Secure Boot keys sit on the disk they protect; keeping `PK.key` and `KEK.key` offline is still open ([D72](log.md#d72)).
- The laptop's TPM refuses after a firmware or Secure Boot change, and a YubiKey or the recovery key opens the disk until the TPM is enrolled again ([decision 0019](0019-yubikeys.md)).

## How it is checked

- `tests/t2-vm.sh` installs into a QEMU VM and boots the result; `tests/t3-vm.sh` boots a copy with Secure Boot in Setup Mode and a software TPM, runs `system/secureboot-setup.sh`, and drills a rollback.
- `system/secureboot-test.sh` proves, on the hardware, that the firmware refuses an unsigned image.
- `dram doctor --boot` warns when Secure Boot is off, a kernel has no UKI on the ESP, or `sbctl verify` finds an unsigned file of mine.

## History

- 2026-10-10: decided.
- 2026-10-11: accepted, built and tested in the VM. The installer (`install/arch-install.sh`), the snapshot hooks, the snapshot boot entries, `system/secureboot-setup.sh` and `system/tpm2-enroll.sh` landed; snap-pac was left out for failing the Community rule. Automatic fallback by boot counting is deferred until the order of the live UKI and the snapshot entries is settled. Build detail: [the boot chain](../docs/platforms/arch/boot-chain.md) and [Secure Boot](../docs/security/boot-trust/secure-boot.md).
- 2026-10-12: amended: I wanted a themed boot menu and a splash before ly once cabin dual-boots Windows, and systemd-boot's menu cannot be themed. rEFInd returned as the front menu, on the UKI chain, signed by sbctl and renewed by a pacman hook, with four entries: Arch Linux, Arch Linux LTS, Windows, and "Snapshots & recovery", which is systemd-boot. systemd-boot keeps the snapshot and fallback UKIs and stays right behind rEFInd in the firmware's boot order. The Plymouth splash came onto the UKIs, and every fallback UKI stays verbose (`docs/platforms/arch/boot-chain.md`).

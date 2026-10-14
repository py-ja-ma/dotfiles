# Arch Linux

[Platforms](../README.md) › Arch Linux

Arch is the primary OS on cabin and lantern, and on campfire once it is installed.
This division installs it from a blank disk, decides which packages each host gets, converges the system layer with `dram apply`, and owns the boot chain from the firmware to the greeter.
The WSL clones run the same user layer and roles without any of the system layer ([WSL](../wsl/README.md)).

| Branch | What it does | Code | Copy alone |
|---|---|---|---|
| [Install](install.md) | puts Arch on a blank disk from the ISO, then bootstraps it into a dram host at first boot | `install/arch-install.sh`, `install/bootstrap.sh`, `install/presets/`, `install/lib/` | yes, after changing the user, time zone and mirrors ([install/README.md](../../../install/README.md)) |
| [Roles](roles.md) | turns a host file and the detected hardware into the package lists the host installs | `modules/hosts/`, `install/lib/roles.sh`, `packages/*.txt` | yes, with your own lists ([packages/README.md](../../../packages/README.md)) |
| [System hooks](hooks.md) | what `dram apply` converges beside the packages: the role scripts, files in `/etc`, enabled units, pacman hooks and timers | `system/apply-hooks.tsv`, `system/files.tsv`, `system/units.tsv`, `system/maintenance.sh`, `system/hooks/` | `maintenance.sh` does; the tables need `dram` ([system/README.md](../../../system/README.md)) |
| [Boot chain](boot-chain.md) | rEFInd in front of signed UKIs, the Plymouth splash, the ly greeter, snapshots with their own boot entries | `system/system-dram.sh` and the scripts it runs, `system/snapshots-setup.sh`, `system/dram-snapshot.sh`, `system/uki-presets.sh` | yes, on the UKI layout the installer makes |

## How the branches fit

`install/arch-install.sh` writes the disk layout, a UKI booted by systemd-boot, the user and the host file with its roles.
At first boot `install/bootstrap.sh` runs `dram apply`, which reads the roles through `install/lib/roles.sh`, installs each list the host takes, then runs the role hooks of `system/apply-hooks.tsv` from top to bottom.
Two of those hooks build the boot chain: `system/snapshots-setup.sh` turns on snapshots and their boot entries, and `system/system-dram.sh` puts rEFInd, the splash and the greeter in place once Secure Boot is set up.
The Secure Boot, TPM2 and YubiKey hooks between them belong to [Boot trust](../../security/boot-trust/README.md) and [Identity](../../security/identity/README.md).

## The layer boundary

Home Manager owns `~/.config` and my command-line tools, pinned by `flake.lock`.
It doesn't own the kernel, the bootloader, the ESP, the initramfs or pacman packages, and on Arch it can't.
Those are package lists and idempotent scripts in `packages/` and `system/`, and `dram apply` converges them.
[Decision 0001](../../../decisions/0001-approach.md) explains the split, and [decision 0008](../../../decisions/0008-system-layer-converge.md) the converge.
A declarative system layer would mean NixOS.

## The user layer

`flake.nix` builds one Home Manager configuration per file in `modules/hosts/`, named `<user>@<host>` ([decision 0006](../../../decisions/0006-flake-layout.md)).
A host file sets flags only: its name, login, roles, form, GPU vendor and whether it is a laptop.
`modules/laptop.nix` and `modules/gpu.nix` turn the flags into configuration, so no setting is copied between host files ([decision 0004](../../../decisions/0004-module-split.md)).
Every module, its job and the branch that documents it are listed in [modules/README.md](../../../modules/README.md).
The Windows PCs come from the same flake through `windows/` ([Windows](../windows/README.md)).

## Hosts

| Host | Record |
|---|---|
| cabin | [hosts/cabin/README.md](../../../hosts/cabin/README.md): board, disks, boot, the case display, monitors |
| lantern | [hosts/lantern/README.md](../../../hosts/lantern/README.md): the laptop's old install, until the reinstall |
| campfire | [hosts/campfire/README.md](../../../hosts/campfire/README.md): not installed yet |

`dram harvest` writes each host's package lists, enabled units, copies of edited `/etc` files and hardware facts into `hosts/<host>/`; [hosts/README.md](../../../hosts/README.md) says which file is which.

## Operating it

- A new machine, or a reinstall: [handbook chapter 1](../../records/handbook/01-install.md).
- The first login on it: [chapter 2](../../records/handbook/02-first-login.md).
- What runs on its own, and what I run weekly: [chapter 3](../../records/handbook/03-cadence.md).
- Updates, releases and rolling back the user layer or the system: [chapter 4](../../records/handbook/04-update-version-rollback.md).
- Adding or removing a package: [chapter 7](../../records/handbook/07-packages.md).
- A host that won't boot or log in: [chapter 11](../../records/handbook/11-troubleshooting.md).

## Status

As of 2026-10-13: cabin runs Arch, reinstalled from a blank disk on 2026-10-11.
The laptop that becomes lantern still runs its old install under the name panasonic, and `hosts/lantern/` holds that install's records until the reinstall.
campfire is not installed.

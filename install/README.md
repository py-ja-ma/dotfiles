# install

[Platforms](../docs/platforms/README.md) › [Arch Linux](../docs/platforms/arch/README.md) › [Install](../docs/platforms/arch/install.md)

The Arch installer and the first-boot bootstrap: from a blank disk to a host converged from this repo.
`arch-install.sh` runs from the Arch ISO; `bootstrap.sh` runs at the first login and installs what the host's roles and hardware call for.

| | |
|---|---|
| Needs | the Arch ISO 2026.10.01 (`iso.pin`), bash, curl and gpg on the Mac for `get-iso.sh`; the rest of this repo for bootstrap; tested in the VM install tests and on cabin 2026-10 |
| Copy alone | the installer yes, after changing the user, time zone, mirrors and presets; bootstrap needs this repo's lists and `dram` |
| License | MIT |

## What it needs

- On the ISO: pacstrap, arch-chroot, genfstab, sgdisk, mkfs.btrfs and mkfs.fat, cryptsetup, bootctl, mkinitcpio and efibootmgr, all on the Arch ISO.
- `lib/detect.sh` and `lib/roles.sh` beside it, and a copy of this repo, which the installer puts at `~/git/dotfiles` on the new system.
- For bootstrap: `packages/`, the signed `[dram]` repo (`pkgs/dram.asc`, `system/pacman-dram-repo.sh`), the scripts in `system/` that `dram apply` runs, `dotfiles/.local/bin/dram`, and the flake for the user layer.
- Not needed: archinstall, an AUR helper, or a network path to archlinux.org.

## Copy it alone

1. Copy `arch-install.sh`, `presets/`, `lib/detect.sh`, `lib/luks.sh`, `lib/roles.sh` and `mirrorlist`.
2. Change the defaults: `--user` (pj), `--timezone` (America/New_York), the mirrors in `mirrorlist`, the layouts in `presets/`.
3. Give it a `modules/hosts/<host>.nix` with a one-line `roles = [ … ];`, or let it write one from `--roles`; it needs a `packages/roles/` directory to check the roles against.
4. From the ISO: `bash arch-install.sh --preset desktop --disk /dev/disk/by-id/<disk> --hostname <host> --dry-run`, then without `--dry-run`.
   It lists every disk, refuses one holding Windows, and asks for the disk's serial number.
5. Reboot: systemd-boot shows the new system's UKI and its fallback.

Use `get-iso.sh` on its own to fetch and verify any Arch ISO: change `VERSION`, `SHA256` and the release key's fingerprint in `iso.pin`.

## How it is wired here

| File | What it does |
|---|---|
| `arch-install.sh` | from the ISO: partitions, btrfs subvolumes, pacstrap from the pinned mirrors, the UKI and systemd-boot, the user, this repo, the host file, `/etc/dram/install-facts.env` |
| `bootstrap.sh` | at the first login: detection, then phases 1 to 6: packages and `dram apply`, `[dram]`, Nix and Home Manager, the greeter, early KMS, hardening |
| `presets/{desktop,bench,laptop,admin}.env` | the disk layouts: campfire and single-disk desktops, cabin, lantern, a homelab admin box |
| `presets/vm-test.env` | the layout of the VM install test (`tests/t2-vm.sh`) |
| `lib/detect.sh` | CPU, GPU, laptop or desktop, WSL or metal, boot mode; sourced, not run |
| `lib/roles.sh` | the only reader of a host's roles and lists; sourced by bootstrap, `dram`, `bin/check.sh` and the Mac's tools |
| `lib/luks.sh` | the LUKS2 helpers the installer and the TPM2 and YubiKey enrolments share |
| `lib/windows-stage.sh` | stages a Windows build; sourced by `bin/push-windows.sh` and `install/windows/apply-windows.sh` ([Releases](../docs/operations/releases/README.md)) |
| `get-iso.sh`, `iso.pin` | downloads the pinned ISO and checks its sha256 and Arch's release signature |
| `mirrorlist` | the mirrors the installer and a new host use until reflector ranks them |
| `nix-install.sha256` | the pinned Nix installer bootstrap checks before running it |
| `mac-launchd.sh` | the Mac's daily backup pull ([macOS](../docs/platforms/macos/README.md)) |
| `windows/` | installing and converging a Windows PC ([install/windows/README.md](windows/README.md)) |

`bin/serve-repo.sh` on the Mac hands this repo to the ISO as a tar, since the ISO has no git.
`tests/t2-vm.sh` runs the installer and bootstrap end to end in a VM on the Mac, and `tests/t3-vm.sh` drills a rollback.
[Handbook chapter 1](../docs/records/handbook/01-install.md) is the walk-through.

## License

MIT, Patrick Jordan.

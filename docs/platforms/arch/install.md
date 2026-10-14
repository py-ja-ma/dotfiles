# Install

[Platforms](../../README.md) › [Arch Linux](../README.md) › Install

Two scripts take a machine from a blank disk to a dram host.
`install/arch-install.sh` runs from the Arch ISO and lays down the disks, a minimal base, a signed-kernel layout booted by systemd-boot, the user and a copy of this repo.
`install/bootstrap.sh` runs at the first login and installs what the host's roles and hardware call for.
[Handbook chapter 1](../../records/handbook/01-install.md) walks through both, command by command, with their output.

| | |
|---|---|
| Code | `install/arch-install.sh`, `install/bootstrap.sh`, `install/presets/`, `install/lib/detect.sh`, `install/lib/luks.sh`, `install/get-iso.sh`, `install/iso.pin`, `install/mirrorlist`, `install/nix-install.sha256`, `bin/serve-repo.sh`, `system/locale-setup.sh` |
| Runs on | every Arch host; a WSL clone runs bootstrap's phases 1 and 3 only ([WSL](../wsl/README.md)) |
| Needs | the Arch ISO 2026.10.01 that `install/iso.pin` names, tested 2026-10 in the VM tests and on cabin |
| Decided in | [decision 0010](../../../decisions/0010-install-path.md) (the script), [decision 0011](../../../decisions/0011-disk-boot-secure-boot-snapshots.md) (disk, boot, snapshots), [decision 0017](../../../decisions/0017-cabin-bench-layout.md) (cabin's disks) |

## How it works

### The ISO and the repo

`install/get-iso.sh` downloads the ISO that `install/iso.pin` names and checks its sha256 and Arch's release signature against the pinned key, in a throwaway GnuPG home.
The ISO has curl and tar but no git, so `bin/serve-repo.sh` on the Mac packs a clone of the checked-out branch with its release tags into a tar and serves it over HTTP, printing the sha256 to type in the ISO.
`--out FILE` writes the tar to a USB stick instead.

### The disk installer

`install/arch-install.sh` lists every disk and touches only `--disk`, plus `--work-disk` for the bench preset.
It refuses a disk holding NTFS, BitLocker or a Windows boot manager, and asks you to type the disk's serial number before it wipes anything.
Then it partitions, creates the btrfs subvolumes, runs pacstrap from the mirrors pinned in `install/mirrorlist`, and writes a UKI preset, systemd-boot, networking, the user, the repo at `~/git/dotfiles` and the host file.
Nothing it runs talks to archlinux.org, which is unreachable from my LAN.
It records what it did in `/etc/dram/install-facts.env`, which bootstrap reads instead of guessing.

| Preset | For | Layout |
|---|---|---|
| `desktop` | campfire and other single-disk desktops | ESP 4 GiB at `/efi`, a btrfs system pool of 256 GiB, a btrfs data pool on the rest, no LUKS |
| `bench` | cabin ([decision 0017](../../../decisions/0017-cabin-bench-layout.md)) | NVMe 1: ESP 4 GiB, system pool 512 GiB, data pool; NVMe 2: one work pool; no LUKS |
| `laptop` | lantern | ESP 4 GiB, LUKS2 with btrfs on the rest, a swapfile the size of RAM for hibernation |
| `admin` | a homelab admin box | ESP 2 GiB, LUKS2 with one btrfs pool |
| `vm-test` | the VM install test (`tests/t2-vm.sh`) | ESP 1 GiB, a 12 GiB system pool and a data pool, serial console |

The data pool (`/data/games`, `/data/emulation`, `/data/recordings`) and cabin's work pool (`/data/vm`, `/data/ml`, `/data/scratch`, containers) are separate filesystems, so a reinstall could keep them.
The installer still wipes every disk it is given: copy what matters off first ([handbook chapter 5](../../records/handbook/05-backup-restore.md)).

cabin's Arch goes on its two NVMe disks, from the ISO:

```sh
bash install/arch-install.sh --preset bench --hostname cabin --user pj \
  --disk /dev/disk/by-id/nvme-<NVMe 1> --work-disk /dev/disk/by-id/nvme-<NVMe 2>
```

### First boot: bootstrap

`install/bootstrap.sh` detects the hardware, shows what it found and lets you override it, then runs six phases.
Each phase is safe to run again, and `--phase N` runs one.

| Phase | Does |
|---|---|
| 0 | detection: CPU and GPU vendors, laptop or desktop, WSL or its own hardware, UEFI ([Roles](roles.md#what-bootstrap-detects)) |
| 1 | `[multilib]` on, one `pacman -Syu`, then `dram apply`: the lists for the host's roles and hardware, the enabled units, the role hooks |
| 2 | the signed `[dram]` repo (`system/pacman-dram-repo.sh`), the packages every host takes from it, and `dram apply` again for the `[dram]` packages a role claims; skipped in WSL |
| 3 | Nix from its pinned installer (`install/nix-install.sha256`) unless one is present, flakes on, then the user layer built with the Home Manager that `flake.lock` pins |
| 4 | the ly greeter on tty2, one Hyprland session in the greeter, then `system/maintenance.sh` ([System hooks](hooks.md)) |
| 5 | a UKI preset for every installed kernel (`system/uki-presets.sh`), the GPU's early KMS modules in a mkinitcpio drop-in and `/etc/kernel/cmdline`, then `mkinitcpio -P` |
| 6 | `system/harden.sh`, which always asks ([Security](../../security/README.md)) |

The rEFInd menu and the Plymouth splash come later, with `dram apply`, once Secure Boot is set up ([Boot chain](boot-chain.md)).
`--yes` answers phases 1 to 5.
Two prompts ask even with `--yes`: a repo that is not at `~/git/dotfiles`, and a `/nix` left half removed.

### The host file

Every host has `modules/hosts/<host>.nix`, and `flake.nix` lists that directory, so a new file adds the host's `<user>@<host>` configuration and its `home-<host>` check by itself ([decision 0006](../../../decisions/0006-flake-layout.md)).
The installer writes the file when the repo has none: the host name, the roles from `--roles` (asked when missing), the GPU vendor and whether it is a laptop.
Add the rest by hand: `user` when the login is not pj, `address` once the host has a LAN reservation (the Mac's push target), and `secrets.enable = true` once its age key is in `.sops.yaml`.

```nix
{ ... }:
{
  dram = {
    hostName = "newbox";
    user = "pj";
    roles = [ "desktop" "dev" ];   # one line: install/lib/roles.sh reads it with grep
    address = "newbox";            # the Mac's ssh name for it: bin/release.sh and bin/push-host.sh
    isLaptop = false;
    gpu = "amd";                   # "intel" | "nvidia" | "amd" | "none"
  };
}
```

`bin/check.sh` §11 checks the flags without Nix, and `nix flake check` refuses a host file that misses one.
[Handbook chapter 2](../../records/handbook/02-first-login.md) commits the new file back to the Mac with the host's first `dram harvest`.

## When it breaks

- The clone path is load-bearing.
  `modules/options.nix` builds every dotfile link from `$HOME/git/dotfiles`; clone anywhere else and every link dangles.
  bootstrap checks it and stops.
- A whole-directory link that becomes per-file links needs the old link removed first.
  When an older generation linked `~/.config/waybar` as one directory and the new one links its files, Home Manager writes the new links through the old one, into the repo, and leaves symlink loops ("Too many levels of symbolic links").
  Run `rm ~/.config/waybar` (the link, not the repo) before switching, and `git checkout -- dotfiles/.config/waybar/` if it already happened.
  It happened on lantern on 2026-10-05.
- A session that started on the old `hyprland.conf` can't take a plain `hyprctl reload`.
  Hyprland picks its config manager once at startup, so after the move to the Lua config a plain reload parses nothing and leaves no keybinds and no monitor rules.
  `dram-theme` reloads, so this bites during a migration: use `hyprctl reload full-reset` (Hyprland 0.56 and later), or log out and in.
  It happened on cabin on 2026-10-05.
- `~/.config/themes/current` must exist before Hyprland starts.
  `dram switch` seeds it to washi the first time, so this only bites when the flake is bypassed.
- ly has no plain `ly.service`, only the template: the unit is `ly@tty2.service`, and `systemctl enable ly` fails with "not-found".
- ly's `dur_file` animation is banned: it crashed the boot twice on lantern on 2026-07-02 and forced a recovery from the ISO.
  `system/apply-ly.sh` accepts only `none` and `matrix`; bootstrap sets `none`, and `sudo bash system/apply-ly.sh --anim matrix` switches to the rain.
- The lock screen and the bar show a Russian date.
  Run `sudo bash system/locale-setup.sh` once to enable `en_US.UTF-8` and `ru_RU.UTF-8`; without it the date falls back to English.
- `system/harden.sh` allows SSH from one subnet only, the `define LAN` line at the top of `system/nftables.conf`.
  On another LAN, edit that line before phase 6, or the next boot locks you out over SSH.
- A machine that already ran its own Hyprland may start a second bar and a second notification daemon.
  On cabin on 2026-10-05, a user `waybar.service` doubled the bar (`systemctl --user disable --now waybar.service`), and an installed `dunst` took the notifications from swaync (`sudo pacman -Rns dunst`).
- Reboot before relying on the machine: after a kernel or initramfs change, the running kernel's modules may be gone from disk.

The rules that have cost a machine before, `home-manager switch` and `home.stateVersion` among them, are on the [Operations](../../operations/README.md) page.

## Limits

- The installer wipes whole disks; it has no mode that keeps a data pool.
- bootstrap installs onto an existing Arch system too, but the boot-chain steps need the UKI layout the installer makes.
  On an older rEFInd-only install it warns and leaves the boot chain alone.
- What a new machine still needs by hand (its SSH key, the YubiKeys, groups, Proton Mail Bridge, the browsers) is in [handbook chapter 2](../../records/handbook/02-first-login.md).

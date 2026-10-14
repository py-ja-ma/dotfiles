# 0010: Install with a pacstrap script of my own, not archinstall

[Platforms › Arch Linux](../docs/platforms/arch/README.md) · accepted 2026-10-11

A pacstrap script with a preset per disk layout installs Arch from a pinned ISO and hands over to the roles; the cost is about 300 lines of installer to own.

## Context

`install/bootstrap.sh` assumes Arch is already installed.
I want one path from the ISO: a repo-driven install, first boot, then the roles.
archinstall 4.5 (2026-09-29, on ISO 2026.10.01) has no Secure Boot, no TPM2, no systemd initramfs without FIDO2, snapshot boot only with GRUB and absolute partition sizes only.
It shipped six releases in six months with schema churn, and an open btrfs + LUKS + manual-partition bug (#3975).
archlinux.org itself is unreachable from the home LAN (an Arch-side block on the WAN address is most likely), while the mirrors, the AUR, WKD and security.archlinux.org work.

## Decision

- A pacstrap-based install script in `install/` with one sourced preset per disk layout
  (desktop two-pool, laptop LUKS, admin box) implementing `decisions/0011`.
- **Disk safety:** the target is chosen by `/dev/disk/by-id`, its serial is typed
  to confirm, and the script refuses any disk carrying NTFS, BitLocker or an
  existing Windows ESP.
- **Pinned inputs:** the ISO is pinned by sha256 in the repo; a shipped mirrorlist
  (geo.mirror.pkgbuild.com, mirror.rackspace.com, mirrors.kernel.org) replaces any call
  to archlinux.org; `pacman-key` uses WKD with a keyserver fallback.
- The repo reaches the ISO from a USB stick or over HTTP from the Mac; for VM tests the
  ISO's `script=` boot parameter / cloud-init seed runs it unattended.
- Hand-off: after first boot, `bootstrap` asks hostname + roles, writes the host file
  (`decisions/0009`), enrolls Secure Boot (`decisions/0011`) and runs `dram apply`.

## Alternatives weighed

| Option | Why not |
|---|---|
| archinstall `--silent` + a post-boot fix-up | less code to own, but most of its output would be overridden (Secure Boot, sd-encrypt, snapshot layout), and the schema keeps moving |
| archinstall as a Python library | same feature gaps, plus an unstable API |
| Calamares-based installers | not Arch-native, more surface |

## Consequences

- The repo owns ~300 lines of install script; the Arch Installation guide is its spec, T2 VM
  runs are its tests.
- Nothing at install time depends on archlinux.org. reflector on installed hosts becomes
  failure-tolerant; the Arch news step probes and skips.
- Handbook 01 is rewritten around the script.

## How it is checked

`tests/t2-vm.sh` runs the install unattended in QEMU (by hand on the Mac; `--bench` installs across two disks), and `install/get-iso.sh` checks the pinned ISO's sha256 and Arch's release signature.
`bin/check.sh` §4 lints the scripts; nothing in `bin/check.sh` runs an install.

## History

- 2026-10-10: proposed ([D15](log.md#d15)).
- 2026-10-11: accepted: `install/arch-install.sh` and its presets built, the VM install test passes, and cabin was reinstalled with it.

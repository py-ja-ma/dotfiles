# system

[Platforms](../docs/platforms/README.md) › [Arch Linux](../docs/platforms/arch/README.md) › [System hooks](../docs/platforms/arch/hooks.md)

The system layer of an Arch host: idempotent root scripts, the files they install under `/etc`, and three tables that tell `dram apply` which script, file and unit each role takes.
Every script answers `--help` (`bin/check.sh` §13 checks it).
The writers take `--dry-run` without root, write a file only when its content changes, and keep the previous one once as `<file>.bak-<stamp>`; `decommission.sh` takes `--plan` instead, and `backup-eva.sh` has no dry run.
A single script carries its facts in its header; this page indexes them and describes the three components here that span several files.

| | |
|---|---|
| Needs | Arch Linux, bash, root for a real run; `dram` for the tables; each script's header names its own packages |
| Copy alone | each script yes, after reading its header's notes; the tables need `dotfiles/.local/bin/dram` |
| License | MIT |

## What it needs

- Arch with pacman and systemd; each script's header lists what else it uses.
- `install/lib/detect.sh` and `install/lib/roles.sh`, which several scripts source.
- For the tables: `dram apply` and `dram doctor` from `dotfiles/.local/bin/dram`, which read them.

## Copy it alone

1. Copy the script and read its header: what it writes, its flags, what to change first (`harden.sh` needs your LAN's subnet in `nftables.conf`, for example).
2. Run it with `--dry-run`, read the diff, then run it as root.
3. Run it again: an idempotent script reports nothing to do.

## How it is wired here

`dram apply` runs the scripts as role hooks from `apply-hooks.tsv`, copies the files listed in `files.tsv`, and enables the units listed in `units.tsv`; `dram doctor` reports drift from all three ([System hooks](../docs/platforms/arch/hooks.md)).

| Entry | What it does | Branch |
|---|---|---|
| `apply-hooks.tsv`, `files.tsv`, `units.tsv` | the hooks, the `/etc` files and the units each role takes | [System hooks](../docs/platforms/arch/hooks.md) |
| `maintenance.sh`, `hooks/50-pkglist.hook`, `hooks/70-proton-pass-sandbox.hook`, `pacman-contrib.conf`, `reflector.conf`, `reflector-tolerant.conf` | pacman's upkeep, its timers and hooks | [System hooks](../docs/platforms/arch/hooks.md) |
| `system-dram.sh`, `apply-refind.sh`, `99-refind.hook`, `plymouth-setup.sh`, `apply-ly.sh`, `uki-presets.sh` | the boot chain from rEFInd to the greeter | [Boot chain](../docs/platforms/arch/boot-chain.md) |
| `snapshots-setup.sh`, `dram-snapshot.sh`, `snapper/`, `initcpio/dram-volatile`, `hooks/00-dram-snap-pre.hook`, `hooks/zz-dram-snap-post.hook` | snapshots and their boot entries | [Boot chain](../docs/platforms/arch/boot-chain.md#snapshots) |
| `locale-setup.sh` | generates `en_US.UTF-8` and `ru_RU.UTF-8`, run by hand once | [Install](../docs/platforms/arch/install.md) |
| `decommission.sh` | a host's local teardown before a reinstall or retirement | [handbook chapter 10](../docs/records/handbook/10-teardown.md) |
| `bench-disk.sh` | lays out cabin's bench disk | [Bench OSes](../docs/platforms/bench/README.md) |
| `windows-esp-retire.sh` | takes Windows' boot files off Arch's ESP once Windows has its own | [Boot guard](../docs/platforms/windows/boot-guard.md) |
| `wsl-setup.sh`, `wsl/` | a WSL clone's system half | [wsl/README.md](wsl/README.md) |
| `house-palette.sh`, `gen-boot-assets.py`, `refind-letterpress/`, `refind-catppuccin/`, `plymouth-letterpress/`, `plymouth-catppuccin/`, `limits-hyprland.conf` | the boot screens' palette and themes; Hyprland's real-time limits | [Shell & bars](../docs/design/shell-and-bars/README.md) |
| `harden.sh`, `nftables.conf`, `network-setup.sh`, `networkmanager/` | firewall, sshd, DNS, NetworkManager | [Network](../docs/security/network/README.md) |
| `secureboot-setup.sh`, `secureboot-test.sh`, `tpm2-enroll.sh` | Secure Boot keys and signing, the enforcement test, lantern's TPM2 unlock | [Boot trust](../docs/security/boot-trust/README.md) |
| `yubikey-setup.sh`, `fido2-enroll.sh`, `pam-u2f.conf`, `u2f-selftest.py`, `secrets-bootstrap.sh` | the YubiKeys and the secrets | [Identity](../docs/security/identity/README.md) |
| `pacman-dram-repo.sh`, `dram-builder-setup.sh`, `flatpak-setup.sh` | the `[dram]` repo, its builder, Flatpak | [Packaging](../docs/toolchain/packaging/README.md) |
| `gaming-setup.sh`, `emulation-setup.sh`, `creator-setup.sh`, `recording-setup.sh`, `re-lab-setup.sh`, `printing-setup.sh`, `virt-setup.sh`, `udev/`, `v4l2loopback.conf`, `v4l2loopback-load.conf` | the work and play roles' setup | [Profiles](../docs/toolchain/profiles/README.md) |
| `backup-eva.sh` | the optional copy to the eva drive | [Backups](../docs/operations/backups/README.md) |

### The convergence tables and `maintenance.sh`

| | |
|---|---|
| Needs | `dram`; pacman-contrib, reflector, arch-audit, rebuild-detector for `maintenance.sh` |
| Copy alone | `maintenance.sh` yes, with `MAINT_COUNTRY` for your mirrors; the tables only with `dram` |
| License | MIT |

`apply-hooks.tsv` is tab-separated: role, script, mode (`auto` or `ask`), when (`pre` or `post`), note.
`files.tsv` maps a source here to its target under `/etc`, its role and the hook that writes it; `units.tsv` lists unit, role and note.
A role column takes a role, `base`, `metal`, `wsl`, `!role` in `units.tsv`, or several joined by `,` that must all hold.
`maintenance.sh` on its own: `sudo bash system/maintenance.sh --dry-run`, then without `--dry-run`; `dram doctor` or `systemctl list-timers` shows the timers afterwards.

### The boot chain

| | |
|---|---|
| Needs | refind, plymouth, ly, mkinitcpio, systemd-boot with UKIs at `/efi/EFI/Linux`, sbctl once Secure Boot is set up; the themes from `system/refind-letterpress/` and `system/plymouth-letterpress/` |
| Copy alone | yes, on a UKI layout: copy the scripts with `house-palette.sh` and the theme directories, then `sudo bash system/system-dram.sh --dry-run` |
| License | MIT; the vendored Catppuccin themes are MIT, Catppuccin's |

`system-dram.sh` runs the other three in boot order and collapses the greeter's two Hyprland sessions into one.
`apply-refind.sh` also installs `dram-refind-first.service`, which puts rEFInd first at every boot, and `99-refind.hook`, which signs rEFInd again after each upgrade.

### Snapshots

| | |
|---|---|
| Needs | btrfs with `@snapshots` and `@home_snapshots` subvolumes, snapper, mkinitcpio, systemd-boot, sbctl to sign the snapshot UKIs |
| Copy alone | yes, on that subvolume layout: copy the six files, run `sudo bash system/snapshots-setup.sh --dry-run`, then without it |
| License | MIT; the snapper configs follow snapper's own template |

After a pacman transaction, `/usr/local/lib/dram/dram-snapshot list` shows the new pre and post snapshots and which have a boot entry; it replaces snap-pac, which has had no release since 2021.

## License

MIT, Patrick Jordan.
`refind-catppuccin/` and `plymouth-catppuccin/` are Catppuccin's, MIT; the recolored icons in `refind-letterpress/icons/` come from them.

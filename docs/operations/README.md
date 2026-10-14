# Operations

[Organization](../README.md) › Operations

Operations runs the machines from day to day: `dram` on each host, the releases and pushes that carry a commit from the Mac to the hosts, the backups, and the checks that run before any of it.
I edit and release on lodge, the Mac.
The hosts apply what they receive, and the Mac does not run Home Manager or `dram` for them.

| Division | Covers |
|---|---|
| [dram CLI](dram/README.md) | `dram` on Arch and in the WSL clones, `dram` on Windows, the command reference |
| [Releases and pushes](releases/README.md) | builds, releases, channels, the previous build, pushes to Arch, WSL and Windows, the `[dram]` repo's sync, host records |
| [Backups](backups/README.md) | borgmatic host to host, the Mac's pull, the eva drive; paused until the NAS |
| [Quality](quality/README.md) | `bin/check.sh`, the tests and their tiers, the register checker, the generators' checks, CI |

```text
lodge: edit, commit -> bash bin/check.sh -> bin/release.sh -> bin/push-host.sh, bin/push-windows.sh
host:  dram update -> dram doctor
```

## Common tasks

| To | Run | Read |
|---|---|---|
| update a host | `dram update`; `--check` previews it, exit 7 means nothing is pending | [dram CLI](dram/README.md#dram-update), handbook [3](../records/handbook/03-cadence.md) and [4](../records/handbook/04-update-version-rollback.md) |
| apply the flake after editing `modules/` | `dram switch` | [dram CLI](dram/README.md#dram-switch) |
| see what a host runs | `dram version` | [Releases and pushes](releases/README.md#the-identity-file) |
| cut a release | `bin/release.sh --dry-run`, then `bin/release.sh -m "<summary>"`, on the Mac | [Releases and pushes](releases/README.md#builds-and-releases), handbook [4](../records/handbook/04-update-version-rollback.md) |
| push without a release | `bin/push-host.sh <user>@<address>` | [Pushes](releases/pushes.md) |
| go back to the previous build | `dram rollback`; `dram builds` lists the last five | [Releases and pushes](releases/README.md#the-previous-build) |
| make a host match the repo | `dram apply --dry-run`, then `dram apply` | [dram CLI](dram/README.md#dram-apply) |
| edit a dotfile | edit it under `dotfiles/`, where the host's link points, and commit | [Platforms › Arch](../platforms/arch/README.md) |
| change the theme | `dram theme` | [Design › Themes](../design/themes/README.md), handbook [6](../records/handbook/06-theme-and-look.md) |
| add an app | its role's list under `packages/roles/`, then `dram update` | [Toolchain › Packaging](../toolchain/packaging/README.md), handbook [7](../records/handbook/07-packages.md) |
| update a vendored package | `dram pkgs update <name>`, `build`, `publish` on cabin, then `bin/sync-dram-repo.sh` | [Toolchain › Packaging](../toolchain/packaging/README.md), [Pushes](releases/pushes.md#the-dram-repo) |
| fix a host after an update | `dram doctor`, then `dram rollback` | handbook [11](../records/handbook/11-troubleshooting.md), [a host that fell behind](releases/README.md#a-host-that-fell-behind) |
| set up a new machine | the installer from the Arch ISO | handbook [1](../records/handbook/01-install.md) and [2](../records/handbook/02-first-login.md) |
| retire or rename a host | `system/decommission.sh --plan`, `bin/forget-host.sh --plan` | handbook [10](../records/handbook/10-teardown.md) and [9](../records/handbook/09-move-or-rename.md) |
| back up or restore a file | paused until the NAS; the snapshots and a copy by hand until then | [Backups](backups/README.md), handbook [5](../records/handbook/05-backup-restore.md) |
| keep a secret, use the YubiKeys | sops-nix; `dram yubikey` | [Security › Identity](../security/identity/README.md), handbook [8](../records/handbook/08-secrets.md) |
| reach home from outside | `vpn`, `vpn-down` | [Security › Network](../security/network/README.md) |
| apply Windows from the flake | `bin/render-windows.sh`, then `bin/push-windows.sh cabin-win --apply` | [Platforms › Windows](../platforms/windows/README.md), [dram on Windows](dram/windows.md) |
| work in Arch from Windows | `bin/push-host.sh --wsl <host> <user>@<pc>`, then `dram update` in the clone | [Platforms › WSL](../platforms/wsl/README.md) |
| check what is trusted | `dram doctor --supply`, `bin/repro.sh` | [Security › Software supply](../security/software-supply/README.md) |
| check the repo | `bash bin/check.sh` on the Mac, `dram check` on a host | [Quality](quality/README.md) |
| find the command for a job | | [Commands](../commands.md): which command when, and each script's `--help` |

## Rules that have cost a machine

1. **Never** run bare `home-manager switch`: it ignores the flake, and it once tore down every dotfile symlink.
   Use `dram switch`.
2. **Never** change `home.stateVersion` in `modules/core.nix` (26.05).
   Nothing checks this.
3. **Never** set ly's `dur_file` animation: it crashed the boot twice and forced a recovery from the ISO.
   `system/apply-ly.sh` refuses it and blanks `dur_file_path`.
4. **Never** run `pacman -Sy <pkg>`: that is a partial upgrade.
   Use `pacman -Syu`, and `dram apply` refuses to install after a bare `-Sy`.
5. **Do not** run `system/harden.sh` before `define LAN` in `system/nftables.conf` names your subnet.
   nftables admits ssh from the LAN only and sshd takes keys only, so a wrong subnet or a missing key locks you out.
   `dram doctor --supply` warns when either drifts.
6. **Never** vendor a package an official repository has, unless `pkgs/OVERRIDES` lists it.
   `[dram]` sits above `[core]`, so a vendored package shadows the official one without a word.
   `dram pkgs check` (`bin/check.sh` §12) refuses such a name.

## Decisions

| Record | Decides |
|---|---|
| [0007](../../decisions/0007-rename-rice-to-dram.md) | the command's name, `dram` |
| [0008](../../decisions/0008-system-layer-converge.md) | `dram apply` converges the system layer |
| [0014](../../decisions/0014-backups-paused-until-nas.md) | backups paused until the NAS |
| [0020](../../decisions/0020-windows-from-the-flake.md) | Windows from the flake, which `dram.ps1` applies |
| [0021](../../decisions/0021-wsl-clone.md) | the WSL clones, which `bin/push-host.sh --wsl` feeds |
| [D26](../../decisions/log.md#d26) | Nix on the Mac runs in a throwaway container under Colima |
| [D47](../../decisions/log.md#d47), [D50](../../decisions/log.md#d50) | eva is never wiped; the old disks go once emptied |
| [D64](../../decisions/log.md#d64) | Windows releases arrive by explicit pushes, and `main` is their default channel |

## Open

- 2026-10-13: the repo has no remote, so CI has never run and the hosts receive everything from the Mac.
- 2026-10-13: backups stay paused until the NAS, and the Crucial P2 still holds keepers to copy off.
- 2026-10-13: the bash completion offers `dram update --aur-only`, which no longer exists, and does not offer `dram boot-to`.
- 2026-10-13: `bin/check.sh` §6 does not read pages under `docs/<directorate>/`.

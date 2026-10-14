# dram CLI

[Operations](../README.md) › dram CLI

`dram` updates, applies, themes and checks a host.
It runs on every Arch host and in the WSL clones.
A Windows PC runs `dram.ps1` under the same name, with the commands that apply there ([dram on Windows](windows.md)).

| Branch | What it does | Code | Copy alone |
|---|---|---|---|
| dram on Arch | the command, its two shims and its bash completion | `dotfiles/.local/bin/dram`, `dram-switch`, `sysupdate`, `dotfiles/.local/share/bash-completion/completions/dram` | no: it reads this repo's layout ([its README](../../../dotfiles/.local/bin/README.md)) |
| dram on Windows | receive, apply, doctor and roll back a Windows release | `install/windows/dram-windows/dram.ps1` | no: it applies a render of `windows/` |
| Command reference | which command to reach for, and every script's `--help` on one page | `bin/gen-commands-doc.py` writes [Commands](../../commands.md) | yes, with Python 3 and scripts whose header is their `--help` |

## How the branches fit

`modules/cli.nix` links `dram`, `dram-switch` and `sysupdate` into `~/.local/bin` on every host, desktop or not.
`modules/shell.nix` links the completion, and the `bash-completion` package loads it on the first `dram <Tab>`.
`dram` reads the host file `modules/hosts/<host>.nix`, the package lists through `install/lib/roles.sh`, and the tables in `system/`.
It runs `bin/check.sh`, `bin/pkgs.sh` and `bin/yubikey.sh` from the checkout at `~/git/dotfiles`, or at `DRAM_REPO` when that is set.
The model behind `update`, `version`, `channel` and `rollback` is on [Releases and pushes](../releases/README.md).

## Commands

| Command | Does |
|---|---|
| `dram switch` | applies the Home Manager flake for `<user>@<host>` and writes `~/.config/dram/release` |
| `dram update` | the whole update, in the order below; `--check` exits 7 when nothing is pending |
| `dram receive` | takes a release from a git bundle, for a WSL clone |
| `dram version` | the running build: release tag, build id, channel, generation; `--json` for scripts |
| `dram channel` | what `dram update` follows: `stable` (the newest `v*` tag) or `main` (`master`) |
| `dram changelog` | release notes from `CHANGELOG.md` |
| `dram theme` | runs `dram-theme`: a rofi picker, `dram theme <name>`, `--list` (bar name and id), `--ids` |
| `dram check` | `bin/check.sh`, then `nix flake check` where Nix is installed |
| `dram doctor` | a read-only health report; each warning names its fix |
| `dram pacnew` | merges `*.pacnew` files with `vim -d` |
| `dram rollback` | the previous build, an older Home Manager generation, or a system snapshot |
| `dram builds` | the recorded builds, newest first, the same as `dram rollback --list` |
| `dram backup` | borgmatic: run, list, check, restore one path |
| `dram apply` | converges the system layer to the host's roles: packages, units, role hooks |
| `dram harvest` | refreshes `hosts/<host>/` from this machine |
| `dram boot-to` | reboots once into another OS on this machine |
| `dram pkgs` | the `[dram]` package repo, through `bin/pkgs.sh` |
| `dram yubikey` | the YubiKeys: `status`, `enroll <label>`, `ssh [<label>]`, `use <label>`, through `bin/yubikey.sh` |
| `dram help` | the command list |

Every subcommand answers `--help`, and a bad flag exits 2 without side effects.
`bin/check.sh` §13 runs each one in a throwaway clone, `boot-to` excepted.
`dram-switch` and `sysupdate` are shims for `dram switch` and `dram update`.
`upgrade` is a bash alias for `dram update --clean` (`modules/shell.nix`), so it exists only in an interactive shell.
Scripts and `ssh <host> upgrade` call `dram` directly.
On a host set up before 2026-10-06, the first `dram` command renames the old `rice` state directories, file by file ([decision 0007](../../../decisions/0007-rename-rice-to-dram.md)).

## `dram switch`

```sh
dram switch              # home-manager switch --flake ~/git/dotfiles#<user>@<host> -b bak-<stamp>
dram switch --show-trace # other arguments pass through to home-manager
```

**Never** run bare `home-manager switch`: it ignores the flake, and it once tore down every dotfile symlink.
The backup suffix carries a date, so a second collision does not stop the switch.
`dram doctor` counts the leftover `*.bak-*` files.

After a successful activation, `dram switch` writes `~/.config/dram/release` and `~/.local/state/dram/last-switch`.
The first names the running build; [the identity file](../releases/README.md#the-identity-file) lists its keys.

## `dram update`

```sh
dram update              # everything below
dram update --check      # read-only: what is pending; exit 7 when nothing is
dram update --full       # also nix flake update; flake.lock comes back if the new pins fail to switch
dram update --clean      # also expire Home Manager generations older than 7 days, then collect garbage
dram update --no-switch  # skip the Home Manager switch
```

The steps run in this order:

| Step | What happens | Why |
|---|---|---|
| 0. The build, then the slot | records the running build under `~/.local/state/dram/builds/<BUILD_ID>/`, then checks out the channel target: `git checkout --detach <tag>` on `stable`, `git checkout master` on `main` | `dram rollback` returns to that record |
| 1. sudo | one prompt, kept fresh by a loop | the upgrade can outlast a sudo ticket |
| 2. Keyring | `pacman -Sy archlinux-keyring`, only when `pacman -Qu archlinux-keyring` says it is behind | a stale keyring is the usual cause of "signature is unknown trust" |
| 3. Cache trim | `paccache -rk2` before the download | the two kept versions are the offline downgrade path |
| 4. Upgrade | `sudo pacman -Syu`: the official repos and `[dram]` in one transaction | the hosts have had no AUR helper since 2026-10-10 ([decision 0013](../../../decisions/0013-software-rules-and-waivers.md)) |
| 5. Flatpak | `flatpak update`, when Flatpak is installed | [Flatpak](../../toolchain/packaging/flatpak.md) |
| 6. pacnew | `pacdiff -o` lists unmerged configuration files | `dram pacnew` merges them |
| 7. Orphans | `pacman -Qqdt`, listed and asked about | nothing is removed without a yes |
| 8. Reboot | says so when the running kernel left the disk, the Hyprland binary changed, or `nvidia-utils` changed | |
| 9. Switch | `dram switch`, unless `--no-switch` | |
| 10. Doctor | `dram doctor --brief`: the warnings only, each with its fix | |

Uncommitted edits to tracked files stop step 0, and the message gives the commit, stash and discard commands.
A `checkpoint` release on the way is applied first, and the run ends with "checkpoint vX reached, run dram update again" ([checkpoints](../releases/README.md#checkpoints)).
The run also refreshes the bar's updates badge (`custom/updates`, signal `SIGRTMIN+8`).
The Hyprland plugins are `[dram]` packages, so step 4 upgrades them with everything else; cabin rebuilds them when Hyprland moves ([Packaging](../../toolchain/packaging/README.md)).

Omarchy's `omarchy-update` runs the same steps with `--noconfirm`, a btrfs snapshot and a fixed package set.
Here `pacman -Syu` asks, each `[dram]` PKGBUILD was reviewed when it was vendored, and the rollback is the previous build plus the pacman cache.

Two steps differ in a WSL clone.
Before step 0 it runs `dram receive` when the bundle `bin/push-host.sh --wsl` staged in `C:\ProgramData\dram` is newer than the checkout, and `--check` counts that bundle as pending.
Step 8 becomes "restart the distro": WSL boots Microsoft's kernel, so only an `/etc/wsl.conf` changed since the distro started asks for `wsl.exe --terminate <distro>`.
Inside WSL, `update`, `switch` and `apply` refuse a host file without `form = "wsl"`, and on metal they refuse one with it.

## `dram receive`

```sh
dram receive                  # in WSL: /mnt/c/ProgramData/dram/dotfiles.bundle
dram receive <bundle> --force # anywhere else name the file; --force discards edits to tracked files
```

A release as a file, for a host that ssh from the Mac does not reach: the WSL clone.
`dram receive` verifies the bundle, then fetches the branch (`master` when the bundle carries it) and every tag into `~/git/dotfiles`.
A checkout on a branch (channel `main`) is reset to the received tip.
A checkout detached at a release (channel `stable`) keeps its place until `dram update`.
These are the steps `bin/push-host.sh` runs over ssh ([Pushes](../releases/pushes.md)).
`--force` works on branch checkouts only.

## `dram doctor`

```sh
dram doctor          # the full report
dram doctor --brief  # warnings only, as dram update prints them
dram doctor --boot   # adds the boot section
dram doctor --supply # only the supply section
```

| Section | Checks |
|---|---|
| systemd | failed system and user units; the error lines of this boot, after known noise is filtered |
| pacman | unmerged `.pacnew` files, orphans, `checkrebuild`, `arch-audit -u`, pending updates, a reboot needed, a dkms module per kernel, `pacman.conf` options, the maintenance timers and hooks |
| boot (`--boot`) | `efibootmgr` boots rEFInd first; rEFInd and the fallback loader are on the ESP; a fallback initramfs per kernel; free space on `/boot` |
| dram | `flake.lock` older than 60 days; the repo dirty, ahead or behind; the running version, build, channel and generation; the checkout is the switched build and not behind its channel; `modules/` or the flake changed after the last switch; `~/.config/themes/current` resolves; leftover `*.bak-*` files |
| backup | `borgmatic.timer`, its last journal line, the peer reachable, the newest archive at most two days old, `passphrase` and `id_ed25519` at mode 0600; while backups are paused it says so as information |
| secrets | with `dram.secrets.enable`: the last `sops-nix.service` run, the decrypted secret at mode 0400, the age key at 0600 |
| login | `pam_gnome_keyring` in `/etc/pam.d/ly` |
| network | one network manager per interface: NetworkManager on desktops and laptops, systemd-networkd on headless hosts |
| yubikeys | once `keys/` lists a key: sshd's `authorized_keys.d` matches `keys/ssh.pub`, git's signing key exists, and on desktops the pam_u2f lines equal `system/pam-u2f.conf` |
| gaming mode | on a host with the `gaming` role: the session packages, Steam's library, shader processing in the background |
| emulation | on a host with the `emulation` role: only allow-listed libretro cores, and none downloaded into the home directory |
| case display | where the case's temperature panel (USB `2022:0522`) is plugged in: `dram-case-display` installed and running |
| declared state | the drift `dram apply` would fix: missing and undeclared packages, units, `/etc` copies |
| supply | altered package files, unaccounted foreign packages, the pins, the `[dram]` repo's health, Flatpak remotes, sshd keys-only, nftables loaded ([integrity](../../security/software-supply/integrity.md)) |

`dram doctor` exits 1 when a warning fired.
In a WSL clone the boot, network, login and firewall checks say they do not apply, and a `wsl` section checks the clone itself.
It looks at the distro's name and host file, Microsoft's kernel, WSL 2.5 or newer, systemd as PID 1, the WSL-breaking units masked, `/` a shared mount, and `/etc/wsl.conf` and Windows' `.wslconfig` against the repo's copies.
It also checks that no Windows directory is on `PATH`, the disk is under 75 % of its cap, Windows' SSH agent holds a YubiKey key from `keys/ssh.pub`, and the staged bundle is not ahead of the checkout.

## `dram pacnew`

`dram pacnew` runs `DIFFPROG="vim -d" pacdiff -s`.
With `-s`, pacdiff calls sudo itself for the merge, so `vim` runs as root only on the one file.
`DIFFPROG=meld dram pacnew` uses another diff tool.

## Version, channel and changelog

```sh
dram version              # version, build, channel, generation, switch time, flake.lock
dram version --json       # the same as one JSON object, plus ahead_of and checkout
dram channel              # stable — the latest release tag (v2026.10.1, checked out)
dram channel stable       # follow the newest v* tag
dram channel main         # follow master, the newest commit pushed from the Mac
dram channel --target     # "<channel> <target> <commits>", for welcome.sh and the bar badge
dram changelog            # the latest section of CHANGELOG.md
dram changelog v2026.10.1 # one release; --since v2026.10.1 prints everything newer
```

`dram version` reads `~/.config/dram/release` and warns when the checkout has moved past the switched build.
Without a channel file the channel is `stable` once a tag exists on the host and `main` before.
Releases are cut on the Mac with `bin/release.sh` and arrive through `bin/push-host.sh`, tags included ([Releases and pushes](../releases/README.md)).

## `dram rollback`

```sh
dram rollback             # the previous build: its commit and generation; pacman -U lines printed, never run
dram rollback --list      # the recorded builds, newest first (= dram builds)
dram rollback 3           # three Home Manager generations back; the checkout stays
dram rollback --system    # the system snapshots and which have a boot entry
dram rollback --system 42 # snapshot 42 becomes the new root, after a yes; reboot to finish
```

With no argument it returns to the newest recorded build whose commit or generation differs from the running one.
It records the current build first, so a second `dram rollback` goes forward again.
It asks, checks out that commit, runs that generation's `activate`, and rewrites `~/.config/dram/release`.
It then prints one `sudo pacman -U /var/cache/pacman/pkg/<file>` line per package whose previous version is still cached, and a `pacman -Rns` line for each package that was not installed then.
A generation that `dram update --clean` expired cannot come back; the message says to check out the commit and run `dram switch`.

With `N` it goes back N Home Manager generations and leaves the checkout alone; `dram switch` goes forward again.
With `--system N` the current root is kept as `@.broken-<stamp>` ([decision 0011](../../../decisions/0011-disk-boot-secure-boot-snapshots.md)).

## `dram backup`

```sh
dram backup                        # = dram backup run: borgmatic --verbosity 1
dram backup list                   # the archives in this host's repository
dram backup check                  # repository and archive consistency
dram backup restore ~/.kube/config # the path from the newest archive, into /tmp/dram-restore/
```

Backups are paused until the NAS, so on a host without `dram.backup.enable`, `run`, `list` and `check` say so and stop ([Backups](../backups/README.md)).
`restore` prints where the file landed, and copying it back is left to you.
`check` is `borgmatic check`, which honors the frequencies in `modules/backup.nix`: repository and archives every two weeks, a test extract monthly.
Inside that window it skips without a word and exits 0, so `borgmatic check --force` is the way to force one.

## `dram apply`

```sh
dram apply --dry-run   # the plan, and every hook run with --dry-run
dram apply             # install and enable what the roles declare, run the role hooks
dram apply --prune     # also remove what no role declares, after the host name is typed
```

`dram apply` converges the system layer to what the repo declares for this host ([decision 0008](../../../decisions/0008-system-layer-converge.md)), as `dram switch` does for the user layer.

| Part | Source | What apply does |
|---|---|---|
| Declared packages | `packages/base.txt`, `packages/metal.txt`, the hardware lists, one `packages/roles/<role>.txt` per role, the `[dram]` install set | installs the missing ones with `pacman -S --needed`, official repos and `[dram]` in separate transactions |
| Undeclared packages | explicit packages no list declares | reports them; `--prune` removes the ones nothing needs |
| Units | `system/units.tsv` | enables the units each role needs, timers with `--now` |
| Role hooks | `system/apply-hooks.tsv` | runs the idempotent `system/` scripts; `ask` hooks need a yes at the terminal |
| Register | `packages/register.tsv` | a `fail` verdict stops the run; `swap` and `pending` are listed, and stop it with `--rollout` |
| Files | `system/files.tsv` | shows `/etc` copies that drifted, with the hook that rewrites them |

The hardware lists come from `install/lib/detect.sh`, and `DRAM_CPU`, `DRAM_GPUS` and `DRAM_FORM` override it.
In a WSL clone the plan is base plus roles minus `packages/wsl-skip.tsv`, with nothing from `[dram]`.
`DRAM_FORM=wsl` previews that plan on any host.
A row in the tables may name a pseudo-role: `base` (every host), `metal` (every host on its own hardware) or `wsl` (every clone).
`!role` is every host without it, and `a,b` needs both.

`dram apply` does not upgrade.
It refuses when the sync databases are newer than the last full upgrade, which would make its install a partial upgrade, and when a configured repository has no sync database yet.
Run `dram update` first, then `dram apply`.
`--prune` keeps base, kernels and headers, firmware, microcode, bootloaders, sbctl, mkinitcpio, systemd, sudo, pacman, glibc, mesa, the NVIDIA driver, dkms, nix, git and openssh.
`--yes` answers the `auto` hooks; the `ask` hooks (`harden.sh`, `system-dram.sh`, `dram-builder-setup.sh`) still wait for a person at the terminal.
The last run is recorded in `~/.local/state/dram/apply-last`, and `dram doctor` shows the same drift in its declared-state section.

## `dram harvest`

`dram harvest` writes `hosts/<host>/{packages,systemd,etc}/` and `hardware.txt` from this machine, then shows `git status` for that directory.
`bin/harvest.sh <host> <ssh-target>` writes the same files from the Mac.
Run it after a big upgrade, and commit.

## `dram boot-to`

```sh
dram boot-to list               # the firmware's boot entries, this Arch marked
dram boot-to fedora             # firmware BootNext to Fedora's entry, then reboot
dram boot-to 0003 --no-reboot   # an entry by number; only set BootNext
```

Each OS on the bench has its own disk and boot partition, so Arch's menu shows only Arch ([decision 0017](../../../decisions/0017-cabin-bench-layout.md)).
`dram boot-to` sets the firmware's one-time `BootNext` and reboots, and the boot after that is Arch again.
It knows `windows`, `debian`, `fedora` and `nixos` by their entries' labels, and tells NixOS's systemd-boot from Arch's by the partition it lives on.

## `dram check`

`dram check` runs `bin/check.sh`, then `nix flake check` when Nix is on `PATH`.
On the Mac, `bash bin/check.sh` runs the same checks without Nix ([Quality](../quality/README.md)).

## Operating it

The daily and monthly routine is handbook [chapter 3](../../records/handbook/03-cadence.md).
Updating, versions and rollback are [chapter 4](../../records/handbook/04-update-version-rollback.md).
When a command fails, start with [chapter 11](../../records/handbook/11-troubleshooting.md).

## Status

As of 2026-10-13:

- The bash completion offers `dram update --aur-only`, which no longer exists, and does not offer `boot-to`.
- `bin/check.sh` §13 does not run `dram boot-to --help`: without `efibootmgr` a bad flag exits 1, not 2.

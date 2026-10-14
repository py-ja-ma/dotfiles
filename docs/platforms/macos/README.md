# macOS

[Platforms](../README.md) › macOS

lodge, a MacBook Pro, is where I edit this repo, run its checks, cut releases and push them to the hosts.
The Mac never applies anything: it has no Nix of its own and no pacman, and the hosts converge themselves with `dram update`.
No flake output describes the Mac; one may later, through nix-darwin ([decision 0018](../../../decisions/0018-one-flake-every-machine.md), proposed).

| | |
|---|---|
| Code | `install/mac-launchd.sh`; the Mac runs most of `bin/`, a few `install/` and `system/` scripts, and the VM tests in `tests/` |
| Runs on | lodge |
| Needs | macOS with its bash 3.2 and BSD tools, git, python3, Homebrew's QEMU for the VM tests, Docker with Colima for the Nix and amd64 containers |
| Decided in | [decision 0001](../../../decisions/0001-approach.md) (the layer boundary), [decision 0015](../../../decisions/0015-containers-podman.md) (Colima on the Mac), [decision log](../../../decisions/log.md#d26) (Nix in a container) |

## What runs on the Mac

| Job | Scripts |
|---|---|
| check | `bin/check.sh`, which `bin/release.sh` runs first |
| release and push | `bin/release.sh`, `bin/push-host.sh`, `bin/push-windows.sh`, `bin/sync-dram-repo.sh` ([Releases](../../operations/releases/README.md), [Pushes](../../operations/releases/pushes.md)) |
| render Windows | `bin/render-windows.sh`, in the `nixos/nix` container ([renderer](../windows/renderer.md)) |
| install a machine | `install/get-iso.sh`, `bin/serve-repo.sh` ([Install](../arch/install.md)) |
| host records | `bin/harvest.sh`, `bin/diff-hosts.sh`, `bin/forget-host.sh` |
| backups | `bin/pull-backups.sh`, run daily by `install/mac-launchd.sh` while backups run ([Backups](../../operations/backups/README.md)) |
| secrets | `system/secrets-bootstrap.sh --register` and its siblings |
| VM tests | `tests/t2-vm.sh`, `tests/t3-vm.sh`, `tests/t2-bootstrap.sh`, `tests/gaming-vm.sh` in QEMU; `tests/yubikey-t1.sh` in an amd64 container |
| generators | `bin/gen-*.py`; `bin/gen-avatar.sh` in a container; `bin/winget-diff.rb` with Homebrew's Ruby |

Everything the Mac runs works with macOS's bash 3.2 and BSD `stat`, `date` and `sed`, and with Apple's `openrsync`.
Colima shares only `$HOME` with its VM, so the scripts feed a container its files on stdin instead of mounting the scratch directory.
The Mac needs mains power for a VM test: on battery with the lid closed it sleeps and freezes the VM.

## The pull job

`install/mac-launchd.sh` installs the launchd job `dev.pj.pull-backups`, which runs `bin/pull-backups.sh` daily at 06:00 and once whenever the job loads, at every login.
launchd replays a missed calendar run only after sleep, never after a power-off, so a Mac that was off at 06:00 pulls at the next login; `pull-backups.sh` skips a host pulled less than 20 hours ago.
Host-to-host backups are paused until the NAS ([decision 0014](../../../decisions/0014-backups-paused-until-nas.md)), so the job has nothing to pull until then:

```sh
bash install/mac-launchd.sh --status       # state, run count, last exit code; exit 1 when not loaded
bash install/mac-launchd.sh                # install or refresh it, and pull once now
bash install/mac-launchd.sh --uninstall    # boot it out; the copies under ~/backups/borg/ stay
```

## Renaming the Mac

Once, by hand:

```sh
sudo scutil --set ComputerName lodge
sudo scutil --set LocalHostName lodge
sudo scutil --set HostName lodge
```

## The YubiKeys on the Mac

Paused since 2026-10-11: the Mac keeps its own software key in each host's `~/.ssh/authorized_keys` and doesn't use the YubiKeys.
Apple's `/usr/bin/ssh` (OpenSSH 10.5) knows the security-key types but has no `SecurityKeyProvider`, so it can't use them anyway.
When the pause ends, the route is Homebrew's OpenSSH, built with libfido2:

```sh
brew install openssh ykman age age-plugin-yubikey sops
hash -r; ssh -V                                     # prints: OpenSSH_10.6p1 from /opt/homebrew/bin
cd ~/.ssh && ssh-keygen -K -N ''                    # per key: PIN and touch, then id_ed25519_sk_rk_dram-<label>
```

Then, in the Mac's own `~/.ssh/config`, by host name, so the launchd job that connects by address keeps the software key:

```
Host cabin lantern campfire
    IdentityFile ~/.ssh/id_ed25519_sk_rk_dram-primary
    IdentityFile ~/.ssh/id_ed25519_sk_rk_dram-spare
    IdentitiesOnly yes
    AddKeysToAgent no              # Apple's agent accepts sk keys and then can't sign
```

Never a `~/.ssh/id_ed25519_sk` on the Mac: it would become a default identity of every ssh, the batch jobs included.
macOS needs no pcscd, and GUI apps don't see `/opt/homebrew/bin`.
Why two YubiKeys and what they open: [YubiKeys](../../security/identity/yubikeys.md).

## Retiring the Mac

The Mac holds the repo and the release tools, the way into the hosts, the `[dram]` carrier and the copies I keep.
[Handbook chapter 10](../../records/handbook/10-teardown.md), "Retire only the Mac", moves each to another machine first.

## Status

As of 2026-10-13: lodge is managed by hand, and its YubiKey setup is paused.

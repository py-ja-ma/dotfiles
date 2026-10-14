# Pushes

[Operations](../README.md) › [Releases and pushes](README.md) › Pushes

The hosts have no git remote, so everything reaches them from the Mac.
An Arch host gets a git bundle over ssh, and a WSL clone gets the same bundle staged on its Windows PC.
A Windows PC gets the flake's render and the files it lists.
The hosts other than the builder get the `[dram]` package repo through the Mac.

| | |
|---|---|
| Code | `bin/push-host.sh`, `bin/push-windows.sh`, `install/lib/windows-stage.sh`, `bin/sync-dram-repo.sh` |
| Runs on | the Mac (bash 3.2, BSD tools); `install/lib/windows-stage.sh` also on Arch |
| Needs | git, ssh, scp, rsync; python3, curl and bsdtar for a Windows push |
| Decided in | [decision 0020](../../../decisions/0020-windows-from-the-flake.md) for Windows, [decision 0021](../../../decisions/0021-wsl-clone.md) for the WSL clones, [D64](../../../decisions/log.md#d64) for explicit pushes |

## How it works

| Push | Script | Carries | Lands in |
|---|---|---|---|
| Arch host | `bin/push-host.sh <user>@<address>` | a git bundle of the branch and every tag, piped over ssh | `~/git/dotfiles` on the host |
| WSL clone | `bin/push-host.sh --wsl <host> <user>@<pc>` | the same bundle, plus `wsl.ps1`, `wslconfig` and `wsl.conf` from the same commit | `C:\ProgramData\dram` on the clone's Windows PC |
| Windows PC | `bin/push-windows.sh <host>` | the render of `windows/build/<host>/` and each file its manifest lists, only the ones that changed | `C:\ProgramData\dram\incoming`, until `dram receive` takes them |
| `[dram]` repo | `bin/sync-dram-repo.sh` | the signed packages and the database the builder published | `/var/lib/dram-repo` on every other host with an address |

`bin/release.sh` runs `bin/push-host.sh` for every host with `dram.address` ([Releases](README.md#builds-and-releases)).
The other three run by hand.

### Arch hosts

`bin/push-host.sh` bundles the branch and every tag, pipes the bundle over ssh, and runs `git fetch` on the host.
It pipes through ssh because scp's sftp subsystem dropped the connection on cabin under load on 2026-10-05.
Tracked files update in place, and untracked and ignored files stay as they are, including runtime state such as `themes/current`.

What happens to the checkout depends on the host's channel:

| Host | After the push |
|---|---|
| on a branch (channel `main`) | `git reset --hard` to the pushed tip |
| detached at a release (channel `stable`) | the refs move, the checkout stays; `dram update` there moves it to the newest tag |

On a branch, the host side refuses to reset over uncommitted edits to tracked files, names them, and asks for a commit, a stash or `--force`.
A detached host is not reset, so its edits stay.
`bin/push-host.sh` needs a clean tree on the Mac and `~/git/dotfiles` already cloned on the host.

### WSL clones

A WSL clone has no ssh of its own.
`--wsl <host>` sends the bundle to the OpenSSH of the clone's Windows PC instead, named by `wsl.windowsHost` in `modules/hosts/<host>.nix`.
The bundle arrives under a temporary name and is renamed, so a clone does not read half a file.
In the clone, `dram update` receives it first, or `dram receive` does it alone ([dram CLI](../dram/README.md#dram-receive)).
Nothing runs in the clone from the Mac, and a failed connection changes nothing, which is what happens when the PC is off or booted into Arch.

### Windows PCs

```sh
bin/push-windows.sh cabin-win                   # stage the release; dram receive switches to it
bin/push-windows.sh cabin-win --apply           # and dram apply converges the PC
bin/push-windows.sh cabin-win --dry-run         # checked in C:\ProgramData\dram\incoming, not switched
bin/push-windows.sh cabin-win --apply --dry-run # received, then winget configure test and -DryRun
```

The push needs a clean tree, because the release is the commit: its version, build and commit travel in `build\push.json` and fill in the manifest's `release` and `commit`.
`bin/render-windows.sh --check` runs first, so a stale render stops the push on the Mac.
Each file the manifest lists is staged from the repo, the render or a pinned download, and must have the manifest's sha256 before anything is copied.

Only what changed travels.
The PC's `build\files.sha256` is read first, and a file already there with the same sha256 stays home, which after the first push is most of the fonts.
The render, `dram.ps1` and the full file list always go, and the incoming `dram.ps1` runs the receive ([dram on Windows](../dram/windows.md)).

The address is `--to <user>@<addr>`, else `address` and `user` in `windows/hosts/<host>.nix`, else the address of the WSL clone whose `wsl.windowsHost` names the PC.
The host key is checked as `HostKeyAlias <host>` on a connection of its own, not multiplexed.
When cabin runs Arch, Arch's key answers at the same address, and the push is refused before anything is written.

For `ssh cabin-win dram …` by hand, the Mac's private `~/.ssh/config.d/windows.conf` holds a block ahead of the shared `Host *`:

```sshconfig
Host cabin-win
    HostName <the PC's address>
    User <user>
    HostKeyAlias cabin-win
    ControlMaster no
    ControlPath none
```

`ControlMaster no` matters: one multiplexed master to cabin's Arch must never carry a Windows command.

`install/lib/windows-stage.sh` is the staging library.
`bin/push-windows.sh` and `install/windows/apply-windows.sh` both stage through it, so the two stage the same bytes, and `bin/render-windows.sh` locks the fonts through it.

### The `[dram]` repo

cabin builds and signs the `[dram]` packages into `/srv/dram` ([Packaging](../../toolchain/packaging/README.md)).
The hosts' ssh keys for each other are pinned to `borg serve`, so the builder cannot rsync to another host, and the Mac carries the repo.
`bin/sync-dram-repo.sh` reads the host files: the one host with the `builder` role is the source, and every other host with a `dram.address` receives the repo.
It pulls `/srv/dram/` into `~/backups/dram/` on the Mac, then rsyncs that mirror to `/var/lib/dram-repo/` on each receiver.

The signatures travel with the files, so a tampered copy fails pacman's `SigLevel = Required DatabaseRequired`.
`--delay-updates --delete-delay` swap the files in only after the whole transfer, so pacman does not see a new `dram.db.sig` beside an old database.
The script stops when the mirror has no `dram.db.tar.zst` after the pull, so an emptied `/srv/dram` cannot wipe the other hosts' repos.
The Mac's mirror doubles as the backup of the signed repo off the builder.

## Use it

```sh
bin/release.sh -m "<summary>"                   # the usual way: tag, then every push above
bin/push-host.sh <user>@<address>               # commits without a release; a stable host keeps its checkout
bin/push-host.sh --wsl cabin-wsl <user>@<pc>    # stage the bundle for a clone
bin/push-windows.sh cabin-win --apply           # a Windows release, applied
bin/sync-dram-repo.sh                           # after each dram pkgs publish on cabin
```

On a host after a push: `dram update --check`, then `dram update`.

## When it breaks

| Symptom | Check | Fix |
|---|---|---|
| `error: uncommitted changes; commit first` | `git status` on the Mac | commit; a push carries commits only |
| the host refuses with a list of files | someone edited tracked files on the host | commit or stash them there, or push again with `--force` to discard them |
| `ssh to <pc> as <host>-win failed` | the PC is off, its OpenSSH is down, or cabin is booted into Arch | boot Windows and push again; a release still counts without the clone |
| `bin/push-windows.sh` stops on a sha256 | the render is stale or a source changed | `bin/render-windows.sh`, commit `windows/build/`, push again |
| `no dram.db.tar.zst after the pull` | `/srv/dram` on the builder is empty or half built | `dram pkgs publish` on cabin, then sync again |
| `want exactly one host with the builder role` | the host files name zero or two builders | give one host the `builder` role |

## Limits

- `bin/push-host.sh --wsl` stages and stops: the clone takes the bundle at its next `dram update`.
- `bin/sync-dram-repo.sh` goes through the Mac, so the Mac must be up after each publish.
- `dram.ps1` cannot run on the Mac, so `tests/push-windows.sh` checks the Windows push against a stand-in ssh, scp and receive ([Quality](../quality/README.md)).

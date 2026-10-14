# Backups

[Operations](../README.md) › Backups

Backups have been paused since 2026-10-10, until the NAS arrives ([decision 0014](../../../decisions/0014-backups-paused-until-nas.md)).
`dram.backup.enable` is off by default, so a host has no borgmatic configuration and no timer, and the Mac pulls nothing.
The pieces below stay in the repo for the day the NAS arrives, and the eva drive keeps an offline copy by hand.

| Branch | What it does | Code | Copy alone |
|---|---|---|---|
| borgmatic | backs up each host daily to a peer over ssh, encrypted | `modules/backup.nix` | yes, a Home Manager module: replace the peer, the paths and the passphrase source |
| The Mac's pull | copies each host's Borg repository to the Mac under the Borg lock | `bin/pull-backups.sh`, scheduled by `install/mac-launchd.sh` | yes, with ssh and rsync on the Mac, borg and rsync on the hosts |
| The offline copy | an encrypted Borg archive of the irreplaceable set on the eva drive, and a plain mirror of this repo | `system/backup-eva.sh` | yes, after changing the drive's label and the source list |

## How the branches fit

When backups run, each host's borgmatic writes to the other host at 03:00, and the Mac pulls both repositories at 06:00.
The Mac's copy is the third one.
eva is a fourth, offline and by hand.
Until the NAS, what protects a host is its snapper snapshots and what you copy off by hand ([handbook chapter 5](../../records/handbook/05-backup-restore.md)).
`dram doctor` reports the pause as information, and `dram backup` says so and stops ([dram CLI](../dram/README.md#dram-backup)).

## What is backed up

What cannot be downloaded again is small, under 1 GB per host:

| Path | Why |
|---|---|
| `~/git` | this repo and every other repository |
| `~/.ssh` | the keys and the untracked `config.d/` |
| `~/documents` | the vault and the hledger journal |
| `~/pictures`, `~/projects` | |
| `~/.config`, minus caches | includes the host's age key, `~/.config/sops/age` ([Secrets](../../security/identity/secrets.md)) |
| `~/.librewolf` | the browser profile |
| `~/.local/share/atuin`, `~/.local/share/fonts` | shell history, fonts outside the repo |
| `~/.local/share/Steam/userdata` | game settings and saves Steam keeps locally |

A host adds its own paths with `dram.backup.extraSources` in its host file.
Everything else (the Steam library, `~/.cache`, `/nix`, Proton prefixes) downloads again.

## borgmatic, host to host

`modules/backup.nix` configures borgmatic from Arch's package through Home Manager, with a user timer.

- The timer runs daily at 03:00, with up to an hour of jitter, and catches up after sleep.
- Each host writes to its peer over ssh: `ssh://<user>@<peer address>/./backups/borg/<host>`.
- A ping before the run skips it with exit 75 when the peer is off, and the next day retries.
- Retention keeps 7 daily, 4 weekly and 6 monthly archives.
- Checks run on the repository and the archives every two weeks, and a test extract monthly.
- The passphrase comes from the sops-nix secret `borg_passphrase` when `dram.secrets.enable` is on, else from `~/.config/borgmatic/passphrase`.

Each host's ssh key is pinned on its peer to `borg serve` in `~/.ssh/authorized_keys`, one line per peer:

```text
command="borg serve --restrict-to-path /home/<user>/backups/borg",restrict <peer public key>
```

The repositories are addressed by LAN address (`dram.backupPeerAddr`), because host names do not resolve between the hosts.
A new repository starts with `borgmatic repo-create --encryption repokey-blake2` on the host that writes it.

## The Mac's pull

`bin/pull-backups.sh` runs at 06:00 and at each login, from the launchd job `install/mac-launchd.sh` installs.
It pulls each host whose host file sets an address and a `backupPeer`, so while backups are paused it has nothing to pull.
For each host it opens one multiplexed ssh connection and probes it.
On the host, `borg --lock-wait 600 with-lock <repo> rsync -a --delete …` copies each repository to `~/backups/borg-stage/<name>/` while it holds the Borg lock, so no copy is taken mid-transaction.
The Mac then rsyncs the staged copy into `~/backups/borg/on-<host>/`, with one retry after 30 seconds.
The 06:05 pull of 2026-10-06 died in rsync's second handshake right after a good probe, which is why one connection now carries every step.

After a successful pull the script touches `on-<host>/.pulled`, and a host pulled less than 20 hours ago is skipped.
launchd replays a missed calendar run after sleep but not after a power-off, so a Mac that was off at 06:00 pulls at the next login.
Each run ends with a `WARN` line for a copy older than two days.
`bash bin/pull-backups.sh --check` prints each copy's age, reads nothing on the hosts, and exits 1 when one is stale.
To force a pull inside the 20 hours, remove `~/backups/borg/on-<host>/.pulled` first.

`on-<host>/` holds what `<host>` stores, which is its peer's repository.
So a retired host's own archives are under `on-<peer>/<host>/`.

## Custody

The Proton Pass copy of the Borg passphrase is the root of trust, with the output of `borg key export <repo-url>` beside it.
The age key that decrypts the passphrase on a host is inside the backup set, and restoring the set needs the passphrase first.
Without the Proton Pass copy, two dead hosts mean two sealed repositories.
The Mac keeps a copy of the passphrase in `~/backups/borg/passphrase`.

## The eva drive and the old disks

eva is a 4 TB USB SSD, NTFS, labeled `eva`, which Linux, macOS and Windows all read.
It is tidied by hand and never wiped ([D47](../../../decisions/log.md#d47)).
It holds what is kept, not what is played: an archive of ROMs, old Windows builds, the keepers of the old Arch install, and the offline Borg copy.

`system/backup-eva.sh` is that copy, run by hand with the drive plugged in, or through the `backup-eva` alias.
It finds the drive by its mount point or its label, and mounts it with `udisksctl` when needed.
It creates an encrypted repository (`repokey-blake2`) at `<eva>/backups/borg-dram` once, then a dated archive of `~/git/dotfiles`, `~/.ssh`, `~/pictures` and the editor settings.
It prunes to 7 daily, 4 weekly and 6 monthly archives, and compacts.
It also mirrors this repo's tracked files and `.git` to `<eva>/backup/` in the clear, so they can be browsed without borg; anything git does not track stays out of the mirror.
The passphrase lives in Proton Pass as "borg eva backup".

The old disks of cabin go once their contents are out ([D50](../../../decisions/log.md#d50)).
The SSK, the old Windows disk, was wiped on 2026-10-12 and is a spare.
The Crucial P2 becomes a Borg target once its keepers are copied off.

## Restore

```sh
dram backup list                                      # the archives in this host's repository
dram backup restore ~/.kube/config                    # from the newest archive, into /tmp/dram-restore/
borgmatic extract --archive latest --path home/<user>/.kube/config --destination /tmp/rt
diff /tmp/rt/home/<user>/.kube/config ~/.kube/config  # the quarterly drill: extract, then compare
```

A copy on the Mac restores there once borg is installed (`brew install borgbackup`):

```sh
export BORG_PASSCOMMAND="cat $HOME/backups/borg/passphrase"
borg list --last 3 ~/backups/borg/on-<peer>/<host>
borg check --verify-data ~/backups/borg/on-<peer>/<host>
```

## Turning backups on again

In the host file, set `backup.enable = true`, `backupPeer` and `backupPeerAddr`; `nix flake check` refuses the first without the other two.
Then put the passphrase into `secrets/pj.yaml` with `system/secrets-bootstrap.sh --init-borg`, run `dram switch`, `borgmatic repo-create`, and `dram backup run`.
Handbook [chapter 5](../../records/handbook/05-backup-restore.md) has the steps, and `bash install/mac-launchd.sh` installs the Mac's job again.

## Retiring a host or the Mac

Retiring a host is handbook [chapter 10](../../records/handbook/10-teardown.md).
On the host, `system/decommission.sh` prints by default each artifact the host holds or is named by: its repository on the peer, the Mac's mirror, the pinned `authorized_keys` line, the sops recipient.
On the Mac, `bin/forget-host.sh <host>` removes the host's files from the repo, which also takes it off the Mac's pull, and deletes the Mac's copy of its archives only with `--delete-backups`.
`bash install/mac-launchd.sh --uninstall` removes the pull job, and `--status` shows it.

## Operating it

Backup and restore are handbook [chapter 5](../../records/handbook/05-backup-restore.md), and the secrets behind them [chapter 8](../../records/handbook/08-secrets.md).

## Status

As of 2026-10-13:

- No host runs borgmatic, and the Mac's pull job is unloaded until the NAS ([decision 0014](../../../decisions/0014-backups-paused-until-nas.md)).
- The Crucial P2 still holds keepers to copy off before it becomes a Borg target.
- borg was not installed on the Mac when last checked on 2026-10-10, so the Mac's copies have not been test-restored there.
- The Mac had no Time Machine destination when checked on 2026-10-07, so a copy on the Mac survives the Mac only on an external disk.
- `dram backup check` follows borgmatic's two-week cadence, and `borgmatic check --force` forces one.

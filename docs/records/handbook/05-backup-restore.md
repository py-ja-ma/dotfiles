# 5. Backup and restore

**Backups are paused until the NAS** (`decisions/0014-backups-paused-until-nas.md`).
No host backs up to another, and the Mac pulls nothing: `dram.backup.enable` is off by
default, so a host has no borgmatic config and no timer; `dram backup` says so, `dram
doctor` reports it as information. This chapter is what protects what until then, how to get
a file back, and how to turn backups on again. The Borg setup that ran until 2026-10-10 —
host-to-host repositories, the Mac's nightly pull, the restore drills — is in
`docs/operations/backups/README.md` and in git history; it returns with the NAS.

## Before you start

- Chapter 4 is done.
- A terminal on the host, and the Mac for §3.

## What protects what, today

| You lose | What brings it back | Not covered |
|---|---|---|
| a working system after an update | the pre/post snapshot of `/` and its boot entry; `dram rollback --system` (chapter 4 §10) | — |
| a file under `~`, deleted or overwritten | the `/home` snapshots: 5 daily, 2 weekly (§1) | a file younger than the newest snapshot |
| this repo, `~/documents/vault`, `~/documents/finance` | git: committed and pulled to the Mac (chapter 2 §4, `docs/toolchain/profiles/office.md`) | work not yet committed and pulled |
| the system pool (a reinstall) | the data pool (`/data/games`, `/data/emulation`, `/data/recordings`) and cabin's work pool are separate filesystems, built so a reinstall can keep them — but today's installer wipes every disk it is given; a keep-the-data reinstall is still to come | `~`: copy it off first (§3) |
| a dead disk, a stolen laptop | nothing automatic | everything you did not copy off (§3) |

## 1. Get a file back from a `/home` snapshot

The snapshots are root-only (`system/snapper/home`), so restore with `sudo`:

```sh
sudo snapper -c home list                               # number, date; type timeline (and pre/post around updates)
sudo snapper -c home status <n>..0 | grep '/vault/'     # what changed since snapshot <n>, under a path
sudo cp -a /home/.snapshots/<n>/snapshot/<user>/path/to/file ~/file.restored
sudo chown "$(id -un):" ~/file.restored
```

`sudo snapper -c home undochange <n>..0 /home/<user>/path/to/file` puts the file back in
place instead (it overwrites the current one). The snapshots live on the same disk as
`/home`: they are a time machine for mistakes, not a backup.

## 2. Get the system back

Chapter 4 §10: boot a snapshot's entry to try it, `dram rollback --system <n>` to make it
the system, and `dram rollback` for the dram build (the user layer) beside it.

## 3. Copy the irreplaceable set to the Mac (by hand, until the NAS)

What cannot be downloaded again: documents, game saves without cloud sync, console
dumps (BIOS files, your own disc images), keys (Proton Pass already holds the PINs, the
recovery keys and the passphrases), photos. From the Mac:

```sh
mkdir -p ~/backups/<host>
rsync -aHv --info=progress2 <user>@<address>:documents/ ~/backups/<host>/documents/
rsync -aHv --info=progress2 <user>@<address>:/data/emulation/bios/ ~/backups/<host>/emulation-bios/
rsync -aHv --info=progress2 <user>@<address>:/data/emulation/saves/ ~/backups/<host>/emulation-saves/
```

Add the paths you care about the same way. The Mac has no Time Machine destination,
so a second copy on an external disk (encrypted) is what survives the Mac.

## 4. When the NAS arrives

The Borg module stays in the repo for exactly this. In the host file:

```nix
backup.enable = true;
backupPeer = "<nas>";            # the host that stores this host's Borg repository
backupPeerAddr = "<its address>";
```

Then the passphrase into `secrets/pj.yaml` (chapter 8; `system/secrets-bootstrap.sh
--init-borg`), `dram switch`, `borgmatic repo-create`, `dram backup run`, and the drills in
`docs/operations/backups/README.md`. `nix flake check` refuses `backup.enable` without a peer.

## Done when

- [ ] `dram doctor` prints `backups are paused until the NAS (decisions/0014): no borgmatic config on this host`
- [ ] you restored one file from a `/home` snapshot with §1
- [ ] the irreplaceable set of this host is on the Mac (§3), dated in your notes

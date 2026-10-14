# 0014: Host-to-host backups are paused until the NAS

[Operations › Backups](../docs/operations/backups/README.md) · accepted 2026-10-11 · amended 2026-10-12

borgmatic stays in the repo but off, and new work lives in git remotes and copies by hand until a NAS arrives in 2027; the cost is a gap with no scheduled backup.

## Context

borgmatic backs each host up to the other (`modules/backup.nix`), and the Mac pulls both
repos nightly (`bin/pull-backups.sh`). Both hosts are being wiped and rebuilt; a NAS
arrives in 2027. A check on 2026-10-10 found the Borg set covers only selected directories, the `[dram]`
signing key's `~/.gnupg` was never in it, borg is not installed on the Mac, and the Mac
has no Time Machine.

## Decision

- `dram.backup.enable` defaults to **false**; no backup peers; the Mac pull and its
  launchd job are off. The module and docs stay, marked "paused until the NAS".
- Before the wipe, data was to leave both hosts through a one-time procedure: key exports, a full home copy to the Mac, a
  final Borg run with a test restore on the Mac, and a second copy on an external
  encrypted disk ([D12](log.md#d12)).
  The fresh start of 2026-10-11 replaced it ([D147](log.md#d147)): new keys at install instead of exports, and the old Arch home kept on eva.
- The signing key was never in the Borg set: its custody is the offline export and Proton Pass (`docs/toolchain/packaging/README.md` §2).
- eva, the offline USB disk, is tidied and never wiped ([D47](log.md#d47)).
- The old drives are wiped once everything is extracted: the old Crucial P2 becomes a local borg target, and the SSK a spare ([D50](log.md#d50)).
  The borg target needs a local-repository option in `modules/backup.nix` first.

## Consequences

- Between the rebuild and the NAS, the only copies of new work are git remotes and
  whatever I copy by hand. Accepted risk; the NAS project restores scheduled backups
  (btrbk or borg to the NAS, with an append-only key).

## How it is checked

`dram doctor`'s "backup" section says backups are paused while a host has no borgmatic configuration, and checks the timer, the peer and the age of the last archive once one exists.
`bin/check.sh` §11 treats `backupPeer` and `backupPeerAddr` as relevant only with `dram.backup.enable`.

## History

- 2026-10-10: proposed.
- 2026-10-11: accepted: `dram.backup.enable` off by default; `dram backup`, `dram doctor` and the Mac's pull honour the pause.
- 2026-10-11: the pre-wipe procedure dropped at the fresh start ([D12](log.md#d12) superseded by [D147](log.md#d147)).
- 2026-10-12: amended: eva is never wiped ([D47](log.md#d47)); the SSK wiped as a spare and the old Crucial P2 to become a borg target ([D50](log.md#d50)).

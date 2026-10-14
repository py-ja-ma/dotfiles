# Backups (eva drive) — SUPERSEDED

> **Superseded 2026-10-05** by `docs/backups.md`: backups now run daily with borgmatic
> to the peer host (`modules/backup.nix`), `rice backup` / `rice backup restore` are the
> commands, and the Mac pulls the repos. Vorta is not used. `system/backup-eva.sh` still
> works as an *optional offline copy*; the package lists it mentions moved to
> `legacy/pkglist*.txt` (the live ones are `packages/*.txt` and `hosts/<h>/packages/`).

The rice repo makes the *desktop* reproducible. This doc covers the things the
repo can **not** regenerate — private keys and pictures — and how
they get backed up to the **eva** external drive with [Borg](https://borgbackup.org).

Two ways to run it, same repo:

- **`system/backup-eva.sh`** — the script. Run it manually, or from cron/a timer.
- **Vorta** — a GUI over the same borg repo, for a click-to-run daily schedule.

---

## What gets backed up (the irreplaceable set)

| Path | Why it's here |
|------|---------------|
| `~/git/dotfiles`  | the rice repo + any other dotfiles repos (in case you haven't pushed) |
| `~/.ssh`          | private keys **and** `config.d/*.conf` — the part deliberately NOT in git |
| `~/Pictures`      | wallpapers, screenshots, saved images |
| `~/.config/VSCodium/User/settings.json` | editor settings — the one config not symlinked into the repo |

Excluded: `node_modules`, `.cache`, `*.tmp`, `*.swp`, nix `result` symlinks, and
anything tagged `CACHEDIR.TAG`. `.git/objects` is *kept* — it's small and makes
the repo restore self-contained.

Everything else on the box is reinstallable (packages via `docs/rice-reinstall.md`) or
already tracked in this git repo, so it's intentionally left out.

### Plain, browsable mirror (alongside the encrypted archive)

After the borg archive, the script *also* rsyncs a plain, un-encrypted copy of
the rice repo to `<eva>/backup/dotfiles`. This is just readable files — no
borg, no passphrase needed to open it. It's safe in the clear because the rice
repo holds **no secrets** (your `~/.ssh` keys are only ever in the *encrypted*
archive). So you get both: a versioned encrypted vault **and** a "just look at
the files on the drive" copy.

### What "in the backup" actually means: a REBUILD RECIPE, not a disk clone

The repo (and therefore the backup) is everything needed to **rebuild** this
machine, but it is **not** a block-level image of `/`. Concretely:

| Custom thing | In the backup as… |
|---|---|
| rEFInd bootloader theme | `system/refind-catppuccin/` + `system/apply-refind.sh` (the theme + installer) |
| Plymouth boot splash | `system/plymouth-catppuccin/` + `system/plymouth-setup.sh` |
| ly greeter | `system/apply-ly.sh` (the script that *configures* `/etc/ly/config.ini`) |
| Installed packages | `packages/*.txt` + `hosts/<h>/packages/` (the **list**, not the binaries; `legacy/pkglist.txt` is the 2026-07 snapshot) |
| The whole riced desktop | `dotfiles/` — every config + all themes |
| Custom scripts / apps | `dotfiles/.local/bin/` + `system/*.sh` |

What is **NOT** snapshotted (it gets *regenerated* on restore, see
`docs/rice-reinstall.md`): the live `/etc` files (`/etc/ly/config.ini`,
`/etc/mkinitcpio.conf`), the ESP / `/boot` (kernels, initramfs, `refind.conf`
boot entries, the refind binary), and the installed package binaries. A restore
= install Arch base → run the `system/` scripts (`apply-refind.sh`,
`plymouth-setup.sh`, `apply-ly.sh`; today `install/bootstrap.sh` does all of it) → clone
this repo → `home-manager switch`. You get the exact riced system back; you do
**not** boot a cloned disk.

> Keep the package list current: run `rice harvest` and commit before a backup if
> you've installed things since it was last updated (`legacy/pkgs-snapshot.sh` is the old way).

---

## Encryption: repokey + a passphrase in Proton Pass

`backup-eva.sh` creates the borg repo **encrypted** (`repokey-blake2`). Why:

- The backup set contains your `~/.ssh` **private keys**. eva is a small
  external drive — the kind of thing that gets lost, stolen, or borrowed. If
  that happens, an unencrypted backup hands over the keys to your homelab.
- "repokey" means the encryption **key is stored inside the repo on eva
  itself**. You never manage a key file — the only thing you need is the
  **passphrase** that unlocks it.
- The passphrase lives in **Proton Pass** (cloud), so it survives even if the
  laptop *and* eva both die. That closes the classic trap of "the secret needed
  to restore the backup was only stored on the machine that died".

**The one hard rule:** put the passphrase in Proton Pass **before** the first
backup run, in an entry called **"borg eva backup"**. A lost passphrase means
the backup is permanently unreadable — borg cannot recover it, ever.

The script asks for the passphrase when it runs (first run: choose it, twice;
later runs: paste it from Proton Pass). Vorta remembers it in your keyring, so
the scheduled daily runs don't prompt.

> Already ran an older version of the script that created an *unencrypted*
> repo? The script detects that, warns, and keeps backing up (a backup beats no
> backup). To switch: rename `<eva>/backups/borg-rice` to `borg-rice-old`,
> re-run the script (it creates a fresh encrypted repo), and delete the old
> folder once the new one has a few days of archives.

---

## Run a backup manually

Plug eva in, then:

```bash
udisksctl mount -b /dev/sda2                 # mounts at /run/media/pj/eva (no sudo)
bash ~/git/dotfiles/system/backup-eva.sh
```

The script is **idempotent and safe to run repeatedly**:

1. Finds where eva is mounted (fails with clear instructions if it isn't).
2. Asks for the passphrase (first run: choose one — put it in Proton Pass first).
3. `borg init` the encrypted repo at `<eva>/backups/borg-rice` — only if absent.
4. `borg create` a new archive `rice-<host>-<YYYY-MM-DD_HHMMSS>`.
5. `borg prune` to **keep daily 7 / weekly 4 / monthly 6**, then `borg compact`.

If eva isn't mounted the script prints exactly how to mount it (including the
NTFS "dirty flag" fix if `udisksctl` refuses a read-write mount) and exits `1`
without touching anything.

### eva mount gotcha (NTFS dirty flag)

After an unclean shutdown, `udisksctl mount` can fail with "bad superblock". Clear
the NTFS dirty bit once with root, then mount normally:

```bash
sudo mount -t ntfs-3g -o rw,uid=1000,gid=1000,windows_names /dev/sda2 /mnt && sudo umount /mnt
udisksctl mount -b /dev/sda2
```

Confirm the device name with `lsblk -f` first (it's the NTFS partition labelled
`eva`, normally `/dev/sda2`).

---

## Restore a file from a backup

List archives, look inside one, and extract:

```bash
export BORG_REPO=/run/media/pj/eva/backups/borg-rice
# each command asks for the passphrase — it's the "borg eva backup" entry in
# Proton Pass. To type it only once:  export BORG_PASSPHRASE='...'

borg list                                   # all archives, newest last
borg list ::rice-panasonic-2026-07-03_1200  # files inside one archive

# extract ONE file — borg paths are relative to /, no leading slash.
# extraction lands under the CURRENT directory, so cd somewhere safe first:
cd /tmp
borg extract ::rice-panasonic-2026-07-03_1200 \
    home/pj/.ssh/config.d/homelab.conf
# -> restored to /tmp/home/pj/.ssh/config.d/homelab.conf

# restore a whole tree (e.g. all of ~/.ssh):
borg extract ::rice-panasonic-2026-07-03_1200 home/pj/.ssh
```

Preview without writing anything: add `--dry-run --list`. Mount an archive to
browse it like a folder: `borg mount ::<archive> /mnt/point` (then `borg umount`).

> This was verified end-to-end with a throwaway encrypted repo: init → create →
> prune → compact → extract round-tripped a file byte-identical, and a wrong
> passphrase was rejected.

---

## Vorta (GUI daily schedule)

Vorta is a Qt GUI over the **same** borg repo. It was left **unconfigured on
purpose** — its config is a SQLite profile DB whose schema shifts between
versions, so hand-seeding it is fragile and not cleanly reversible. Instead, do
this one-time click-through (2 minutes). It points Vorta at the repo the script
already created, so run `backup-eva.sh` **once first** (or let Vorta init it).

1. Plug in eva and mount it (`udisksctl mount -b /dev/sda2`).
2. Launch **Vorta** (app grid / `vorta`).
3. **Repository → Add existing repository** (run `backup-eva.sh` once first so
   the repo exists). Path:
   `/run/media/pj/eva/backups/borg-rice`
   When asked for the **passphrase**, paste the "borg eva backup" entry from
   Proton Pass. Vorta stores it in your keyring so scheduled runs don't prompt.
   Click **Add**.
4. **Sources** tab → **Add folder** (use **Add file** for the last one):
   - `/home/pj/git/dotfiles`
   - `/home/pj/.ssh`
   - `/home/pj/Pictures`
   - `/home/pj/.config/VSCodium/User/settings.json`
5. **Schedule** tab → tick **Backup every … day(s)** and set a daily time (e.g.
   14:00). Also tick **"but only if the repository drive is mounted"** so it
   skips silently when eva is unplugged. (Vorta has its *own* scheduler and must
   be running — it is not a systemd timer; `docs/backups.md` is the plan that
   replaces this with borgmatic + a real timer.)
6. **Pruning** tab → enable it, set **Keep 7 daily, 4 weekly, 6 monthly** to
   match the script.
7. (Optional) **Exclude** patterns → add `node_modules`, `.cache`, `*.tmp`,
   `*.swp` to mirror the script's excludes.
8. Click **Start Backup** once to confirm it works.

The script and Vorta share one repo and one retention policy, so you can use
either — Vorta for the automatic daily run, the script for a manual/CLI backup.

---

## When gitea exists (future)

eva is the **interim** target. Once my Gitea and backup server are up:

1. Give the repo a remote — one line, then `git push` after each commit:
   `cd ~/git/dotfiles && git remote add origin <gitea-url> && git push -u origin main`
2. Move the borg target to the server: `borg init -e repokey-blake2 pj@<backup-host>:/srv/backups/rice`,
   then change `REPO=` in `backup-eva.sh` (or add the SSH path as a second repo in Vorta).
   Same passphrase workflow — repokey travels inside the repo, Proton Pass keeps the passphrase.
3. Keep eva as the offline second copy (3-2-1 rule: two places, one offline).

Until then the repo is intentionally remote-less; its history is covered by the
eva backup (`~/git/dotfiles` is in the backup set).

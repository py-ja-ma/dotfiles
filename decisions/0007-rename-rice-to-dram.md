# 0007: The project's word is dram, not rice

[Operations › dram CLI](../docs/operations/dram/README.md) · accepted 2026-10-06

Every name that said rice says dram, and the old state moves once per host; the cost was a release of shims and a root step on each host.

## Context

The CLI, the Nix option namespace, the package repo, the state directories and
the docs all carried the word `rice` — /r/unixporn's term for a customised
desktop. It named the whole setup well enough while it was one laptop's
Hyprland config; it reads oddly next to the seventeen Letterpress themes, which
are named for drinks (`docs/design/README.md`), and it collides with the food in
every sentence that explains it.

## Decision

The word is **`dram`** — a measure of whiskey — everywhere, with one scripted
word-boundary pass (`rice`→`dram`, `Rice`→`Dram`, `RICE`→`DRAM`, plus the
`RICE_*` / `rice_*` identifiers) and the files moved with `git mv`:

| was | is |
|---|---|
| `dotfiles/.local/bin/rice`, `rice-switch`, `rice-theme`, `rice-theme-auto`, `gsimplecal-rice.sh`, `iwgtk-rice.sh` | `dram`, `dram-switch`, `dram-theme`, `dram-theme-auto`, `gsimplecal-dram.sh`, `iwgtk-dram.sh` |
| `completions/rice`, `bin/sync-rice-repo.sh`, `system/pacman-rice-repo.sh`, `system/rice-builder-setup.sh`, `system/system-rice.sh` | `completions/dram`, `bin/sync-dram-repo.sh`, `system/pacman-dram-repo.sh`, `system/dram-builder-setup.sh`, `system/system-dram.sh` |
| `docs/rice-cli.md`, `rice-terminal.md`, `rice-nix-manager.md`; `pkgs/rice.asc` | `docs/dram-cli.md`, `dram-terminal.md`, `dram-nix-manager.md`; `pkgs/dram.asc` (same bytes until the key is re-exported) |
| `rice.*` options, `_module.args.rice`, `rice.link` | `dram.*`, `_module.args.dram`, `dram.link` |
| `RICE_REPO`, `RICE_PEER`, `RICE_GPGKEY`, `RICE_LAPTOP`, `RICE_HOST`, … | `DRAM_*` |
| `~/.config/rice`, `~/.local/state/rice`, `~/.cache/rice`, `~/.cache/rice-pkgs` | `~/.config/dram`, … (moved once by `dram switch` / `dram update`; `gpgkey`, `release`, `channel`, `builds/` keep their names inside) |
| `rice-theme-auto.{service,timer}` | `dram-theme-auto.{service,timer}` (Home Manager replaces the units on the switch) |
| `[rice]`, `/etc/pacman.d/rice.conf`, `/var/lib/rice-repo/rice.db*`, `/srv/rice`, `/var/lib/archbuild/rice-x86_64` | `[dram]`, `dram.conf`, `/var/lib/dram-repo/dram.db*`, `/srv/dram`, `dram-x86_64` (root, see below) |
| commit subjects `rice: …` | `dram: …` (`bin/release.sh` buckets both) |

**Not renamed**: `CHANGELOG.md`, `pkgs/BUILDLOG`, the superseded files of the time
(retired from the repo since) and the six docs the handbook index marks as history (`docs/history/panasonic-survey-2026-10-05.md`,
`docs/history/rice-README-original.md`, `docs/history/fixes-2026-10-05.md`, `docs/history/rice-backup.md`,
`docs/history/rice-reinstall.md`, `docs/history/tonight.md`; under `docs/history/` since
2026-10-07, at the `docs/` root before) keep their names and their text.
The one sentence that explains the old name lives in `README.md`.

**Shims for one release.** `rice`, `rice-switch`, `rice-theme` and
`rice-theme-auto` remain as four-line scripts that print `rice is now dram` on
stderr and `exec` the new name (resolved next to themselves through the
`~/.local/bin` symlink, so `rice switch` works before the first `dram switch`
has linked `dram`). They answer `--help` and are linked by `modules/desktop.nix`
/ `theme.nix`; `docs/commands.md` lists them under "renamed". They go in the
release after v2026.10.2.

**Removed 2026-10-07 (shipped in the next release, the one after v2026.10.7):**
the four `rice*` scripts, their `modules/desktop.nix` / `theme.nix` links, the
`treefmt.toml` entries and the `complete … rice` alias in the bash completion.
`migrate_rice_dirs` in `dram` and `--migrate-from-rice` in the two root scripts
stay: they move state, not names.

**Root-level migration**, scripted and dry-runnable, run once per host as root:

```sh
sudo bash system/pacman-dram-repo.sh --dry-run --migrate-from-rice   # then without --dry-run, both hosts
sudo bash system/dram-builder-setup.sh --dry-run --migrate-from-rice # then without --dry-run, cabin only
```

The first swaps the `Include` line in `/etc/pacman.conf` to `dram.conf` in
place, removes `rice.conf`, moves `/var/lib/rice-repo` and renames `rice.db*` /
`rice.files*` inside it (plain renames; `repo-add`'s symlinks are re-pointed; the
detached signatures sign the unchanged tarball bytes, so they stay valid),
writes `dram.conf`, and ends with `pacman -Sy`. The second does the same for
`/srv/rice`, moves the chroot, adds the uid `pj dram packages <…>` to the signing
key as the builder user and makes it primary, re-exports `pkgs/dram.asc` and prints the commit command.

## Consequences

- `dram doctor` warns `[dram] repo is still configured under its pre-2026-10-06
  name` with the migration command until the root step has run on that host;
  `pacman -Sl rice` keeps working until then, `pacman -Sl dram` after.
- `system/backup-eva.sh` moves the drive's `borg-rice` repo to `borg-dram` on
  its next run and prunes both archive prefixes under the same rule.
- `bin/sync-dram-repo.sh` mirrors to `~/backups/dram/` on the Mac (the old
  mirror directory was moved by hand).
- The `hosts/<h>/` harvest copies (`etc/pacman.conf`, `systemd/enabled-user.txt`)
  were renamed with the tree and describe the post-migration state; `dram
  harvest` after the root step makes them exact again.

## How it is checked

Nothing checks the word itself.
`dram doctor` warns `[dram] repo is still configured under its pre-2026-10-06 name`, with the migration command, until the root step has run on a host.

## History

- 2026-10-06: accepted; the user layer renamed on both hosts, with shims for one release; the root-level moves run once per host.
- 2026-10-07: the four `rice*` shims removed, shipped in the release after v2026.10.7.

# Releases and pushes

[Operations](../README.md) › Releases and pushes

How a commit on the Mac becomes what a host runs.
A build is a commit, a release is a tagged build with release notes, a channel decides which build a host follows, and the previous build is one command away.
The vocabulary is the Steam Deck's, and the hosts are the Arch machines, the WSL clones and the Windows PCs.

| Branch | What it does | Code | Copy alone |
|---|---|---|---|
| Releases | tags the next `vYYYY.MM.N`, writes its `CHANGELOG.md` section, pushes it to every host | `bin/release.sh` | yes, with `bin/push-host.sh` and a check script to gate on |
| Channels | decides whether a host follows the newest release or the newest push | `dram channel`, `dram update` | no: part of `dram` |
| Pushes | carries commits and tags to the hosts as a git bundle, a release to a Windows PC, and the `[dram]` repo from the builder to the other hosts | `bin/push-host.sh`, `bin/push-windows.sh`, `install/lib/windows-stage.sh`, `bin/sync-dram-repo.sh` | each script's header says ([Pushes](pushes.md)) |
| Host records | writes a host's packages, units and `/etc` copies into `hosts/<host>/`, compares two hosts, forgets a retired one | `bin/harvest.sh`, `bin/diff-hosts.sh`, `bin/forget-host.sh` | yes, with ssh and a `hosts/<host>/` layout |

## How the branches fit

The hosts have no git remote.
`bin/release.sh` gates on `bin/check.sh`, tags the release, and hands each host to `bin/push-host.sh`, whose bundle carries the branch and every tag.
On a host, `dram update` resolves the channel's target among those tags and checks it out ([dram CLI](../dram/README.md#dram-update)).
A WSL clone gets the same bundle through its Windows PC, and a Windows PC gets its own release from `bin/push-windows.sh` ([Pushes](pushes.md)).

```text
Mac:  edit, commit -> bin/check.sh -> bin/release.sh -> bin/push-host.sh (bundle: master + tags)
host: dram update  -> checkout of the channel target -> pacman -Syu -> dram switch -> dram doctor --brief
```

## Builds and releases

A build is a commit of this repo.
Its id is `<commit date>.<short sha>` (`20261006.74acdbe`), the shape of a SteamOS `BUILD_ID`, computed from git and not stored in the repo.

A release is an annotated tag `vYYYY.MM.N` on a build.
The number is the year and the month, and `N` counts up within the month, like SteamOS build numbers (`20240508.1`).
`bin/release.sh` on the Mac cuts one:

```sh
bin/release.sh --dry-run                      # the next tag, the CHANGELOG section, the push targets
bin/release.sh -m "one line: what this is"    # commit CHANGELOG.md, tag, push to every host
bin/release.sh -m "<summary>" --checkpoint    # a build every host must pass through (below)
bin/release.sh -m "<summary>" --no-push       # tag only; bin/push-host.sh later
```

It runs these steps in order:

1. It checks that the tree is clean, on `master`, and that `bash bin/check.sh` passes.
2. It computes the next tag for this month from the existing `v*` tags.
3. It writes a section at the top of `CHANGELOG.md`: the tag, the date, the summary, and the commits since the previous tag.
   The commits are grouped `dram`, `docs`, `pkgs` and `other` by their subject's prefix when any commit has one.
4. It commits that file as `release vX: <summary>` and tags the commit, with the summary as the annotation.
5. It runs `bin/push-host.sh <user>@<address>` for every `modules/hosts/*.nix` that sets `dram.address`, and `bin/push-host.sh --wsl` for a WSL clone.

A clone whose Windows PC is off, or booted into Arch, gets a warning, and the release still counts.
`CHANGELOG.md` holds the release notes, newest first, and `dram changelog` prints them on a host.

## The identity file

`dram switch` writes `~/.config/dram/release` after each successful activation, and `dram rollback` after it activates a generation.
It has the shape of `os-release`, one `KEY=value` per line:

| Key | Value |
|---|---|
| `ID` | `dram` |
| `VERSION_ID` | the nearest `v*` tag at or below the commit, or `0.0.0-dev` before the first release |
| `BUILD_ID` | `<commit date YYYYMMDD>.<short sha>` |
| `COMMIT` | the full sha |
| `BRANCH` | the channel at the time, `stable` or `main` |
| `HOST` | `/etc/hostname` |
| `HM_GENERATION` | the newest Home Manager generation id when the file was written; builds are compared by store path, because a rollback mints a new id for an old path |
| `FLAKE_LOCK` | the first 12 hex digits of `sha256(flake.lock)` |
| `SWITCHED` | ISO 8601 |

`dram version` prints it as a card, and `dram version --json` as one JSON object with the keys in lower case.
The JSON adds `ahead_of`, which is `{tag, commits}` past the nearest tag or `null` on a release, and `checkout`, what the working tree is at.

```text
dram v2026.10.1 · build 20261006.3b1f2c0 · channel stable
  commit       3b1f2c0 (release v2026.10.1: first tagged release)
  host         lantern
  generation   59 (2026-10-06 22:40)
  switched     2026-10-06T22:40:12-06:00
  flake.lock   02075f20f275
```

When the checkout has moved past the switched build, the card says so: the build exists but is not active, and `dram switch` activates it.
`~/.local/state/dram/last-switch`, in epoch seconds, is still written for the scripts that read it.

## Channels

`~/.config/dram/channel` holds one word:

| Channel | `dram update` follows | For |
|---|---|---|
| `stable` | the highest `v*` tag on the host's local refs | a host that runs only cut releases |
| `main` | `master` as last pushed from the Mac | the canary, or a host being worked on |

`dram channel` prints the channel and its target, and `dram channel stable` or `dram channel main` writes the file.
Without the file the channel is `stable` once a tag exists on the host, and `main` before.
`dram channel --target` prints `<channel> <target> <commits>` for scripts, with `commits` 0 when the checkout is the target; the welcome toast and the bar badge use it.

The slot switch is a checkout.
The hosts' `~/.local/bin` and `~/.config` are symlinks into `~/git/dotfiles`, so the checkout is the live configuration.
`dram update` resolves the channel's target on the local refs, then runs `git checkout --detach <tag>` on `stable` or `git checkout master` on `main`.
It refuses when tracked files have uncommitted edits, and says how to commit, stash or discard them; untracked and ignored files stay out of the way.

`dram update --check` adds one line, `dram: <current> -> <target> (N commits)` or `dram: up to date`.
It exits 7 when nothing at all is pending (no package, no Flatpak, no build), the convention of SteamOS's `steamos-update check`.
Exit 0 means there is something to apply, and any other exit is the builder's own status: read its output.

`bin/push-host.sh` follows the channel too.
A host on a branch (`main`) is reset to the pushed tip.
A host detached at a release (`stable`) gets its refs updated and keeps its checkout until `dram update` moves it to the newest tag.
So a push makes a release available on a stable host, and the host's `dram update` applies it.
`dram update` also fixes the attachment when the commit is already right: a stable host ends detached at its tag, and a main host attached to `master`.

## Checkpoints

A release whose annotation contains the word `checkpoint` (`bin/release.sh --checkpoint`) is a build every host passes through on its way to a later one.
It mirrors the checkpoint builds of SteamOS's `steamos-atomupd`, for a change the next build depends on: a migration in `dram switch`, a renamed state file, a package that must be installed before the one after it.
When the way from the checkout to the channel's target crosses a checkpoint, `dram update` applies the checkpoint instead and ends with `checkpoint vX reached, run dram update again`, exit 0.
The second run continues to the target, and `dram update --check` says `via checkpoint vX first` when one lies on the way.

## The previous build

Before `dram update` or `dram rollback` changes anything, it records the running build under `~/.local/state/dram/builds/<BUILD_ID>/`:

| File | Holds |
|---|---|
| `release` | the identity file as it was |
| `pkgs.txt` | `pacman -Q` |
| `hm-generation` | `<id> <store path>` of the active Home Manager generation |
| `commit` | the sha |

The last five records are kept, and `dram rollback --list` (or `dram builds`) shows them, newest first, with the running one marked.

`dram rollback` with no argument goes to the newest record whose commit or generation differs from what runs.
It records the current build first, checks out that commit, activates that generation, and rewrites the identity file.
It prints the package side and runs none of it.
That is one `sudo pacman -U /var/cache/pacman/pkg/<file>` line per package whose previous version is still cached (`paccache -rk2` keeps two), and a note for each that is not.
A package that did not exist then gets a `pacman -Rns` line.
`dram rollback N` goes N Home Manager generations back and leaves the checkout alone.

## What a host shows without asking

| Where | What it shows |
|---|---|
| the welcome toast (`welcome.sh`) | `dram vX available (stable)` when the channel's target is not the checkout, and `update applied — reboot to finish` while `~/.local/state/dram/reboot-required` is newer than this boot |
| the bar badge (`waybar-updates.sh`, `custom/updates`) | a pending build counts as one more pending item; the tooltip names the target tag and the channel; a click runs `dram update` |
| `dram doctor`, dram section | the running version, build, channel and generation, and a warning with its fix when the checkout is not the switched build or the host is behind its channel |

The badge caches package counts for 30 minutes, so it can disagree with the toast's live count for that long.
The build part of the badge is read from local git each time.

## What does not map from SteamOS

| SteamOS | Here | Why |
|---|---|---|
| A/B root partitions, the update written to the idle slot and booted into | a git checkout plus Home Manager generations | the user layer sits on a mutable Arch root, so there is no second root to flash; git makes the files atomic enough, and a failed `dram switch` leaves the previous generation active |
| a read-only root, `steamos-readonly disable` to touch it | none | pacman owns the packages, and `system/maintenance.sh` converges `/etc` |
| the image as the unit of update | the commit, with pacman as a separate stream | Arch updates packages continuously; the repo pins its own content and `flake.lock`, and `dram update` runs both streams in one command |
| "previous build" boots the other slot | `dram rollback`: the previous commit and generation, and printed `pacman -U` lines | the package side cannot be atomic without a second root, so it is made explicit, and the cache keeps two versions of each package |
| `steamos-select-branch` with rel, rc, beta and main | `dram channel stable` or `main` | two channels cover two kinds of host: a canary on `main` and hosts that run only releases |
| an update server (`steamos-atomupd`) | `bin/push-host.sh` from the Mac, tags in the bundle | the hosts have no remote, and the Mac is the source of truth |

System snapshots fill part of the gap since 2026-10-11: `dram rollback --system` makes a snapper snapshot the new root ([decision 0011](../../../decisions/0011-disk-boot-secure-boot-snapshots.md)).

## A host that fell behind

A host that is days or weeks behind needs only `dram update`, with `dram update --check` as the preview.
This procedure is for a host months behind, where the transaction is too big to risk on an ssh session.
I first used it on cabin on 2026-10-05, about four months and 638 packages behind.

Before the upgrade, in order:

```sh
pgrep -a pacman; ls /var/lib/pacman/db.lck   # a transaction already running, or one interrupted?
sudo pacman -Sy archlinux-keyring           # the keyring first: a stale one fails the signatures
pacman -Qqe > ~/explicit.txt                # what you have, to rebuild or roll back from
pacman -Q > ~/all-versions.txt
sudo pacman -Su --print --print-format '%n' # the dry run that finds the blockers
```

Read the Arch news first, from another network such as a phone hotspot.
archlinux.org is unreachable from this LAN, and the VPN leaves through the same home address ([handbook chapter 11](../../records/handbook/11-troubleshooting.md)).
Months of Arch carry manual interventions, so check each news item against what is installed.
Keep `/var/cache/pacman/pkg` until the host works again: it holds the old versions for a downgrade.

Run the upgrade detached, so it survives a dropped ssh session:

```sh
sudo systemd-run --unit=arch-upgrade \
  --property=StandardOutput=file:/tmp/upgrade.log \
  --property=StandardError=append:/tmp/upgrade.log \
  --property=TimeoutStartSec=infinity \
  pacman -Su --noconfirm --noprogressbar --disable-download-timeout
systemctl is-active arch-upgrade
tail -f /tmp/upgrade.log
systemctl show arch-upgrade -p Result -p ExecMainStatus
```

Then check and finish:

```sh
dram doctor --boot   # dkms per kernel, pacnew, orphans, failed units, the ESP, a reboot needed
dram pacnew          # merge each file; do not take the new one blindly
dram switch          # the Home Manager layer
dram harvest         # then commit hosts/<host>/
```

Reboot afterwards: the running kernel's modules were replaced on disk.

A package that pins `=exact-version` of another vetoes the whole transaction.
On 2026-10-05 `lib32-audit` and `qemu-block-gluster` stopped the upgrade that way:

```text
:: installing audit (4.2.1-1) breaks dependency 'audit=4.1.4' required by lib32-audit
:: installing qemu-common (11.1.1-4) breaks dependency 'qemu-common=11.0.1-1' required by qemu-block-gluster
```

`pacman -Rdd <pkg>` removes only the pinning package, without its dependants, and the upgrade then goes through.
Rebuild or replace the package afterwards.
Since 2026-10-06 the packages that came from the AUR are vendored, reviewed and built once into the signed `[dram]` repo, so a host no longer builds them itself ([Packaging](../../toolchain/packaging/README.md)).

## Operating it

Cutting a release and moving a host between channels are handbook [chapter 4](../../records/handbook/04-update-version-rollback.md), sections 8 and 9.
Retiring or renaming a host, with `bin/forget-host.sh`, is [chapter 10](../../records/handbook/10-teardown.md) and [chapter 9](../../records/handbook/09-move-or-rename.md).

## Status

As of 2026-10-13:

- The newest release is v2026.10.27, of 2026-10-12.
- `bin/release.sh` writes section headings as `## vX — <date>` and groups commits by subject prefix.
  Changelog groups by kind of change (added, changed, fixed, removed, security) are not built.
- A host sees re-pointed documentation paths in `dram`'s messages only after the release that carries them.

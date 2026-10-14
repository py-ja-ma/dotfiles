# 4. Update, version, rollback

What a host runs, how it moves to the next build, and how it goes back. The
vocabulary is the Steam Deck's: a **build** is what runs, a **release** is a
build with a name and notes, a **channel** decides which build a host follows,
and the **previous build** is one command away. Every command prints what it
did; the quoted blocks are from lantern on 2026-10-06 (the Mac for section
8), except that the `dram update` and `dram rollback` blocks in sections 5 and 6
are the code's own strings (`dotfiles/.local/bin/dram`). Depth: `docs/operations/releases/README.md` (the model, and what does not map from SteamOS),
`docs/operations/dram/README.md` (every flag), `docs/commands.md` ("Release" table),
`bin/release.sh --help`, `bin/push-host.sh --help`.

## Before you start

- Chapter 3 is done: `dram update` has run once on this host and `dram doctor`
  shows no warnings.
- `dram switch` has run since the release model landed, so
  `cat ~/.config/dram/release` prints nine `KEY=value` lines. `dram version`
  refuses with `[x] no /home/pj/.config/dram/release yet — dram switch writes it`
  until it has.
- A terminal, not a pipe: `dram update` asks about orphans and `dram rollback`
  asks before it moves; a question with no terminal is answered `n`
  (`ssh -t pj@<host> dram rollback` keeps the terminal). Once a desktop host's
  YubiKey second factor is on, the sudo inside these needs the key at that
  machine: run them at its keyboard (`docs/security/identity/yubikeys.md`).
- For the release half: the Mac with a clean tree on `master` and SSH to every
  host (`dram.address` in `modules/hosts/*.nix`).

## 1. Builds and releases

Two things can go back: the **dram build** (sections 1–9: this repo's checkout and its
Home Manager generation — the user layer) and the **system** (section 10: the packages and
`/etc`, from the snapshot taken before every pacman transaction). They are independent.

A **build** is a commit of `~/git/dotfiles`. Its id is `<commit date>.<short sha>`,
computed from git, never stored in the repo. The hosts' `~/.local/bin` and
`~/.config` are symlinks into that checkout, so the checkout *is* the running
configuration once `dram switch` has activated it.

A **release** is an annotated tag `vYYYY.MM.N` on a build, cut on the Mac by
`bin/release.sh` (section 8), with a section in `CHANGELOG.md`. The hosts have
no git remote: tags and `master` arrive in the bundle `bin/push-host.sh`
pipes over SSH, so a release exists on a host only after a push.

```sh
git -C ~/git/dotfiles tag                  # v2026.10.1
git -C ~/git/dotfiles log --oneline -1     # ac23151 release v2026.10.1: first tagged release: handbook chapters 1–3
```

## 2. `dram version` — what runs

`dram switch` writes `~/.config/dram/release` after every successful
activation (and `dram rollback` after every activation it does). It is
`os-release` in shape; `dram version` prints it as a card:

```
dram v2026.10.1 · build 20261006.ac23151 · channel stable
  commit       ac23151 (release v2026.10.1: first tagged release: handbook chapters 1–3)
  host         lantern
  generation   58 (2026-10-06 21:13)
  switched     2026-10-06T21:44:22-04:00
  flake.lock   02075f20f275
```

| Line | Meaning |
|---|---|
| `v2026.10.1` | `VERSION_ID`: the nearest `v*` tag at or below the switched commit; `0.0.0-dev` before the first release reached this host |
| `build 20261006.ac23151` | `BUILD_ID`: commit date and short sha |
| `channel stable` | what `dram update` follows (section 3) |
| `generation 58 (…)` | the Home Manager generation that activation produced, and its date |
| `switched` | when `dram switch` (or `dram rollback`) wrote the file |
| `flake.lock` | the first 12 hex of `sha256(flake.lock)`: two hosts with the same value run the same nix pins |

Two extra lines appear when they apply: `N commits ahead of vX` when the
switched build is past its nearest tag (a `main` host between releases), and
`[!] the checkout is at <name>, not the switched build — dram switch` when
the working tree has moved (a push landed, or `dram update` checked out a
target and the switch failed). That second state is "built but not
activated"; `dram switch` resolves it.

`dram version --json` prints the same as one object for scripts, with
`ahead_of` (`null` on a release) and `checkout` (what the tree is at now):

```
{"id":"dram","version":"v2026.10.1","build":"20261006.ac23151","commit":"ac23151beae85ef3d09ac45835a627e78d30c210","channel":"stable","host":"lantern","generation":"58","generation_date":"2026-10-06 21:13","flake_lock":"02075f20f275","switched":"2026-10-06T21:44:22-04:00","ahead_of":null,"checkout":"v2026.10.1"}
```

`cat ~/.config/dram/release` is the raw file (`ID`, `VERSION_ID`, `BUILD_ID`,
`COMMIT`, `BRANCH`, `HOST`, `HM_GENERATION`, `FLAKE_LOCK`, `SWITCHED`).

## 3. Channels — what a host follows

`~/.config/dram/channel` holds one word. `dram channel` prints it with the
target it resolves to on the host's local refs, and whether the checkout is
there:

```sh
dram channel             # stable — the latest release tag (v2026.10.1, checked out)
dram channel --target    # stable v2026.10.1 0      (for scripts: channel, target, commits away)
```

| Channel | `dram update` moves the checkout to | For a host that |
|---|---|---|
| `stable` | the highest `v*` tag on the host, `git checkout --detach <tag>` | only ever runs a cut release; a push from the Mac makes a release *available*, `dram update` applies it |
| `main` | `master` as last pushed from the Mac, `git checkout master` | is the canary or is being worked on; every `bin/push-host.sh` resets it to the pushed tip at once |

Without the file the channel is `stable` once any `v*` tag exists on the host
and `main` before, and `dram channel` adds
`(default: no /home/pj/.config/dram/channel; dram channel stable|main writes it)`.
`dram channel stable` / `dram channel main` writes the file and says what it
means:

```
[ok] channel: stable — dram update follows the latest release tag (v*)
    the checkout is already at v2026.10.1
```

or `    target vX is N commits from the checkout: dram update`. Writing the
file moves nothing; the next `dram update` does (section 9). A channel with
nothing to follow yet (`stable` on a host that has never received a tag) says
`[!] nothing to follow yet (no v* tag on this host)`, and `dram update` leaves
the checkout where it is.

The welcome toast says `dram vX available (stable)` and the bar's updates
badge counts one more item (tooltip `dram: vX available (stable, N commits) —
dram changelog`) whenever the target is not the checkout; both read
`dram channel --target`.

## 4. `dram update --check` — is anything pending

Read-only, over SSH if you like. It lists pending repo (including `[dram]`) and Flatpak
updates, fixable CVEs, the channel target, then *builds* (never switches) the
dram to prove the flake still evaluates:

```
==> Pending repo updates (checkupdates — read-only, own temp DB)
[ok] no repo updates

==> Pending Flatpak updates (flatpak remote-ls --updates)
[ok] no flatpak updates

==> Vulnerable packages with a fix available (arch-audit -u)

==> Dram (channel stable: the latest release tag)
dram: up to date (v2026.10.1)

==> Proving the dram still evaluates (build only — NOT switched)
$ home-manager build --flake /home/pj/git/dotfiles#pj@lantern --extra-experimental-features nix-command flakes --no-out-link
[ok] dram builds for pj@lantern

==> Check done. Nothing is pending (exit 7). Nothing was changed.
```

| Exit | Means | Last line |
|---|---|---|
| `7` | nothing at all is pending: no package, no Flatpak, no dram build | `Check done. Nothing is pending (exit 7). Nothing was changed.` |
| `0` | something is pending; the dram line reads `dram: v2026.10.1 -> v2026.10.2 (N commits)` and/or a package list printed | `Check done. Nothing was changed.` |
| other | the flake failed to build: `[!] dram build FAILED for pj@<host> — fix the flake before 'dram update'` | `Check done. Nothing was changed.` |

Exit 7 is the SteamOS `steamos-update check` convention: `dram update --check;
echo rc=$?` printing `rc=7` is the healthy weekly answer. A checkpoint on the
way (section 7) adds `    via checkpoint vX first (dram update twice)`.

## 5. `dram update` — the daily flow

One command, in this order. Each heading is a `==>` line; the `[ok]` lines are
what a healthy run prints.

1. **Record the running build.** `Recording the running build (dram rollback
   goes back to it)` → `[ok] builds/20261006.ac23151 (v2026.10.1, generation 58)`.
   The snapshot lands under `~/.local/state/dram/builds/<BUILD_ID>/` (section 6)
   before anything changes.
2. **Resolve the channel and move the checkout.** `Channel stable`, then one of:
   - `[ok] the checkout is the channel target (v2026.10.1 = v2026.10.1)` — nothing
     to move. If the commit is right but the attachment is wrong it is fixed
     here: `[ok] detached at v2026.10.1 (a push from the Mac waits for dram
     update)` on stable, `[ok] attached to master (follows pushes from the Mac)`
     on main.
   - `    v2026.10.1 -> v2026.10.2 (N commits)`, then
     `$ git -C /home/pj/git/dotfiles checkout -q --detach v2026.10.2` (or
     `checkout -q master`) and `[ok] checkout at v2026.10.2`.
   - a refusal: uncommitted edits to tracked files stop the run here, with the
     files listed and
     `[x] uncommitted edits to tracked files in /home/pj/git/dotfiles — commit
     them (git -C /home/pj/git/dotfiles commit -a), stash them (git -C
     /home/pj/git/dotfiles stash), or discard (git -C /home/pj/git/dotfiles
     checkout -- <file>); then dram update again`. Untracked and ignored files
     are never in the way.3. **sudo once**; a keepalive keeps the ticket fresh through the upgrade.
4. **Keyring.** `[ok] archlinux-keyring is current`, or `archlinux-keyring
   refreshed first` when `pacman -Qu archlinux-keyring` said it was behind.
5. **Package cache** `$ sudo paccache -rk2`: two versions of everything stay in
   `/var/cache/pacman/pkg`; that is the offline downgrade path section 6 prints.
6. **Upgrade** `sudo pacman -Syu` (official + `[dram]` in one transaction; no AUR
   helper since 2026-10-10, `decisions/0013`) → `[ok] system software up to date`.
7. **Flatpak** `$ sudo flatpak update -y --noninteractive`.
8. **pacnew / pacsave** → `[ok] none`, or the list and `[!] merge them with: dram pacnew`.
9. **Orphans** → `[ok] none`, or the list and the question `Remove them (sudo
    pacman -Rns)? [y/N]`; `n` prints `kept. Later: sudo pacman -Rns $(pacman -Qqdt)`.
10. **Switch.** `Rebuilding the dram (home-manager flake at /home/pj/git/dotfiles)`
    → `[ok] dram rebuilt (current generation active)`; this writes
    `~/.config/dram/release`. A failure prints `[!] dram rebuild FAILED — the
    PREVIOUS generation is still active, nothing broke`; the checkout has
    moved, the generation has not, and `dram version` says so until
    `dram switch` succeeds or `dram rollback` returns.
11. **Reboot?** `[ok] no reboot needed`, or the reasons and `[!] reboot when
    convenient` (section 7).
12. **Doctor.** `dram doctor --brief`: only warnings, each with its fix.
13. `==> Done.`

Flags (`dram update --help`): `--clean` adds generation expiry and garbage
collection after the switch (chapter 3; a build whose generation has expired
cannot be rolled back to), `--full` runs `nix flake update` first and restores
`flake.lock` if the new pins fail to switch, `--no-switch` stops before 10.

## 6. The previous build — `dram builds`, `dram rollback`

Step 1 of every `dram update` (and of every `dram rollback`) records the build
that is running under `~/.local/state/dram/builds/<BUILD_ID>/`: `release`
(the identity file as it was), `pkgs.txt` (`pacman -Q`), `hm-generation`
(`<id> <store path>`), `commit`. The last five are kept.

```sh
dram builds                       # = dram rollback --list; newest first, the running one marked
```

On a host that has not run `dram update` since the model landed it prints
`    no builds recorded yet (dram update records one before it changes anything)`
(lantern); afterwards a table with the columns `build  version  commit
gen  recorded` and `  (= the running build)` on the current row.

`dram rollback` with no argument is "previous build": the newest record whose
commit *or* generation differs from what runs.

```
==> Previous build: 20261006.ac23151 (v2026.10.1, recorded 2026-10-06 21:44)
    commit      ac23151 release v2026.10.1: first tagged release: handbook chapter  (now: v2026.10.2)
    generation  58 /nix/store/…-home-manager-generation  (now: 59)
    Roll back to it? (the checkout moves, the generation is activated; pacman lines are printed, not run) [y/N] y
==> Recording the running build first (dram rollback again = forward)
[ok] builds/20261006.<sha>
==> Checkout
$ git -C /home/pj/git/dotfiles checkout -q --detach <commit>
[ok] checkout at v2026.10.1
==> Home Manager generation 58
$ /nix/store/…/activate
[ok] generation 58 active
==> Packages that differ from the previous build (printed, not run — the cache keeps 2 versions)
    sudo pacman -U /var/cache/pacman/pkg/<name>-<old>-x86_64.pkg.tar.zst   # <name> <new> -> <old>
    <name> <new> -> <old>   (not in /var/cache/pacman/pkg: paccache trimmed it; downgrade from the ALA)
    <name> <ver> was not installed in the previous build:  sudo pacman -Rns <name>

[ok] back on v2026.10.1 build 20261006.ac23151. Forward again: dram rollback (to the build just recorded) or dram update
```

(The lines above are the code's own strings, `dotfiles/.local/bin/dram`.) What it
does, in order: records the current build (so a second `dram rollback` is
"forward"), asks, checks out the recorded commit (`master` if that is where
`master` points, detached otherwise; the same dirty-tree refusal as an
update), activates the recorded generation with a dated `bak-<stamp>` backup
suffix, rewrites `~/.config/dram/release`, and prints the package side.

What does **not** roll back on its own:

- **pacman.** Nothing in pacman is run. One `sudo pacman -U
  /var/cache/pacman/pkg/<file>` line is printed per package whose previous
  version is still in the cache (`paccache -rk2` keeps two), a note for each
  that is not (the Arch Linux Archive is the way then), a `pacman -Rns` line
  for packages that did not exist in that build, and `sudo pacman -S <name>`
  for one that has since been removed. `[ok] packages: identical to the
  previous build` when nothing differs. Paste what you want; the system layer
  (`/etc`, hooks, timers from `system/maintenance.sh`) is not part of a build at all —
  to put packages and `/etc` back together, roll the system back (section 10).
- **The kernel.** It is a package on that list like any other: pasting its
  `pacman -U` line reinstalls the old kernel and the hook rebuilds the
  initramfs, but the *running* kernel changes only at the next boot, and until
  then `dram doctor` says `reboot needed`.
- **An expired generation.** After `dram update --clean` has expired it the
  record is still listed but cannot be activated:
  `[x] generation N is gone (… dram update --clean expired it); check out
  <commit> and dram switch instead`.

`[x] no previous build differs from the running one (<BUILD_ID>); dram rollback
--list` means every record is the build that runs now. `dram rollback N` keeps
its old meaning — N Home Manager generations back, the checkout untouched —
and ends `[ok] generation from <date> is active. Forward again: dram switch`.

## 7. Reboot rules, and checkpoints

`dram update` ends with `Reboot?` and `dram doctor` has a `reboot needed`
line. Both fire for exactly three reasons: `running kernel <ver> is no longer
on disk (kernel updated)`, `the running Hyprland binary was replaced (hyprland
updated)`, or `~/.local/state/dram/reboot-required` is newer than this boot
(`dram update` writes it when `nvidia-utils` or `hyprland` changed version).
While that file is newer than the boot, the welcome toast adds `update applied
— reboot to finish`. The old kernel's modules are gone from disk after a kernel
update, so reboot before relying on a USB device or VPN that needs a module not
yet loaded. Nothing in `dram switch`, `dram channel` or a `dram rollback` whose
printed pacman lines you did not paste needs a reboot; a pasted kernel line does.

A **checkpoint** is a release whose tag annotation contains the word
`checkpoint` (`bin/release.sh --checkpoint`): a build every host must pass
through, for a change the *next* build assumes has run. When one lies between
the checkout and the channel target, `dram update` warns `[!] checkpoint vX
lies between <current> and <target> — applying it first`, runs the whole flow
for it, and ends with `==> checkpoint vX reached, run dram update again` and
`    the channel target is vY; this build had to be passed through on the way
there`, exit 0. The second run continues to the target.

## 8. Cutting a release (Mac)

```sh
cd ~/git/dotfiles
git status --short                       # prints nothing; on master
bin/release.sh --dry-run                 # the next tag, the CHANGELOG section, the push targets; changes nothing
bin/release.sh -m "one line: what this is"
bin/release.sh -m "…" --checkpoint       # every host must pass through this one
bin/release.sh -m "…" --no-push          # tag only; bin/push-host.sh pj@<address> later
```

The dry run on 2026-10-06, two commits after the first tag:

```
==> Preconditions
[ok] tree clean, on master at fc6b90b dram doctor: compare modules/ commits against the last dram sw
[ok] bin/check.sh: all checks passed, 30 warning(s)

==> Release v2026.10.2 (previous: v2026.10.1; N commit(s))

==> CHANGELOG.md section
## v2026.10.2 — 2026-10-06

(dry run: no summary given)

### dram
- dram doctor: compare modules/ commits against the last dram switch, not the generation date

### other
- handbook: chapters 05 backup, 06 theme, 07 packages, 08 secrets (final text)

==> Push targets (bin/push-host.sh)
    cabin  pj@cabin
    lantern  ranger@lantern

==> Dry run: nothing written, tagged or pushed. Next: bin/release.sh -m "<summary>"
```

That output is from 2026-10-06.
Since 2026-10-13 the section's heading reads `## v2026.10.2 (2026-10-06)`, and its groups are Removed, Added, Changed, Fixed and Security, picked by each commit's `Changelog:` trailer; a commit without one is Changed (`docs/records/changelog.md`).

The real run, in order: the tree is clean and on `master` and `bash
bin/check.sh` is green (exit 1 otherwise); the next `vYYYY.MM.N` is one above
the highest N this month; `CHANGELOG.md` gets that section at the top, the
commits since the previous tag in their groups; the file is committed as `release vX: <summary>`; the
annotated tag goes on that commit; `bin/push-host.sh pj@<address>` runs for
every host with `dram.address`, as that host's login (`dram.user`: `ranger@` for lantern
since 2026-10-11; a host without an address, like campfire before its reservation, is
listed as `not pushed`). "Nothing new since the last tag" is exit 1 too. While a host is
being reinstalled, or still runs a pre-2026-10 install, release with `--no-push` and push to
the others by hand: a push to a host whose login does not exist yet fails.

On a host the notes are `dram changelog` (the latest section), `dram changelog
v2026.10.1` (one), `dram changelog --since v2026.10.1` (everything newer).
On 2026-10-06 the first one printed:

```
## v2026.10.1 — 2026-10-06

first tagged release: handbook chapters 1–3

### dram
- dram: --check headline via channel_desc, the checkout line prints git -C, wider subject in dram version
- dram: the release model — version, channel, changelog, update --check exit 7, builds + rollback to the previous build
…
```

What a push does to a host depends on its channel (`bin/push-host.sh
--help`): a host on a branch (`main`) is `git reset --hard` to the pushed tip
at once; a host detached at a release (`stable`) only gets its refs updated and
keeps its checkout until `dram update` moves it. Either way the host refuses a
push over uncommitted edits to tracked files and names them (`--force` discards).

## 9. Moving a host between channels, and holding it still

**stable → main** (make it the canary): `dram channel main`, then `dram update`
checks out `master` and runs the flow. From then on every push from the Mac is
live on it at once (scripts are symlinks); `dram switch` is still needed after a
`modules/` change, and `dram doctor` says so.

**main → stable**: `dram channel stable`, then `dram update` checks out the
newest tag. That can be *older* than the commit the host was on (`master` ahead
of the last release); the checkout and generation go back, the packages do not
— the printed `dram channel` line says `N commits away` before you run it.

**Holding a stable host at one release.** There is no pin command; a stable
host runs the newest release that has *reached* it, so the hold is on the Mac
side: `bin/release.sh -m "…" --no-push`, then `bin/push-host.sh pj@<address>`
only to the hosts meant to move. To hold a host at an older release after
newer tags have already landed on it: `git -C ~/git/dotfiles checkout --detach
vX && dram switch`; `dram doctor` then warns `behind channel stable: vY is
N commits from the checkout` with the fix `dram update`, and that is the one
command to avoid while the hold lasts — update packages with the lower-level
`sudo pacman -Syu` meanwhile, which does not touch the checkout.

The doctor's `dram` section is the summary of all of this:

```
[i] running v2026.10.1 · build 20261006.ac23151 · channel stable · generation 58 (dram version)
[ok] the switched build is the checkout (v2026.10.1)
[ok] channel stable: the checkout is the target (v2026.10.1)
```

and its two warnings: `the checkout (<name>) is not the switched build
(<BUILD_ID>)` → `dram switch`; `behind channel <ch>: <target> is N commits from
the checkout` → `dram update  (dram changelog for the notes)`.

## 10. The system — snapshots, booting one, rolling back

Every pacman transaction (`dram update`, `dram apply`, a `pacman -S`) takes a snapper
**pre** snapshot of `/` before and a **post** after (`system/hooks/00-dram-snap-pre.hook`,
`zz-dram-snap-post.hook`), and the newest five pre snapshots get a signed boot entry each,
built from that snapshot's own kernel and modules (`system/dram-snapshot.sh`). systemd-boot
lists them below **Arch Linux** as `Arch snapshot <n> — <date> <description>`; they are
never the default. `/home` has its own light timeline; `/data/*`, `/var/log`, the pacman
cache, Flatpaks and the Secure Boot keys are separate subvolumes that no rollback touches.

**Try an old state, changing nothing:** reboot and pick the snapshot's entry. It boots
read-only with a RAM overlay: everything works, nothing written survives the next boot.

**Make it the system:**

```sh
dram rollback --system            # the snapshots, and which have a boot entry
dram rollback --system <n>        # a dry run first, then: Make snapshot <n> the new root (reboot to finish)? [y/N]
sudo reboot
```

`@` becomes `@.broken-<stamp>`, a writable copy of snapshot `<n>` becomes `@`, and the live
UKI is rebuilt inside it. The QEMU drill (2026-10-11) ended with:

```
==> done — reboot into the restored root. The old one is @.broken-20261011-100258:
    when the restored system is good: sudo mount -o subvolid=5 /dev/vda2 /mnt && sudo btrfs subvolume delete /mnt/@.broken-20261011-100258
```

The dram build is not part of it: after a system rollback, `dram version` still names the
switched build, and `dram rollback` (section 6) moves that side. A snapshot from before the
YubiKey second factor was switched on lets the password alone in until it ages out
(`docs/security/identity/yubikeys.md`).

## Done when

- [ ] `dram version` prints a card whose `commit` is the one `git -C ~/git/dotfiles log -1` shows, with no `[!]` line
- [ ] `dram channel` ends `checked out` (or, with no `~/.config/dram/channel` yet, adds the `(default: …)` note), and `dram channel --target` ends in `0`
- [ ] `dram update --check; echo rc=$?` ends `Nothing is pending (exit 7)` and `rc=7` on a current host
- [ ] `dram update` has run once since this chapter, so `dram builds` lists at least one build marked `(= the running build)`
- [ ] `dram changelog` prints the section for the tag `dram version` names
- [ ] on the Mac, `bin/release.sh --dry-run` reaches `Dry run: nothing written, tagged or pushed`
- [ ] `dram doctor` prints the three `dram` lines above with no `behind channel` warning
- [ ] `ls -d ~/.config/dram ~/.config/rice` finds the first and says `No such file` for the second (the first `dram switch` after the 2026-10-06 rename moved it)
- [ ] `dram rollback --system` lists the pre/post pairs of the last update, and the boot menu shows their entries

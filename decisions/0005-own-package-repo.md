# 0005: A signed package repo of my own for everything from the AUR

[Toolchain › Packaging](../docs/toolchain/packaging/README.md) · accepted 2026-10-06 · amended 2026-10-11

Every AUR package is vendored, reviewed, pinned and built once on cabin into the signed `[dram]` repo; the cost is a build host and a review for every update.

## Context

`decisions/0003` sends every GUI/GL program to pacman, which for ~15 packages meant
the AUR: each host cloned a PKGBUILD, built it as `pj` with a warm sudo ticket
(`SudoLoop`), and loaded the result — including two Hyprland plugins compiled at
GitHub HEAD by hyprpm and loaded *into the compositor*. The 2026-06 "malicious AUR
adoptions" incident and the review in `docs/security/software-supply/README.md` rated this the #1 and
#2 risk on the machines: any `build()` or `pkgver()` could escalate silently, twice,
and nothing recorded which PKGBUILD commit a host had actually built.

## Decision

Vendor the PKGBUILDs into this repo (`pkgs/<name>/`: PKGBUILD, `.SRCINFO`,
`UPSTREAM` = the AUR commit taken, `REVIEW.md`, `PIN`), pin every source
(a sha256 computed here, `#commit=`/`#tag=`, `validpgpkeys`), strip anything that runs
unread upstream shell at build time, and **build once on cabin in a clean devtools
chroot** (`makechrootpkg -c`), sign with a dedicated key (`pkgs/dram.asc`), and serve
the result as a pacman repo `[dram]` (`repo-add -s`, `SigLevel = Required
DatabaseRequired`, `file:///var/lib/dram-repo`, listed above `[core]`) that rsync
carries to the other host. `dram pkgs {check,update,build,publish,sync,log,list}`
(`bin/pkgs.sh`) is the whole workflow; `docs/toolchain/packaging/README.md` is the runbook,
`pkgs/README.md` the policy. The Hyprland plugins became packages
(`hyprland-plugin-hyprtasking`, `-hyprfocus`, `depends=('hyprland=<ver>')`) loaded by
`hl.plugin.load`; hyprpm is retired.

## Alternatives weighed

| Option | Why not |
|---|---|
| paru `LocalRepo` + `Chroot` | fast to turn on, and the chroot removes the sudo amplifier — but the PKGBUILDs live in paru's cache, not in this repo's git history; no review diff, no pins, every host still builds |
| aurutils (`aur sync -c`) | same shape and the same gap: a local repo fed from AUR HEAD, reviewed by whoever is at the keyboard that day |
| nixpkgs | forbidden for GUI/GL by `decisions/0003` (Mesa/NVIDIA mismatch); most of the set is GUI |
| Flatpak | a sandbox, not provenance — Flathub verifies the publisher, not the build; and theming does not reach it. Kept as the carve-out for vendor binaries and, since 2026-10-11, the emulators (`docs/toolchain/packaging/flatpak.md`) |
| keep building on every host, review harder | review was already the policy (`paru.conf` without `SkipReview`); the problem was the blast radius and the absence of a record |

## Consequences

- Trust moves from "the AUR maintainer today" to "the git history of `pkgs/` and the
  chroot on cabin". The signature says *built on cabin from this PKGBUILD at this
  commit* — nothing more (`docs/security/software-supply/integrity.md`).
- cabin is a build host: `packages/roles/builder.txt`, `/var/lib/archbuild`, `/srv/dram`, the
  private key in `~/.gnupg`, whose custody is an offline export (`docs/toolchain/packaging/README.md` §2),
  not the borg set. The other hosts only sync.
- `[dram]` above `[core]` shadows silently; `dram pkgs check` refuses official names
  unless in `pkgs/OVERRIDES`.
- A Hyprland bump needs the two plugin packages rebuilt **before** `dram update`
  (`docs/toolchain/packaging/README.md` §9), otherwise Hyprland starts without them until it is done.
- Updating a package means reading an AUR diff (`dram pkgs update`), which is the
  point. `packages/aur.txt` lists nothing: paru is off the hosts, so nothing reads it to
  build, and anything from the AUR is vendored into `pkgs/`.
- `dram doctor --supply` checks that every foreign package is in `pkgs/manifest.txt` ∪
  `packages/aur.txt`, and that `[dram]` is signed and complete.

## How it is checked

`bin/check.sh` §12 runs `bin/pkgs.sh check`: the manifest matches the package directories, every source is pinned, and no vendored name shadows an official one unless `pkgs/OVERRIDES` lists it.
`dram doctor --supply` fails a foreign package that is not in the manifest, and an unsigned or incomplete `[dram]`.

## History

- 2026-10-06: accepted and built; both hosts install from `[dram]`.
- 2026-10-07: the frozen lib32 set was vendored too, from Arch's last official PKGBUILDs, so `packages/aur.txt` emptied.
- 2026-10-10: paru left the hosts ([0013](0013-software-rules-and-waivers.md)).
- 2026-10-10: cabin stays the builder, its key to be restored from the offline export ([D10](log.md#d10)).
- 2026-10-11: amended at the fresh start: a new signing key made at install, the old one retired ([D147](log.md#d147)).
- 2026-10-11: the 12 lib32 wine libraries and `lib32-pipewire-jack` left `pkgs/` ([D31](log.md#d31)).

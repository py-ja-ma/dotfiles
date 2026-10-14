# pkgs

[Toolchain](../docs/toolchain/README.md) › [Packaging](../docs/toolchain/packaging/README.md) › The `[dram]` repo

A signed pacman repo of reviewed, pinned PKGBUILDs, built in a clean chroot on one host and installed by pacman on the others.
Each package that would come from the AUR or a vendor lives here as a recipe I have read, with its sources pinned by hash.
cabin builds and signs them, and each Arch host installs them from `/var/lib/dram-repo` over `file://`.

| | |
|---|---|
| Needs | Arch Linux; devtools and diffoscope on the builder; GnuPG; rsync over SSH to carry the repo; tested 2026-10 |
| Copy alone | yes, with your own signing key and builder host |
| License | the recipes I wrote: MIT; vendored AUR recipes: their AUR terms; each package: its own license, in its `REVIEW.md` |

## What it needs

- Arch Linux with `devtools` (`makechrootpkg`, `mkarchroot`) and `diffoscope` on the builder: `packages/roles/builder.txt`.
- GnuPG 2 for the signing key, and `pacman-contrib` for `updpkgsums`.
- `bin/pkgs.sh`, the tool behind `dram pkgs`. It reads this directory, and `packages/*.txt` and `packages/roles/*.txt` to tell which names a role installs.
- `system/dram-builder-setup.sh` makes the builder: the chroot, `/srv/dram`.
- `system/pacman-dram-repo.sh` adds the repo to a host: the key, `/etc/pacman.d/dram.conf`, the `Include`.
- `bin/sync-dram-repo.sh`, only where the hosts cannot reach each other: it carries the repo through a third machine. It finds the builder and the other hosts through `install/lib/roles.sh`.
- Not needed: Nix, Home Manager or the `dram` command. `bin/pkgs.sh check|build|publish` runs on its own.

## Copy it alone

1. Copy `bin/pkgs.sh`, `system/dram-builder-setup.sh`, `system/pacman-dram-repo.sh` and the `pkgs/<name>/` directories you want.
2. Write your own `pkgs/manifest.txt` with one `name=pkgver-pkgrel` line per package, start `pkgs/BUILDLOG` empty, and delete `pkgs/dram.asc`.
3. On the builder, as root: `DRAM_BUILDER_HOST=$(hostname) DRAM_BUILDER_USER=<you> bash system/dram-builder-setup.sh`.
4. As that user: `bin/pkgs.sh key --new`. It makes an ed25519 signing key, exports `pkgs/dram.asc` and pins the fingerprint in `system/pacman-dram-repo.sh`. Set `PACKAGER` to your name and address first.
5. `bin/pkgs.sh check`, then `bin/pkgs.sh build` and `bin/pkgs.sh publish`.
6. On each host: `sudo DRAM_REPO_OWNER=<you> bash system/pacman-dram-repo.sh`, fill `/var/lib/dram-repo`, then run it again to add the `Include`.
7. `pacman -Sl dram` lists the packages, and `pacman -Qi <name>` shows your `PACKAGER` once one is installed.

## How it is wired here

`dram pkgs <command>` runs `bin/pkgs.sh`, and `bin/check.sh` §12 runs `bin/pkgs.sh check` on each check.
cabin is the builder (`packages/roles/builder.txt`; `dram apply` asks before it runs `system/dram-builder-setup.sh`).
Phase 2 of `install/bootstrap.sh` adds `[dram]` to a new host, and `system/apply-hooks.tsv` runs `system/pacman-dram-repo.sh` on each metal host before anything installs from it.
The Mac carries the repo from cabin to lantern with `bin/sync-dram-repo.sh`, because the hosts' SSH keys for each other are pinned to `borg serve`.
`packages/register.tsv` holds a verdict for each name in `manifest.txt`, and `bin/check.sh` §15 checks it.
The runbook, with each command and its output, is the [Packaging](../docs/toolchain/packaging/README.md) page.

| Package | What | Installed with | License |
|---|---|---|---|
| `dram-case-display` | my driver for the case's temperature panel | cabin (`packages/host-cabin.txt`) | mine, MIT |
| [`dram-gaming-mode`](dram-gaming-mode/README.md) | my ly sessions and switching for Gaming Mode | the gaming role | mine, MIT |
| `gamescope-session`, `gamescope-session-steam` | the gamescope Gaming Mode session, OpenGamingCollective's fork | the gaming role | MIT |
| `game-devices-udev` | udev rules for third-party game controllers | the gaming role | MIT |
| `xpadneo-dkms` | the Xbox controller driver for Bluetooth | the gaming role | GPL-2.0-only and GPL-3.0-or-later |
| `jagex-launcher` | Jagex's Linux launcher for OSRS | the gaming role | Jagex's EULA, waived |
| `hyprland-plugin-hyprfocus`, `hyprland-plugin-hyprtasking` | Hyprland plugins, bound to its ABI | the desktop role | BSD-3-Clause |
| `proton-pass-bin` | the Proton Pass desktop app | the desktop role | MIT and GPL-3.0-or-later |
| `proton-pass-cli` | the Proton Pass command line | every host | GPL-3.0-or-later |
| `vscodium-bin` | VSCodium | the dev role | MIT |
| `imhex-bin`, `uefitool-ng` | a hex editor; UEFI firmware tools | the re-lab role | GPL-2.0; BSD-2-Clause |
| `redumper`, `xdvdfs` | a CD and DVD dumper; Xbox XISO tools | the dump-kit role | GPL-3.0-only; MIT |
| `rpcs3-bin`, `vita3k-bin`, `xenia-canary-bin` | PS3, PS Vita and Xbox 360 emulators | the emulation role | GPL-2.0-only; GPL-2.0-only; BSD-3-Clause |

A `[dram]` name that no packages list mentions goes to every host (`dram pkgs list --install`, bootstrap phase 2).
A name listed in a role, hardware or host file installs only with that role or on that host, through `dram apply`.
`dram pkgs list --repo` is everything installable from `[dram]`.

## Policy

Each package goes through review, bump, build, sign and publish.

1. Review: a package enters `pkgs/` only after its PKGBUILD, `.install` and hooks have been read.
   `REVIEW.md` records what it is, what runs at build and install time, and what changed against the AUR.
   `UPSTREAM` records the exact commit that was read: `aur:<pkgbase> <sha> <date>`, `own:` for my own packages, `arch:` for an ex-official one.
2. Bump: `dram pkgs update [name]` shows the AUR diff since `UPSTREAM` (`PKGBUILD`, `*.install`, hooks) in `$PAGER`, and merges it on top of this copy only after a `y`.
   `PIN` says how to pin the sources again, and `updpkgsums` must then agree with the pasted hash.
   `.SRCINFO`, `UPSTREAM` and `manifest.txt` are rewritten, one commit per package.
3. Build: `dram pkgs build [name]` runs `makechrootpkg -c -u` in `/var/lib/archbuild/dram-x86_64`, a throwaway chroot that never sees the user's `$HOME` or sudo ticket.
   Build-only dependencies (`BUILD-ONLY`) go in with `-I`.
4. Sign: each package file gets a detached signature from the key in `~/.config/dram/gpgkey`, and `repo-add -s` signs the database.
   Hosts run `SigLevel = Required DatabaseRequired`.
5. Publish: `dram pkgs publish` writes `/srv/dram/dram.db` and rsyncs `/srv/dram/` to `/var/lib/dram-repo/` on cabin, and the Mac carries it to lantern.
   An ordinary `dram update` (`pacman -Syu`) then installs the packages.

The rules that follow from it:

- Each source is pinned.
  A release tarball has a sha256, sha512 or b2 sum computed from my own download.
  A git source has `#commit=` or `#tag=`, with a real checksum where upstream has one, and `SKIP` only for the git checkout itself.
  A vendor binary has the hash the vendor publishes.
  There are no `-git` packages, no `pkgver()` functions and no md5 sums, and `dram pkgs check` enforces it.
- One recipe resolves its dependencies at build time, which `dram pkgs check` cannot see.
  `proton-pass-cli` runs `cargo fetch` without `--locked`, because upstream's `Cargo.lock` lags its `Cargo.toml` at the tag.
- `pkgver` and `pkgrel` stay what the AUR or the vendor says.
  `[dram]` wins over the AUR because it is a real repo, not through inflated versions.
  A package bumped ahead of the AUR (proton-pass-bin) carries the newer version.
- Signing keys ride along.
  When upstream signs its release, the public key lives in `pkgs/<name>/keys/pgp/<fpr>.asc`, so makepkg imports it and the chroot needs no keyserver.
  As of 2026-10-13 `game-devices-udev` is the one package that does.
- The Hyprland plugins are bound to Hyprland's ABI: they carry `depends=('hyprland=<version>')`, and a Hyprland bump means rebuilding both (§9 of the runbook).
- An ex-official package comes from Arch's own repo, not from whoever adopted the name in the AUR.
  That is the last official PKGBUILD from `gitlab.archlinux.org/archlinux/packaging/packages/<name>`, at the tag the host had installed.
  `UPSTREAM` says `arch:<gitlab path> <commit> <date>`, and bumps are by hand per `PIN`.
  The 12 `lib32-*` wine dependencies came this way, until I dropped the set on 2026-10-11 ([D31](../decisions/log.md#d31)).
- A `[dram]` dependency needs no extra file.
  `dram pkgs build` reads `depends` and `makedepends` from each `.SRCINFO`, keeps the names that are in `manifest.txt`, builds in dependency order and feeds the chain into the chroot with `makechrootpkg -I`.
  So spell a `[dram]` dependency out in the PKGBUILD: the chroot never sees the `[dram]` repo itself.
- One directory may build several names.
  Each produced name has its own line in `manifest.txt`.
  `dram pkgs check` maps it back to the directory whose `.SRCINFO` has `pkgname = <name>`, and `build` and `update` take either name.

## How to add a package

```sh
name=foo
mkdir pkgs/$name && cd pkgs/$name
curl -O "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=$name"   # and the .install, hooks, patches
# read it, all of it, then:
#   pin: a release tarball and the sha256 you computed, or #commit=/#tag=; the vendor hash for a -bin
#   strip anything that runs upstream shell you have not read (install.sh, curl, npm install)
#   keep pkgver and pkgrel
makepkg --printsrcinfo > .SRCINFO                      # on the builder
printf 'aur:%s %s %s\n' $name <sha-from-cgit-log> <date> > UPSTREAM
$EDITOR REVIEW.md                                      # the fact box and three sections, as in any sibling
echo "$name=<pkgver-pkgrel>" >> ../manifest.txt && sort -o ../manifest.txt ../manifest.txt
dram pkgs check $name && dram pkgs build $name && dram pkgs publish
```

A package that is only a build dependency goes in `BUILD-ONLY` too.
`packages/aur.txt` stays empty: a name lives in one list only.

## Repo order and shadowing

`/etc/pacman.conf` includes `/etc/pacman.d/dram.conf` above `[core]`, so for a name in both, pacman takes this repo's package.
Nothing needs that as of 2026-10-13, and it is dangerous by default: `dram pkgs check` refuses a vendored name that `pacman -Slq core extra multilib` knows, unless `OVERRIDES` lists it with a reason in its `REVIEW.md`.
`OVERRIDES` is empty.

## Key custody

- One signing key, made on cabin by `dram pkgs key --new` as the builder user. Its fingerprint is in `~/.config/dram/gpgkey`, outside the repo, and its public half in `pkgs/dram.asc`.
- `system/pacman-dram-repo.sh` pins the fingerprint (`EXPECTED_FPR`), imports the key into pacman's keyring on each host, signs it locally, and refuses any other key.
- The private key lives in `~/.gnupg` on cabin and in one export, on offline media and in Proton Pass. `~/.gnupg` is not in the Borg set (`modules/backup.nix`), and the passphrase is in Proton Pass.
- The key expires after two years: `gpg --quick-set-expire <fpr> 2y`, export `dram.asc` again, commit, and run `system/pacman-dram-repo.sh` on each host. `dram doctor --supply` warns from 90 days before.
- A lost key: `dram pkgs key --new`, commit the new `dram.asc` with the new pin, run the setup script on each host, rebuild and publish everything. Installed packages stay; pacman does not check their old signatures again.
- A compromised builder means a compromised key. That is the threat model, and why the builder is the desktop on the LAN, not the laptop.

## Files

| File | What it does |
|---|---|
| `manifest.txt` | `name=pkgver-pkgrel` for each package, as its `.SRCINFO` says; the install set is this minus `BUILD-ONLY` |
| `BUILD-ONLY` | names built only to feed other builds, never installed on a host |
| `OVERRIDES` | names allowed to shadow core, extra or multilib; empty |
| `BUILDLOG` | `name version sha256 date`, one line per build (`dram pkgs log`) |
| `dram.asc` | the public half of the signing key |
| `<name>/PKGBUILD` | the reviewed recipe, sources pinned |
| `<name>/.SRCINFO` | written by `makepkg --printsrcinfo`; `dram pkgs update` writes it again |
| `<name>/UPSTREAM` | `aur:`, `own:` or `arch:`, the commit that was read, and its date |
| `<name>/REVIEW.md` | the fact box, what it is, what runs at build and install time, what changed |
| `<name>/PIN` | how to pin this package's sources again on a bump |
| `<name>/keys/pgp/*.asc` | upstream signing keys, where upstream signs |
| `<name>/*.install`, `*.hook`, `*.sh`, `*.desktop` | helper files, vendored and checksummed in the PKGBUILD |

Build output (`src/`, `pkg/`, downloaded sources, `*.pkg.tar.*`, `PKGBUILD.aur`, `*.rej`) is in `.gitignore`.

## License

The files I wrote here (`manifest.txt`, the lists, `dram-gaming-mode/` and `dram-case-display/`, and my changes to the recipes) are MIT, Patrick Jordan.
A vendored recipe keeps the terms of its AUR repository, which most do not state.
Each `REVIEW.md` names its AUR source, and my changes are offered on the same terms.
Each package's software keeps its own license, in the table above and in its `REVIEW.md`.
`vscodium-bin/LICENSE` is VSCodium's MIT license, and `jagex-launcher/JAGEX-EULA` is Jagex's proprietary EULA.
Never publish `/srv/dram` or a host's `/var/lib/dram-repo`: the built packages hold proprietary payloads (the Jagex AppImage, Proton Pass, the vendor `-bin` builds).

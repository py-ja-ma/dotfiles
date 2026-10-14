# Packaging

[Toolchain](../README.md) › Packaging

Packaging decides where each program comes from, and builds the ones Arch does not ship.
cabin builds every AUR-origin package once, in a throwaway chroot, signs it, and each Arch host installs it with pacman from the `[dram]` repo.
No host builds anything as its user, and nothing from the AUR runs with a sudo ticket ([decision 0005](../../../decisions/0005-own-package-repo.md)).

| Branch | What it does | Code | Copy alone |
|---|---|---|---|
| The `[dram]` repo | vendored recipes, clean-chroot builds, signatures, publishing | [`pkgs/`](../../../pkgs/README.md), `bin/pkgs.sh`, `system/dram-builder-setup.sh`, `system/pacman-dram-repo.sh`, `bin/sync-dram-repo.sh` | yes, with your own key and builder |
| [Flatpak](flatpak.md) | vendor binaries and verified emulators, each in a least-privilege sandbox | `system/flatpak-setup.sh`, [`packages/flatpak/`](../../../packages/flatpak/README.md) | yes |
| Role lists | which names each role installs, per source | [`packages/roles/`](../../../packages/roles/README.md), `packages/winget/`, `packages/uv/` | yes |

## How the branches fit

Each name a host installs comes from one of these sources.
A pacman name lives in one list only, and `bin/check.sh` §3 fails on a duplicate.

| Source | For | Lists |
|---|---|---|
| Arch's repos | anything with a window or GL, daemons, kernel-adjacent tools | `packages/*.txt`, `packages/roles/*.txt` |
| `[dram]` | what only the AUR or a vendor ships, reviewed and pinned | `pkgs/manifest.txt`, and a role list when one role needs it |
| nixpkgs | self-contained command-line tools whose version I pin | `home.packages` in `modules/*.nix`, pinned by `flake.lock` |
| Flathub | vendor binaries I cannot build, and verified emulators | `packages/flatpak/<role>.txt` |
| uv and Ghidra | the re-lab role's per-user tools | `packages/uv/re-lab.txt`, `packages/ghidra-extensions.tsv` |
| winget | the Windows PCs' apps, by the same role names | `packages/winget/<role>.txt` |

The rule for pacman against nixpkgs is [decision 0003](../../../decisions/0003-gui-apps-from-pacman-over-nixpkgs.md).
There is no AUR helper on any host: `packages/aur.txt` stays empty, and `bin/check.sh` §3 refuses an AUR name in a repo list.
Each name needs a verdict in `packages/register.tsv` ([decision 0013](../../../decisions/0013-software-rules-and-waivers.md)).

The rest of this page is the `[dram]` runbook.
`pkgs/README.md` holds the policy the runbook follows.

```text
pkgs/<name>/PKGBUILD ──dram pkgs build──▶ /srv/dram/*.pkg.tar.zst + .sig
            (cabin, clean chroot, signed)        │
                          dram pkgs publish (repo-add -s, rsync; this host only)
                                                 ▼
          cabin:/var/lib/dram-repo   ──bin/sync-dram-repo.sh (Mac)──▶   lantern:/var/lib/dram-repo
                 [dram] in pacman.conf, above [core], SigLevel = Required DatabaseRequired
                                    dram update → pacman -Syu
```

Nothing listens on the network: the packages travel by rsync over the same SSH the Mac uses.
A pacman repo is a directory with a database file, and `[dram]` is one more.

## 0. The `dram pkgs` commands

`dram pkgs` is `bin/pkgs.sh`, and each command prints what to do next.

| Command | Where | Does |
|---|---|---|
| `dram pkgs check [name]` | anywhere, the Mac too | manifest against directories, versions, pins, no shadowing of an official repo, keys vendored |
| `dram pkgs update [name]` | cabin | the AUR diff since the last review, merged on top of this copy, re-pinned, `.SRCINFO` rewritten, committed |
| `dram pkgs build [name]` | cabin | `makechrootpkg -c -u`, a detached signature, a line in `pkgs/BUILDLOG` |
| `dram pkgs publish` | cabin | `repo-add -s` into `/srv/dram/dram.db`, rsync to cabin's own `/var/lib/dram-repo` |
| `dram pkgs list [--install]` | anywhere | the manifest's names; `--install` is the set every host gets |
| `dram pkgs log <file>` | cabin | name, version, sha256 and date appended to `pkgs/BUILDLOG` |
| `dram pkgs key [--new]` | cabin | the signing key's fingerprint and expiry, and whether `pkgs/dram.asc` and the pin agree; `--new` makes a key |

The other hosts get the repo from the Mac (`bin/sync-dram-repo.sh`, §4).
The hosts' SSH keys for each other are pinned to `borg serve`, so there is no host-to-host path.

## 1. First-time builder setup

```sh
sudo bash ~/git/dotfiles/system/dram-builder-setup.sh --dry-run   # read it
sudo bash ~/git/dotfiles/system/dram-builder-setup.sh
```

It installs `packages/roles/builder.txt` (`devtools`, `diffoscope`) and creates the clean chroot at `/var/lib/archbuild/dram-x86_64/root` from devtools' own pacman config.
The chroot sees the official repos only, because a chroot that saw `[dram]` would build against itself.
It creates `/srv/dram` owned by the builder user, and prints the next step.
It never makes a key.

## 2. The signing key

As the builder user, never with sudo:

```sh
dram pkgs key --new    # gpg asks for the key's passphrase: keep it in Proton Pass
# prints: [ok] key <FPR>: ~/.config/dram/gpgkey, pkgs/dram.asc, the pin in system/pacman-dram-repo.sh
git -C ~/git/dotfiles commit -m "pkgs: a new dram signing key" pkgs/dram.asc system/pacman-dram-repo.sh
gpg --armor --export-secret-keys <FPR> > /run/media/<you>/<offline stick>/dram-signing.asc
```

`dram pkgs key --new` makes an ed25519 signing key that expires in two years, writes its fingerprint to `~/.config/dram/gpgkey`, exports the public half to `pkgs/dram.asc` and pins the fingerprint in `system/pacman-dram-repo.sh`.
The private key stays in `~/.gnupg` on cabin, and `gpg-agent` caches the passphrase for a build session.
`~/.gnupg` is not in the Borg set (`modules/backup.nix`), so the export on offline media and in Proton Pass is the key's only other copy.

The fingerprint is pinned: `EXPECTED_FPR=044DFA31C5CD72299A1460B56EF00BFB391BD348` in `system/pacman-dram-repo.sh`, the key made on cabin on 2026-10-11 that expires on 2028-10-10.
The script refuses to `lsign` any other key, so a swapped `dram.asc` in a compromised checkout stops there.
`dram doctor --supply` warns from 90 days before the expiry.

To extend it: `gpg --quick-set-expire <FPR> 2y`, export `pkgs/dram.asc` again, commit, then step 4 on each host.
Step 4 imports the key again even when it is present, so a new expiry or a revoked uid reaches pacman's keyring.
To rotate it, or after losing it: `dram pkgs key --new`, one commit with the new `pkgs/dram.asc` and the new pin, step 4 on each host, then rebuild everything.
[Handbook chapter 7](../../records/handbook/07-packages.md) walks through a rotation on a fresh builder.

## 3. First build and publish

```sh
cd ~/git/dotfiles
dram pkgs check                        # green before anything is built
dram pkgs build                        # everything in pkgs/manifest.txt, dependencies first
dram pkgs publish                      # repo-add -s, rsync to /var/lib/dram-repo here
sudo bash system/pacman-dram-repo.sh   # imports dram.asc into pacman-key, writes the stanza, adds the Include
dram update                            # pacman -Syu now sees [dram]
```

`dram pkgs build <name>` builds one package.
Each build cleans the chroot copy, updates it, installs the PKGBUILD's dependencies from the official repos and the `[dram]` build dependencies with `-I`, builds, copies the package to `/srv/dram`, signs it with `gpg --detach-sign` and appends to `pkgs/BUILDLOG`.
`makechrootpkg` runs itself as root, so each build asks for sudo once, and the PKGBUILD never sees that ticket.
Downloaded sources are cached per package in `~/.cache/dram-pkgs/src/<pkg>`, because makepkg reuses a cached file by name and many sources are called `LICENSE`.
Build logs go to `~/.cache/dram-pkgs/log`.

The order matters the first time only: `pacman-dram-repo.sh` refuses to add the `Include` while `/var/lib/dram-repo/dram.db` is missing, because pacman would fail on every `-Sy`.

`[dram]` sits above `[core]`, so for each name in `pkgs/manifest.txt` pacman takes this repo's package.
With the same `pkgver-pkgrel` it reinstalls nothing until the version moves.
`pacman -Qi proton-pass-bin` shows `Packager : pj dram packages` once it did.
To switch at once: `sudo pacman -S $(dram pkgs list --install)`.

## 4. Adding `[dram]` on another host

```sh
mac$  bin/push-host.sh pj@<host address>   # the hosts have no remote; this brings pkgs/dram.asc
host$ sudo bash system/pacman-dram-repo.sh # key, stanza, /var/lib/dram-repo; the Include waits for the sync
mac$  bin/sync-dram-repo.sh                # cabin:/srv/dram to the Mac's mirror to the host's /var/lib/dram-repo
host$ sudo bash system/pacman-dram-repo.sh # now adds the Include above [core]
host$ dram update
```

From then on, each `dram pkgs publish` on cabin is followed by `bin/sync-dram-repo.sh` on the Mac.
cabin's SSH key on lantern is restricted to `borg serve`, so `dram pkgs publish` writes cabin only and the Mac carries the repo: cabin, then `~/backups/dram/`, then each other host's `/var/lib/dram-repo/`.
The Mac's copy doubles as the backup of the signed repo off the builder.
`bin/sync-dram-repo.sh` finds the builder and the other hosts from the host files: the host with the `builder` role, and each host with a `dram.address`.

## 5. How `dram update` uses it

`dram update` runs the keyring update, paccache, then `sudo pacman -Syu`.
`[dram]` is an ordinary sync repo: each package comes from `file:///var/lib/dram-repo`, is checked against the key, and is never built on the host.
paru left the hosts on 2026-10-10 ([decision 0013](../../../decisions/0013-software-rules-and-waivers.md)).
What the AUR used to carry is vendored into `pkgs/`, or swapped: the GTK themes for adw-gtk3, LocalSend and Vesktop for Flatpaks, Spotify for `spotify-launcher`.
`checkupdates`, behind the bar's update count and `dram update --check`, covers `[dram]` too.
`dram doctor --supply` checks that each `pacman -Qm` name is in `pkgs/manifest.txt` or `packages/aur.txt`.

On a new machine, phase 2 of `install/bootstrap.sh` runs `system/pacman-dram-repo.sh` when `pkgs/dram.asc` exists, installs `dram pkgs list --install` (the set every host gets), then runs `dram apply` again for the `[dram]` names a role lists.

## 6. Updating a vendored package

```sh
dram pkgs update                  # every package; or: dram pkgs update proton-pass-bin
```

For each package it clones the AUR repo into `~/.cache/dram-pkgs/aur/`, compares HEAD with the commit in `pkgs/<name>/UPSTREAM`, and shows the commit log and the diff of `PKGBUILD`, `*.install`, hooks and scripts in `$PAGER`.
Read the diff.
A new file in `source=`, any `.install` change, `sudo`, `/tmp`, `curl` or `npm install` in a build, or an unexpected maintainer is the reason this workflow exists.
Answer `y` and it:

1. applies the AUR delta on top of this copy, so local edits survive: the setuid strip, the unsquashfs `prepare()`, the single-package plugin.
   A conflict leaves `PKGBUILD.aur` and `*.rej` to merge by hand.
2. prints `pkgs/<name>/PIN`, how to pin again (the vendor hash for a `-bin`, tag to commit for git sources), and offers `$EDITOR`.
3. runs `updpkgsums`.
   For a vendor binary the hash it computes must equal the one pasted from the vendor, or stop.
4. writes `.SRCINFO`, `UPSTREAM` and `pkgs/manifest.txt` again, runs `dram pkgs check`, and commits `pkgs/<name>: sync with AUR <base> @<sha> (<version>)`.

Then `dram pkgs build <name> && dram pkgs publish`, and `dram update` on each host.
`hyprland-plugin-hyprtasking` has no AUR upstream (`own:` in `UPSTREAM`): bump its `_commit` by hand per its `PIN`.
An ex-official package (`arch:` in `UPSTREAM`, Arch's last PKGBUILD from `gitlab.archlinux.org`) has nothing to diff against, so `update` only reminds you; bump it per `PIN` when the matching 64-bit package moves.

## 7. Vendoring a new package

`pkgs/README.md` has the steps under "How to add a package".
Fetch the AUR PKGBUILD and read it, pin every source, remove anything that runs unread upstream shell at build time, and keep `pkgver` and `pkgrel`.
Write `.SRCINFO` (`makepkg --printsrcinfo`), `UPSTREAM` (`aur:<pkgbase> <sha> <date>` from the AUR cgit log), `REVIEW.md` and, if pinning again is not obvious, a `PIN`.
Add the line to `pkgs/manifest.txt`, then `dram pkgs check <name>`, build and publish.
A name that exists in core, extra or multilib is refused unless `pkgs/OVERRIDES` lists it: `[dram]` sits above `[core]`, so shadowing is silent and total.

## 8. Rolling back

pacman keeps the last two versions of each package in `/var/cache/pacman/pkg` (`paccache -rk2`, [Arch](../../platforms/arch/README.md)).
For a `[dram]` package that misbehaves:

```sh
ls /var/cache/pacman/pkg/proton-pass-bin-*            # what is there
sudo pacman -U /var/cache/pacman/pkg/proton-pass-bin-1.40.0-1-x86_64.pkg.tar.zst
```

That reinstalls the previous build.
The next `dram update` upgrades it again: to hold it, add it to `IgnorePkg` in `/etc/pacman.conf` until a fixed package is published.
To drop `[dram]` from a host, delete the `Include` line from `/etc/pacman.conf`; the installed packages stay, and nothing updates them any more.

`/srv/dram` keeps the current version of each package only (`repo-add -R`).
Older builds survive in the pacman caches, and in `pkgs/BUILDLOG` by hash.

## 9. When Hyprland bumps

Plugins are compiled against Hyprland's exact ABI.
Both plugin packages carry `depends=('hyprland=<version>')`, so after a Hyprland upgrade pacman refuses to keep them until they are rebuilt.
A stale plugin would crash the compositor at login, so the refusal is the point.

```sh
dram update --check                          # shows hyprland pending
# in pkgs/hyprland-plugin-hyprfocus/PKGBUILD and pkgs/hyprland-plugin-hyprtasking/PKGBUILD:
#   pkgver=<new hyprland version>; depends=('hyprland=<new version>'); _commit=<per PIN>
#   (hyprfocus: the hyprland-plugins commit the AUR hyprland-plugins package pins for that
#    version; hyprtasking: the matching commit_pins row in upstream hyprpm.toml, or newer main)
dram pkgs check hyprland-plugin-hyprfocus hyprland-plugin-hyprtasking
dram pkgs build hyprland-plugin-hyprfocus hyprland-plugin-hyprtasking   # the chroot pulls the new hyprland
dram pkgs publish
dram update                                  # hyprland and both plugins in one transaction
```

Build before upgrading the host.
The chroot gets the new Hyprland from the mirrors either way, and `dram update` then upgrades Hyprland and both plugins together.
A host upgraded first loses the plugins to the conflict, Hyprland starts without them (`hyprland.lua` guards on `hl.plugin.<name>`), and the rebuilt packages bring them back.
After login, `hyprctl plugin list` shows them.

`hyprland.lua` loads both from `[dram]` with `hl.plugin.load("/usr/lib/hyprland/libhyprtasking.so")` and `…/libhyprfocus.so`.
hyprpm left on 2026-10-06, and a host without `[dram]` runs without the plugins.

## 10. Where things are

| Path | Holds |
|---|---|
| `pkgs/<name>/` | PKGBUILD, `.SRCINFO`, `UPSTREAM`, `REVIEW.md`, `PIN`, vendored keys and helper files |
| `pkgs/manifest.txt`, `pkgs/BUILD-ONLY`, `pkgs/OVERRIDES`, `pkgs/BUILDLOG`, `pkgs/dram.asc` | the install set, build-only dependencies, the shadowing allow-list, build hashes, the public key |
| `bin/pkgs.sh` | `dram pkgs` |
| `system/dram-builder-setup.sh` | the builder: devtools, the chroot, `/srv/dram` |
| `system/pacman-dram-repo.sh` | each host: the key in pacman-key, `/etc/pacman.d/dram.conf`, `/var/lib/dram-repo`, the Include |
| `bin/sync-dram-repo.sh` | the Mac: the builder's repo to the other hosts |
| `packages/roles/builder.txt` | what only the builder needs |
| `/var/lib/archbuild/dram-x86_64/{root,pj}` | the pristine chroot and the working copy, on cabin |
| `/srv/dram` | built and signed packages and `dram.db`, on cabin |
| `/var/lib/dram-repo` | what pacman reads, on each host |
| `~/.config/dram/gpgkey`, `~/.config/dram/peer` | the signing key's fingerprint; a peer override |
| `~/.cache/dram-pkgs/{aur,src,log}` | AUR clones, the source cache, build logs |

## Operating it

Adding, removing and vendoring packages, and a key rotation on a fresh builder: [handbook chapter 7](../../records/handbook/07-packages.md).

## Status

As of 2026-10-13 `[dram]` holds 19 packages, and `pkgs/BUILDLOG` records the last build of each on cabin, on 2026-10-11 or 2026-10-12.
`packages/aur.txt` is empty, and cabin's last harvest (`hosts/cabin/packages/aur.txt`) lists no foreign package.

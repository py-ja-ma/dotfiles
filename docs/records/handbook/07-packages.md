# 7. Packages and the `[dram]` repo

Software reaches a host through four channels, and every installed package
belongs to exactly one of them. This chapter says which channel a package
goes to, where its name is written down, and how to add, update and remove
one without leaving a stray behind. The test at the end is mechanical:
`dram doctor --supply` all `[ok]` and `pacman -Qm` empty.

Reference: `docs/toolchain/packaging/README.md` (the `[dram]` runbook end to end),
`pkgs/README.md` (the policy), `docs/security/software-supply/README.md` (the threat review and
the status), `docs/security/software-supply/integrity.md` (what every `dram doctor --supply` line
means), `docs/toolchain/packaging/flatpak.md`, `docs/toolchain/README.md` (one app per job and where each
comes from), `decisions/0003-gui-apps-from-pacman-over-nixpkgs.md`,
`decisions/0005-own-package-repo.md`, `docs/commands.md` (`dram pkgs --help`).

## Before you start

- A host past chapter 2 with `[dram]` enabled: `pacman -Sl dram | wc -l` prints
  the number of packages in `pkgs/manifest.txt` (18 on 2026-10-11). If it prints 0,
  see "Enabling `[dram]` on a host" below; on a fresh fleet, "`[dram]` from scratch".
- `dram pkgs --help` prints the `usage: pkgs.sh <check|update|build|publish|log|list|key>`
  block.
- For building: cabin (the builder role), with `sudo bash system/dram-builder-setup.sh`
  done once and the signing key's fingerprint in `~/.config/dram/gpgkey`.
- For carrying packages to the other hosts: the Mac.

## The four sources and the rule

| Source | Owns | Declared in | Installed by |
|---|---|---|---|
| **pacman, official repos** (`core`, `extra`, `multilib`) | anything that opens a window or touches GL/Vulkan/VA-API, daemons, kernel-adjacent tools, fonts packaged by Arch | `packages/*.txt` | `install/bootstrap.sh` phase 1, `dram apply` on the host, or `sudo pacman -S` by hand |
| **`[dram]`**, the repo this repo builds | every AUR-origin or vendor-binary package: VSCodium, Proton Pass, the Hyprland plugins, Gaming Mode's sessions, the emulators without an Arch or Flathub build, ImHex (no AUR helper on the hosts since 2026-10-10, `decisions/0013`) | `pkgs/<name>/` plus one line in `pkgs/manifest.txt`; a role file lists the ones only that role installs (`pkgs/README.md`) | `dram apply` the first time, `dram update` after (pacman sees `[dram]` as a normal signed repo, above `[core]`) |
| **Flatpak** (Flathub only) | vendor binaries that cannot be built and need no theming (Vesktop, LocalSend, Flatseal) and, for the emulation role, Flathub-verified emulators | `packages/flatpak/<role>.txt`, overrides in `dotfiles/.local/share/flatpak/overrides/<id>` | `sudo bash system/flatpak-setup.sh`; updated by `dram update` |
| **Nix** (the flake) | CLI and TUI tools (`bat eza fd rg btop atuin starship …`, the homelab kit `kubectl talosctl sops age …`), the Letterpress fonts, and the dotfile wiring | `home.packages` in `modules/shell.nix`, `modules/dev.nix`, `modules/desktop.nix`, pinned by `flake.lock` | `dram switch` |

The rule (`decisions/0003`): on Arch, a nixpkgs GUI program links against
nixpkgs' own Mesa and cannot see the driver pacman installed, so **nothing
with a window or GL goes into `home.packages`**. A self-contained static CLI
whose version is the same on both hosts goes to Nix; a daemon, a
kernel-adjacent tool or anything with a window goes to pacman. Since
`decisions/0005`, "AUR" means `[dram]`: no host builds from the AUR any more,
and `packages/aur.txt` lists only what is deliberately not vendored yet (today:
nothing). Flatpak is the carve-out for a vendor binary nobody can build, from
a Flathub-verified publisher, with the sandbox tightened in the override file.
`bash bin/check.sh` §3 warns about packages declared but installed nowhere, and
about explicit packages no manifest declares (`hosts/<h>/packages/` is the evidence).

When in doubt: `type -a <cmd>` shows whether the binary on `$PATH` is
`~/.nix-profile/bin/<cmd>` or `/usr/bin/<cmd>`; `pacman -Qi <pkg>` shows
`Packager : pj dram packages …` for a `[dram]` package and an Arch developer
for an official one.

## `packages/*.txt`: which host reads which

One package name per line, own-line comments only (`# why`), no inline
comments, one token per line; `bash bin/check.sh` §3 fails on anything else,
on a name in two repo lists, and on an AUR name in a repo list.

| File | Who installs it |
|---|---|
| `base.txt` | every host, headless or not, on metal or in WSL (the implicit base role: the userland) |
| `metal.txt` | every host on its own hardware, never a WSL clone: the kernel and firmware, the boot chain, disks, power, Wi-Fi, disk health, snapshots, the firewall |
| `wsl-skip.tsv` | not a list: what a WSL clone leaves out although its roles declare it (the Windows build of an app, the VM kit, the GUIs, printing and scanning, `[dram]` names), one reason per row |
| `roles/<role>.txt` | every host whose `modules/hosts/<name>.nix` lists the role in `roles = [ … ]` (one line; `decisions/0009-roles-and-host-shape.md`). cabin has every role; lantern desktop, gaming, dump-kit, re-lab, sysadmin, dev, college, office, telephony; campfire desktop, creator, recording, sysadmin; the WSL clones dev, sysadmin, office, college (thermos-wsl also re-lab) |
| `cpu-amd.txt` / `cpu-intel.txt` | cabin / lantern (CPU microcode) |
| `gpu-nvidia.txt` / `gpu-intel.txt` / `gpu-amd.txt` | cabin / lantern / no host today |
| `laptop.txt` | lantern (battery, lid, backlight) |
| `host-<name>.txt` | the one host whose `/etc/hostname` (or `hosts/<name>/`) is `<name>`: what is about that box, not its vendors. Today `host-cabin.txt`: `linux-lts`, `linux-lts-headers` and `nvidia-open-lts` (cabin's second kernel, with its prebuilt NVIDIA module), and `dram-case-display` from `[dram]` (the temperature panel on its case, `docs/case-display.md`) |
| `roles/builder.txt` | the host with the builder role (cabin): `devtools`, `diffoscope`; `system/dram-builder-setup.sh` makes the chroot around them |
| `aur.txt` | what is deliberately not vendored yet; empty, and nothing builds it (no AUR helper since 2026-10-10); anything from the AUR is vendored instead (below). `dram doctor --supply` expects every `pacman -Qm` name to be here or in `pkgs/manifest.txt` |

`install/bootstrap.sh` detects CPU, GPU and form factor and picks the lists, adds the
host's roles from its host file, plus `host-<name>.txt` when `/etc/hostname` has one —
one reader for every caller, `install/lib/roles.sh`. Inside WSL the form factor is `wsl`:
no `metal.txt` and no hardware list, and `dram apply` drops the `wsl-skip.tsv` names. `dram apply` on the host uses it
too: it detects the hardware, adds the roles and the `[dram]` install set, shows the plan
(missing packages, undeclared explicit ones, units to enable, `/etc` drift, register
verdicts) and asks before installing (`decisions/0008`). `bash bin/check.sh` §3 derives
the same per-host set when it
compares the lists with `hosts/<host>/packages/explicit.txt`. `dram update`
upgrades what is installed; it does not read the lists, so a new name needs one
explicit install.

## Adding or removing an official package

Add:

```sh
cd ~/git/dotfiles
$EDITOR packages/roles/<role>.txt    # or base.txt (every host) / a hardware list; one name, an own-line comment above it saying why
$EDITOR packages/register.tsv        # one row: name<TAB>verdict<TAB>until<TAB>note — the package's verdict on
                                     # the three rules (decisions/0013); a proprietary or Russia/China-backed
                                     # package needs a signed waiver first, an unknown-origin one an Origin ruling
CHECK_PKGDB=1 bash bin/check.sh      # "all checks passed"; CHECK_PKGDB=1 also proves the name exists
                                     # in core/extra/multilib or [dram] (bin/check-pkgnames.py) —
                                     # it cannot tell a right name from a wrong package (extra/cutter)
git commit -am "packages: <name>"
bin/push-host.sh <user>@<address>    # on the Mac; the hosts have no git remote
```

then on each host that reads that list:

```sh
sudo pacman -S --needed <name>
```

`--needed` makes a second run a no-op. Or let the host converge to its lists:
`dram apply --dry-run` prints the plan, `dram apply` installs everything declared and
missing (never `-Syu`; it refuses when the sync databases are newer than the last full
upgrade — run `dram update` first), enables the declared units and runs the role hooks.
`dram apply --prune` also removes explicit packages no role declares (you type the
hostname; kernels, bootloaders and the GPU driver are protected).

Remove: delete the line, `bash bin/check.sh`, commit, push, then on each host:

```sh
sudo pacman -Rns <name>              # the package and the dependencies only it needed
pacman -Qqdt                         # orphans left behind; empty is the goal
sudo pacman -Rns $(pacman -Qqdt)     # when it is not empty
```

`dram doctor` warns about orphans (`N orphaned package(s)`) and `dram update`
asks to remove them on every run. `dram harvest` afterwards refreshes
`hosts/<host>/packages/*.txt` with what is really installed; commit it.

## Adding an AUR package: vendor it into `[dram]`

Nothing is installed from the AUR directly. The package's PKGBUILD is copied
into this repo, read, pinned, built once on cabin in a clean chroot, signed,
and served to both hosts. Steps (full detail: `pkgs/README.md` "How to add a
package" and `docs/toolchain/packaging/README.md` §7):

1. **Fetch and read.** On the Mac or a host:

   ```sh
   cd ~/git/dotfiles
   name=<aur-name>
   mkdir pkgs/$name && cd pkgs/$name
   curl -O "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=$name"   # and every .install, hook, patch it lists
   ```

   Read all of it. Pin every source: a release tarball with a sha256 computed
   from a download made here, or `#commit=`/`#tag=` for git sources, or the hash
   the vendor publishes for a `-bin`. Remove anything that runs unread
   upstream shell at build time (`install.sh`, `curl`, `npm install`). Keep
   `pkgver` and `pkgrel` as upstream has them. No `-git` packages, no
   `pkgver()` functions, no md5.

2. **Record what was read.** Three files next to the PKGBUILD:

   - `UPSTREAM`: one line, `aur:<pkgbase> <commit sha from the AUR cgit log> <date>`.
   - `REVIEW.md`: three bullets: what the package is, what runs at build and
     install time, what was changed against the AUR. `dram pkgs check`
     refuses a directory without it.
   - `PIN` (optional): how to re-pin the sources on a bump when it is not
     obvious.
   - `.SRCINFO`: `makepkg --printsrcinfo > .SRCINFO` on cabin (Linux only).

3. **List it.** `echo "$name=<pkgver>-<pkgrel>" >> pkgs/manifest.txt && sort -o pkgs/manifest.txt pkgs/manifest.txt`.
   A package that exists only as a build dependency goes into `pkgs/BUILD-ONLY`
   too. If the name was in `packages/aur.txt`, delete it there: a name lives in
   exactly one list.

4. **Check.** Runs anywhere, including the Mac:

   ```sh
   dram pkgs check $name            # or: bash bin/pkgs.sh check <name>
   ```

   The good result is `[ok]` lines and exit 0. A `[!]` names the rule broken:
   a missing file, an unpinned source, a version that differs from
   `.SRCINFO`, or a name that shadows an official package. Shadowing is
   refused on purpose: `[dram]` sits above `[core]` in `pacman.conf`, so a
   vendored name silently replaces Arch's build on every host; it is allowed
   only when listed in `pkgs/OVERRIDES` with the reason in `REVIEW.md`.

5. **Build and publish on cabin** (the only builder; `packages/roles/builder.txt`,
   the chroot at `/var/lib/archbuild/dram-x86_64`, the key in `~/.gnupg`):

   ```sh
   git commit -am "pkgs: $name"
   # on the Mac (when the edit was made there): bin/push-host.sh pj@cabin
   # on cabin:
   cd ~/git/dotfiles
   dram pkgs build $name            # makechrootpkg -c -u; one sudo prompt; signs the package; appends to pkgs/BUILDLOG
   dram pkgs publish                # repo-add -s into /srv/dram/dram.db, rsync to /var/lib/dram-repo here
   git commit -am "pkgs: build $name"
   # on the Mac afterwards: git pull pj@cabin:git/dotfiles master
   ```

   `build` prints the chroot steps and ends with the signed file's name and a
   `BUILDLOG` line; `publish` ends with the `rsync` summary and writes this
   host only: cabin's key on lantern is restricted to `borg serve` (chapter 5)
   and cannot rsync there, so the Mac carries the repo (next step).

6. **Carry it to lantern from the Mac.** The Mac holds unrestricted keys to
   both hosts:

   ```sh
   bash bin/sync-dram-repo.sh       # cabin:/srv/dram -> ~/backups/dram/ -> lantern:/var/lib/dram-repo
   ```

   It prints an rsync summary per leg and exits 0. (There is no host-to-host
   pull: lantern's key on cabin is restricted to `borg serve`.)

7. **Install on both hosts.** `dram update`, or just
   `sudo pacman -Syu --needed $name`. Confirm with
   `pacman -Qi $name | grep Packager` (`pj dram packages`) and
   `dram doctor --supply`.

**Signing key.** One key, generated on cabin as `pj`, never exported in private
form; its fingerprint is in `~/.config/dram/gpgkey` (not in the repo), its
public half is `pkgs/dram.asc` (committed). `system/pacman-dram-repo.sh`
imports and locally signs it into pacman's keyring on every host; hosts run
`SigLevel = Required DatabaseRequired`, so an unsigned or re-signed file is
refused. It expires after two years: `gpg --quick-set-expire <fpr> 2y`,
re-export `dram.asc`, commit, re-run `pacman-dram-repo.sh` on both hosts. The
private key is inside cabin's Borg set (chapter 5); the passphrase is not.

**Updating a vendored package.** `dram pkgs update <name>` on cabin clones the
AUR history, shows the diff since the commit in `UPSTREAM` in `$PAGER`, and on
`y` merges it on top of the vendored copy, shows `PIN`, runs `updpkgsums`,
regenerates `.SRCINFO`, rewrites `UPSTREAM` and `manifest.txt`, and commits.
Then steps 5 to 7. Read the diff: a new file in `source=`, any `.install`
change, `sudo`/`/tmp`/`curl`/`npm install` in a build, or an unexpected
maintainer is the reason this workflow exists. A Hyprland upgrade needs the two
plugin packages rebuilt *before* `dram update` (`docs/toolchain/packaging/README.md` §9).

## `[dram]` from scratch (a fresh builder: cabin, 2026-10)

The 2026-10 reinstall starts the fleet with **new keys** ([D147](../../../decisions/log.md#d147)): the
`[dram]` signing key that signed everything until then stays on the old cabin and is
not trusted again. On the new cabin, after chapter 1 (its bootstrap already ran
`pacman-dram-repo.sh` with the old public key, and `dram apply` reported the `[dram]` names
it could not install yet) and chapter 2 §3 (git signs every commit, and a fresh install has
no key to sign with yet):

```sh
# on cabin
sudo bash ~/git/dotfiles/system/dram-builder-setup.sh   # devtools, the clean chroot, /srv/dram; prints the next step
dram pkgs key --new                                     # as pj, never sudo: gpg asks the key's passphrase (Proton Pass)
# [ok] key <FPR>: ~/.config/dram/gpgkey, pkgs/dram.asc, the pin in system/pacman-dram-repo.sh
git -C ~/git/dotfiles commit -m "pkgs: a new dram signing key" pkgs/dram.asc system/pacman-dram-repo.sh
gpg --armor --export-secret-keys <FPR> > /run/media/<you>/<offline stick>/dram-signing.asc   # custody: offline + Proton Pass
dram pkgs check                                         # green before anything is built
dram pkgs build                                         # every package in pkgs/manifest.txt, dependencies first (an hour or more)
dram pkgs publish                                       # repo-add -s into /srv/dram, rsync to /var/lib/dram-repo here
git -C ~/git/dotfiles commit -m "pkgs: the first builds under the new key" pkgs/BUILDLOG   # build appended the hashes
sudo bash ~/git/dotfiles/system/pacman-dram-repo.sh     # trusts the new key, drops the old one, adds the Include above [core]
# on the Mac: the key commit into a release
git pull pj@cabin:git/dotfiles master
bin/release.sh -m "a new [dram] signing key" --no-push  # --no-push while an old machine still answers at a host's address
bin/push-host.sh pj@cabin
# on cabin
dram update                                             # to that release; pacman -Syu now sees [dram]
dram apply                                              # the [dram] names the roles list (Gaming Mode, VSCodium, the emulators …)
```

Not `dram update` on cabin between the key commit and that release: on channel stable it
moves the checkout to the newest tag, which still pins the old key, and the next `dram
apply` would trust the old key again and drop the new one from pacman's keyring. If it
happened anyway: the release, `dram update`, then `sudo bash
~/git/dotfiles/system/pacman-dram-repo.sh` once more.

`dram pkgs key` (no flag) shows the pinned fingerprint, `pkgs/dram.asc`'s and the one this
host signs with — all three must be the same. `pacman-dram-repo.sh` prints `removed the
rotated-out [dram] key 6F000C2F…` once. Every other host enables `[dram]` only after that
release: `bin/sync-dram-repo.sh` on the Mac, then the steps below.

### Enabling `[dram]` on a host

Once per host, after `pkgs/dram.asc` exists in the checkout:

```sh
sudo bash ~/git/dotfiles/system/pacman-dram-repo.sh --dry-run   # read it
sudo bash ~/git/dotfiles/system/pacman-dram-repo.sh             # key, /etc/pacman.d/dram.conf, /var/lib/dram-repo
# fill /var/lib/dram-repo: `dram pkgs publish` on cabin, or bin/sync-dram-repo.sh from the Mac for the others
sudo bash ~/git/dotfiles/system/pacman-dram-repo.sh             # now adds the Include above [core]
dram update
```

The script refuses to add the `Include` while `/var/lib/dram-repo/dram.db` is
missing (a missing database would break every `pacman -Sy`), which is why it
runs twice.

## Adding a Flatpak

Only for a vendor binary that cannot be built, where theming does not matter,
from Flathub, preferably with the verified badge
(`https://flathub.org/apps/<id>`). Checklist (`docs/toolchain/packaging/flatpak.md` "Adding an app"):

1. Read the manifest's `finish-args` (`github.com/flathub/<id>`) and decide
   what to take away. `host`, `home`, `device=all`, `system-bus`,
   `session-bus`: no by default.
2. Write `dotfiles/.local/share/flatpak/overrides/<id>` in
   `flatpak-metadata(5)` format, with the header listing what is kept,
   removed and never granted (copy `dev.vencord.Vesktop` as the template:
   Wayland plus `fallback-x11`, `pulseaudio`, `dri` only, no tray names,
   Downloads read-write, Pictures read-only).
3. Add the id to `packages/flatpak/<role>.txt`, a row to the tables in
   `docs/toolchain/packaging/flatpak.md` and `docs/toolchain/README.md`; commit; push to the host.
4. On the host:

   ```sh
   sudo bash ~/git/dotfiles/system/flatpak-setup.sh     # installs the app, copies the override to /var/lib/flatpak/overrides/
   flatpak info --show-permissions <id>                 # what the sandbox really has
   ```

5. For a protocol handler, set the default in `xdg.mimeApps`
   (`modules/desktop.nix`), not with `xdg-mime` by hand (chapter 2).

The overrides directory is linked into the repo as a whole, so an edit made in
**Flatseal** (`flatpak run com.github.tchx84.Flatseal`) or with
`flatpak override --user` lands in `dotfiles/.local/share/flatpak/overrides/<id>`
and shows in `git status`. Commit it and re-run the setup script so the system
copy matches, or `git checkout` it. Flatpak apps do not see the nix-profile
fonts or the GTK recolouring; that is the accepted trade.

Remove a Flatpak: `flatpak uninstall <id> && flatpak uninstall --unused`, delete
the override file and the `packages/flatpak/` entry and the doc rows, commit.

## Removing cleanly

After any removal, three questions, each with a command:

```sh
pacman -Qqdt                     # orphans: dependencies nothing needs any more -> sudo pacman -Rns $(pacman -Qqdt)
pacman -Qm                       # foreign packages: not from any configured repo; must be empty
dram doctor --supply             # every foreign name accounted for, [dram] signed and complete, Flathub only
```

An `unaccounted foreign package: <x>` line means `<x>` is installed but is in
neither `pkgs/manifest.txt` nor `packages/aur.txt`: it got on the box outside
the declared channels. Either vendor it (above), list it in `packages/aur.txt`
with an own-line comment saying why it is not vendored, or
`sudo pacman -Rns <x>`. The converse, `[i] listed but not installed here`, is
information: a host-specific package that this host does not have.

A `[dram]` package that misbehaves after an update rolls back from pacman's
cache (`ls /var/cache/pacman/pkg/<name>-*`, `sudo pacman -U <older file>`);
`paccache -rk2` keeps the last two versions.

## The `[dram]` trust model

Every package in `[dram]` is a PKGBUILD that someone read, with sources pinned
to a hash computed from a download made here or to a commit, built once in a
throwaway devtools chroot on cabin that never sees `[dram]` itself nor a sudo
ticket, signed with a key that exists only on cabin (and its offline export), and
served over `file://` from a directory the Mac fills with rsync over SSH; nothing
listens on the network, and every host refuses an unsigned package or database and
any key but the pinned one.
What the signature proves is exactly "built on cabin from this PKGBUILD at
this commit", and `pkgs/BUILDLOG` records the hash of every build; what it does
not prove is that upstream is honest, which is why `dram pkgs update` puts
the upstream diff on screen before anything is merged. The review that led here, the ranked threat table and what
is still open are in `docs/security/software-supply/README.md`.

The repo was called `[rice]` until 2026-10-06, and the old hosts carried a one-off
cleanup list on 2026-10-07; both are history (git log) since the 2026-10 reinstall.

## Windows: `packages/winget/`

The register's three rules cover Windows too (`decisions/0013` is for every
machine). Windows lists its apps under Arch's role names,
`packages/winget/<role>.txt` (base, desktop, chat, gaming, creator, office,
college, dev, sysadmin, re-lab), plus `host-<host>.txt` for what is about one box
(cabin-win's case panel and NVIDIA App), the
way `packages/host-cabin.txt` works on Arch. One name per line, own-line comments
only, each name in one list and prefixed: `winget:<id>` (a winget package,
`winget:Valve.Steam`), `msstore:<id>` (a Microsoft Store product: Spotify is
`msstore:9NCBCSZSJRSB`) or `manual:<name>` (installed by a Script unit or by hand:
`manual:jagex-launcher`, `manual:marvel-rivals`). The flake renders these lists
(decisions/0020, docs/platforms/windows/README.md): a Windows host installs every name of the
lists its roles name, unless its host file holds it back (`windows/hosts/<host>.nix`),
through its committed build (`windows/build/<host>/`) and
`install/windows/apply-windows.sh`; a `manual:` name is a Script unit's or is
installed by hand (`windows/packages.nix` says how). The house fonts come from
`install/windows/fonts.pin`, whose fonts carry their Arch rows.

`bin/check-register.py` (§15) keeps the lists and the converge honest: every
listed name needs a register row under the Arch rules (no row, an expired waiver
or a `fail` verdict fails; `swap` and `pending` warn, also under `--rollout`,
which stays the Arch rebuilds' gate), every `WinGetPackage` unit of a rendered
build must be listed (an `Ensure: Absent` unit needs a `fail` row instead), and
a row whose note starts `= <name> (Arch)` must carry that Arch row's verdict and
date: `winget:Valve.Steam` is `= steam (Arch)`, so renewing the Steam waiver
renews both rows in one commit. `python3 bin/check-register.py --list` prints
every name with its list and verdict. Adding a Windows app is its list line, its
register row and a render (`bin/render-windows.sh`, which commits nothing: commit
`windows/build/` with them), in one commit.

## Done when

- [ ] `dram doctor --supply` on each host prints only `[ok]` and `[i]` lines
      and ends without a `warning(s)` summary (exit 0).
- [ ] `pacman -Qm` on each host prints nothing.
- [ ] `pacman -Sl dram | wc -l` equals the number of names in
      `pkgs/manifest.txt` (`dram pkgs list | wc -l`) on each host.
- [ ] `dram pkgs key` on cabin shows one fingerprint three times.
- [ ] `bash bin/check.sh` on the Mac ends with `all checks passed`
      (§3 for the lists, §12 for `pkgs/`).
- [ ] `flatpak list --app --columns=application,origin` shows only the three
      apps, all `flathub`.

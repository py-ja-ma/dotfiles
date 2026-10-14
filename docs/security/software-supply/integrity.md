# Integrity

[Security](../README.md) › [Software supply](README.md) › Integrity

Two tools check what landed on a host, on two rhythms.
`dram doctor --supply` asks whether what is on disk is what the packages shipped, and whether every foreign package is accounted for and pinned.
`bin/repro.sh` asks whether a packager's binary could have come from the published source.

| | |
|---|---|
| Code | the supply section of `dram doctor` (`dotfiles/.local/bin/dram`), `bin/repro.sh` |
| Runs on | any Arch host on its own hardware; `repro.sh` needs root for its build container |
| Needs | `archlinux-repro` (in `packages/base.txt`); `diffoscope` and `devtools` for `--ours` (`packages/roles/builder.txt`) |
| Decided in | built 2026-10-06 |

| Tool | When | Cost |
|---|---|---|
| `dram doctor --supply` | at the end of every `dram update` (as `--brief`), and whenever something feels off | read-only, seconds; `pacman -Qkk` is the slow part, 10 to 30 s |
| `bin/repro.sh` | monthly, and after an update that touched the kernel, Hyprland, openssh, sudo, systemd or pacman | minutes per package |

Both print `[skip]` lines when an input does not exist yet, such as `pkgs/manifest.txt` or Flatpak on a host without it.

## What each supply line means

| Line | Meaning | Fix |
|---|---|---|
| `N package(s) with altered files outside /etc: ...` | `pacman -Qkk` found a file outside `/etc` whose size, mtime, permissions or existence differs from the package database; the first 20 are listed | [an altered file](#an-altered-file), below |
| `[i] edited config files (expected) in: ...` | the same check, with every differing file under `/etc`: your edits | nothing; `dram pacnew` keeps them merged |
| `unaccounted foreign package: X` | `pacman -Qm` lists X, and neither `pkgs/manifest.txt` nor `packages/aur.txt` names it: something arrived outside the declared channels. `-debug` packages fold into their parent | vendor it into `pkgs/`, or remove it |
| `[i] listed but not installed here: ...` | declared and absent on this host; normal for host-specific packages | nothing, unless it should be here |
| `plugin package X built for hyprland A, hyprland is B` | `pkgs/<X>/PKGBUILD` pins `hyprland=A`; a plugin built against other headers loads into the compositor with a mismatched ABI | `dram pkgs build X`, publish, sync |
| `N yazi flavor/plugin(s) without a rev pin` | a dependency in `dotfiles/.config/yazi/package.toml` has no `rev`, so `ya pkg install` would clone it at HEAD. The flavors are generated in the repo and the file declares none, which reports ok | drop the dependency, or pin its `rev` |
| `N editor extension(s) not pinned to @version` | an id in `dotfiles/.local/bin/codium-themes-install` has no `@version`, so a reinstall takes whatever the marketplace serves that day | `codium --list-extensions --show-versions`, then write `id@version` |
| `[dram] SigLevel ...`, `database signature missing`, `repo has N, manifest lists M` | `/etc/pacman.d/dram.conf` must require package and database signatures, `/var/lib/dram-repo/dram.db.sig` must exist, and `pacman -Sl dram` must list the manifest | on cabin `dram pkgs publish`, then `bin/sync-dram-repo.sh` from the Mac |
| `flatpak app(s) not from flathub`, `remote(s) other than flathub` | Flatpak is allowed from Flathub only; another remote is an unreviewed channel | `flatpak remote-delete <name>`, and reinstall the app from Flathub |
| `sshd: password authentication is not explicitly off` | no `PasswordAuthentication no` in `/etc/ssh/sshd_config.d/*.conf` or `sshd_config`, read from the files | `sudo bash system/harden.sh` ([SSH](../identity/ssh.md)) |
| `nftables is not loaded — no firewall` | the ruleset is not loaded; the unit is a oneshot, so "inactive" alone is normal | `sudo bash system/harden.sh` ([Firewall](../network/firewall.md)) |

`arch-audit -u` (fixable CVEs) and `checkrebuild` stay in the pacman section of `dram doctor`.
`pacman-key --check-trust-db` does not run: it needs root and is slow, and `dram update` and the WKD timer refresh the keyring.

## An altered file

1. Find who owns it and what changed: `pacman -Qo /usr/bin/foo` names the package, and `pacman -Qkk foo` lists each differing file with the reason. An mtime-only difference on a font cache or a `.pyc` is usually a post-install hook; find out which one.
2. Compare it with the cached original, since `paccache -rk2` keeps the last two package files:
   ```sh
   f=/var/cache/pacman/pkg/$(pacman -Q foo | tr ' ' '-')-x86_64.pkg.tar.zst
   bsdtar -xOf "$f" usr/bin/foo | cmp - /usr/bin/foo
   bsdtar -xOf "$f" usr/bin/foo | diffoscope - /usr/bin/foo     # when cmp says they differ
   ```
   If the cache was trimmed, `sudo pacman -Sw foo` downloads the current version without installing it.
3. Reinstall with `sudo pacman -S foo`, which resets every file, then run `pacman -Qkk foo` again. If the file comes back altered by itself, find the hook: `grep -rl foo /usr/share/libalpm/hooks /etc/pacman.d/hooks`.
4. If the content differs and no hook explains it, treat the host as compromised rather than cleaned: an attacker who could write `/usr/bin` could have written anything else. Pull the backups from the other host ([the backups page](../../operations/backups/README.md)), reinstall from `install/`, and rotate the SSH keys and the Proton passwords.

## bin/repro.sh

```sh
bin/repro.sh                         # linux linux-lts hyprland openssh sudo systemd pacman
bin/repro.sh openssh sudo            # a subset
bin/repro.sh --ours hyprland-plugin-hyprfocus          # a vendored package, built twice
bin/repro.sh --ours /var/lib/dram-repo/<name>-<ver>-x86_64.pkg.tar.zst   # rebuilt against the published file
bin/repro.sh -n ...                  # print the commands only
```

### Official packages

They go through `archlinux-repro`, as `repro <file>`.
It reads the package's `.BUILDINFO` (the exact package versions of the packager's build chroot, `SOURCE_DATE_EPOCH`, the build options), recreates that chroot from the Arch archive in a container, rebuilds from the PKGBUILD at the recorded commit, and compares the result with the file on disk.
It needs root (systemd-nspawn), a few minutes per package, and disk space under `/var/lib/archlinux-repro`.
It prints `reproducible` or `NOT reproducible` per package, but its exit 1 covers both "not reproducible" and "the build failed", so read the log in `~/.local/state/dram/repro/`.
`repro -f` means "use the local PKGBUILD", the one in the current directory, which must match `.BUILDINFO`'s `pkgbuild_sha256sum`; it does not mean "force".

A `NOT reproducible` on an official package is first a question for https://reproducible.archlinux.org, where most known build-path and timestamp issues are tracked, and only then a question about your mirror.

### Packages from [dram]

They have no second party who built them.
`--ours <file>` first reads the file's `.BUILDINFO`: when every package in its build chroot was official, `repro -f` run from `pkgs/<name>` rebuilds it from the Arch archive with my PKGBUILD, an independent rebuild.
A package whose chroot held other `[dram]` packages gets the double build instead: `--ours <name>` builds `pkgs/<name>` twice with `makechrootpkg` into a scratch directory, with the same `SOURCE_DATE_EPOCH`, and runs `diffoscope` on the two results.
It never goes through `dram pkgs build`, which would sign the result, put it in `/srv/dram` and write `pkgs/BUILDLOG`.
Identical output means the PKGBUILD is deterministic, so a later difference after a "harmless" update is worth a question.
It does not mean the sources are what upstream published: the pinned `sha256sums` and `validpgpkeys` in the PKGBUILD are for that.

## Limits

- A compromised root can lie to `pacman -Qkk`. The check reads the local database and the filesystem through the running kernel, and a rootkit that patches either, or pacman itself, passes it. It catches sloppy tampering and drift, not a capable attacker. Checking offline, from the ISO against the package cache, is the next step, and it is not automated.
- A signature proves who signed, not what is inside. A valid signature on an Arch package says a packager's key signed that archive, not that the source was reviewed or the build machine was clean. Reproducible builds close part of that gap, and the recipe review in `dram pkgs update` another part.
- `repro` needs every build input in the Arch archive: official packages, and a `[dram]` package whose chroot held nothing from `[dram]`. For the rest, the double build proves determinism and nothing more.
- A pin freezes what you got, so an upstream change becomes a visible diff instead of a silent drift. It does not review what you froze.
- `[dram]` is signed with my own key. Its signature says "built on cabin from `pkgs/<name>/PKGBUILD` at that commit"; the trust is in the git history of `pkgs/` and the chroot build, not in the key.
- The sshd and firewall checks read configuration, not state. `PasswordAuthentication no` in a file takes effect only after `systemctl reload sshd`, and `dram doctor` cannot run `sshd -T` without root.
- Flatpak is a sandbox, not provenance. Flathub verifies little about who uploads; the "verified" badge is the only signal, and `dram doctor` does not check it.

# hosts

[Platforms](../docs/platforms/README.md) › Host records

One directory per host: what `dram harvest` last recorded on that machine, and a README written by hand about its hardware and quirks.
The records are evidence, not configuration: nothing reads them to decide what a host installs.
`bin/check.sh` compares them with the package lists, and `bin/diff-hosts.sh` compares two hosts.

| | |
|---|---|
| Needs | a host that runs `dram harvest`, or the Mac with `bin/harvest.sh <host> <ssh-target>` |
| Copy alone | no: these are my machines' records; copy the layout, not the files |
| License | MIT for the READMEs; the copies under `etc/` are the Arch packages' own files with local edits, under each package's license |

## What it needs

- `dram harvest` on the host, or `bin/harvest.sh` on the Mac, which writes the same files over ssh.
- A host file `modules/hosts/<host>.nix` for each directory: `bin/check.sh` §2 fails a directory without one, and a host file without its directory.

## Copy it alone

Don't copy the records.
To keep records of your own machines, copy `bin/harvest.sh`, run it against each machine, and commit what it writes.

## How it is wired here

| File | Written by | What it holds |
|---|---|---|
| `README.md` | hand | the board, disks, boot, network, quirks, and what has been done to the machine |
| `hardware.txt` | harvest | host name, CPU, GPU, kernel, boot mode, bootloader, ESP, form, the disks and their filesystems |
| `explicit.txt` in `packages/` | harvest | `pacman -Qqe`: what was installed by name |
| `aur.txt` in `packages/` | harvest | `pacman -Qqm`: foreign packages, empty since the AUR helper left the hosts |
| `versions.lock` in `packages/` | harvest | every installed package and its version |
| `enabled-system.txt`, `enabled-user.txt`, `default-target.txt` in `systemd/` | harvest | the enabled units and the default target |
| `etc/` | harvest | copies of the edited `/etc` files: `fstab`, `mkinitcpio.conf`, `pacman.conf`, `locale.gen`, the pacman hooks in use |
| `secureboot-baseline-<date>.txt` | hand | cabin's Secure Boot variables as accepted on that date ([Boot trust](../docs/security/boot-trust/README.md)) |

`bin/check.sh` §3 warns about a host's explicit package that no list it reads declares, and about a declared package that no host has.
A WSL clone's directory fills on its first `dram harvest` in the clone, with a `hardware.txt` that says `form: wsl`.

| Host | Record |
|---|---|
| [cabin](cabin/README.md) | the desktop and bench; harvested 2026-10-11 after its reinstall |
| [lantern](lantern/README.md) | the travel laptop's old install, until it is reinstalled |
| [campfire](campfire/README.md) | not installed |
| [cabin-wsl](cabin-wsl/README.md) | the WSL clone on cabin-win |
| [thermos-wsl](thermos-wsl/README.md) | the WSL clone planned on thermos |

## License

MIT, Patrick Jordan, for the READMEs and the harvest's own lists.
The files under `*/etc/` are copies of distribution files with local edits, under the license of the Arch package that ships each.

# packages

[Platforms](../docs/platforms/README.md) › [Arch Linux](../docs/platforms/arch/README.md) › [Roles](../docs/platforms/arch/roles.md)

Every package list in the repo: what each host installs on Arch, in WSL and on Windows, one name per line.
A host's lists follow from its roles, its detected hardware and its form; `install/lib/roles.sh` is the only reader that decides which.

| | |
|---|---|
| Needs | pacman for the Arch lists, winget for the Windows lists; a reader such as `install/lib/roles.sh`; tested 2026-10 |
| Copy alone | yes: each list is plain text, one name per line, comments on their own lines |
| License | MIT |

## What it needs

- pacman, to install a list: `grep -vE '^[[:space:]]*(#|$)' packages/base.txt | sudo pacman -S --needed -`.
- A row in `packages/register.tsv` for every name, which `bin/check.sh` §15 enforces ([decision 0013](../decisions/0013-software-rules-and-waivers.md)).
- Not needed: Nix, Home Manager or `dram` to read or install a list.

## Copy it alone

1. Copy the lists you want; keep one name per line, and comments on lines of their own: `bin/check.sh` §3 refuses an inline comment.
2. Replace `host-cabin.txt` with a list per machine of yours, named `host-<hostname>.txt`.
3. Install with the `pacman` line above, or source `install/lib/roles.sh` and call `host_package_files` to get the lists a host reads.

## How it is wired here

| List | Who reads it | What decides | Documented on |
|---|---|---|---|
| `base.txt` | `install/lib/roles.sh` | every host, on metal or in WSL | [Roles](../docs/platforms/arch/roles.md) |
| `metal.txt` | `install/lib/roles.sh` | every host on its own hardware | [Roles](../docs/platforms/arch/roles.md) |
| `cpu-amd.txt`, `cpu-intel.txt` | `install/lib/roles.sh` | the detected CPU | [Roles](../docs/platforms/arch/roles.md#hardware-lists) |
| `gpu-amd.txt`, `gpu-intel.txt`, `gpu-nvidia.txt` | `install/lib/roles.sh`; bootstrap swaps in `nvidia-dkms` for a card older than Turing | the detected GPUs | [Roles](../docs/platforms/arch/roles.md#hardware-lists) |
| `laptop.txt` | `install/lib/roles.sh` | a battery | [Roles](../docs/platforms/arch/roles.md#hardware-lists) |
| `host-<host>.txt` | `install/lib/roles.sh` | the host's name | [Roles](../docs/platforms/arch/roles.md) |
| `roles/<role>.txt` | `install/lib/roles.sh`; `modules/options.nix` builds the allowed roles from the file names | the host's roles line | [roles/README.md](roles/README.md) |
| `flatpak/<role>.txt` | `system/flatpak-setup.sh` | the host's roles | [flatpak/README.md](flatpak/README.md) |
| `uv/re-lab.txt`, `ghidra-extensions.tsv` | `re-lab-tools`, per user | the re-lab role | [Toolchain](../docs/toolchain/README.md) |
| `aur.txt` | bootstrap, which only warns | empty: an AUR package is vendored into `pkgs/` instead | [Toolchain](../docs/toolchain/README.md) |
| `wsl-skip.tsv` | `install/lib/roles.sh` | names a WSL clone's roles declare but it never installs, one reason each | [WSL](../docs/platforms/wsl/README.md) |
| `register.tsv` | `bin/check-register.py`, `dram apply` | a verdict for every name in every list | [Register](../docs/security/software-supply/register.md) |
| `winget/<role>.txt`, `winget/host-<host>.txt` | the Windows renderer (`windows/lib.nix`), `bin/check-register.py` | a Windows host's roles and name | below |

`bin/check.sh` §3 lints the Arch lists: no inline comments, no duplicates, no AUR name in a repo list.
It warns when a declared name is installed on no host, or when a host's explicit package is in no list it reads, using the host's last harvest in `hosts/<host>/packages/`.
With `CHECK_PKGDB=1` every name must also resolve in core, extra, multilib or `[dram]`.

### The Windows lists

`packages/winget/` holds the Windows PCs' lists under Arch's role names, plus `host-<host>.txt` for what concerns one PC: cabin-win's case panel driver and the NVIDIA App, thermos' work tools.
A line is one prefixed name:

| Prefix | Meaning | Example |
|---|---|---|
| `winget:<id>` | a winget package | `winget:Valve.Steam` |
| `msstore:<id>` | a Microsoft Store product | `msstore:9NCBCSZSJRSB` (Spotify) |
| `manual:<name>` | installed by a Script unit, or by hand as `windows/packages.nix` says | `manual:nvidia-app` |

Each name is in one list only, with comments on lines of their own.
The renderer installs every name of the lists a host's roles name, unless the host file holds it back ([renderer](../docs/platforms/windows/renderer.md)).
A register row whose note starts `= <name> (Arch)` keeps that Arch row's verdict and date, so renewing a waiver renews both rows in one commit.
This directory takes no README of its own: every file under `packages/winget/` is a stamped render input, and a new one would make the build stale.

## License

MIT, Patrick Jordan.

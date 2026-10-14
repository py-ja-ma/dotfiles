# wsl

[Platforms](../../docs/platforms/README.md) › [WSL](../../docs/platforms/wsl/README.md)

The system half of the Arch clone in WSL 2: the files `system/wsl-setup.sh` installs into the official Arch image so `dram apply` and Home Manager can converge it like any Arch host.
The clone never gets a kernel, boot chain, firewall or session of its own; Windows owns those.

| | |
|---|---|
| Needs | WSL 2 with the official Arch image, systemd in the distro, openssh, rootless Podman's `shadow` tools; on Windows, `install/windows/dram-windows/wsl.ps1` and `install/windows/wslconfig`; tested on cabin-win 2026-10-12 |
| Copy alone | no: the clone is this repo's Arch user layer and roles converged inside WSL, so it needs the rest of the repo |
| License | MIT |

## What it needs

- A host file with `form = "wsl"` and a `wsl` block (`modules/hosts/cabin-wsl.nix`), which `install/lib/roles.sh` reads for the distro's name and the agent.
- `system/wsl-setup.sh`, the `wsl` row of `system/apply-hooks.tsv` that runs it, and the `wsl` rows of `system/files.tsv` and `system/units.tsv`.
- `keys/ssh.pub` for the clone's sshd, and `packages/wsl-skip.tsv` for what the clone's roles leave out.

## Copy it alone

The files here only make sense inside this repo's clone.
`wsl.conf` and `sshd.conf` are worth reading on their own: an Arch distro with systemd, its own host name and no Windows `PATH`, and an sshd on loopback that takes only keys.

## How it is wired here

| File | Installed to | What it does |
|---|---|---|
| `wsl.conf` | `/etc/wsl.conf`, with the host, user and distro filled in | the distro's own name, so `dram` loads the clone's host file and not cabin's; systemd on; the default user; `appendWindowsPath=false` |
| `sshd.conf` | `/etc/ssh/sshd_config.d/10-dram-wsl.conf` | sshd on `127.0.0.1:2222` for VSCodium's Open Remote - SSH: keys only, a touch for a security key |
| `dram-wsl-rshared.service` | `/etc/systemd/system/` | makes `/` a shared mount at boot, which rootless Podman needs |
| `70-dram-wsl-yubikey.rules` | `/etc/udev/rules.d/` | a YubiKey attached with `usbipd`: its hidraw node for wheel |

`wsl-setup.sh` also keeps the units Microsoft lists as breaking WSL masked, turns linger on for the login, restores the file capabilities of `newuidmap` and `newgidmap`, and writes the YubiKeys' keys from `keys/ssh.pub` for sshd.
`bin/push-host.sh --wsl` stages `wsl.conf` on the Windows PC with the repo's bundle, and `wsl.ps1` writes it into a new distro before the first boot.
`dram doctor` in the clone compares `/etc/wsl.conf` with this file and checks the masks, linger and the shared mount.
`bin/check.sh` §21 checks what a clone's plan holds.

## License

MIT, Patrick Jordan.

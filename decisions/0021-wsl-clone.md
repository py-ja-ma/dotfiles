# 0021: Arch in WSL 2 is a clone of the user layer and the CLI roles

[Platforms › WSL clone](../docs/platforms/wsl/README.md) · proposed 2026-10-12

A WSL clone is an Arch host made from the official image and this repo, with `form = "wsl"` and nothing of the metal layer; the cost is a second kind of host that every script must recognize.

## Context

I want Arch in WSL to be a straight clone of the Arch setup, and Windows to stay subordinate to Arch, the primary OS.
The coding and homelab profiles on Windows need a Linux to work in: VSCodium runs natively on Windows, git lives
only in the clone ([D58](log.md#d58)), and the toolchains, npm, rootless Podman and kind with it
([D54](log.md#d54) to [D57](log.md#d57)).

What WSL gives: the official Arch image (`wsl --install archlinux`; monthly, reproducible,
Sigstore-signed; `base` alone, systemd on, no user, an empty keyring) in an ext4 VHDX that
Windows boots with Microsoft's kernel. What it cannot give: a kernel, boot chain, firewall,
network stack, session, audio or GPU driver of the clone's own — Windows owns the VM.

## Decision

- **Converge, never copy.** A clone is an Arch host made from the official image and this
  repo, like any other: the same package lists and register, `dram apply`, Home Manager,
  the release, channel and rollback flow. No tarball of cabin's root (it drags the metal
  units, kernels and session along) and no `wsl --mount` of Arch's disks (that hands
  Windows a read-write path into Arch's pools: the reverse of "Windows at the mercy of
  Arch"). The VHDX is disposable: `wsl --unregister`, then the runbook, in under an hour.
- **A platform, not a role:** `form = "wsl"` in the host file (`modules/options.nix`; metal
  is the default), with `gpu = "none"` and `wsl.{windowsHost, distro, sshAgent}`. Hosts
  `cabin-wsl` (dev, sysadmin) and `thermos-wsl` (dev, sysadmin, re-lab); both also office
  and college since 2026-10-12, the terminal half of the work and finance profiles ([D141](log.md#d141)).
  `/etc/wsl.conf`
  names the distro `<host>-wsl`: WSL would take the Windows name (`cabin`), and `dram`,
  `bootstrap.sh` and the hooks refuse a host file of the other kind.
- **What a clone never is:** no kernel, initramfs, UKIs, Secure Boot, snapper or dkms; no
  Hyprland, greeter, audio, power or Bluetooth; no firewall or network manager (Windows'
  firewall and the Hyper-V firewall, WSL's DNS); no GPU driver (CUDA would come from
  Windows' `libcuda`); no gaming, emulation, creator, recording or builder role; no
  `[dram]` repo (v1). Assertions (`modules/options.nix`) and `bin/check.sh` §21 hold it.
- **Packages:** `packages/base.txt` is the userland every host gets; `packages/metal.txt`
  (kernel, firmware, boot, disks, power, Wi-Fi, disk health, snapshots, firewall) and the
  hardware lists go to metal hosts only (`install/lib/roles.sh`); `packages/wsl-skip.tsv`
  names what a clone leaves out although its roles declare it, each with a reason
  (VSCodium's Windows build, the VM kit, the GUIs while WSLg is off, printing and scanning,
  the `[dram]` names).
- **System layer:** `system/*.tsv` take the pseudo-roles `metal` and `wsl` (and `a,b`);
  `system/wsl-setup.sh` is the `wsl` hook: wsl.conf and the hostname, Microsoft's masks,
  metal units off, linger, rootless Podman's fixes, sshd on 127.0.0.1:2222.
- **Keys:** Windows keeps the YubiKey. ssh and git signing in the clone reach Windows'
  OpenSSH agent through `wsl2-ssh-agent` from nixpkgs (MIT, Japan; never the AUR package,
  whose maintainer lists China); the touch comes through Windows Hello ([D79](log.md#d79)).
  `usbipd-win` only on demand, under a waiver not yet signed ([D118](log.md#d118)).
- **Editing from Windows:** VSCodium native with Open Remote - SSH to the clone's sshd on
  `127.0.0.1:2222` (loopback only, keys only, a touch per login), not Open Remote - WSL
  (stale since 2025-04) ([D55](log.md#d55)).
- **Windows' side:** `%UserProfile%\.wslconfig` from `install/windows/wslconfig` (mirrored
  networking, memory and swap capped, `defaultVhdSize` 128 GB on cabin and 96 GB on
  thermos set before the distro exists, sparse, WSLg and nested virtualisation off; [D80](log.md#d80));
  the VHDX on C:, never on Arch's disks or eva; `install/windows/dram-windows/wsl.ps1` builds
  the clone, by hand.
- **Updates:** the Mac stages the release bundle through Windows' OpenSSH
  (`bin/push-host.sh --wsl`, HostKeyAlias `<pc>-win`) in `C:\ProgramData\dram`; `dram update`
  in the clone receives it (`dram receive`), then runs as on Arch, with "restart the distro"
  for "reboot". No sshd for pushes, no inbound firewall hole.
- **NixOS-WSL is not this:** it is another OS, and it was struck from the plan of
  `decisions/0018` on 2026-10-12 ([D139](log.md#d139)).

## Consequences

- Every metal host is unchanged: cabin's, lantern's and campfire's Home Manager activation
  derivations are byte-identical before and after the change, and so are their declared
  package sets and the units, `/etc` files and hooks `dram apply` selects for them.
- `modules/cli.nix` gives every host the `dram` CLI, `~/.ssh/config`, starship, yazi, btop's
  template and the themes; fzf no longer exits on a host without the desktop role.
- `diffutils` is declared in base: the official image has no kernel to pull it in, and the
  scripts compare files with `cmp`.
- Windows admin is root of the clone's VM: it can stop, export or delete it, and the VHDX is
  only as private as BitLocker on C:. "Windows at the mercy of Arch" holds for what the
  clone contains (this repo declares it), not for who hosts it.
- The clone sleeps when idle; its timers run only while it runs. A push fails harmlessly
  while its Windows PC is off or cabin is in Arch; the next push catches up.
- Open: the acceptance itself ([D77](log.md#d77), [D78](log.md#d78)); usbipd-win ([D118](log.md#d118)); copying the YubiKeys'
  resident handles into a clone (usbip once, or Windows' `ssh-keygen -K`); thermos' LAN
  reservation; WSLg; signed release tags for `dram receive` to verify.

## As built

`modules/{cli,options,dev,gpu,laptop}.nix`, `modules/hosts/{cabin,thermos}-wsl.nix`,
`hosts/{cabin,thermos}-wsl/`; `packages/{base,metal}.txt`, `packages/wsl-skip.tsv`,
`packages/register.tsv` (wsl2-ssh-agent, diffutils); `install/lib/{detect,roles}.sh`,
`install/bootstrap.sh`; `system/{units,apply-hooks,files}.tsv`, `system/wsl-setup.sh`,
`system/wsl/`, `system/maintenance.sh`, `system/virt-setup.sh`; `dotfiles/.local/bin/dram`
(guard, `receive`, update, the doctor's wsl section, harvest); `bin/{check,push-host,release}.sh`;
`install/windows/wslconfig`, `install/windows/dram-windows/wsl.ps1`; `docs/platforms/wsl/README.md`. Tested
without a Windows PC: `nix flake check --all-systems --no-build`, the two clone homes built
(for aarch64-linux, natively: under the Mac's x86_64 emulation Nix's builder gets no pty),
`bin/check.sh` (§21 tried with bad edits), `system/wsl-setup.sh`,
`dram apply --dry-run`, `dram receive`, the guard and `install/bootstrap.sh --dry-run` in an
Arch container standing in for cabin-wsl, and `wsl.ps1` parsed by PowerShell 7.

## How it is checked

`bin/check.sh` §21 fails a `packages/wsl-skip.tsv` row without a reason or naming nothing declared, a clone whose plan holds a metal, hardware or `[dram]` name, and a clone with a session or hardware role.
`modules/options.nix` asserts the same shape at evaluation, and `dram doctor`'s "wsl" section checks a running clone.

## History

- 2026-10-12: proposed ([D77](log.md#d77), [D78](log.md#d78)) and built in the repo; tested without a Windows PC.
- 2026-10-12: cabin-wsl built on cabin-win and running; the clones take office and college ([D141](log.md#d141)). Acceptance pending.

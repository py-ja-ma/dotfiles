# 0009: A host is a hostname, its detected hardware and a list of roles

[Platforms › Arch Linux](../docs/platforms/arch/README.md) · accepted 2026-10-10 · amended 2026-10-12

A host file names the host and its roles, and the hardware is detected; the cost is a package list per role to keep honest, on every OS that takes the role.

## Context

The repo is shaped around two known machines: IPs and backup peers in
`modules/hosts/*.nix`, hardcoded addresses in `bin/` scripts, a cabin-only
builder.txt and `packages/host-cabin.txt`.
I want any PC (cabin, panasonic, a new recorder, future admin boxes) spun up from the same repo.
`decisions/0004` already reduced a host file to flags; this finishes the job.

## Decision

- **Host file:** `modules/hosts/<name>.nix` is `dram = { hostName; roles = [ … ]; }` plus
  the hardware flags `bootstrap` detected (`gpu`, `isLaptop`). It is written by the
  installer, not by hand. `address`, `backupPeer`, `backupPeerAddr` become optional and
  unused while backups are paused (`decisions/0014`).
- **Manifests:** one file per role under a new packages/roles directory; the CPU/GPU
  splits and `packages/laptop.txt` stay and are chosen by detection — laptop is
  hardware (`dram.isLaptop`), not a role. `packages/base.txt` is the implicit base role. The same role names drive the Home Manager
  modules (a module is imported only when its role is on).
- **Roles:**

| Role | Holds |
|---|---|
| base | always: core system, network, shell, maintenance |
| desktop | Hyprland + the Letterpress set, browser, mail, files |
| gaming | Steam, gamescope session, controllers, MangoHud, gamemode |
| emulation | the emulator set (`decisions/0016`), Steam ROM Manager |
| dump-kit | disc and BIOS dumping tools (redumper, ddrescue, chdman, maxcso) |
| re-lab | reverse engineering + hardware hacking |
| dev | VSCodium, toolchains, Podman |
| ml | uv-managed PyTorch, llama.cpp, Jupyter; CUDA opt-in |
| college | Computer Engineering tools (KiCad, Verilog toolchain, Octave, Typst…) |
| office | Taskwarrior, notes vault, hledger, LibreOffice, PDF tools |
| creator | OBS on the machine being recorded |
| recording | capture, OBS, Kdenlive on the recorder |
| sysadmin | the homelab CLI kit |
| telephony | the Yate lab and its firewall rules |
| builder | the `[dram]` build chroot (one host) |

- **Machines:** the first split (2026-10-10) gave each host exactly the packages it had before
  it: cabin = desktop gaming creator re-lab sysadmin dev office builder; panasonic =
  desktop gaming re-lab sysadmin dev office. The planned additions (cabin: emulation, ml,
  college; panasonic: dump-kit, college, telephony; recorder = desktop recording) went
  into the host files as those roles were filled.

## Consequences

- A new machine needs no repo edit before install: bootstrap asks hostname + roles and
  writes the host file, which `dram harvest` later commits.
- `bin/check.sh` checks that every role named by a host exists and every manifest line
  resolves (T1 test).
- builder.txt became `packages/roles/builder.txt`. `packages/host-cabin.txt` (grub,
  linux-lts + headers on 2026-10-10) stays as the per-host extras file;
  `install/lib/roles.sh` still reads any `host-<name>.txt`.
- Moving packages into roles changed panasonic's set slightly: diffoscope left it (a
  builder tool), and it gained linux-headers + dkms (now in base, so any DKMS module
  builds on any box) and MangoHud + the lib32 JACK shim (the gaming role it already had).

## Where a host runs

Besides its roles and detected hardware, a host has a **form**: `metal` (its own hardware,
the default) or `wsl` (Arch inside WSL 2 on a Windows PC, `decisions/0021-wsl-clone.md`). Like the hardware it is
detected (`detect_platform` in `install/lib/detect.sh`) and the host file must agree
(`form = "wsl";`, one line). `packages/base.txt` became the userland every host gets; the
kernel, firmware, boot, disk, power, Wi-Fi, disk-health, snapshot and firewall packages
moved to `packages/metal.txt`, which `install/lib/roles.sh` adds — with the cpu, gpu and
laptop lists — for metal hosts only; `packages/wsl-skip.tsv` names what a clone's roles
declare but it never installs. `system/*.tsv` match the pseudo-roles `metal` and `wsl`
beside `base` and the roles. Every metal host's package set is unchanged by the split.

## Roles beyond Arch

A Windows PC takes Arch's role names, with base implicit ([D52](log.md#d52)): a role there is winget IDs plus settings, in `packages/winget/<role>.txt` and `windows/roles/<role>.nix` ([0020](0020-windows-from-the-flake.md)).
The dual-boot and laptop settings are the host's shape, not a role.
The profiles I name (work, finance, coding, gaming, homelab) map to these roles ([D53](log.md#d53)).
A new role, chat, carries Mumble, IRC and TeamSpeak on every declarative build, the apps only ([D45](log.md#d45)): its Windows list exists, and the Arch list is still to come.
The WSL clones take the terminal half of office and college beside dev and sysadmin ([D141](log.md#d141)).

## How it is checked

`bin/check.sh` §11 fails a host file whose roles are not on one line or name a role without its `packages/roles/<role>.txt`, and one that misses `hostName`, `isLaptop` or `gpu`.
`bin/check.sh` §3 keeps the lists to one name per line with no duplicates, and §21 holds a clone's plan to no metal, hardware or `[dram]` name.

## History

- 2026-10-10: accepted and built: `install/lib/roles.sh`, the role lists, `dram.roles`; the flake evaluated for cabin, panasonic and a headless test host in a `nixos/nix` container.
- 2026-10-12: amended: the form `metal` or `wsl` ([0021](0021-wsl-clone.md)); Windows takes the same role names ([D52](log.md#d52), [D53](log.md#d53)); the chat role ([D45](log.md#d45)); the clones' office and college ([D141](log.md#d141)).

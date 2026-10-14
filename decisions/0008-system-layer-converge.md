# 0008: The system layer converges with dram apply

[Platforms › Arch Linux](../docs/platforms/arch/README.md) · accepted 2026-10-10

`dram apply` installs and enables what a host's roles declare and reports what nothing declares, pruning only on request; the cost is a converge step I maintain myself.

## Context

`decisions/0001` still holds: Nix on Arch cannot own the kernel, bootloader, ESP,
initramfs or pacman packages. Until 2026-10-10 that layer was manifests plus idempotent
scripts (`install/bootstrap.sh`, `system/*.sh` and an apply-packages script in `bin/`), which install what is
listed but never notice what is installed and not listed.
I want any PC to be fully declarative and SteamOS-like.
I compared a converge step of my own with decman, aconfmgr, metapac and pacdef, Ansible, and image-based Arch (mkosi with systemd-sysupdate, arkdep, frzr, SteamOS).

## Decision

Add `dram apply`: the role manifests (`decisions/0009`) are the declared set ([D9](log.md#d9), [D25](log.md#d25)).

- **Plan → apply.** `dram apply --dry-run` prints the plan; `dram apply` installs missing
  packages with `pacman -S --needed` (`[dram]` names included), writes the tracked
  `/etc` files from one table (source in the repo → target, mode, owner), enables and
  disables the declared units, and runs the per-role setup hooks that are idempotent.
- **Undeclared packages are reported, not removed.** `--prune` removes explicit packages
  no role declares, after a typed confirmation, never touching a protected list (base,
  kernel(s), bootloader, firmware, the running GPU driver).
- **Apply never upgrades.** Only `dram update` runs `-Syu`; apply refuses to run on a
  partially upgraded system.
- `dram doctor` gains a drift section (missing, undeclared, changed `/etc` files,
  unit state). The apply-packages script retires; `dram harvest` stays as the "record
  what is" half.

## Alternatives weighed

| Option | Why not |
|---|---|
| decman | closest in spirit (dry-run, prune) — but one maintainer, AUR-only, runs `-Syu` inside every apply and removes before it upgrades. I copy the algorithm, not the code |
| aconfmgr | no tagged releases, one maintainer, unnamed MIT-style license |
| metapac / pacdef | packages only, no dry-run; pacdef archived 2025 |
| Ansible (already in the kit) | `--check --diff` is good, but it cannot prune what is not declared |
| Image-based A/B (mkosi + systemd-sysupdate) | the only image route that fits signed UKIs, but it means owning an image build, an update server and signing; arkdep/frzr document no Secure Boot; SteamOS 3.8 needs an AMD GPU. Realistic as a 2027 spike on the recorder or a homelab box |

## Consequences

- "Declarative" on Arch now means: the repo states the system, `dram apply` converges
  to it, `dram doctor` shows drift, snapshots (`decisions/0011`) make each converge
  reversible. It is not an immutable root; the handbook says so plainly.
- Every package line must be a real package and every role it sits in must exist —
  `bin/check.sh` gains that lint, plus the compliance rule from `decisions/0013`.
- `system/maintenance.sh` becomes a consumer of the files/units table instead of
  carrying its own list.

## As built

- `dram apply [--dry-run] [--prune] [--yes] [--rollout]` in `dotfiles/.local/bin/dram`;
  `dram doctor` runs the same plan as its "declared state" section.
- **Who writes `/etc`:** the existing idempotent scripts keep writing their files
  (write-on-change with a `.bak`); `dram apply` runs them as **role hooks** from
  `system/apply-hooks.tsv`. Hooks that can cost remote access or a boot (`harden.sh`,
  `system-dram.sh`, `dram-builder-setup.sh`) are `ask` hooks and never run with `--yes`.
  `system/files.tsv` is the inventory of verbatim copies that doctor compares; templated
  files stay with their hooks. Moving `maintenance.sh` itself onto the table is left for
  later — it already converges, and rewriting it untested on a host is the larger risk.
- **Units:** `system/units.tsv` lists the system units each role needs enabled; apply
  enables the missing ones (timers with `--now`). Conditional units (iwd, docker) stay
  with their scripts.
- **Packages:** declared = base + hardware + roles (`install/lib/roles.sh`) + the builder
  role + the `[dram]` install set. Missing names come from `pacman -T` (provides count).
  The partial-upgrade guard compares the sync databases' mtime with the last "starting
  full system upgrade" in `/var/log/pacman.log`.
- **Prune** marks undeclared explicit packages `--asdeps` and removes the ones nothing
  needs (`pacman -Qqdt`), after the hostname is typed; the protected list covers base,
  kernels and headers, firmware and microcode, bootloaders, sbctl, mkinitcpio, systemd,
  sudo, pacman, glibc, mesa, the NVIDIA driver, dkms, nix, git and openssh.
- **Register:** a declared name with verdict `fail` stops the plan; `swap`/`pending` are
  listed, and stop it under `--rollout`.
- The apply-packages script was retired.

## How it is checked

`dram doctor`'s "declared state" section shows the drift between a host and its roles: missing and undeclared packages, changed `/etc` files, unit state.
`bin/check.sh` §3 keeps the package lists to one name per line with no duplicates, §11 fails a role without its list, and §15 fails a declared name without a register verdict.

## History

- 2026-10-10: accepted and built, with the refinements under "As built".
- 2026-10-12: the system tables learned the pseudo-roles `metal` and `wsl` for the WSL clones ([0021](0021-wsl-clone.md)).

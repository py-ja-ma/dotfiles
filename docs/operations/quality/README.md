# Quality

[Operations](../README.md) › Quality

What checks the repo before anything reaches a host.
`bin/check.sh` runs on the Mac, on each host through `dram check`, and in CI once the repo has a remote.
`bin/release.sh` cuts no release unless it passes.

| Branch | What it does | Code | Copy alone |
|---|---|---|---|
| Repo checks | 22 sections of invariants, without Nix, on the Mac's bash 3.2 or a host | `bin/check.sh` and its helpers | no: each section knows this repo's layout ([check.sh](check-sh.md)) |
| Tests | the tiers T0 to T4: static checks, real packages in a container, installs in a VM, a rollback drill, hardware smoke | `tests/` | the harness, in parts ([tests](../../../tests/README.md)) |
| The register checker | each installed name has a verdict against the FOSS, Origin and Community rules | `bin/check-register.py`, `bin/check-pkgnames.py` | yes, with a register of your own |
| The generators' checks | each generated file matches what its generator writes | `--check` modes, listed below | with each generator |
| CI | `nix flake check` and `bin/check.sh` on each push | `.github/workflows/check.yml` | yes, a GitHub Actions workflow |
| Lint and format | the statix lints, treefmt's formatters, the editor settings | `statix.toml`, `treefmt.toml`, `.editorconfig` | yes |

## How the branches fit

`dram check` runs `bin/check.sh`, then `nix flake check` where Nix is installed.
`bin/check.sh` runs the T0 tests itself, in sections 16 to 22, and the checkers and the generators' `--check` modes in their sections.
The T1 tests run in a throwaway amd64 Arch container, the T2 and T3 tests in QEMU on the Mac, and T4 on the machines ([tests](../../../tests/README.md)).
On the Mac, Nix runs in a throwaway `nixos/nix` container under Colima ([D26](../../../decisions/log.md#d26)), and `bin/render-windows.sh` starts it itself.

## The register checker

`bin/check-register.py` reads `packages/register.tsv`, the machine-readable half of [decision 0013](../../../decisions/0013-software-rules-and-waivers.md).
It collects the names this repo installs from the pacman lists, the `[dram]` install set, the Flatpak lists, the Nix user layer and the Windows lists.
It fails on a declared name without a row, an unknown verdict, a duplicate row, a waiver past its date, and a declared name whose verdict is `fail`.
Names still marked `swap` or `pending` warn, and fail with `--rollout`, which `CHECK_ROLLOUT=1` passes from `bin/check.sh`; set it before rebuilding a machine.
A Windows row whose note starts `= <name> (Arch)` must carry that Arch row's verdict and date.
The rules, the verdicts and the rulings themselves belong to [Software supply](../../security/software-supply/README.md).

`bin/check-pkgnames.py` checks that each name in the pacman lists resolves in core, extra, multilib or `[dram]`.
It downloads the sync databases from a mirror, so it runs only with `CHECK_PKGDB=1`.

## The generators' checks

| Generator | Writes | Checked by |
|---|---|---|
| `bin/gen-commands-doc.py` | `docs/commands.md` | `--check`, `bin/check.sh` §13 |
| `bin/gen-windows-look.py` | `install/windows/letterpress/` | `--check`, `bin/check.sh` §19 |
| `bin/render-windows.sh` | `windows/build/<host>/` | `--check` re-hashes the inputs, `bin/check.sh` §19; `nix flake check` compares the build with a fresh render |
| `bin/gen-gtk-css.py` and the other theme generators | each theme's adapter files | nothing yet: commit their output |
| `dotfiles/.local/bin/keybind-cheatsheet.sh --markdown` | `docs/design/shell-and-bars/keybinds.md` | nothing yet |

To change a generated file, edit its source, run the generator, and commit both in one commit.

## CI

`.github/workflows/check.yml` runs the same two gates as a host: `nix flake check --all-systems --no-build` and `bin/check.sh`.
Its actions are pinned to a commit, and shfmt is a pinned binary checked by sha256.
A weekly run catches drift in the inputs.

## Operating it

Before a release: `bash bin/check.sh` on the Mac, which `bin/release.sh` runs again.
On a host: `dram check`.
The tests' commands and run times are in [tests/README.md](../../../tests/README.md).

## Status

As of 2026-10-13:

- The repo has no remote, so CI has never run.
- `bin/check.sh` §6 checks backticked paths in `docs/*.md` and a few named pages; pages under `docs/<directorate>/` and links are not checked yet.
- The theme generators and `docs/design/shell-and-bars/keybinds.md` have no `--check`.

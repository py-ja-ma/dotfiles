# Pins

[Security](../README.md) › [Software supply](README.md) › Pins

Every download this repo makes by itself is pinned: by a sha256, a commit, a signing key's fingerprint, or a version that a check holds it to.
A pin turns an upstream change into a diff in a commit I read, instead of a silent drift.
It does not review what it pins ([Integrity](integrity.md#limits)).

| | |
|---|---|
| Code | the files in the table below |
| Runs on | the Mac, where the pins are bumped and checked; the hosts verify them at install and apply |
| Needs | nothing beyond the tools each row names |
| Decided in | [0005](../../../decisions/0005-own-package-repo.md) for `[dram]` and [0010](../../../decisions/0010-install-path.md) for the ISO |

## What is pinned

| Pin | Pins | Checked by | Bumped by |
|---|---|---|---|
| `install/iso.pin` | the Arch ISO by sha256, and the release key's fingerprint for its signature | `install/get-iso.sh`, which refuses either mismatch | a new version and sha256 from the mirror, then `get-iso.sh` |
| `install/nix-install.sha256` | the Nix installer script, a versioned URL and its sha256 | `install/bootstrap.sh` before it runs the script | by hand |
| `install/mirrorlist` | the Arch mirrors a new host starts with | nothing: a fixed list, since archlinux.org's mirror status is unreachable from the home LAN | reflector refreshes it on the host when it can |
| `flake.lock` | nixpkgs, Home Manager, sops-nix and git-hooks, each by revision and hash | Nix itself; `bin/check.sh` §8 warns when it is older than 60 days | `dram update --full`; `.github/workflows/update-lock.yml` weekly, once the repo has a remote |
| `pkgs/<name>/PKGBUILD` and `PIN` | each vendored recipe's sources by tag or commit, with `sha256sums` and `validpgpkeys`; `PIN` says how to re-pin | `dram pkgs check` (`bin/check.sh` §12) | `dram pkgs update <name>`, which shows the diff |
| `pkgs/dram.asc` | the `[dram]` signing key, `044DFA31C5CD72299A1460B56EF00BFB391BD348` | `system/pacman-dram-repo.sh` refuses a key with another fingerprint | a new key only by decision, as at the reinstalls of 2026-10-11 |
| `install/windows/fonts.pin` and `fonts.lock` | the house fonts on Windows, each download by sha256 and each font file it yields | `install/windows/apply-windows.sh` refuses a mismatch; the render lists every file | a new URL and sha256, then `bin/render-windows.sh --lock` |
| `install/windows/cursors.pin` | GNOME's Adwaita pointer for Windows, by sha256 | as fonts.pin | as fonts.pin |
| the Script units' downloads | LibreHardwareMonitor 0.9.6's library and obs-backgroundremoval 1.4.1 on Windows, by SHA-256 | the unit refuses a mismatch | the unit's file and a re-render |
| `packages/uv/re-lab.txt` | the re-lab role's uv tools, `name==version` | `re-lab-tools` installs exactly that version | by hand |
| `packages/ghidra-extensions.tsv` | Ghidra extensions by URL and sha256 | `re-lab-tools` refuses a mismatch | by hand, with the digest GitHub publishes |
| `.github/workflows/*.yml` | every action by commit SHA, the tag in a comment; `shfmt` by its release checksums | GitHub, when a remote exists | by hand |
| `dotfiles/.local/bin/codium-themes-install` | marketplace extensions as `id@version`, kept for comparison: the editor's theme is generated in the repo | `dram doctor --supply` | by hand |

Two channels need no pin of mine: Arch's repos and Flathub sign their packages, and pacman and Flatpak check the signatures.

## Bump one

Change the pin and whatever it pins in one commit, then run `bash bin/check.sh` on the Mac.
For a render input (the Windows pins), run `bin/render-windows.sh` and commit `windows/build/` with it, or §19 fails.
A release takes the change to the hosts.

## Limits

A pin proves that the bytes did not change since I pinned them, not that they were good then.
`install/mirrorlist` pins addresses, not content: pacman's signature check carries the trust there.

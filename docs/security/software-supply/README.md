# Software supply

[Security](../README.md) › Software supply

What gets onto a host, and through which channel: Arch's signed repos, my own signed `[dram]` repo for everything that came from the AUR, verified Flatpaks from Flathub, Nix packages pinned by `flake.lock`, and on Windows winget and the Store.
Every installed name has a verdict against three rules, and every download the repo makes itself is pinned by a hash, a commit or a key.
The Arch hosts and the Windows PCs carry all of it; a WSL clone takes the Arch half without `[dram]`.

| Branch | What it does | Code | Copy alone |
|---|---|---|---|
| [Register](register.md) | one verdict per installed name against FOSS, Origin and Community, and the waivers | `packages/register.tsv`, `bin/check-register.py` | yes: the checker, with your own rows |
| [Integrity](integrity.md) | asks whether what is on disk is what the packages shipped, and whether a binary could have come from its source | `dram doctor --supply`, `bin/repro.sh` | `bin/repro.sh` yes, on Arch |
| [Pins](pins.md) | lists every download the repo makes and what pins it | `flake.lock`, `install/iso.pin`, `install/nix-install.sha256`, `pkgs/*/PIN`, `install/windows/*.pin`, `.github/workflows/` | the pattern, not the pins |

The `[dram]` repo itself (the vendored recipes, the build chroot, the signing key) is a Toolchain page: [packaging](../../toolchain/packaging/README.md) and `pkgs/README.md`.

## The channels

| Channel | What guards it | Left open |
|---|---|---|
| Arch's core, extra, multilib | pacman checks every package and database signature against Arch's keyring; mirrors from a shipped list (`install/mirrorlist`) | a signature proves who signed, not what is inside ([Integrity](integrity.md#limits)) |
| `[dram]`, my own repo | every AUR recipe vendored into `pkgs/`, its diff read on every bump; built in a clean chroot on cabin; signed; `SigLevel = Required DatabaseRequired`; listed above `[core]`, and `dram pkgs check` refuses a name that shadows an official package | the trust is in the git history of `pkgs/` and the chroot build, not in the key |
| the AUR | never built on a host: `packages/aur.txt` stays empty and no AUR helper is installed ([decision 0005](../../../decisions/0005-own-package-repo.md)) | |
| Flathub | verified apps only, least-privilege overrides, no other remote; `dram doctor --supply` checks the remotes | Flatpak is a sandbox, not provenance |
| Nix | `flake.lock` pins every input by revision and hash; binaries come from `cache.nixos.org` under its signing key | |
| vendor self-updaters: Steam, the Jagex Launcher, Spotify | waived ([Register](register.md#waivers)) | their binaries are trusted at launch, not at install |
| update plumbing: `checkupdates`, reflector, arch-audit, the keyring sync | read-only; pacman still checks every signature | |
| Windows: winget, the Store, Script units | each name has a register row; a Script unit's download is pinned by SHA-256; the build is rendered from the repo | a winget manifest is the publisher's word |
| CI (`.github/workflows/`) | every action pinned to a commit, `shfmt` checked against its release checksums before it runs | it runs only once the repo has a remote |

A recipe update shows its diff in `dram pkgs update`, and that diff gets read.
What would have caught every AUR incident of 2025 and 2026: an unexplained extra file in `source=`, any change to an `.install` file, `sudo`, `/tmp`, `npm install` or `curl` in a build or install step, and a maintainer change on a package you did not expect to change.

## How the branches fit

The register decides what may be installed.
The pins fix which bytes arrive.
Integrity checks what landed.
`bin/check.sh` runs the register's check (§15) and the `[dram]` manifest and pins (§12, `dram pkgs check`) on every run, on the Mac too.
`dram update` ends with `dram doctor --brief`, which runs the supply checks on the host.
The rules: [decision 0013](../../../decisions/0013-software-rules-and-waivers.md); the own repo: [decision 0005](../../../decisions/0005-own-package-repo.md).

## Operating it

Adding or removing a package, and its register row: [handbook chapter 7](../../records/handbook/07-packages.md).
Monthly: `bin/repro.sh` on a host, and the register's `pass-flag` rows and waivers that come due ([handbook chapter 3](../../records/handbook/03-cadence.md)).

## Status

Reviewed on 2026-10-06: nothing installed was malicious.
Every cached AUR recipe equaled its upstream, `pacman -Qkk` showed no altered file, no build ran `curl | sh`, `eval`, base64 or `sudo`, and no name matched the incident patterns of 2025 and 2026.
What changed since then, by date:

| Date | Change |
|---|---|
| 2026-10-06 | the AUR helper's `SudoLoop` removed; Hyprland plugins became `[dram]` packages and hyprpm left; `[dram]` live on both hosts; Spotify through `spotify-launcher`; Vesktop and LocalSend from Flathub; sshd keys-only and the firewall on; `dram doctor --supply` and `bin/repro.sh` built |
| 2026-10-07 | the CI actions pinned by commit, `shfmt` checked by checksum |
| 2026-10-10 | the register and its check; paru off the hosts and out of `pkgs/`; the Origin and Community failures swapped out ([D7](../../../decisions/log.md#d7), [D30](../../../decisions/log.md#d30)) |
| 2026-10-11 | the reinstalls: a new `[dram]` signing key, `044DFA31C5CD72299A1460B56EF00BFB391BD348`; the 12 lib32 Wine libraries left `[dram]` ([D31](../../../decisions/log.md#d31)) |
| 2026-10-12 | the Windows catalogue scored, its swaps and never-add rows in the register ([D61](../../../decisions/log.md#d61)) |

Open since 2026-10-06: `proton-pass-bin` is pinned at 1.41.1 while Proton rolls it out in stages; bump it when 1.41 reaches every user.

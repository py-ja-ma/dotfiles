# 0013: Every package passes three rules or carries a waiver

[Security › Software supply](../docs/security/software-supply/README.md) · accepted 2026-10-10

Every installed name passes the FOSS, Origin and Community rules or has a dated waiver; the cost is a review each month and a few tools swapped out.

## Context

Every machine built from this repo runs software that is free and open source, is not controlled from Russia or China, and has an active community.
When something fails a rule and I still need it, it gets a written waiver with a re-check date, so no rule bends without a record.
In 2026-10 I scored every installed package, and every project the new roles would add, against the three rules.

## Decision

| Rule | Passes when |
|---|---|
| FOSS | the shipped artifact has an OSI-approved license or one the FSF lists as free (ly's WTFPL, the Vim license) |
| Origin | no controlling company, foundation or funder is headquartered in Russia or China, and the people leading the last 12 months of commits are not documented as based there |
| Community | two of: in Arch's core or extra, or verified on Flathub; two or more active maintainers, or a steward organization; a release in the last 12 months; a public tracker that answers |

Evidence is documented facts only: profile location fields, project sites, registries, the news, and never a guess from a name.
When nobody leading a project has published a location, its Origin is unclear, and I rule each such project myself ([D13](log.md#d13)).
A ruled project is `pass-flag`, and the monthly review checks it again.
A failing project is swapped for a compliant one where one exists; a waiver is for a real loss of capability, with its reason, scope and re-check date in the register.
`packages/register.tsv` holds one verdict per installed name: the pacman lists, the `[dram]` install set, Flatpak app IDs, Nix `home.packages` and `programs.*`, and the Windows lists, plus `fail` rows that forbid known-bad packages.

Waived on 2026-10-10 until 2027-10-10 ([D6](log.md#d6)):

| Waived | Scope |
|---|---|
| Steam, NVIDIA's driver userspace, firmware and microcode | the hosts that need them |
| Spotify through spotify-launcher, the Jagex Launcher, the Discord service behind Vesktop | desktop and gaming |
| nmap | sysadmin and re-lab |
| CUDA, cuDNN and PyPI's NVIDIA wheels | the opt-in `ml-cuda` role |
| tools a course requires | per tool and time-boxed, preferably on Windows |

Swapped out: fastfetch, Papirus and papirus-folders, 7-Zip, unrar, unzip, qt6ct, ipmitool, Rizin and Cutter (for radare2 and Ghidra), Microsoft's VS Code (for VSCodium), Obsidian (for a git vault and Zettlr), Docker Desktop on the Mac (for Colima), and the Community failures wlogout, iwgtk, paru on the hosts, Bibata, ble.sh, picocom and wireless_tools ([D7](log.md#d7), [D30](log.md#d30)).
Never added: Audacity, OnlyOffice, WPS Office, Logseq, AFFiNE, showmethekey, DuckStation, BigPEmu, the Model 2 emulator, the non-commercial libretro cores, and model weights from Chinese labs.

## Alternatives

| Option | Why not |
|---|---|
| an unclear Origin passes by itself | I rule each one myself, so a gap in the evidence never passes unseen |
| the OSI list alone | it would force a new display manager (ly) and editor (vim) for license technicalities ([D14](log.md#d14)) |
| Origin applied to every contributor | nearly every large project has a contributor somewhere; the rule targets control and leadership |

## Consequences

- Adding a package is a two-part change in one commit: the manifest line and its register row.
- The register is reviewed every month, and whenever a waiver's date comes.
- Games on cabin-win whose publisher fails Origin stay only under a waiver for cabin-win alone ([D92](log.md#d92), [D138](log.md#d138)).
- Whether the waiver for Windows 11 covers the FOSS side of closed Windows apps ([D121](log.md#d121)), and a waiver class for tools a job mandates ([D128](log.md#d128)), are open.

## How it is checked

`bin/check.sh` §15 runs `bin/check-register.py`.
It fails on an installed name without a row, an expired waiver and a forbidden name, and warns on `swap` and `pending` names.
`CHECK_ROLLOUT=1`, set before a machine is rebuilt, turns those warnings into failures.
How to read and add a row, the waivers and the Origin rulings: [the register page](../docs/security/software-supply/register.md).

## History

- 2026-10-10: accepted; the register, its check and `bin/check.sh` §15 built, and the swaps made.
- 2026-10-11: the open Origin cases ruled; Obsidian swapped for a git vault and Zettlr after a trial ([D5](log.md#d5)).
- 2026-10-12: the Windows catalogue scored, with its swaps and never-add list as `fail` rows ([D61](log.md#d61)).

# The software register

[Security](../README.md) › [Software supply](README.md) › Register

`packages/register.tsv` holds one verdict per name this repo installs, against three rules: free software, no control from Russia or China, and a living community.
`bin/check-register.py` fails the repo when an installed name has no verdict, when a waiver is past its date, or when a forbidden name is declared.
The rules and why they exist: [decision 0013](../../../decisions/0013-software-rules-and-waivers.md).

| | |
|---|---|
| Code | `packages/register.tsv`, `bin/check-register.py`; `bin/check.sh` §15 runs the checker |
| Runs on | the Mac and any host, at every `bin/check.sh`; `dram apply --dry-run` shows the verdicts of what it would install |
| Needs | Python 3 alone (standard library) |
| Decided in | [0013](../../../decisions/0013-software-rules-and-waivers.md), [D1](../../../decisions/log.md#d1), [D13](../../../decisions/log.md#d13), [D14](../../../decisions/log.md#d14) |

## The rules

| Rule | Passes when |
|---|---|
| FOSS | the shipped artifact has an OSI-approved license or one the FSF lists as free (ly's WTFPL, the Vim license). A `-bin` repack of free source passes; a proprietary binary does not |
| Origin | no controlling company, foundation or funder is headquartered in Russia or China, and the people who led the last 12 months of commits are not documented as based there. Hardware is out of scope unless its required software fails the rule |
| Community | two of four: in Arch's core or extra, or verified on Flathub; two or more active maintainers, or a steward organization; a release in the last 12 months; a public tracker that answers |

Evidence is documented facts only: profile location fields, project sites, registries, the news.
A name is never evidence of where a person lives.
Origin judges the people and the entity who lead a project, so one contributor in Russia or China inside a large project is noted and does not fail it.
A project whose leaders publish no location is "Origin unclear": I rule each one myself, case by case ([D13](../../../decisions/log.md#d13)).

## Reading a row

Four TAB-separated columns: the name, the verdict, the re-check date of a waiver (else `-`), and a note with the evidence.

| Verdict | Means | `bin/check.sh` |
|---|---|---|
| `pass` | passes all three rules | quiet |
| `pass-flag` | Origin unclear, accepted by a ruling | quiet; re-checked at the monthly review |
| `waiver` | fails a rule and stays, signed, with a re-check date | fails once the date has passed |
| `swap` | decided to go; the note says what replaces it | warns; fails under `CHECK_ROLLOUT=1` |
| `pending` | waits for a ruling | warns; fails under `CHECK_ROLLOUT=1` for an Arch name |
| `fail` | forbidden: listed to block it | fails when anything declares it |

A note gives the license, who leads the project and where (as published), how many of the four Community criteria it meets, and any ruling with its date and decision ID.
Windows names carry a prefix: `winget:<id>`, `msstore:<id>`, or `manual:<name>` for what a Script unit installs or is installed by hand.
A Windows row whose note starts `= <name> (Arch)` is that Arch row's twin, and the checker holds it to the same verdict and date.

## Add a package

1. Score it against the three rules with documented facts; the note says what you found.
2. Add the manifest line and the register row in the same commit: `packages/<list>.txt`, `packages/roles/<role>.txt`, `packages/flatpak/<role>.txt`, `packages/winget/<role>.txt`, or a `home.packages` line in `modules/`.
3. An unclear Origin goes in as `pending` until I rule it.
4. Run `bash bin/check.sh`; §15 must say every declared name has a verdict.

A name the register lists that nothing declares is a warning: drop the row, or mark it `fail` to forbid it.

## Waivers

The register is the waiver register: each waived name has a row with its re-check date, and the checker fails an expired one.
On 2026-10-19 the Arch side carries 13 waivers and the Windows side 9.

| Waived | Rule failed | Scope | Signed | Re-check |
|---|---|---|---|---|
| Steam; NVIDIA's driver userspace; firmware and CPU microcode; Spotify; the Jagex Launcher; nmap; CUDA and cuDNN | FOSS | as each row says; CUDA only in the opt-in `ml-cuda` role | 2026-10-10 ([D6](../../../decisions/log.md#d6)) | 2027-10-10 |
| playerctl | Community: no release since 2021 | desktop | 2026-10-11 | 2027-04-11 |
| unzip, only as winetricks' dependency | Community and license | the Wine role | 2026-10-12 | 2027-10-12 |
| Steam, the Jagex Launcher, Spotify and the NVIDIA App on Windows | FOSS | cabin-win | 2026-10-12 ([D102](../../../decisions/log.md#d102)) | 2027-10-10 |
| Marvel Rivals | Origin and FOSS | cabin-win only, through Steam | 2026-10-12 ([D138](../../../decisions/log.md#d138)) | 2027-10-12 |
| the EA app, Battle.net, Hytale's launcher | FOSS | cabin-win | 2026-10-12 ([D97](../../../decisions/log.md#d97) to [D99](../../../decisions/log.md#d99)) | 2027-10-12 |
| TeamSpeak | FOSS | the chat role, every build | 2026-10-12 ([D46](../../../decisions/log.md#d46)) | 2027-10-12 |

Three waivers have no row, because no list installs them as a package:

| Waived | Rule failed | Scope | Signed | Re-check |
|---|---|---|---|---|
| the Discord service behind Vesktop (the client itself passes) | FOSS | desktop | 2026-10-10 ([D6](../../../decisions/log.md#d6)) | 2027-10-10 |
| tools a course requires (MATLAB, Quartus, Vivado and the like) | FOSS | per tool and per term, on Windows by preference | 2026-10-10 ([D6](../../../decisions/log.md#d6)) | the end of each term |
| Windows 11 and the closed software tested inside it | FOSS | cabin's Windows disk, thermos | 2026-10-11 | 2027-10-11 |

Whether the Windows 11 waiver covers the FOSS side of closed Windows apps, such as the Epic and Ubisoft launchers, is open ([D121](../../../decisions/log.md#d121)).
So is a waiver class for tools a job mandates ([D128](../../../decisions/log.md#d128)).

## Origin rulings

Each project whose leaders publish no location gets a ruling: accept (its row becomes `pass-flag`) or swap.
The evidence for each installed one is in its register row; a ruled project that nothing installed on 2026-10-13, such as SageMath, or FFmpeg as a dependency, has none.

| Ruled | Accepted |
|---|---|
| 2026-10-10 | yazi; strace (the maintainer's older profile named a Moscow employer, his 2026 profile does not); SageMath (one of several leaders lists Beijing, no steward in China); Logisim-evolution (Swiss leaders); the emulator group: Dolphin, PCSX2, xemu, RetroArch, RPCS3, shadPS4, Cemu, melonDS, mGBA, Flycast, MAME, ares, Supermodel, Xenia Canary, PrimeHack ([decision 0016](../../../decisions/0016-emulation-set-and-flatpak.md)) |
| 2026-10-11, base and desktop | FFmpeg, wireguard-tools, LibreWolf, socat, wl-clipboard, fzf, zoxide, git-delta, direnv, udiskie, gsimplecal, mission-center, thunar-archive-plugin, EB Garamond, Vesktop, libva-nvidia-driver, blueman, man-pages, diffoscope |
| 2026-10-11, gaming and dumping | MangoHud, game-devices-udev, redumper, xdvdfs, v4l2loopback-dkms |
| 2026-10-11, re-lab | pwndbg, pwntools, unicorn, capstone, jadx, OpenOCD, minicom, the PS2 and PSP Ghidra loaders, UEFITool |
| 2026-10-11, creator, dev, college, office | gpu-screen-recorder, MediaInfo, v4l-utils, VSCodium, Open Remote - SSH, Neovim, ngspice, Verilator, GTKWave, Xournal++, Anki, PDF Arranger, OCRmyPDF, Yate, just, ShellCheck, pre-commit, nvtop, avrdude, gnuplot |
| 2026-10-11, the YubiKeys | age-plugin-yubikey ([D38](../../../decisions/log.md#d38)) |
| 2026-10-12 | RuneLite, VLC (the SageMath precedent), Transmission; the Epic and Ubisoft launchers with a flag; PawnIO ([D124](../../../decisions/log.md#d124)); KiCad and LibreOffice with a flag, each with one documented core contributor in Moscow ([D139](../../../decisions/log.md#d139)) |

Swapped or skipped instead of accepted: duf (Community: no commits in a year) on 2026-10-11; flashprog (flashrom passes), Tenacity (Ardour and Kdenlive cover it) and the Switch Ghidra loader (no Switch work), skipped on 2026-10-11; qBittorrent (a lead with no location and a yandex.ru address), swapped for Transmission on 2026-10-12.
The lib32 Wine libraries left `[dram]` instead of being ruled ([D31](../../../decisions/log.md#d31)).

Settled without a ruling, because nothing installs them: Rizin, Cutter, Logseq, OnlyOffice, Decky Loader, vkBasalt, the ChimeraOS session originals, Eden, Ryubing, Citron NEO, EmuDeck itself, GEF, Fava, Paperless-ngx, DocuSeal, OpenSign, aichat, mono, uwsm, wlogout, paru, Bibata, picocom, and the console-side homebrew tools.

Never ruled: sane-airscan and unpaper for the office role; their lines stay commented out in `packages/roles/office.txt` until they are.

Noted and not ruled: libfido2 and pam-u2f pass, although their second maintainer publishes no location.
He commits from a Yubico address, and Yubico AB is Swedish with no staff reported in China or Russia.
Transitive dependencies with no published location (python-pskc through ykman, libcbor through libfido2) are not scored.

## Never added

Known failures for the planned roles, each forbidden by a `fail` row where it has a package name: Audacity (a Russian-founded owner), OnlyOffice, WPS Office, Logseq, AFFiNE, showmethekey, DuckStation, BigPEmu, the Model 2 emulator, the libretro cores with non-commercial licenses, and model weights from Chinese labs.
The Windows never-add list is the `fail` rows of the Windows section ([D61](../../../decisions/log.md#d61)).

## Copy it alone

1. Copy `bin/check-register.py` and start `packages/register.tsv` empty: the rows are my verdicts, not yours.
2. Point `declared()` at your own package lists. It reads `packages/*.txt`, `packages/roles/*.txt`, `pkgs/manifest.txt` minus `pkgs/BUILD-ONLY`, `packages/flatpak/*.txt`, `packages/uv/*.txt`, `packages/ghidra-extensions.tsv` and the `home.packages`, `programs.*` and `${pkgs.<name>}` references in `modules/*.nix`.
3. Run `python3 bin/check-register.py --list`: every declared name with its source and verdict, `-` where a row is missing.
4. Add a row per name until `python3 bin/check-register.py` exits 0.

The Windows half reads `packages/winget/*.txt` and the WinGetPackage units of `windows/build/*/*.winget`; without them it reports zero Windows names and passes.

## How it is checked

`bin/check.sh` §15 runs `bin/check-register.py` and fails on a declared name without a row, an unknown verdict, a duplicate row, a waiver without a date or past it, a declared name marked `fail`, a Windows twin that disagrees with its Arch row, and a WinGetPackage unit of a rendered Windows build whose package no list names.
`CHECK_ROLLOUT=1 bash bin/check.sh`, run before a machine is rebuilt, turns the `swap` and `pending` warnings into failures.
The monthly review re-checks every `pass-flag` row and every waiver whose date comes due.

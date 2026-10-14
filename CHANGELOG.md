# Changelog

Release notes, newest first: one section per release tag, written by `bin/release.sh`
from the commits since the previous tag. On a host `dram changelog` prints the latest
section, `dram changelog vX` one release, `dram changelog --since vX` everything newer.
How a section is written: `docs/records/changelog.md`.

## v2026.10.29 (2026-10-13)

The first public release: the configuration of my Arch Linux hosts, my Windows PCs and their WSL clones, under the MIT license, with its pages arranged by an org chart.

### Added
- install: Arch hosts from a pinned ISO, a repo-driven disk installer and per-role package lists.
- dram: one command updates, applies, themes, checks and rolls back a host; `dram apply` converges the system layer.
- windows: Windows PCs rendered from the same Nix flake and applied by `dram.ps1`.
- wsl: Arch in WSL 2 as a clone of the user layer and the terminal roles.
- themes: Letterpress, 17 themes across Hyprland, Waybar, rofi, kitty, the boot menu and Windows.
- packaging: the `[dram]` pacman repo of reviewed, pinned recipes, built and signed on cabin.
- profiles: office, college, re-lab, creator, gaming with a SteamOS-style Gaming Mode, emulation, chat.
- identity: two YubiKeys for SSH, sudo and lantern's disk; secrets in sops with age.
- boot-trust: Secure Boot with my own keys and signed UKIs; lantern unlocks its disk with TPM2 and a PIN.
- network: a default-deny firewall; sshd takes keys only, and only from the LAN.
- software-supply: every installed name has a FOSS, Origin and Community verdict or a dated waiver.
- releases: releases cut on the Mac and pushed to each host, on the main or the stable channel.
- records: 27 decision records and a log of 148 numbered decisions, the handbook and a style guide.
- records: `docs/map.tsv` places each file in the org chart; `docs/catalogue.md` lists what can be copied alone.
- license: MIT for my own work; `REUSE.toml` names each third-party file with its holder and license.

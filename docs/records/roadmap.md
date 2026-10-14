# Roadmap

[Office of Records](README.md) › Roadmap

Ideas from about 30 public Home Manager and Hyprland setups that I compared with this repo on 2026-10-05: what I adopted, what is queued and what I rejected, each with the repo it came from.
The page was last brought up to date on 2026-10-07; struck items live under "Closed" at the end with the date they closed.
Decisions taken since then are in [the decision log](../../decisions/log.md).

## Adopted
- **`checks` in `flake.nix`** so `nix flake check` instantiates both hosts.
  Source pattern: portothree/dotfiles.
- **PCI vendor-ID GPU detection** (`[10de:` `[1002:` `[8086:` on class-03 devices)
  in `install/lib/detect.sh`, replacing name matching.
  Source pattern: suraj-lab/arch_hyprland_dots.
- **ADR 0003** making the GUI-from-pacman rule explicit.
- **`bin/push-host.sh`** — git-bundle sync that leaves runtime state alone.
- **Third-machine installer path** — `[multilib]` enabled automatically, and
  `system/plymouth-setup.sh` parametrised by vendor (`KMS_MODULES` /
  `KMS_CMDLINE` / `DROP_KMS_HOOK`) so `bootstrap.sh` phase 5 runs for every
  GPU instead of refusing non-Intel. First Home Manager switch uses the
  home-manager pinned in `flake.lock`.
- **Battery-based laptop detection** in `hyprland.lua` (`/sys/class/power_supply/
  BAT*/present`, `DRAM_LAPTOP=0/1` override) instead of a hostname compare.
- **waybar `config.jsonc` default** via `lib.mkDefault` in `desktop.nix`, so a
  host module can be `{ ... }: { }`; a desktop overrides it in `laptop.nix`.
- **`dram update --check`** (was `sysupdate --check`) — read-only preview that also builds the dram.
- **Standard app set** (`docs/toolchain/README.md`, 2026-10-05) — one app per job on both
  hosts: LibreWolf, Proton Pass, Thunderbird + Proton Mail, Thunar, VS Code, the
  RE kit, a nixpkgs homelab CLI kit, gnome-keyring, hyprpolkitagent, fontconfig
  defaults. `nwg-look`, `nwg-displays`, `polkit-kde-agent`, `vscodium-bin` out.
- **Proton Mail Bridge** (plan is paid, 2026-10-05) — `protonmail-bridge` from extra,
  run as the HM user service `protonmail-bridge`; all mail in Thunderbird.
- **WireGuard to the UniFi gateway** (`docs/security/network/vpn.md`) — `wireguard-tools` + a per-host
  `/etc/wireguard/home.conf` exported from UniFi; `wg-quick@home`. Tailscale was removed
  2026-10-05: I want nothing that needs an account.
- **`dram` CLI** (`docs/operations/dram/README.md`, 2026-10-05) — `switch/update/theme/check/doctor/
  pacnew/rollback/backup/harvest/pkgs`; `sysupdate`/`dram-switch` are shims. `dram update`
  does keyring → `paccache` → `paru -Syu` → flatpak → pacnew/orphans/reboot →
  switch → `doctor --brief` (+ `--supply`).
- **Pacman upkeep declared** (`system/maintenance.sh`, `docs/platforms/arch/hooks.md`) —
  pkglist hook, rebuild-detector, paccache/reflector/arch-audit timers, `paru.conf`
  without `SkipReview`, `pacman.conf` options. Waybar `custom/updates` badge.
- **`bin/check.sh`** — nix-free invariant checker (link targets, host wiring, package
  lists, shellcheck/shfmt, docs paths, secrets, `/usr/bin` refs, waybar JSON); `dram check`.
- **`dram harvest`** — local refresh of `hosts/<h>/` (the old `sysupdate --harvest` item).
- **Module split + host flags** (2026-10-06, `decisions/0004-module-split.md`) —
  the old `common.nix` became `modules/default.nix` importing `options / core / shell / dev /
  desktop / theme / laptop / gpu / backup / secrets`; every `dram.*` option lives in
  `modules/options.nix`; `link` is defined once (`_module.args.dram`); a host file is
  `dram = { hostName; backupPeer; backupPeerAddr; isLaptop; gpu; }` and nothing else.
  Closes queued items 3 (feature flags) and most of 2 (host facts in one place — the
  `bootstrap.sh`-readable half is still open, see below).
- **CI** (`.github/workflows/check.yml`, `update-lock.yml`) — `nix flake check
  --all-systems --no-build -L` (every host + the lint hooks, since 2026-10-06),
  `bin/check.sh` with shellcheck + shfmt, `flake-checker-action`, weekly cron; a weekly
  `flake.lock` PR via `update-flake-lock`; actions pinned to commits. Closes queued
  items 1 and 9. Activates when the repo gets a GitHub remote.
- **Format config** (`treefmt.toml`, `.editorconfig`, `formatter` in `flake.nix` =
  `nixfmt-tree`) — nixfmt / `shfmt -i 2 -ci -bn` / stylua. The tree was **not**
  reformatted when this landed; the shell scripts were shfmt-formatted on
  2026-10-07 (`bin/check.sh` §4 now fails on drift), nixfmt/stylua still pending.
- **sops-nix, on for both hosts** (`modules/secrets.nix`, `.sops.yaml`,
  `secrets/README.md`, `docs/security/identity/secrets.md`) — `dram.secrets.enable = true` in both host
  files since 2026-10-06; `secrets/pj.yaml` holds `borg_passphrase` and
  `modules/backup.nix` reads it through the sops path. Closes queued item 7.
- **Python scripts renamed `.sh` → `.py`** (`brightness-slider`, `waybar-window`,
  `waybar-workspace`) with every caller updated; `bin/check.sh` §5 is clean.
  (The two waybar scripts were deleted again on 2026-10-06 by the Letterpress
  masthead — `hyprland/window` and `hyprland/workspaces` replaced them;
  `brightness-slider.py` remains.)
- **Own signed package repo `[dram]`** (2026-10-06, `decisions/0005-own-package-repo.md`,
  `docs/toolchain/packaging/README.md`, `docs/security/software-supply/README.md`) — 25 vendored PKGBUILDs in `pkgs/` (13
  AUR-origin + the 12 ex-official lib32 names, one of them a split), built in a clean
  chroot on cabin, `dram pkgs`, `[dram]` above `[core]` on both hosts; `packages/aur.txt`
  lists nothing (empty today). Hyprland plugins are packages loaded by
  `hl.plugin.load`; hyprpm retired.
- **Flatpak for two vendor binaries** (Vesktop, LocalSend + Flatseal; `docs/toolchain/packaging/flatpak.md`,
  `system/flatpak-setup.sh`), least-privilege overrides tracked in `dotfiles/`.
- **One GTK theme** — adw-gtk3 + a generated `gtk.css`/`gtk3.css` per dram theme
  (`bin/gen-gtk-css.py`); the seven AUR GTK theme packages are gone (`docs/design/README.md`).
- **"Letterpress" design system** (`docs/design/README.md`, `docs/design/themes/wallpaper.md`) — Fraunces/EB
  Garamond/Monaspace, one accent ink per theme, generated rofi/GTK, day/night themes.
- **Backups wired** — borgmatic host-to-host + nightly Mac pull (`docs/operations/backups/README.md`,
  `modules/backup.nix`, `dram backup`).
- **Hardening applied on both hosts** (2026-10-06, `system/harden.sh`, `docs/security/network/hardening.md`):
  sshd keys-only, nftables LAN-only, sysctl, DoT, faillock. Orphan pass on cabin done.
- **`dram doctor --supply` + `bin/repro.sh`** (`docs/security/software-supply/integrity.md`).
- **`xdg.mimeApps`** declared in `modules/desktop.nix` (2026-10-06): browser, file manager,
  mail, `discord:`, text, images, PDF — closes queued item 10 and the UX-audit bullet.

## Queued, in priority order
(Numbers are the original queue numbers; the closed ones are listed under "Closed".)

- **5.** **Split `hyprland.lua` by concern** — `env → settings → animations → devices →
   rules → binds → autostart` as `require`s; NVIDIA env in its own file. Source:
   fancypantalons/hyprland-config.
- **8.** **`aconfmgr save`** for the system layer, replacing hand-maintained
   `hosts/<h>/etc` copies. `save` only at first — `apply` removes packages not in
   the config.

## Rejected
- `wayland.windowManager.hyprland.settings` with `configType = "lua"` — generates
  invalid Lua (home-manager#9468, closed not-planned).
- `io.popen("hostname")` in `hyprland.lua` — a synchronous subprocess inside the
  compositor. (This repo reads a file, which is fine.)
- flake-parts — a framework for two `homeConfigurations`.
- Stylix — fights `mkOutOfStoreSymlink`; the dram already has a palette-file design.
- nixGL-wrapping Hyprland/Waybar — pacman owns those (ADR 0003).
- chezmoi / yadm — a second templating engine beside Nix.
- Monolithic JaKooLit-style installers — assume NVIDIA, no dry-run.

## From the UX audit (2026-10-05 evening) — still open, user's call
- **`welcome.sh` toast** fires every login; cosmetic.

## Closed
Queued items, by their original number:
- **0.** ~~Deliberate orphan pass on cabin; firewall/hardening on cabin~~ — both done 2026-10-06.
- **1.** ~~borgmatic `settings` port~~ — done 2026-10-06 (a1ba814): `modules/backup.nix` is one
   `settings` attrset.
- **1b.** ~~Vendor cabin's lib32 set into `pkgs/` and lift the `IgnorePkg` freeze~~ — done
   2026-10-06: the 11 `pkgs/lib32-*` directories (12 names, `pkgs/manifest.txt`) are built
   and installed on both hosts; `system/maintenance.sh` now *removes* the `IgnorePkg`
   line (`docs/security/software-supply/README.md`).
- **2.** ~~Host facts readable outside Nix~~ — done 2026-10-06: `modules/core.nix` writes
   `~/.config/dram/facts.lua` from the flags and `dram doctor` asserts `gpu` against
   `lspci` and `host` against `/etc/hostname` (`decisions/0006-flake-layout.md`).
- **3.** ~~Feature flags over hostname branches~~ — done 2026-10-06 (`decisions/0004-module-split.md`).
- **4.** ~~A Nix-generated Lua fact file for `hyprland.lua`~~ — done 2026-10-06:
   `~/.config/dram/facts.lua` (`{ host, laptop, gpu, location, backupPeer }`), read with
   `pcall(dofile)`; the `/etc/hostname` read and the battery probe remain as fallbacks.
- **6.** ~~Pre-commit via `cachix/git-hooks.nix`~~ — done 2026-10-06 for statix, deadnix,
   shellcheck (`checks.<system>.pre-commit`, `nix develop`); nixfmt/shfmt/stylua wait for
   the one-off reformat commit (`decisions/0006-flake-layout.md`).
- **7.** ~~Secrets: finish the sops-nix bootstrap~~ — done 2026-10-06: age keys on both hosts,
   `secrets/pj.yaml` tracked, `dram.secrets.enable = true` in both host files,
   `modules/backup.nix` reads the sops path (`docs/security/identity/secrets.md`).
- **9.** ~~Nightly `flake-checker-action`~~ — in `.github/workflows/check.yml` (weekly), 2026-10-06.
- **10.** ~~Declare `xdg.mimeApps` in `modules/desktop.nix`~~ — done 2026-10-06 (`docs/toolchain/README.md`,
    "Default applications").

UX-audit bullets:
- DONE 2026-10-05 (user decided): tearing + `immediate` for games, VRR left off; Feral
  `gamemode` installed on both (use `gamemoderun %command%` in Steam launch options);
  CUPS: units disabled 2026-10-05, packages removed 2026-10-07 (never configured on
  cabin; reinstall recipe in handbook 07 "Host-side cleanup"); `krdp` removed; cabin
  Wi-Fi driver blacklisted (always wired); orphan pass done; Bolt data removed.
  Hardening: applied 2026-10-06 (`docs/security/network/hardening.md`).
- ~~**Unbound tools**: `wofi`, `hyprshot`, `nwg-look`, `nwg-displays`, `htop`, `kvantum`,
  `firefox`, `kooha`, `polkit-kde-agent`, `vorta`~~ — gone from `packages/base.txt` and,
  per the re-run harvest, from both `hosts/<h>/packages/` lists (2026-10-06).
- ~~`xdg.mimeApps`~~ — declared in `modules/desktop.nix` 2026-10-06.
- ~~**One `refind.conf` template**~~ — done, then superseded 2026-10-12: `system/apply-refind.sh`
  writes the menu for the UKI chain from what is on the ESP (`docs/platforms/arch/boot-chain.md`).
- Backups: wired 2026-10-05 — borgmatic host-to-host + Mac pull (`docs/operations/backups/README.md`); `dram backup`, `dram doctor` checks archive age.

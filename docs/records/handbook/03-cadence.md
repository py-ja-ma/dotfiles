# 3. Cadence

What to run, how often, what healthy output looks like, and which timer already
does it. Nothing updates unattended: the timers trim, re-rank mirrors, scan and
snapshot; `dram update` is yours. Every pacman transaction takes a pre/post snapshot of
`/` and a boot entry for it (`decisions/0011-disk-boot-secure-boot-snapshots.md`).
Backups are paused until the NAS (`decisions/0014-backups-paused-until-nas.md`). Depth: `docs/platforms/arch/hooks.md` (every timer and
hook), `docs/operations/dram/README.md` (every subcommand), `docs/commands.md` (which command when).

## Before you start

- Chapters 1 and 2 are done; `dram doctor` is clean apart from the warnings chapter 1 §9 expects.
- A terminal on the host (`SUPER+Q`), or `ssh pj@<host>` from the Mac. `upgrade`
  is a bash alias and does not exist over `ssh host upgrade`; call `dram` directly.

## 1. The timers that run on their own

```sh
systemctl list-timers --no-pager | grep -E 'paccache|reflector|arch-audit|wkd|snapper|fstrim'
systemctl --user list-timers --no-pager            # dram-theme-auto.timer
```

| Timer | When | Does | Healthy |
|---|---|---|---|
| `snapper-cleanup.timer` | daily | trims `/`'s pre/post snapshots to 12 + 6 important, `/home`'s timeline to its daily/weekly set; the boot entries of removed snapshots go with them | `sudo snapper -c root list \| wc -l` stays bounded |
| `snapper-timeline.timer` | hourly | `/home` timeline snapshots; the cleanup keeps 5 daily and 2 weekly (`system/snapper/home`) | `sudo snapper -c home list` shows recent `timeline` rows |
| `fstrim.timer` | weekly | TRIM on the SSDs | `systemctl status fstrim.timer` |
| `dram-theme-auto.timer` (user) | every 10 min and at login | `washi-day` by day, `washi` + 4000 K night light by night; never overrides a hand-picked theme | `dram-theme-auto --print` ends `action=none` |
| `arch-audit.timer` | daily 00:00 | fixable CVEs into the journal | `dram doctor`: `no fixable CVEs (arch-audit -u)` |
| `paccache.timer` | weekly (Monday) | keeps two versions of each package in `/var/cache/pacman/pkg` | `ls /var/cache/pacman/pkg \| wc -l` stays bounded |
| `reflector.timer` | weekly | ten newest https mirrors in `MAINT_COUNTRY`, by rate, to `/etc/pacman.d/mirrorlist` | `grep -m1 '^# With:' /etc/pacman.d/mirrorlist` prints the reflector command once it has run; when archlinux.org cannot be reached (chapter 11 §5) it fails softly and the installer's pinned list stays |
| `archlinux-keyring-wkd-sync.timer` | weekly | refreshes developer keys from WKD | `dram doctor`: `maintenance timers + hooks in place` |

`system/maintenance.sh` installs the system timers and hooks; `dram doctor`
warns `maintenance not installed: …` with the fix when one is missing.

## 2. The table

| How often | Run | Healthy output | Timer |
|---|---|---|---|
| **Daily** (a glance) | the welcome toast / the bar's updates badge | no badge = nothing pending; the badge caches 30 min | `waybar-updates.sh` |
| Daily | `dram doctor --brief` | `[ok] doctor: all clear` and exit 0 when clean; exit 1 while any warning stands | — |
| **Weekly** | `dram update --check` | `no repo updates` / the pending list (`checkupdates` covers `[dram]`); `dram: up to date (vX)` or `dram: <current> -> <target> (N commits)`; `dram builds for pj@<host>`; `Check done. Nothing is pending (exit 7). Nothing was changed.` | — |
| Weekly | `dram update` | `archlinux-keyring is current`, `system software up to date`, pacnew `none`, orphans `none`, `dram rebuilt (current generation active)`, `no reboot needed` or `reboot when convenient`, then `dram doctor --brief` | — |
| Weekly | reboot if `dram update` asked | `dram doctor`: `no reboot needed` | — |
| **Monthly** | `dram update --clean` (= `upgrade` in a shell) | the weekly lines plus `HM generations older than 7 days expired`, `nix store garbage-collected` | — |
| Monthly | `sudo -v; dram doctor --boot` | boot section all `[ok]`: systemd-boot first, Secure Boot enforcing, `/efi free` above 400 MB, a UKI per kernel, `sbctl verify` clean, snapshot entries present | — |
| Monthly | `sudo btrfs scrub start -B /` (and `/data/games` where a data pool exists) | `Error summary:    no errors found` (every checksum on the pool re-read) | — |
| Monthly | `dram yubikey status` with a key plugged in | both keys listed, `FIDO2 PIN: 8 of 8 tries left` (`docs/security/identity/yubikeys.md`) | — |
| Monthly | `bin/repro.sh` (also after a kernel / Hyprland / openssh / sudo / systemd / pacman update) | `reproducible` per package (`docs/security/software-supply/integrity.md`) | — |
| Monthly | `sudo flatpak update` and `flatpak uninstall --unused` | `Nothing to do.` on a current host (`dram update` already runs the update) | — |
| **Quarterly** | `dram update --full` | `flake.lock updated`, `dram rebuilt`; `flake.lock was bumped — commit it when happy`. `dram doctor` warns at 60 days of age | — |
| Quarterly | `dram harvest` then commit `hosts/<host>/` | `[ok] wrote hosts/<host>/ (explicit=N aur=M)` | — |
| Quarterly | `dram check` | `bin/check.sh` all `[ok]`, `nix flake check` silent, exit 0 | — |
| **After a hardware change** (board, disk slot, GPU, monitor) | `sudo mkinitcpio -P` (rebuilds and re-signs the UKIs); GPU: set `dram.gpu` in `modules/hosts/<host>.nix`, `bash install/bootstrap.sh --phase 1` and `--phase 5`, `dram switch`; a new board: Secure Boot from Setup Mode again (chapter 1 §8) and, on a laptop, `sudo bash system/tpm2-enroll.sh --reenroll`; a BIOS update, CMOS clear or "Load Defaults": check the firmware's Secure Boot settings (MSI: Secure Boot Preset → Maximum Security) and prove enforcement again (chapter 1 §8, `system/secureboot-test.sh`); then `dram harvest` | `facts.lua: gpu = <vendor> (lspci agrees)`; `dram doctor --boot` all `[ok]`; `secureboot-test.sh --check` prints `[ok]` | — |
| After a hardware change | `monitors-pin.sh` once the monitors stand where they belong, then `hyprctl reload` (it rewrites `~/.config/dram/monitors.lua`) | each workspace lands on the intended output | — |
| **After a move** (`docs/platforms/arch/hooks.md`, "Moving house") | `sudo timedatectl set-timezone <Zone>`; `dram.location = "LAT LON"` in `modules/options.nix` or the host file, `dram switch`; a new subnet in each host's `/etc/dram/lan.nft` and new `HostName` lines in the Mac's `~/.ssh/config` (chapter 9, §3); a new WireGuard `.conf` | `timedatectl` shows the zone; `dram-theme-auto --print` shows the new sunrise/sunset; `ssh <user>@<host>` still works from the Mac | — |

## 3. `dram update` and its flags

| Run | Does | Use it |
|---|---|---|
| `dram update` | keyring (only if behind) → `paccache -rk2` → `sudo pacman -Syu` (repo + `[dram]`; a pre/post snapshot and its boot entry come with it) → `flatpak update` → pacnew / orphans / reboot report → `dram switch` → `dram doctor --brief` (the supply section is part of every doctor run) | weekly |
| `dram update --check` | read-only: `checkupdates` (repo + `[dram]`), `flatpak remote-ls --updates`, `arch-audit -u`, the channel target (`dram: up to date` or `dram: <current> -> <target> (N commits)`), then a build (not a switch) of the dram; **exit 7 when nothing at all is pending**, 0 when something is, 1 when the build failed | before an update, or over ssh to see what is pending |
| `dram version` | the running build from `~/.config/dram/release`: release tag, build `<date>.<sha>`, channel, generation; `--json` for scripts; warns when the checkout has moved past the switched build | after an update, or to answer "what does this host run" (chapter 4) |
| `dram channel` | what `dram update` follows: `stable` (the latest `v*` tag) or `main` (`master`); `dram channel stable` / `main` sets it, `--target` for scripts | before the first update on a host meant to follow releases, or meant not to |
| `dram rollback` | the previous build: its commit checked out, its Home Manager generation activated, the `sudo pacman -U` lines for packages that differ **printed, never run**; `dram builds` lists the last five | after an update went wrong (chapter 4) |
| `dram rollback --system [N]` | the system itself: the snapshots, or `/` restored to snapshot N (boot it first from the menu to try it) | when packages or `/etc` broke the machine (chapter 4) |
| `dram update --clean` | the above plus `home-manager expire-generations "-7 days"` and `nix-collect-garbage --delete-older-than 7d` | monthly (`upgrade` alias) |
| `dram update --full` | the above plus `nix flake update` first; `flake.lock` is restored from git if the rebuilt dram fails to switch | quarterly, or when `dram doctor` says `flake.lock is N days old` |
| `dram update --no-switch` | everything except the final `dram switch` | when `modules/` is mid-edit |

`sysupdate` is a shim for `dram update` with the same flags. `dram switch` alone
applies the flake after a `modules/` edit; `dram rollback N` goes back N Home
Manager generations (asks first), `dram switch` forward again; `dram rollback`
with no number is the previous build (chapter 4). Generations older than 7 days
disappear with `--clean`, so roll back before the monthly run.

## 4. When to reboot

`dram update` ends with a `Reboot?` section and `dram doctor` has a `reboot
needed` line. Both fire for exactly three reasons: the running kernel is no
longer on disk (`uname -r` is not in `ls /usr/lib/modules`), the running
Hyprland binary was replaced, or `nvidia-utils` changed. Reboot then, before
relying on the machine: the old kernel's modules are gone from disk, so a USB
device or a VPN that needs a module not yet loaded fails until the reboot.

Also reboot after anything that rewrote the UKIs or the boot chain by hand
(`sudo mkinitcpio -P`, `system/secureboot-setup.sh`, `system/tpm2-enroll.sh`,
`bootstrap.sh --phase 5`), and log out and back in after
`system/maintenance.sh` (the `limits.d` realtime line applies at login; `ulimit
-r` prints `99` afterwards) and after `usermod -aG`.

No reboot is needed for `dram switch`, `dram theme`, `dram update` runs that
touched no kernel/Hyprland/driver, Flatpak updates, or `harden.sh` (its rules
load live; `sudo nft list ruleset` shows them).

## Done when

- [ ] `systemctl list-timers` shows `paccache`, `reflector`, `arch-audit`, `archlinux-keyring-wkd-sync`, `snapper-cleanup`, `snapper-timeline`, `fstrim`; `systemctl --user list-timers` shows `dram-theme-auto`
- [ ] `dram update --check` ends `Check done. Nothing is pending (exit 7). Nothing was changed.` with exit 7
- [ ] `dram update` has run once from this chapter and ended in `dram doctor --brief` with no warnings
- [ ] `sudo snapper -c root list` shows the update's pre/post pair, and the boot menu its entry
- [ ] `dram doctor` says `no reboot needed`

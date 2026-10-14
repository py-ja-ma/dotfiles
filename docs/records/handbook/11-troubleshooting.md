# 11. Troubleshooting

Symptom → the check that proves the diagnosis → the fix. Grouped by where it happens. Every
fix that writes a boot file leaves the previous one as `<file>.bak-<stamp>` next to it.
Depth: `decisions/0011-disk-boot-secure-boot-snapshots.md` (the disk, systemd-boot,
Secure Boot, the snapshots), `docs/security/identity/yubikeys.md`, `docs/platforms/arch/hooks.md` ("What `dram doctor`
checks"), `docs/security/software-supply/integrity.md` (every `supply` line), `docs/security/identity/secrets.md`, `docs/toolchain/packaging/README.md`.
`docs/platforms/arch/boot-chain.md` (rEFInd in front, the splash) and `docs/platforms/arch/boot-chain.md` (every way around a layer).

## Before you start

- `dram doctor` first: every warning names its fix, and most rows below are one of its
  lines. `sudo -v; dram doctor --boot` adds the boot chain, `--supply` the provenance
  section.
- The repo at `~/git/dotfiles`; `cd` there for the `system/` scripts.
- For boot problems, in order: rEFInd's menu (five seconds: Arch Linux, Arch Linux LTS,
  Windows, Snapshots & recovery); behind its last tile, or by itself when rEFInd fails, the
  systemd-boot menu (three seconds; any key holds it) — `Arch Linux (<version>)`, its fallback `Arch Linux (<version>~fallback)`
  (every module, no autodetect), on cabin the same pair for the LTS kernel (the version
  ends in `-lts`), and the snapshot entries `Arch snapshot <n> — <date> pacman: …`
  (read-only with a throwaway overlay); Ctrl+Alt+F1 for a text console once the kernel is
  up; the Arch ISO as the last rung (the last row of §1). `sudo bootctl list` prints the
  same entries; `sudo bootctl set-oneshot <id>` boots one of them once.

## 1. Boot

| Symptom | Check | Fix |
|---|---|---|
| Firmware boots Windows, another disk, or "no bootable device"; rEFInd's menu never shows | `efibootmgr` (`BootOrder` starts with `rEFInd`, then `Linux Boot Manager`); `dram boot-to list` names this Arch's entry | `sudo bash system/apply-refind.sh` puts rEFInd first again (or `sudo efibootmgr -o <rEFInd>,<Linux Boot Manager>,…`). Cannot boot Arch at all: the firmware's one-time boot menu (F12 / F8 / F11 by board) → `Linux Boot Manager`, or the disk itself (`\EFI\BOOT\BOOTX64.EFI` is systemd-boot too); else the ISO row below and `bootctl install --esp-path=/efi` |
| "Security Violation", "Verification failed" or a silent return to the firmware menu after an update | Secure Boot refused an unsigned file: boot once with Secure Boot off in the firmware, then `sudo sbctl verify` (each file `✓ signed`) | `sudo bash system/secureboot-setup.sh` (signs systemd-boot at the source and every UKI, registers them for re-signing); `sudo mkinitcpio -P` re-signs the UKIs through sbctl's hook; Secure Boot back on, reboot; rEFInd: `sudo /usr/local/lib/dram/refind-update`. `dram doctor --boot`: `sbctl verify: everything of ours on the ESP is signed` (Windows' files are Microsoft's) |
| The menu shows, the entry fails ("Failed to execute", "Error loading") | from a snapshot entry or the fallback: `ls -l /efi/EFI/Linux/`; `df -m /efi` | `sudo mkinitcpio -P`; `/efi` full (under 400 MB free: `dram doctor --boot` warns) → `sudo snapper -c root delete <n>` on old snapshots, their UKIs go with them |
| cabin's menu has no LTS entry | `ls /efi/EFI/Linux/` lacks `arch-linux-lts.efi`; `dram doctor --boot`: `no /efi/EFI/Linux/arch-linux-lts.efi` | `sudo bash system/uki-presets.sh` (a kernel the roles added gets a UKI preset, is built and signed; `dram apply` runs it too) |
| Black screen after the menu (NVIDIA most often) | boot the fallback entry; `lsinitcpio /efi/EFI/Linux/arch-linux.efi \| grep -E 'i915\|amdgpu\|nvidia\|nouveau'` (NVIDIA: four `nvidia*`, zero `nouveau`); `cat /etc/mkinitcpio.conf.d/10-kms.conf /etc/kernel/cmdline` | `bash install/bootstrap.sh --phase 5` (the GPU's early-KMS modules and `nvidia_drm.modeset=1`, then the UKIs); or restore a `.bak-<stamp>` of the drop-in and `sudo mkinitcpio -P` |
| Black screen after a hardware change (new board, disk in another slot, new GPU) | the fallback entry boots (it has every module) | `sudo mkinitcpio -P` on the live hardware; a GPU change: `dram.gpu` in the host file and phase 5 (chapter 3, "After a hardware change"); a new board: Secure Boot from Setup Mode again (chapter 1 §8) |
| `systemctl --failed` lists `systemd-tpm2-setup-early`, `systemd-pcrproduct` and `systemd-pcrlogin@<uid>`; the system is `degraded` from the first boot | `journalctl -b -u systemd-tpm2-setup-early`: `Failed to initialize NvPCR index: No such file or directory`; `sudo systemd-analyze nvpcrs` shows no values; `dram doctor` prints it as `[i]` | not a fault here: systemd 262 creates its NvPCRs only from a UKI that embeds a signed initrd PCR policy (ukify `--sign-initrd-pcrs`), and mkinitcpio's UKIs have none — upstream issue github.com/systemd/systemd/issues/43848, fix PRs open. Nothing in this setup binds to NvPCRs (lantern's disk uses PCR 7). Clearing the TPM does not change it (tried on cabin, 2026-10-11). It goes away with the systemd fix |
| lantern asks for the recovery key, or "Please enter LUKS2 token PIN" refuses the right TPM PIN | after a firmware update or a Secure Boot key change the TPM's PCR 7 no longer matches | `docs/security/identity/yubikeys.md`, "lantern's disk": a YubiKey and its FIDO2 PIN, else the recovery key (Proton Pass); then `sudo bash system/tpm2-enroll.sh --reenroll` |
| An unsigned image (an Arch ISO) boots although `bootctl status` says `Secure Boot: enabled (user)`; `sbctl status` lists `FQ0001` | `sudo bash system/secureboot-test.sh --arm`, reboot, `--check` (exit 1 = the unsigned loader ran) | the firmware runs images that fail verification (MSI's default "Hardware/OS Compatibility"): firmware → Secure Boot → **Secure Boot Preset → Maximum Security** (older MSI: Image Execution Policy, Removable and Fixed Media → Deny Execute). Leave the keys alone. Prove it again with the tests in chapter 1 §8; `FQ0001` itself never goes away (sbctl reads only the board model) |
| A snapshot entry boots, but changes vanish at the next reboot | expected: snapshot entries run read-only with a RAM overlay (`systemd.volatile=overlay`) | to keep that state: `dram rollback --system <n>` (asks, then reboot); chapter 4 §10 |
| No snapshot entries in the menu | `dram rollback --system` lists the snapshots and which have an entry; `dram doctor --boot` | only `pre` snapshots of pacman transactions get entries (the newest five); none before the first update. `sudo /usr/local/lib/dram/dram-snapshot ukis` rebuilds them; a snapshot from before `snapshots-setup.sh` cannot have one |
| Kernel boots, then a text console instead of ly | `systemctl status ly@tty2.service`; `systemctl is-enabled ly@tty2.service` | `sudo systemctl enable --now ly@tty2.service`. There is no plain `ly.service`; `systemctl enable ly` fails with `not-found` |
| ly draws garbage, crashes, or burns CPU | `grep -E '^(animation\|dur_file_path)' /etc/ly/config.ini`; `ls /etc/ly/*.dur` must print nothing | `sudo bash system/apply-ly.sh --anim none` (refuses `dur`; scrubs `.dur` files). Only `none` and `matrix` are allowed |
| Password refused at ly after a few tries, even the right one | from Ctrl+Alt+F1: `faillock --user <user>` shows the failures (5 tries, 10-minute unlock) | wait 10 minutes, or `sudo faillock --user <user> --reset`; counters also clear on reboot. The right password and no touch is §4, not this |
| Two `Hyprland` entries in the greeter | `ls /usr/share/wayland-sessions/`; `grep '^NoExtract' /etc/pacman.conf` | `sudo bash system/system-dram.sh` (collapses the sessions, adds the `NoExtract` line) |
| ly accepts the password, Hyprland never appears, back to the greeter | Ctrl+Alt+F1: `ls -l ~/.config/themes/current/palette.lua`; `tail -20 ~/.cache/hyprland/hyprland.log` | `dram theme washi` (the `current` link is runtime state Hyprland needs at start); `dram switch` seeds it on first switch |
| Login takes two minutes, then works | `systemd-analyze critical-chain graphical.target` names `systemd-networkd-wait-online` | the drop-in from `hosts/lantern/README.md` (`--any --timeout=20` for wait-online) when a link has no carrier |
| Nothing above helps: the system does not boot from any entry | — | from the Arch ISO, Secure Boot off for that boot: `mount -o subvol=@ /dev/disk/by-label/dram-sys /mnt` (lantern: `cryptsetup open /dev/disk/by-label/dram-sys dram-sys` with the recovery key, then `/dev/mapper/dram-sys`), `mount /dev/disk/by-label/ESP /mnt/efi`, `mount -o subvol=@sbctl /dev/disk/by-label/dram-sys /mnt/var/lib/sbctl` (the same device), `arch-chroot /mnt`, then `mkinitcpio -P` and `bootctl install --esp-path=/efi --graceful`; or roll back from there with `snapper -c root list` and a snapshot entry. Exit, `umount -R /mnt`, Secure Boot on, reboot |

## 2. Session

| Symptom | Check | Fix |
|---|---|---|
| No bar | `pgrep -a waybar` prints nothing | `SUPER+SHIFT+B` (toggles the bar and pauses the fullscreen auto-hide); else log out and in. `waybar -c ~/.config/waybar/config.jsonc` in a terminal prints the parse error |
| Two bars on every monitor | `systemctl --user is-enabled waybar.service` prints `enabled` | `systemctl --user disable --now waybar.service`; hyprland.lua starts waybar itself |
| Bar or lock screen in the wrong font, missing glyphs, English date | `fc-list \| grep -ciE 'literata\|fraunces\|monaspace'` (> 0); `locale -a \| grep ru_RU` | `dram switch` (the fonts come from the flake), then `fc-cache -f` and log out; `sudo bash system/locale-setup.sh` for the locale |
| Theme half applied (some apps old colours) | `ls -l ~/.config/themes/current`; `dram doctor` dram section (`theme: <id>`, `*.bak-*` count) | `dram theme <id>` again (idempotent); restart the apps that do not reload (browsers, VSCodium). `find ~/.config -maxdepth 3 -name '*.bak-*'` lists Home Manager leftovers to review and delete |
| Browser or Thunderbird chrome unthemed | `ls ~/.librewolf/*/chrome/userChrome.css ~/.thunderbird/*/chrome/userChrome.css` | open the app once so the profile exists, quit, `dram theme <id>`, restart |
| `EN`/`RU` does not switch, or only one keyboard switched | `kb-layout.sh status` in a terminal on the desktop (over ssh it prints `kb-layout.sh: hyprctl failed (no Hyprland session)`); `hyprctl devices \| grep -A2 -i keyboard` lists the devices | `kb-layout.sh en` / `kb-layout.sh ru` sets every device; the binds are left Alt+Shift (either order) and `SUPER+ALT+SPACE`; right Alt/Shift do nothing by design |
| Night light stuck on or off | `pgrep -a hyprsunset` (exactly one); `dram-theme-auto --print` (`night light=…`); `cat ~/.config/dram/location` | `nightlight.sh` once more hands control back to the sun; `dram-theme-auto --nightlight` re-applies the sun state; wrong times → `dram.location`, `dram switch` |
| Theme flips back to `washi` by itself | `dram-theme-auto --print` says `action=switch` | expected only when the current theme is `washi` or `washi-day`; any other theme picked with `SUPER+T` is left alone |
| No notifications, no welcome toast | `pgrep -a swaync`; `pacman -Q dunst` | `sudo pacman -Rns dunst` if present (it races swaync for the bus name); `systemctl --user is-enabled swaync.service` must print `masked` (bootstrap phase 3 masks it); `notify-send test` to confirm |
| Apps ask for a keyring password at every start | `dram doctor` login section; `systemctl --user is-enabled gnome-keyring-daemon.socket` must print `masked` | `grep pam_gnome_keyring /etc/pam.d/ly`; `systemctl --user mask gnome-keyring-daemon.socket gnome-keyring-daemon.service`; log out and in |
| A new or re-plugged monitor stays black | `hyprctl monitors` lists it | `quote-wallpaper.sh --show`; `wallpaper-hotplug.sh` is autostarted and does this on hotplug |
| Keybinds gone after a reload | `hyprctl binds \| wc -l` prints 0 | log out and in; never plain `hyprctl reload` a session started on an old `.conf` (`docs/platforms/arch/install.md`) |
| `dram doctor`: `N error-level journal lines this boot (last 3 below; known noise filtered)` | `journalctl -p3 -b` | expected on these hosts: `virt/tdx: TDX not supported`, `Failed to set mode: Failed (0x03)`, `gkr-pam: unable to locate daemon control file`; anything else → `systemctl status <unit>` for the unit the line names |

## 3. Updates and the flake

| Symptom | Check | Fix |
|---|---|---|
| `dram update` dies with `/var/lib/pacman/db.lck exists` | `pgrep -a pacman` | nothing running → `sudo rm /var/lib/pacman/db.lck`, run again |
| `signature from … is unknown trust` / `invalid or corrupted package (PGP signature)` on an official package | `pacman -Qu archlinux-keyring` prints the package → it is behind | `sudo pacman -Sy archlinux-keyring` then `dram update` (it does this itself when it can see the keyring is behind); the WKD timer refreshes keys weekly |
| `.pacnew` files reported | `pacdiff -o` | `dram pacnew` (`vim -d` per file; `DIFFPROG=meld dram pacnew`); after a `locale.gen.pacnew`: `sudo bash system/locale-setup.sh` |
| `dram switch` fails: an existing file is in the way | the message names the path; `ls -l <path>` | `dram switch` already backs files up as `bak-<stamp>`; a *directory* that used to be one symlink must go first: `rm ~/.config/<dir>` (the link, not the repo) then `dram switch` (`docs/platforms/arch/install.md`) |
| `dram switch` fails to evaluate, or the desktop is wrong after it | the error names the module and line; `home-manager generations` lists what exists | `dram rollback 1` (one generation back; `dram rollback 2` two back; `dram rollback` alone is the previous *build*, chapter 4); the previous generation stays active after a failed switch, so nothing is broken until the rollback is confirmed |
| `dram update` ends `dram rebuild FAILED — the PREVIOUS generation is still active` | the lines above it | fix the flake and `dram switch`; with `--full` it has already restored `flake.lock` to the last-good pins |
| `nix flake check` fails | `bash bin/check.sh` first (§2 hosts agree, §11 host flags); `git status` (flakes see tracked files only — `git add` a new file); `nix flake check --show-trace` | add the missing `dram.*` option to `modules/hosts/<host>.nix`; `git add` the file |
| `dram update --check` says `dram build FAILED for <user>@<host>` | same as above | fix before `dram update`; nothing was changed |
| `dram update --check` exits 7 | the last line is `Check done. Nothing is pending (exit 7). Nothing was changed.` | not a failure: nothing is pending (no package, Flatpak or dram build); 0 means something is, 1 means the build failed |
| `dram version` prints `[!] the checkout is at <x>, not the switched build`; `dram doctor`: `the checkout (<x>) is not the switched build (<build>)` | `dram version` (`commit`) vs `git -C ~/git/dotfiles log -1` | `dram switch` (a push or a checkout landed without a switch); `dram rollback` if the new build is unwanted |
| `dram doctor`: `behind channel stable: vX is N commits from the checkout` | `dram channel` says `N commits away: dram update`; `dram changelog` for the notes | `dram update` (moves the checkout to the tag, then the normal flow); a host meant to follow every push: `dram channel main` first |
| `dram update` stops at `[x] uncommitted edits to tracked files in /home/<user>/git/dotfiles` | the files are listed above the line; `git -C ~/git/dotfiles status --porcelain --untracked-files=no` | commit (`git -C ~/git/dotfiles commit -a`), stash (`git -C ~/git/dotfiles stash`) or discard (`git -C ~/git/dotfiles checkout -- <file>`), then `dram update` again; untracked files never block |
| `dram update --check`: `nothing to follow yet: no v* tag on this host (dram channel main; bin/release.sh on the Mac cuts a tag)`; `dram channel`: `nothing to follow yet (no v* tag on this host)` | `git -C ~/git/dotfiles tag` prints nothing | `bin/release.sh -m "…"` on the Mac (pushes the tag), or `dram channel main` to follow plain pushes |
| An update went wrong; want the previous build | `dram builds` lists it with its version and generation | `dram rollback` (no number): checkout + generation back, then paste the printed `sudo pacman -U` lines you want; reboot if a kernel line was pasted |
| `dram rollback`: `no previous build differs from the running one` / `generation N is gone (… --clean expired it)` | `dram builds`; `home-manager generations` | nothing recorded to go back to (the first `dram update` records one); expired generation → `git -C ~/git/dotfiles checkout <commit>` then `dram switch` |
| `reboot needed:` keeps appearing | `uname -r` vs `ls /usr/lib/modules` | reboot |
| `dkms: no module installed for kernel(s)` | `pacman -Q linux-headers linux-lts-headers` | install the missing headers; `sudo dkms autoinstall -k <ver>` |
| `flake.lock is N days old` | `dram doctor` dram section | `dram update --full`; commit `flake.lock` when happy |
| `modules/ or flake changed after the last dram switch (generation N days old)` right after a push | `git -C ~/git/dotfiles log -1` is newer than `~/.local/state/dram/last-switch` | `dram switch` (it writes `last-switch`) |
| `checkrebuild` names a package | `checkrebuild -v`; `pacman -Qi <pkg> \| grep Packager` | it is a `[dram]` package (`packages/aur.txt` is empty and there is no AUR helper): on cabin `dram pkgs build <pkg> && dram pkgs publish`, then `bin/sync-dram-repo.sh` from the Mac, then `dram update` on each host — the `lib32-mpg123` case of 2026-10-06. |

## 4. YubiKeys and secrets

| Symptom | Check | Fix |
|---|---|---|
| `sudo` says `Sorry, try again.` after the right password, with no touch prompt | `dram yubikey status` with a key plugged in; `dram doctor` yubikeys section | plug a listed key in **at this machine** and touch it when it blinks (`Please touch the FIDO authenticator.`). Over ssh on a desktop host this fails by design: do admin at its keyboard (`docs/security/identity/yubikeys.md`, "Daily use") |
| `sudo`, ly or hyprlock takes the password and then waits | the key blinks; a notification says it waits for a touch | touch it. Nothing plugged in: Ctrl+C (sudo), plug one in, again |
| `dram doctor`: `second factor OFF for <user> on this host` | `grep "^$(id -un):" /etc/dram/u2f_mappings` prints nothing | at the machine, a listed key plugged in: `sudo bash system/yubikey-setup.sh` (a test touch, then on) |
| `dram doctor`: `pam_u2f line missing in: …` or `differs from system/pam-u2f.conf in: …` | `grep pam_u2f /etc/pam.d/sudo /etc/pam.d/login /etc/pam.d/polkit-1` | `sudo bash system/yubikey-setup.sh`; after a `sudo`/`pambase` update left a `.pacnew`, merge it first (§3, `dram pacnew`) |
| `ssh <host>` asks for a password or ends in `Permission denied (publickey)` with the key plugged in | `ssh -v <host> 2>&1 \| grep -E 'Offering\|sk-'`; on the host, `dram doctor`: `sshd accepts the YubiKeys' SSH keys` | `dram yubikey ssh` (the handles `~/.ssh/id_ed25519_sk*`, FIDO2 PIN and a touch); on the host `sudo bash system/harden.sh` when its keys file differs from `keys/ssh.pub` |
| `git commit` fails: `signing failed` or `No such file or directory` for `id_ed25519_sk` | `ls -l ~/.ssh/id_ed25519_sk*`; `git config --get user.signingkey` | plug the key in and touch; `dram yubikey ssh` restores the handles; `dram yubikey use spare` while the primary is away |
| The FIDO2 PIN was refused and now the key does not answer | `ykman fido info` (its PIN line) | three wrong in a row: unplug and re-plug. Eight: the PIN is blocked — `ykman fido reset` wipes that key's FIDO2 credentials (SSH, pam-u2f, lantern's slot); then `docs/security/identity/yubikeys.md` "A key is lost" for it and enrol it again under a new label |
| sops with a YubiKey stops at the PIN; the PIV PIN is blocked | `ykman piv info` (PIN tries) | `ykman piv access unblock-pin` with the PUK (Proton Pass). PUK blocked too: `ykman piv reset` loses that key's age identity — re-key `secrets/pj.yaml` with the other key (chapter 8) |
| Both keys lost: no sudo on any desktop host | — | `docs/security/identity/yubikeys.md`, "Both keys gone: the break-glass" (from the ISO, empty `/etc/dram/u2f_mappings`) |
| `sops`: `Failed to get the data key required to decrypt the SOPS file` | this host's age key is not a recipient yet: `age-keygen -y ~/.config/sops/age/keys.txt` vs `.sops.yaml` | chapter 8, "Adding a host"; meanwhile `SOPS_AGE_KEY_FILE=~/.config/sops/age/yubikey-primary.txt sops …` decrypts with a key |
| `sops-nix.service result: failed` | `journalctl --user -u sops-nix`; `ls -l ~/.config/sops/age/keys.txt` (0600) | key missing → `bash system/secrets-bootstrap.sh`; key not a recipient → the row above, then `dram switch` |
| `dram doctor`: `backups are paused until the NAS (decisions/0014): no borgmatic config on this host` | — | information, not a fault (chapter 5). The Borg rows come back with the NAS: `docs/operations/backups/README.md` |

## 5. Network

| Symptom | Check | Fix |
|---|---|---|
| `reflector` fails while `checkupdates` works | `curl -sI --max-time 5 https://archlinux.org \| head -1` gets no reply from the LAN; mirrors answer | only `archlinux.org`/`www` (209.126.35.79) fail: TCP connects, then the server closes the connection after the TLS hello. aur, wiki, security, gitlab, WKD and the mirrors all work — so `arch-audit` (security.archlinux.org) and `pacman-key` are **not** affected. Most likely an Arch-side block on the home WAN IP (diagnosed 2026-10-10); to fix, test from a phone hotspot, then check UniFi IPS and Xfinity's security filter, else ask Arch account support. Updates work regardless. Arch news is **off** for that reason: `dram update` has no news step, paru (and its `NewsOnUpgrade`) is gone, `informant` is not installed — read https://archlinux.org/news/ from another network (a phone hotspot; **not** over the VPN, which leaves through the same home IP) before a big update; `reflector`'s saved mirrorlist stays valid |
| `ssh <user>@<host>` drops with `Connection closed by remote host` once, works on retry | `journalctl -u sshd -n 20` on the host shows nothing persistent | transient; retry. Persistent → `sudo nft list ruleset \| grep 'dport 22'` must show the LAN rule |
| Locked out over SSH after `harden.sh` | from the console: `grep 'define LAN' system/nftables.conf` vs `ip -4 route \| grep -w src` | fix the `define LAN` subnet in `system/nftables.conf`, `sudo bash system/harden.sh` again (re-run after every edit of that file) |
| `Permission denied (publickey)` from a new machine | sshd is keys-only (`dram doctor --supply`: `sshd: PasswordAuthentication no`) | a YubiKey needs no host change: `ssh-keygen -K` on the new machine (OpenSSH 8.2+ with libfido2) loads the handles every host already accepts. Else append the machine's public key as a plain line to `~/.ssh/authorized_keys` on the host, from a machine that already has access |
| No Wi-Fi | `nmcli device`; `journalctl -b -u NetworkManager -u wpa_supplicant` (headless hosts: `systemctl is-active iwd`, `iwctl station list`) | `docs/security/network/networkmanager.md`; a desktop still on networkd: `sudo bash system/network-setup.sh` at the machine |
| VPN up but nothing reachable | `sudo wg` shows no `latest handshake` | the client `.conf` is stale or the gateway's WAN name changed; re-export from UniFi to `/etc/wireguard/home.conf` (`docs/security/network/vpn.md`) |

## 6. Packages and `[dram]`

| Symptom | Check | Fix |
|---|---|---|
| `[dram]` package: `signature from "pj dram packages" is unknown trust` / `marginal trust` (also right after a re-key) | `dram doctor --supply` (`[dram] SigLevel`, `database is signed`); `pacman -Sl dram \| wc -l` | `sudo bash system/pacman-dram-repo.sh` (idempotent: imports and locally signs `pkgs/dram.asc`, drops an older dram key, writes the stanza) then `dram update` |
| `pacman-dram-repo.sh`: `pkgs/dram.asc fingerprint X != expected Y — refusing to lsign an unknown key` | the key and its pin travel in one commit (`dram pkgs key --new`): `git log -1 --format=%h -- pkgs/dram.asc system/pacman-dram-repo.sh` here and on the builder | bring the builder's commit here (pull to the Mac, release, `dram update`), then run it again |
| `dram pkgs build`: `no signing key in ~/.config/dram/gpgkey` | `gpg --list-secret-keys` | a fresh builder: `dram pkgs key --new` (chapter 7, "`[dram]` from scratch"); a kept key: `gpg --import` its export, its fingerprint into that file |
| `pacman -Sy` fails on `dram.db` (`failed to synchronize all databases`) | `ls /var/lib/dram-repo/dram.db /var/lib/dram-repo/dram.db.sig` | `bin/sync-dram-repo.sh` from the Mac (carries cabin's `/srv/dram` over); `sudo bash system/pacman-dram-repo.sh` only adds the `Include` once the db exists |
| `[dram] repo has N package(s), pkgs/manifest.txt lists M` | `dram pkgs list \| wc -l` | on cabin `dram pkgs build && dram pkgs publish`; then `bin/sync-dram-repo.sh` from the Mac |
| `unaccounted foreign package: X` | `pacman -Qi X` (`Packager`, install date) | vendor it into `pkgs/` (`docs/toolchain/packaging/README.md` §7), add it to `packages/aur.txt` with a comment (nothing builds that list; it only silences the check), or `sudo pacman -Rns X` |
| `[i] listed but not installed here: …` | — | information: declared for another host (a role package on a host without that role) |
| `plugin package X built for hyprland A, hyprland is B` | `pacman -Q hyprland` | on cabin `dram pkgs build hyprland-plugin-hyprtasking hyprland-plugin-hyprfocus && dram pkgs publish`, then `dram update` here |
| `N package(s) with altered files outside /etc` | `pacman -Qkk <pkg>`; `pacman -Qo <file>` | compare with the cached package and reinstall per `docs/security/software-supply/integrity.md`, "Reacting to an altered file" |
| `N orphaned package(s)` | `pacman -Qqdt` | `sudo pacman -Rns $(pacman -Qqdt)`; `dram update` asks the same question |
| `dram pkgs check` refuses a package name | the name exists in an official repo (`pacman -Si <name>`) | `[dram]` sits above `[core]` and would shadow it silently; list it in `pkgs/OVERRIDES` only on purpose |
| `maintenance not installed: …` / `pacman.conf is missing …` | `dram doctor` pacman section | `sudo bash system/maintenance.sh --dry-run`, then without the flag |

## Done when

- [ ] `dram doctor` (and `--boot`, `--supply`) shows only the noise listed in chapter 1
- [ ] the fix applied is the one the doctor line named, and the line is `[ok]` on the next run
- [ ] any `.bak-<stamp>` restored from is noted, and `sudo mkinitcpio -P` was run if it was a mkinitcpio file or `/etc/kernel/cmdline`
- [ ] a boot-level fix was followed by a reboot through the normal **Arch Linux** entry, not only the fallback or a snapshot

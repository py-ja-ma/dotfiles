> **Historical plan (2026-07), not current state.** panasonic is not on LUKS
> (`hosts/panasonic/README.md`); the live runbook for a new or rebuilt machine is
> `docs/new-machine.md` + `install/bootstrap.sh`. Read `rice-switch` here as
> `rice switch`; the ly notes (`/etc/ly/config.ini`) are still right for ly 1.4/1.5
> (`system/apply-ly.sh`, `docs/boot-chain.md`).

# Wipe-and-reinstall runbook — pj's Panasonic laptop

Full recovery from a bare Arch ISO to the working Hyprland rice, for the planned
**LUKS full-disk-encryption** reinstall. This repo + this file = complete recovery.
Assumes Arch install basics; this covers what is specific to THIS machine.

Order: **Arch base+LUKS → packages → Nix/Home-Manager → system ricing → post-install checklist.**

---

## 0. Before you wipe — grab these (NOT in the repo)

Copy to the `eva` drive (or another USB) first. Without them you lose access/history:

- `~/.ssh/config.d/*.conf`   — private homelab hosts/IPs/users (gitignored by design)
- `~/.ssh/id_ed25519*`       — your SSH keys (or plan to re-enrol new keys everywhere)
- Proton Pass is cloud-synced (has your key passphrases) — just remember the master password.
- Anything under `~/Pictures`, `~/Documents`, browser profiles, Obsidian vault you care about.
- Confirm the repo itself is pushed to a git remote (as of this writing there may be **no remote** —
  push it somewhere before wiping, or clone from the `eva` backup at
  `/run/media/pj/eva/backup/panasonic`).

`eva` = `/dev/sda2`, NTFS 3.6 TB (USB, label "eva"/ESD-S1C). Mount without sudo:
`udisksctl mount -b /dev/sda2` → `/run/media/pj/eva`. If it refuses RW ("bad superblock",
NTFS dirty flag from an unclean reboot), mount RO with `-o ro`, or clear the flag:
`sudo mount -t ntfs-3g -o rw,uid=1000,gid=1000,windows_names /dev/sda2 /mnt && sudo umount /mnt`.

---

## 1. Fresh Arch install + LUKS (machine-specific notes)

Boot the Arch ISO, `iwctl`/ethernet to get online, `timedatectl`, then partition. The current
(pre-LUKS) layout for reference — a single NVMe `nvme0n1` (476.9 G), rEFInd bootloader, **zram**
swap (no swap partition), LVM:

```
nvme0n1p1  1G    vfat   /boot   (EFI system partition)
nvme0n1p2/3       LVM2   ArchinstallVg -> root (47G, ext4 /) + home (428G, ext4 /home)
zram0      7.6G  zram   swap    (managed by zram-generator, NOT a partition)
```

### LUKS target layout (LVM-on-LUKS)
Encrypt the big partition, put LVM inside it, keep an **unencrypted EFI partition** for the
bootloader:

```
nvme0n1p1  ~1G   vfat            EFI system partition (UNencrypted) -> /boot or /efi
nvme0n1p2  rest  crypto_LUKS     -> luksOpen -> LVM VG -> root (ext4 /) + home (ext4 /home)
```

```bash
cryptsetup luksFormat --type luks2 /dev/nvme0n1p2
cryptsetup open /dev/nvme0n1p2 cryptlvm
pvcreate /dev/mapper/cryptlvm && vgcreate ArchinstallVg /dev/mapper/cryptlvm
lvcreate -L 60G ArchinstallVg -n root
lvcreate -l 100%FREE ArchinstallVg -n home
mkfs.ext4 /dev/ArchinstallVg/root && mkfs.ext4 /dev/ArchinstallVg/home
mkfs.fat -F32 /dev/nvme0n1p1
```

Key install-time details specific to this box:
- **swap:** none on disk — keep using **zram**. Install `zram-generator` and drop
  `/etc/systemd/zram-generator.conf`:
  ```ini
  [zram0]
  zram-size = 7825
  compression-algorithm = zstd
  ```
- **mkinitcpio HOOKS** must include `encrypt` (before `lvm2`) and `lvm2`, e.g.
  `HOOKS=(base udev autodetect microcode modeset keyboard keymap consolefont block encrypt lvm2 filesystems fsck)`.
  Then `mkinitcpio -P`.
- **microcode:** `intel-ucode` (Intel CPU).
- **Bootloader = rEFInd** (this repo themes it). After `pacman -S refind` run `refind-install`.
  For LUKS you must pass the unlock + root to the kernel. Set in `/boot/refind_linux.conf` (or the
  rEFInd manual stanza) a `cryptdevice` line:
  ```
  "Boot"  "root=/dev/ArchinstallVg/root rw cryptdevice=UUID=<luks-partition-UUID>:cryptlvm ... quiet splash"
  ```
  Get the UUID with `blkid /dev/nvme0n1p2`. Keep the rEFInd `linux-fallback`/verbose entry
  (no `quiet splash`) as a recovery net.
- **Graphics = Intel iGPU + Wayland.** MUST install `mesa vulkan-intel intel-media-driver
  libva-intel-driver intel-ucode linux-firmware` (+ `lib32-mesa lib32-vulkan-intel` for Steam).
  Removing these has broken the login greeter before. Never strip GPU drivers.
- **Secure Boot:** do it *with* this LUKS reinstall if at all (was deliberately deferred until now).

### Networking (systemd-networkd — NOT NetworkManager)
NetworkManager is NOT installed. IP is done by **systemd-networkd** + **systemd-resolved**, Wi-Fi
auth by **iwd**. Enable all three: `systemctl enable systemd-networkd systemd-resolved iwd`.
`/etc/resolv.conf` is a symlink to `/run/systemd/resolve/stub-resolv.conf`.

Recreate `/etc/systemd/network/` (these are the Arch example units — Ethernet preferred over
Wi-Fi over WWAN via route metrics). The daily driver reaches the internet via a **USB-Ethernet
dongle** (enumerates as `enp0s13f0u1u1` / `en*`); Wi-Fi is `wl*` via iwd.

`20-ethernet.network`:
```ini
[Match]
Name=en*
Name=eth*
[Link]
RequiredForOnline=routable
[Network]
DHCP=yes
MulticastDNS=yes
[DHCPv4]
RouteMetric=100
[IPv6AcceptRA]
RouteMetric=100
```
`20-wlan.network`: same but `[Match] Name=wl*` and `RouteMetric=600`.
`20-wwan.network`: `[Match] Name=ww*`, `DHCP=yes`, `RouteMetric=700`.

Connect Wi-Fi: `iwctl` → `station wlan0 connect <SSID>`.

### Monitors
Laptop + up to 2 external displays. **The laptop panel is "main"/display 1 — NOT an external.**
Assignments live in `dotfiles/.config/hypr/hyprland.lua` (`hl.monitor{...}` + `hl.workspace_rule`):

| Output | Panel | Res / scale | Role | Workspaces |
|--------|-------|-------------|------|------------|
| `eDP-1` | AU Optronics (laptop) | 1920x1200, scale **1.5** | main / "Panasonic" | 1–3 |
| `DP-6`  | NZXT CANVAS 27Q | 2560x1440 | external | 4–6 |
| `DP-4`  | NZXT CANVAS 27Q | 2560x1440 | external | 7–9 |

Caveat: **DP port numbers (DP-4 / DP-6) can shift** depending on which dock port / cable each
monitor uses — if externals land on the wrong workspaces after reinstall, check
`hyprctl monitors` and update the port names in `hyprland.lua`. Both externals are the same model,
so you can't disambiguate them by EDID/description — only by port. Waybar runs two bars: a compact
one on `eDP-1` and a full one on the externals (`output: "!eDP-1"` — only the single-string negation
form works in this waybar build). Lid-close while docked disables `eDP-1` via `~/.local/bin/lid.sh`.

### The eva external drive
See §0. It's a **USB NTFS backup drive**, not part of the install — no fstab entry needed
(mounted on demand via `udisksctl`). `ntfs-3g` is in the package list so RW mounts work.

---

## 2. Reinstall exact packages

The curated package sets live in `packages/`: `base.txt` plus the vendor splits
`cpu-<v>.txt`, `gpu-<v>.txt`, `laptop.txt`, and `aur.txt`. `install/bootstrap.sh` reads
**those** (selecting the splits from hardware detection) — it does **not** read
`legacy/pkglist*.txt`. A per-host "what is actually installed" snapshot is harvested into
`hosts/<h>/packages/` by `bin/harvest.sh`.

> `legacy/pkglist.txt` / `legacy/pkglist-aur.txt` are the older panasonic snapshot
> (`pacman -Qqen` / `-Qqem` via `legacy/pkgs-snapshot.sh`). They are kept for that
> script only and are superseded by `packages/*.txt` and `hosts/<h>/packages/`.
> Both now start with a comment header, so do not pipe them into pacman.

```bash
sudo pacman -Syu --needed git base-devel

# Repo packages for THIS machine (panasonic = Intel laptop):
grep -hvE '^\s*(#|$)' ~/git/dotfiles/packages/{base,cpu-intel,gpu-intel,laptop}.txt | sort -u \
  | sudo pacman -S --needed -

# AUR helper, then AUR packages:
command -v paru || { tmp=$(mktemp -d); git clone https://aur.archlinux.org/paru.git "$tmp/paru";
  ( cd "$tmp/paru" && makepkg -si ); rm -rf "$tmp"; }
grep -hvE '^\s*(#|$)' ~/git/dotfiles/packages/aur.txt | paru -S --needed -
```

`bootstrap.sh` automates all of §2–§3 (same `packages/` files, plus `[multilib]`
enablement) and the system ricing — running it is equivalent to doing these sections by
hand. See `docs/new-machine.md`.

---

## 3. Nix + Home Manager bootstrap

Install Nix (either works; Determinate has a friendlier uninstaller and enables flakes by default):

```bash
# Official multi-user (what bootstrap.sh uses):
sh <(curl -L https://nixos.org/nix/install) --daemon --yes
#   — or Determinate Systems installer:
# curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# load nix into the current shell:
. /etc/profile.d/nix.sh 2>/dev/null || . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

Enable flakes (the official installer does NOT enable them globally — this rice passes the flag
per-invocation via `rice-switch`, but enabling once is convenient):
```bash
mkdir -p ~/.config/nix
printf 'experimental-features = nix-command flakes\n' >> ~/.config/nix/nix.conf
```

Clone the repo to the **exact path** the flake hardcodes (`modules/options.nix` builds every
dotfile symlink from the literal string `~/git/dotfiles` — a different clone path
leaves every symlink dangling):
```bash
git clone <repo-remote-or-eva-backup> ~/git/dotfiles
```

First Home-Manager apply, using the home-manager **pinned in `flake.lock`** (this is what
`install/bootstrap.sh` phase 3 does). The flake has one output per host,
`homeConfigurations."pj@<hostname>"`, so the attr is **`"pj@$(cat /etc/hostname)"`**
(there is no `hostname` binary on the hosts):
```bash
cd ~/git/dotfiles
nix --extra-experimental-features 'nix-command flakes' \
  build --no-link ".#homeConfigurations.\"pj@$(cat /etc/hostname)\".activationPackage"
HOME_MANAGER_BACKUP_EXT=bak "$(nix --extra-experimental-features 'nix-command flakes' \
  path-info ".#homeConfigurations.\"pj@$(cat /etc/hostname)\".activationPackage")/activate"
```
(`HOME_MANAGER_BACKUP_EXT=bak` is what `switch -b bak` does: files in the way are renamed
`*.bak` instead of aborting.) After that first run, `home-manager` is on PATH — from then
on **always use `rice-switch`** (never bare `home-manager switch`; it reads the stale
`~/.config/home-manager/home.nix` and once tore down every dotfile symlink).

The unpinned `nix run home-manager/master -- switch -b bak --flake ~/git/dotfiles#pj@$(cat /etc/hostname)`
also works, but whatever `master` is that day may not match `flake.lock`; prefer the pinned
build above.

---

## 4. Post-install checklist

```bash
# 4a. SSH: restore private hosts + generate a key for this device
mkdir -p ~/.ssh/config.d ~/.ssh/sockets && chmod 700 ~/.ssh ~/.ssh/sockets ~/.ssh/config.d
cp /run/media/pj/eva/.../config.d/*.conf ~/.ssh/config.d/     # from your §0 backup
ssh-keygen -t ed25519 -C "pj@panasonic"                       # passphrase -> Proton Pass
#   (~/.ssh/sockets is also auto-created by modules/desktop.nix's activation; ~/.ssh/config is a repo symlink)
#   enrol the new pubkey on the homelab hosts / jump box.
systemctl --user enable --now ssh-agent.service               # units ship with openssh

# 4b. Re-apply the rice (idempotent; also proves rice-switch works)
rice-switch
# Hyprland's exec-once owns swaync; mask the Arch package's duplicate user unit
# or every rice-switch will warn "user systemd session is degraded":
systemctl --user mask swaync.service

# 4c. System hardening (nftables default-deny, sysctl, DoT, hygiene tools, enables ly@tty2)
sudo bash ~/git/dotfiles/system/harden.sh

# 4d. Login manager + boot ricing
sudo bash ~/git/dotfiles/system/system-rice.sh     # rEFInd Catppuccin theme + single session
sudo bash ~/git/dotfiles/system/plymouth-setup.sh  # orbiting-dots splash
sudo bash ~/git/dotfiles/system/apply-ly.sh --anim none   # plain greeter — see WARNING below
sudo systemctl enable ly@tty2.service                             # (harden.sh also does this)

# 4e. Verify
hyprctl monitors                 # eDP-1 main + DP-6/DP-4 on right workspaces
networkctl status                # dongle/wlan routable
rice-theme catppuccin-mocha      # pick a theme (SUPER+T in-session); latte = light
```

### WARNINGS (learned the hard way)
- **ly `animation = dur_file` is BANNED** — it crashed the boot twice and forced ISO recovery on
  this exact hardware. `apply-ly.sh` refuses it. Only `none` (default) and `matrix` are
  accepted. If ly ever crashes at boot, suspect the animation first.
- Set `allow_empty_password = false` in `/etc/ly/config.ini` before enabling ly.
- **Never remove Intel graphics drivers** (see §1).
- After confirming everything works, reboot once and re-verify LUKS unlock + greeter + monitors.

---

## Recovery quick-reference (one screen)
```
LUKS:     cryptdevice=UUID=<p2>:cryptlvm in refind_linux.conf; encrypt+lvm2 in mkinitcpio HOOKS
swap:     zram only (zram-generator.conf, 7825M zstd)
net:      systemd-networkd + resolved + iwd; /etc/systemd/network/20-{ethernet,wlan,wwan}.network
monitors: eDP-1 main(1.5x) ws1-3 | DP-6 ws4-6 | DP-4 ws7-9  (port#s can shift -> hyprctl monitors)
pkgs:     packages/{base,cpu-intel,gpu-intel,laptop}.txt -> pacman ; packages/aur.txt -> paru  (or just bootstrap.sh)
nix:      clone to EXACTLY ~/git/dotfiles ; home-manager switch --flake ".#pj@$(cat /etc/hostname)" ; then rice-switch
ssh:      restore ~/.ssh/config.d/*.conf ; ssh-keygen -t ed25519 ; enable --user ssh-agent
harden:   sudo bash system/harden.sh   (never ly dur_file; never remove Intel drivers)
eva:      udisksctl mount -b /dev/sda2  (dirty flag -> mount -o ro, or clear via ntfs-3g)
```

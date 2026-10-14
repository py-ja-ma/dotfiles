# 1. Install

From the Arch ISO to a dram host: systemd-boot and a signed kernel image (UKI), btrfs with
snapshots you can boot, Secure Boot with our keys and Microsoft's, the roles' packages,
and Hyprland behind ly. The same steps install any machine; where cabin, lantern or
campfire differ, the step says so. The decisions behind it: `decisions/0010-install-path.md`
(the install script), `decisions/0011-disk-boot-secure-boot-snapshots.md` (disk, boot,
Secure Boot, snapshots), `decisions/0009-roles-and-host-shape.md` (roles),
`decisions/0017-cabin-bench-layout.md` (cabin's four disks, also `docs/platforms/bench/README.md`).

## Before you start

- **The Mac (lodge)** with this repo on `master`, a clean tree, and `bash bin/check.sh`
  green. A new host follows `master`'s release tags from its first `dram update`
  (chapter 4), so install from `master` after the newest release: a host installed from any
  other branch is moved back to the newest tag by that first update.
- **A USB stick** of 2 GB or more. Everything on it is erased.
- **Ethernet**, or the Wi-Fi name and password.
- **From Proton Pass:** the login password for the new host; for the laptop and admin
  presets also a LUKS passphrase (long — the TPM PIN replaces it day to day, §8).
- **The host file.** `modules/hosts/<name>.nix` exists for cabin (login `pj`), lantern
  (`ranger`) and campfire (`pj`): roles, login, LAN address. For a machine without one, the
  installer writes it from `--roles`, and chapter 2 commits it.
- **Which disk(s) to wipe.** The installer wipes only `--disk` (and, for cabin, the
  `--work-disk`), lists every disk first, refuses any disk that holds Windows, and asks you
  to type the disk's serial number. Everything else is untouched.

## 1. The ISO on a USB stick (on the Mac)

```sh
cd ~/git/dotfiles
bash install/get-iso.sh
# prints: OK /Users/pj/vm-bench/iso/archlinux-2026.10.01-x86_64.iso (sha256 + signature by 3E80CA1A8B89F69CBA57D98A76A5EF9054449A5C)
```

It downloads the ISO pinned in `install/iso.pin` and checks both its sha256 and Arch's
release signature (Pierre Schmitz's key). Then write it to the stick:

```sh
diskutil list external                     # the stick is /dev/diskN — check the size twice
diskutil unmountDisk /dev/diskN
sudo dd if=$HOME/vm-bench/iso/archlinux-2026.10.01-x86_64.iso of=/dev/rdiskN bs=4m status=progress
diskutil eject /dev/diskN
```

`dd` to the wrong disk destroys it: `diskutil list external` shows only removable disks.

## 2. Firmware settings (on the machine)

Enter setup (Del or F2 on most boards):

| Setting | Value | Why |
|---|---|---|
| Boot mode | UEFI only: CSM / Legacy **off** | systemd-boot and the UKIs are UEFI programs |
| Fast Boot | off | otherwise the USB stick and the boot menu are skipped |
| Secure Boot | **Setup Mode**: mode Custom, then delete / clear the Platform Key (the menu names vary). On MSI (cabin): Settings → Security → Secure Boot → mode Custom → Key Management: **Provision Factory Defaults → Disabled** first (or the board puts its keys back at the next reboot), then **Delete All Secure Boot Variables**; and **Secure Boot Preset → Maximum Security** (one dropdown on the same page; older MSI firmware calls it Image Execution Policy: Removable and Fixed Media → Deny Execute). MSI's default, "Hardware/OS Compatibility", runs unsigned code anyway (§8 proves it is off) | the unsigned ISO boots, and §8 enrolls our keys plus Microsoft's |
| TPM | on (fTPM on AMD, PTT on Intel) | the laptop's disk unlock |

Save, and boot the stick from the one-time boot menu (F12 on most boards, F11 on MSI): its UEFI entry.

cabin: install **Windows first**, alone on its 1 TB SATA disk, with the NVMe disks
disabled or unplugged (`docs/platforms/bench/README.md` §1), then come back here. Arch never touches that disk.

## 3. Boot the ISO and get online

Pick **Arch Linux install medium (x86_64, UEFI)**. A root shell appears.

```sh
cat /sys/firmware/efi/fw_platform_size     # prints: 64 — booted in UEFI mode
iwctl station wlan0 connect "<SSID>"       # Wi-Fi only (iwctl device list for the name); Ethernet needs nothing
ping -c 1 geo.mirror.pkgbuild.com          # prints: 1 packets transmitted, 1 received
```

To type the long commands below from the Mac instead: `passwd` (a throwaway root password
for this live session), `ip -4 addr` for its address, then `ssh root@<address>` on the Mac.

## 4. The repo into the ISO

On the Mac, on `master`, with a clean tree:

```sh
bash bin/serve-repo.sh
# Serving master at <sha> with <n> tag(s)
#   sha256 <64 hex>
# In the Arch ISO (as root):
#   curl -fO http://<the Mac's address>:8000/dotfiles.tar
#   sha256sum dotfiles.tar             # must print <64 hex>
#   mkdir /root/dotfiles && tar -xf dotfiles.tar -C /root/dotfiles
# Ctrl-C here when the download is done.
```

Type the three printed lines in the ISO. The sha256 must match what the Mac printed — it is
what proves the download is the tar the Mac made (a clone of `master` with its release
tags; the ISO has no git, so it travels as a tar). If macOS asks whether python3 may accept
incoming connections, allow it. Ctrl-C on the Mac once the download is done.

Without a network between them: `bash bin/serve-repo.sh --out /Volumes/<STICK>/dotfiles.tar`
on the Mac, then in the ISO `mkdir /media && mount /dev/disk/by-label/<STICK> /media` and the
two lines it printed (`sha256sum`, `tar -xf`).

## 5. Pick the preset and the disk(s)

| Preset | For | Layout |
|---|---|---|
| `bench` | cabin | NVMe 1 (`--disk`): ESP 4 GiB, btrfs system pool 512 GiB, btrfs data pool on the rest (games, the emulation tree, recordings — kept across reinstalls); NVMe 2 (`--work-disk`): one btrfs work pool (VMs, ML, containers, scratch). No disk encryption |
| `desktop` | campfire and other one-disk desktops | ESP 4 GiB, system pool 256 GiB, data pool on the rest. No disk encryption |
| `laptop` | lantern | ESP 4 GiB, LUKS2 + one btrfs pool, a swapfile the size of RAM (hibernation) |
| `admin` | headless homelab boxes | ESP 2 GiB, LUKS2 + one btrfs pool, zram swap |

(`vm-test` is the QEMU test's.) Find the disks by their stable names:

```sh
lsblk -do NAME,SIZE,MODEL,SERIAL,TRAN      # what is in the machine
ls -l /dev/disk/by-id/ | grep -v part       # the names to type: nvme-<model>_<serial>, ata-…
```

## 6. Dry run, then install

```sh
cd /root/dotfiles
bash install/arch-install.sh --preset <preset> --disk /dev/disk/by-id/<disk> --hostname <name> --dry-run
```

The dry run prints the preset, every disk with `WILL BE WIPED:` or `not touched:` beside it,
and every command it would run as `[dry-run] …`. Read the disk lines. Then the real run —
per machine:

```sh
# cabin — two NVMe; the SATA disks (Windows, the bench) are refused or untouched
bash install/arch-install.sh --preset bench --hostname cabin \
  --disk /dev/disk/by-id/nvme-<NVMe 1> --work-disk /dev/disk/by-id/nvme-<NVMe 2>
# lantern — its login is ranger (modules/hosts/lantern.nix)
bash install/arch-install.sh --preset laptop --hostname lantern --user ranger --disk /dev/disk/by-id/nvme-<disk>
# campfire
bash install/arch-install.sh --preset desktop --hostname campfire --disk /dev/disk/by-id/nvme-<disk>
# a machine with no host file yet: its roles, space separated (asked when omitted)
bash install/arch-install.sh --preset desktop --hostname <name> --roles "desktop dev" --disk /dev/disk/by-id/<disk>
```

It asks, in order: the serial of each disk it wipes (typed exactly), the LUKS passphrase
twice (laptop and admin), and the login password twice. Then it works through its steps
(output from the bench preset in the QEMU test, 2026-10-11):

```
###### 0) Preflight — preset bench: bench: NVMe 1 = ESP 4 GiB + system 512 GiB + data pool; NVMe 2 = work pool; no LUKS
  Disks on this machine:
    /dev/vda   40G  VMTEST1 virtio
    /dev/vdb   20G  VMWORK1 virtio
  WILL BE WIPED:  /dev/vda (system + data)
  WILL BE WIPED:  /dev/vdb (work pool)
###### 1) Partitions on /dev/vda
###### 3) Filesystems and subvolumes (decisions/0011)
###### 3b) Work pool on /dev/vdb
###### 4) Base system (pacstrap; the roles come later through dram apply)
###### 5) Configure the new system
###### 6) This repo and the host file
###### Done — vmtest is installed on /dev/vda
  Next: reboot, log in as pj, then:
    cd ~/git/dotfiles && bash install/bootstrap.sh
```

A refusal ends with a `**` line and changes nothing that is not already done: `holds
Windows … refusing` (the wrong disk), `serial not typed — nothing was changed`, `the mirrors
are unreachable` (the network). What it wrote: the ESP at `/efi` with systemd-boot and the
UKI, the btrfs subvolumes, `/etc/dram/install-facts.env` (what the first boot reads), this
repo at `~/git/dotfiles` (the host has no git remote; the Mac pushes to it), the user in
`wheel` with root locked, systemd-networkd + iwd (with the Wi-Fi the ISO knew).

```sh
reboot                                      # pull the stick when the screen goes dark
```

## 7. First boot: bootstrap

systemd-boot shows **Arch Linux** for three seconds (snapshot entries join it later). On the
laptop presets the disk asks for the LUKS passphrase. Log in on the console as the user.

First let the Mac in — `harden.sh` turns sshd to keys only and refuses while no key is
there:

```sh
sudo systemctl enable --now sshd            # on the new host
ip -4 addr | grep inet                      # its address (cabin and lantern have UniFi reservations)
ssh-keygen -R <address>                     # on the Mac, for a reinstalled host: forget its old host key
ssh-copy-id -i ~/.ssh/id_ed25519.pub pj@<address>   # on the Mac (ranger@ for lantern); the password once
```

Then the bootstrap, dry run first:

```sh
cd ~/git/dotfiles
bash install/bootstrap.sh --dry-run         # every phase as [dry-run] lines, then "(dry run: nothing was changed)"
bash install/bootstrap.sh
```

| Phase | What it does | What to answer |
|---|---|---|
| 0 Hardware | CPU, GPU, form factor, `Boot: systemd-boot (from /etc/dram/install-facts.env)`, the roles from the host file, the package files | `y` to "Use this detection?" |
| 1 Packages | enables `[multilib]`, one `pacman -Syu`, then `dram apply` (chapter 7): the roles' packages, the units, the role hooks | `y` to the install; for each `ask` hook see below |
| 2 `[dram]` | our signed package repo. On a fresh fleet it comes from cabin: on cabin, chapter 7 ("`[dram]` from scratch") builds it after this bootstrap; on the others `bin/sync-dram-repo.sh` from the Mac. Until then it prints `[dram] not synced on this host yet` — go on | — |
| 3 Nix + Home Manager | the pinned, sha256-checked Nix installer, then the user layer for `<user>@<name>` (the first build takes 10–30 minutes) | — |
| 4 Greeter | ly on tty2, one Hyprland session, `system/maintenance.sh` (hooks, timers) | — |
| 5 Early KMS | the GPU's kernel modules into the initramfs, the UKIs rebuilt | — |
| 6 Hardening | `system/harden.sh` again (`dram apply` already asked) | `n` if you answered `y` in phase 1 |

The `ask` hooks of `dram apply` (each asks "Run it?"):

| Hook | Answer |
|---|---|
| `system/harden.sh` | `y`, on the home network. The firewall allows SSH only from the LAN, which it writes once to `/etc/dram/lan.nft` from the subnet it finds (or `DRAM_LAN=<cidr>`): run elsewhere, it would lock SSH from home out at the next boot |
| `system/secureboot-setup.sh` | `y`: creates the keys and signs systemd-boot and the UKIs; it enrolls only in Setup Mode, where it asks you to type `microsoft` (§8) |
| `system/tpm2-enroll.sh`, `system/fido2-enroll.sh` (laptop) | `n` now — after Secure Boot is on (§8) and the YubiKeys are enrolled (chapter 2) |
| `system/yubikey-setup.sh` (desktop) | `y` is harmless: with no YubiKey listed it asks for nothing (chapter 2 switches it on) |
| `system/system-dram.sh` (desktop) | `y`: ly in the house palette, one Hyprland session |
| `system/dram-builder-setup.sh` (cabin) | `y`: the clean build chroot and `/srv/dram` (chapter 7, "`[dram]` from scratch") |
| `system/recording-setup.sh` (campfire) | `y`: the firewall opening for OBS from cabin |

`dram apply` also reports the `[dram]` names it could not install yet (`Gaming Mode`,
VSCodium, …): they come with the repo in phase 2. Afterwards:

```sh
exec bash -l
command -v dram                             # prints: /home/<user>/.local/bin/dram
dram doctor --brief                         # warnings only; Secure Boot and [dram] warnings are expected now
sudo reboot
```

ly shows the host's name and its session: **Hyprland**, or, once the gaming role's `[dram]`
packages are in, **Desktop** and **Gaming Mode** (`docs/toolchain/profiles/gaming.md`). Log in.

## 8. Secure Boot, then the laptop's disk

If the firmware is not in Setup Mode yet, do §2's Secure Boot row now. Then:

```sh
sudo bash ~/git/dotfiles/system/secureboot-setup.sh
# ==> firmware is in Setup Mode: enroll our keys + Microsoft's (+ the firmware vendor's when it has a default db)
#     Enroll now? Type 'microsoft' to confirm Microsoft's keys go in too: microsoft
# Enrolled keys to the EFI variables!
# [ok] enrolled. Reboot; the firmware enforces Secure Boot from now on (turn it on in setup if it does not)
```

Microsoft's keys always go in: graphics cards' firmware and Windows' boot manager are signed
by Microsoft, and cabin has no other graphics to fall back to. Reboot, set Secure Boot to
**Enabled** in setup if it is not, and check:

```sh
sudo bootctl status | grep 'Secure Boot'    # prints: Secure Boot: enabled (user)
sudo sbctl verify                           # every file under /efi: ✓ signed (the ESP is root-only)
```

"Enabled" is what the firmware reports, not proof that it checks anything (cabin's MSI
board ran unsigned images with it until the Secure Boot Preset was Maximum Security). Prove
it, both halves:

```sh
# removable media: the firmware's boot menu (F12 / F11 on MSI) -> the Arch ISO stick's UEFI entry
#   -> refused ("image is unsigned" or a Secure Boot violation); then boot Arch normally
# fixed media: an unsigned loader on the ESP, booted once
sudo bash ~/git/dotfiles/system/secureboot-test.sh --arm     # armed: Boot<n> runs once at the next boot
sudo reboot                                                  # press Enter if the firmware reports an unsigned image
sudo bash ~/git/dotfiles/system/secureboot-test.sh --check   # [ok] the firmware refused the unsigned image …
```

`sbctl status` may still print `FQ0001` on an MSI board: sbctl infers that quirk from the
board model and BIOS date and cannot read the setting — the two tests above are the answer.

The laptop: the TPM and its PIN unlock the disk from now on, with a recovery key beside them.

```sh
sudo bash ~/git/dotfiles/system/tpm2-enroll.sh
# ==> recovery key (shown once — store it in Proton Pass NOW)
# ==> TPM2 + PIN, bound to PCR 7          — the new PIN, twice
```

Reboot: the disk asks "Please enter LUKS2 token PIN" — the TPM PIN. Keep the passphrase
slot until both the PIN and the recovery key have opened the disk once. The YubiKeys join
in chapter 2 (`system/fido2-enroll.sh`).

cabin: Windows boots from `dram boot-to windows` or the firmware's boot menu. If Windows
turned on device encryption, it asks once for its BitLocker recovery key after the key
change (in the Microsoft account it was set up with).

## 9. Verify

```sh
dram doctor                                 # every section; warnings name their fix
dram doctor --boot                          # plus the ESP and the boot entries
sudo snapper -c root list | tail -3         # pre/post pairs from the bootstrap's pacman runs
sudo ls /efi/EFI/Linux/                      # arch-linux.efi, arch-linux-fallback.efi, arch-snap-<n>.efi …
```

Expected now, not defects: `[dram]` names reported missing until the repo is synced
(chapter 7), the yubikeys section until chapter 2, and `backups are paused until the NAS`.

## Done when

- [ ] `sudo bootctl status` prints `Secure Boot: enabled (user)`; systemd-boot lists Arch Linux and snapshot entries
- [ ] ly logs you in to Hyprland
- [ ] `command -v dram` prints `~/.local/bin/dram` in a login shell
- [ ] `dram doctor` shows only the expected warnings above
- [ ] `dram apply --dry-run` prints `every declared package is installed` (after chapter 7 on a fresh fleet)
- [ ] the Mac reaches the host: `ssh <user>@<address> true` from the Mac exits 0
- [ ] laptop: the TPM PIN opens the disk, and the recovery key is in Proton Pass
- [ ] a machine that had no host file: `modules/hosts/<name>.nix` committed (chapter 2)

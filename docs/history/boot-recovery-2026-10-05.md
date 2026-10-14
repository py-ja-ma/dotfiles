# Boot recovery (UEFI + rEFInd, GRUB fallback) on Arch

Written after recovering `cabin` on 2026-10-05 following a motherboard swap and an
NVMe move to a different M.2 slot; extended the same evening when cabin moved from
GRUB to rEFInd (GRUB kept as the firmware-menu fallback). A short lantern section is
at the end.

## Layout on cabin

- ESP is `nvme0n1p1`, vfat, UUID `C8E7-E87A`, **mounted at `/boot`** (not `/boot/efi`)
- Kernels, initramfs, `amd-ucode.img`, `grub/`, `EFI/refind/` (plus its
  `themes/letterpress/`, rendered by `system/apply-refind.sh`) and `refind_linux.conf` all live directly on the ESP
- `refind_linux.conf` holds the kernel options rEFInd uses for each auto-detected kernel
  (`linux` and `linux-lts` → two entries). The stanzas rely on the **`microcode`
  mkinitcpio hook** to load `amd-ucode`; there is **no** `initrd=amd-ucode.img` line, and
  adding one by hand is unnecessary.
- `/EFI/refind/refind_x64.efi` is the loader the `rEFInd` NVRAM entry points at;
  `/EFI/GRUB/grubx64.efi` is GRUB (its own NVRAM entry, second in BootOrder);
  `/EFI/BOOT/BOOTX64.EFI` is the removable-path copy of GRUB
- Root is `nvme0n1p2` ext4, UUID `364a3692-e5aa-456a-9862-22df230fa0d8`
- `/home` is `nvme0n1p3` ext4
- `nvme0n1p4` / `p5` are leftover Windows LDM-metadata and MSR partitions. Harmless. Leave them.
- `/etc/fstab` references everything by **UUID**, so moving the drive between slots
  does not break it.

## What broke after the motherboard swap

Two independent failures:

1. **No firmware boot entry for GRUB.** GRUB had originally been installed with
   `grub-install --removable`, which writes the loader to `\EFI\BOOT\BOOTX64.EFI`
   and deliberately creates **no** NVRAM entry. The old board happened to try that
   fallback path on a fixed disk; the new board did not. Compounding it, `BootOrder`
   led with `BBS(HD,...)` legacy-CSM entries that tried to legacy-boot the NVMe
   (no MBR boot code, dead end), then a stale `Windows Boot Manager` entry pointing
   at a `bootmgfw.efi` whose Windows volume no longer exists.

2. **Initramfs built against the old hardware.** `HOOKS` contains `autodetect`,
   which strips every storage module not present at build time. The images were
   months old, so they could have lacked the module needed to see the root device.

## Recovery procedure

Boot the **Arch ISO in UEFI mode** (`[ -d /sys/firmware/efi ]` must be true -
`efibootmgr` cannot write EFI variables from a CSM/BIOS-booted session).

```sh
mount /dev/nvme0n1p2 /mnt
mount /dev/nvme0n1p1 /mnt/boot          # ESP at /boot on this host

# GRUB (the fallback): creates /EFI/GRUB/grubx64.efi AND an NVRAM entry
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot \
    --bootloader-id=GRUB --recheck

# also refresh the removable fallback path, belt and braces
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot \
    --removable --recheck

arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# rEFInd (the default): recreates the NVRAM entry and refreshes /EFI/refind/.
# It keeps the existing refind.conf (theme include and all) and does not touch
# refind_linux.conf when one is already present.
arch-chroot /mnt refind-install

# rEFInd first, GRUB second. Get the four-digit IDs from `efibootmgr` first.
efibootmgr -o <refind>,<grub>

# rebuild initramfs against the NEW hardware (autodetect sees the live machine)
arch-chroot /mnt mkinitcpio -P
```

Verify before rebooting:

```sh
efibootmgr                                      # the rEFInd entry must lead BootOrder; GRUB second
find /mnt/boot/EFI -iname '*.efi'               # /EFI/refind/refind_x64.efi, /EFI/GRUB/grubx64.efi
                                                # and /EFI/BOOT/BOOTX64.EFI must all be present
arch-chroot /mnt lsinitcpio /boot/initramfs-linux.img | grep -E 'nvme|nvidia|plymouthd|nouveau'
#   cabin: nvme driver present, nvidia*.ko x4 (nvidia, nvidia_modeset, nvidia_uvm,
#   nvidia_drm), plymouthd present, and ZERO nouveau lines
```

Then in firmware setup: **CSM off / UEFI-only**, **Secure Boot off** (rEFInd and GRUB
are unsigned).

## If rEFInd's menu is broken

rEFInd misconfigured (bad theme include, broken `refind_linux.conf`, stale binary) is
recovered **without** an ISO because GRUB is still installed with its own NVRAM entry:

- At power-on, open the firmware boot menu — **F12** on cabin's Gigabyte board (**Del**
  for setup) — and pick **`GRUB`** (`Boot0001`), or the **`UEFI OS`** removable entry,
  which is `\EFI\BOOT\BOOTX64.EFI` (also GRUB). Either boots the same kernels from
  `/boot/grub/grub.cfg`.
- From a running system, `sudo efibootmgr -n 0001` sets a **one-shot** `BootNext` to
  GRUB for the next reboot only; BootOrder is untouched, so rEFInd is back the time
  after.
- GRUB shows **no Plymouth splash** — expected. Its kernel line has no `splash`; you
  get verbose boot straight into ly.
- Once in, fix rEFInd (restore `refind.conf.bak-*` / `refind_linux.conf.bak-*` on the
  ESP, or re-run `sudo refind-install` + `sudo bash system/apply-refind.sh cabin`, see `docs/boot-chain.md`) and check
  `efibootmgr` still lists rEFInd first.

## Gotchas worth remembering

- **`grub-install` is not re-run on package upgrade.** After `grub` 2.14 -> 2.16 the
  ESP still held the 2.14 `grubx64.efi` while `/boot/grub/*.mod` were 2.16. That
  core/module mismatch can fail to boot. **Always re-run `grub-install` after a
  GRUB version bump.** See `docs/arch-upgrade.md`.
- **rEFInd's ESP copy is refreshed only by `system/99-refind.hook`** (the `refind`
  package ships no pacman hook). `install/bootstrap.sh` phase 4 installs it to
  `/etc/pacman.d/hooks/`; make sure it is there (`ls /etc/pacman.d/hooks/`) or a
  `refind` upgrade leaves a stale `refind_x64.efi` on the ESP — the GRUB failure
  mode above, in rEFInd form.
- **Never use `grub-install --removable` as the only install** on an internal disk.
  It creates no NVRAM entry, so you are relying on firmware fallback behaviour.
- A `--removable` install is still useful *alongside* the real one as a backup path.
- The fallback initramfs (no `autodetect`, every module) is the thing that saves you
  after a hardware change. It is enabled on `cabin` via `PRESETS=('default' 'fallback')`
  in `/etc/mkinitcpio.d/linux-lts.preset`, so it rebuilds automatically on kernel updates.
- ESP is only 1 GiB. Two kernels + two initramfs + one fallback image is ~512 MiB.
  Adding a second fallback would get tight.

## lantern

rEFInd only — no GRUB installed. Root is **LVM** (`/dev/ArchinstallVg/root`), which
`refind_linux.conf` names by device path (not UUID); the file has the standard
(`quiet splash ...`) line plus a verbose fallback line. Since 2026-10-05 (evening):

- `/EFI/BOOT/BOOTX64.EFI` is a **copy of rEFInd**, so a lost NVRAM entry still boots
  through the firmware's removable path.
- `/etc/mkinitcpio.d/linux.preset` has `PRESETS=('default' 'fallback')`, so an
  `initramfs-linux-fallback.img` exists and is rebuilt on every kernel update.

Recovery is the rEFInd part of the procedure above with `vgchange -ay` before mounting
root, and `arch-chroot /mnt refind-install` as the only loader step.

# Boot chain

[Platforms](../../README.md) › [Arch Linux](../README.md) › Boot chain

An Arch host boots rEFInd, then a signed kernel image (UKI), then the Plymouth splash, then the ly greeter, then Hyprland.
systemd-boot sits behind rEFInd for the fallback and snapshot images, and the firmware falls back to it when rEFInd fails.
Every script here takes `--dry-run`, writes a file only when its content changes, and keeps the previous one once as `<file>.bak-<stamp>`.

| | |
|---|---|
| Code | `system/system-dram.sh`, `system/apply-refind.sh`, `system/99-refind.hook`, `system/plymouth-setup.sh`, `system/apply-ly.sh`, `system/uki-presets.sh`, `system/snapshots-setup.sh`, `system/dram-snapshot.sh`, `system/snapper/`, `system/hooks/00-dram-snap-pre.hook`, `system/hooks/zz-dram-snap-post.hook`, `system/initcpio/dram-volatile` |
| Runs on | every Arch host on its own hardware with the installer's UKI layout; the WSL clones have no boot chain |
| Needs | refind, ly 1.4.1, plymouth, mkinitcpio, systemd-boot, snapper, btrfs-progs, sbctl once Secure Boot is set up; tested on cabin 2026-10 |
| Decided in | [decision 0011](../../../decisions/0011-disk-boot-secure-boot-snapshots.md); Windows' entry: [decision log](../../../decisions/log.md#d66) |

## How it works

```
firmware (Secure Boot: my keys and Microsoft's)
  └─► rEFInd, signed (the letterpress theme, 4 tiles, 3 s)
        ├─► Arch Linux        /EFI/Linux/arch-linux.efi       (signed UKI: the plymouth hook, early KMS,
        ├─► Arch Linux LTS    /EFI/Linux/arch-linux-lts.efi    "quiet splash" in its command line)
        │     └─► Plymouth "letterpress"
        │           └─► ly@tty2
        │                 └─► Hyprland
        ├─► Windows           its own firmware entry on WIN-ESP, started by BootNext
        └─► Snapshots & recovery   systemd-boot's menu: the verbose fallback UKIs, the snapshot UKIs
```

`dram apply` runs `system/system-dram.sh` once Secure Boot and the disk-unlock enrolments are done, since both change the kernel command line.
It runs four steps in boot order:

| Step | Script | What it writes |
|---|---|---|
| 1 | `system/apply-refind.sh` | `<ESP>/EFI/refind/refind_x64.efi`, signed by sbctl; the theme; `refind.conf`; `/usr/local/lib/dram/refind-update` with its pacman hook `99-refind.hook`; `dram-refind-first.service`; the NVRAM entry `rEFInd` first in the boot order |
| 2 | `system/plymouth-setup.sh` | the splash theme in `/usr/share/plymouth/themes/`, the `plymouth` hook after `systemd`, the splash words in `/etc/kernel/cmdline`, `/etc/kernel/cmdline.fallback` without them; then `mkinitcpio -P` when something changed |
| 3 | `system/apply-ly.sh` | `/etc/ly/config.ini`, or `config.lua` where the installed ly ships one |
| 4 | inside `system-dram.sh` | one Hyprland session in the greeter, and `NoExtract` for `hyprland-uwsm.desktop` so an upgrade can't bring the second one back |

The colors, the wordmark and the themes themselves are Design's, under [Shell & bars](../../design/shell-and-bars/README.md); the boot chain only installs them.
Secure Boot, the signing of each UKI and lantern's TPM2 unlock are [Boot trust](../../security/boot-trust/README.md).

### rEFInd in front

`refind.conf` has `scanfor manual`, `timeout 3`, `use_nvram false`, `default_selection "Arch Linux"` and one entry per boot target found on the ESP.
The UKIs carry their own signed command line, so the entries pass no options.
The fallback and snapshot UKIs stay behind "Snapshots & recovery", which keeps the menu at four tiles.

Windows boots from its own ESP, labeled WIN-ESP on the 1 TB SSD, since 2026-10-12.
Its tile asks the firmware to start Windows' own entry (`firmware_bootnum`), so rEFInd never loads Windows' boot manager and BitLocker's measurements don't change when rEFInd does.
Without a WIN-ESP the tile loads `/EFI/Microsoft/Boot/bootmgfw.efi` from Arch's ESP, as it did before the move ([boot guard](../windows/boot-guard.md)).

The binary on the ESP is sbctl's signed copy of `/usr/share/refind/refind_x64.efi`.
On every `refind` upgrade the pacman hook runs `refind-update`, which signs it again, or copies it on a host without sbctl keys.
The MSI firmware reshuffles the boot order whenever drives come or go: plugging in two old drives put rEFInd last on 2026-10-12.
`dram-refind-first.service` runs `/usr/local/lib/dram/refind-first` at every boot and moves rEFInd back to the front, moving nothing else.
Windows has the same guard ([boot guard](../windows/boot-guard.md)).

### The splash and the greeter

Plymouth's theme shows the wordmark and a 1 px rule that grows with the boot's progress; a script error never blocks the boot.
The fallback UKIs are built from `/etc/kernel/cmdline.fallback`, so they stay verbose and load every module.
Early KMS must be in the initramfs already, from bootstrap's phase 5, or the splash shows late.

Every ly release up to v1.5.0 (2026-10-04), the Arch package 1.4.1 included, reads `/etc/ly/config.ini`; only upstream's development branch reads `config.lua`.
`apply-ly.sh` writes Lua when the installed package ships `/etc/ly/config.lua` and the ini file otherwise, using only keys that 1.4.1 and 1.5.0 share.
It sets the house palette, a big clock, the host name as the title, no animation, and an empty `dur_file_path` with any `/etc/ly/*.dur` removed.
The `dur` animation faulted the greeter at boot twice on 2026-07-02 and forced a recovery from the ISO, so the script refuses it.
The terminal comes from the `ly@tty2` unit; there is no `tty` key.
`system/harden.sh` calls `apply-ly.sh` instead of editing the file, so the greeter has one writer.

### Snapshots

`system/snapshots-setup.sh` turns on snapshots on a host with the installer's btrfs layout, skipping one without it:

- snapper's `root` and `home` configs from `system/snapper/`, on the `@snapshots` and `@home_snapshots` subvolumes;
- the helper `/usr/local/lib/dram/dram-snapshot`, from `system/dram-snapshot.sh`;
- two pacman hooks: `00-dram-snap-pre.hook` takes a snapshot before every transaction, `zz-dram-snap-post.hook` the matching one after;
- the snapper timers: a daily and weekly safety net for `/home`, and the cleanup.

After each transaction the helper builds one signed UKI for each of the newest five "pre" snapshots, from that snapshot's own kernel and modules, and removes stale ones.
A snapshot entry boots read-only with a throwaway overlay (`systemd.volatile=overlay`).
`system/initcpio/dram-volatile` adds what the overlay needs to those images only: without it a snapshot entry hung at the end of the initramfs in the rollback test (`tests/t3-vm.sh`) on 2026-10-11.
`dram rollback --system N` makes snapshot N the new root and keeps the broken one as `@.broken-<stamp>` until you delete it.
The helper replaces snap-pac, which has had no release since 2021.

## Apply

`dram apply` runs it all and asks first.
By hand, dry run first:

```sh
cd ~/git/dotfiles
sudo bash system/system-dram.sh --dry-run        # the diffs of steps 1 to 3
sudo bash system/system-dram.sh                  # rEFInd, Plymouth and mkinitcpio -P, ly, one session
sudo bash system/apply-refind.sh                 # one step: the menu, the theme, the hook, the boot order
sudo bash system/plymouth-setup.sh               # one step: the splash, then the UKIs rebuilt
sudo bash system/apply-ly.sh                     # one step: the greeter, at the next logout
sudo bash system/snapshots-setup.sh --dry-run    # snapshots: what would change
```

## Verify without rebooting

```sh
sudo -v; dram doctor --boot                      # rEFInd first, systemd-boot behind it, everything signed, the splash
efibootmgr | head -3                             # BootOrder starts with rEFInd's number
sudo grep -E '^(timeout|scanfor|default_selection|include|menuentry)|loader|firmware_bootnum' /efi/EFI/refind/refind.conf
sudo sbctl verify | grep -E 'refind|EFI/Linux'   # all signed
plymouth-set-default-theme                       # prints: letterpress
cat /etc/kernel/cmdline /etc/kernel/cmdline.fallback
sudo objcopy -O binary --only-section=.cmdline /efi/EFI/Linux/arch-linux.efi /dev/stdout; echo   # the UKI's own: … quiet splash …
sudo /usr/local/lib/dram/dram-snapshot list      # the snapshots, and which have a boot entry
```

Then reboot: rEFInd's menu for 3 s, the splash, ly.

## Recovery

Every layer has a way around it, from the mildest to the ISO.

| What you see | Do |
|---|---|
| rEFInd's menu is missing, broken or not first | the firmware starts systemd-boot by itself; or F11 at power-on, then Linux Boot Manager; then `sudo bash ~/git/dotfiles/system/apply-refind.sh` |
| an image refused ("Security Violation", or the firmware skips it) | boot through systemd-boot (F11), then `sudo sbctl verify` and `sudo sbctl sign-all`; for rEFInd itself, `sudo /usr/local/lib/dram/refind-update` |
| the splash hangs, or a black screen before ly | rEFInd, Snapshots & recovery, then a fallback entry: verbose, no splash, every module; read where it stops |
| an update broke the system | rEFInd, Snapshots & recovery, then an Arch snapshot entry; then `dram rollback --system N` |
| ly misbehaves | Ctrl+Alt+F1 is a plain getty; restore the `.bak`, or run `apply-ly.sh` again |
| nothing boots at all | the Arch ISO with Secure Boot on ([handbook chapter 11](../../records/handbook/11-troubleshooting.md)): mount, `arch-chroot`, fix |

- Each script leaves the previous file beside the new one (`refind.conf.bak-<stamp>`, `/etc/kernel/cmdline.bak-<stamp>`, the mkinitcpio and preset files).
  Copy one back, then run `sudo mkinitcpio -P` for anything under `/etc/mkinitcpio*` or `/etc/kernel`.
- To take rEFInd out of the way for good: `sudo efibootmgr -o <Linux Boot Manager>,…`; `dram boot-to list` shows the numbers.
- To drop the splash: `sudo sed -i 's/ quiet splash.*//' /etc/kernel/cmdline && sudo mkinitcpio -P`.
- The old themes stay installable: `sudo bash system/apply-refind.sh --theme catppuccin` and `sudo bash system/plymouth-setup.sh --theme catppuccin`.
- After a BIOS update, a CMOS clear or "Load Defaults", the Secure Boot preset and keys may be back at the factory state: [handbook chapter 1](../../records/handbook/01-install.md) §2 and §8, and `system/secureboot-test.sh`.
- `maintenance.sh` warns when `/etc/pacman.d/hooks/99-refind.hook` is missing, which would leave rEFInd's ESP copy unsigned after an upgrade.

## Limits

- `apply-refind.sh` and `plymouth-setup.sh` handle only the UKI layout `install/arch-install.sh` makes; on an older rEFInd-only install they refuse.
- Snapshots cover `/` and `/home` only; the data and work pools have none.
- A rollback keeps the broken root until you delete it, and the snapshots share the disk with the system pool.

# lantern

The travel laptop, an Intel machine with Arch Linux and Hyprland.
Until its reinstall from this repo it runs its old install, under the name panasonic, and this directory holds that install's records.
The reinstall takes the laptop preset: LUKS2 with TPM2 and a PIN, btrfs, hibernation, systemd-boot with signed UKIs ([Install](../../docs/platforms/arch/install.md)).

| | |
|---|---|
| CPU | Intel TigerLake-LP GT2 |
| GPU | Intel Iris Xe, `i915` (`xe` also loads but binds no device) |
| Boot | UEFI, then rEFInd, then Plymouth (letterpress), then `ly@tty2`, then Hyprland through `hyprland.desktop` |
| Root | LVM: `/dev/ArchinstallVg/root`, ext4, on two physical volumes (`nvme0n1p2` and `p3`); no LUKS |
| ESP | `nvme0n1p1`, vfat at `/boot`, about 1 GB |
| Kernels | `linux` only |
| Swap | zram-generator, `zram-size = 7825` (15.6 GB of RAM) |
| Battery | `BAT1`, not `BAT0` |
| Panel | `eDP-1` 1920x1200 at scale 1.5, plus the two NZXT CANVAS 27Q matched by description when docked (`monitors-pin.sh`, once, docked) |
| Network | systemd-networkd and iwd, no NetworkManager; a USB Ethernet dongle and Wi-Fi |
| Firewall and SSH | nftables with policy `drop`; `system/harden.sh` applied 2026-10-06: SSH and LocalSend from the LAN, sshd keys-only. The ruleset it replaced carried SIP and RTP rules (UDP 5060, 16384 to 32768) for the Yate lab that `system/nftables.conf` doesn't have; add them there if that work resumes |
| Packages | takes the `[dram]` repo built on cabin through `bin/sync-dram-repo.sh` from the Mac; no foreign packages |

## Fixed on 2026-10-05

Two fixes made on the old install, which its reinstall makes moot:

- `systemd-networkd-wait-online` waited for every link, including the unplugged Ethernet, so the graphical target came up two minutes late and every login sat on a countdown.
  A drop-in, `/etc/systemd/system/systemd-networkd-wait-online.service.d/any.conf`, passes `--any --timeout=20`.
- A second greeter, `ly@tty1`, had been enabled since July and took the console's getty with it; it was disabled and `getty@tty1` restored.

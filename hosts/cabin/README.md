# cabin

The desktop: every role but ml-cuda, the `[dram]` package builder, and the bench for every operating system ([decision 0017](../../decisions/0017-cabin-bench-layout.md)).
Arch was reinstalled from a blank disk on 2026-10-11, and Windows 11 installed beside it on its own disk on 2026-10-12.

| | |
|---|---|
| Board | MSI B550 (MS-7C56), BIOS 07/22/2026; Del for setup, F7 for advanced, F11 for the boot menu |
| CPU / GPU | AMD Ryzen 9 5950X (no integrated GPU) / NVIDIA RTX 3080 Ti (`nvidia-open`, `nvidia-open-lts`; early KMS, `nvidia_drm.modeset=1`) |
| Disks | 990 PRO 2 TB (the CPU's slot, PCIe 4): ESP 4 GiB at `/efi`, btrfs system pool 512 GiB, data pool; 990 EVO Plus 2 TB (the chipset's slot, PCIe 3): the work pool; 870 EVO 2 TB SATA: the bench, blank until `system/bench-disk.sh`; MX500 1 TB SATA: Windows 11 with its own ESP, labeled WIN-ESP ([Bench OSes](../../docs/platforms/bench/README.md)) |
| Boot | rEFInd in front of systemd-boot, signed UKIs for `linux` and `linux-lts` with their fallbacks and snapshot entries, Windows through its own firmware entry ([Boot chain](../../docs/platforms/arch/boot-chain.md)); Secure Boot with my keys, Microsoft's and the board's, Secure Boot Preset "Maximum Security": an unsigned USB image and an unsigned ESP loader are refused (`system/secureboot-test.sh`) |
| TPM | AMD fTPM, unused (no disk encryption); systemd 262's NvPCR units fail, an upstream issue that `dram doctor` shows as `[i]` |
| Network | NetworkManager, wired `enp42s0`, a fixed address on the home LAN (a UniFi reservation); `system/harden.sh` ran on 2026-10-13: the default-deny ruleset with SSH and LocalSend from the LAN only, sshd keys-only (`docs/security/network/firewall.md`) |
| Case | Antec Flux Pro (Noctua Edition); its panel shows the CPU and GPU temperatures from `dram-case-display` on Arch and `case-display.ps1` on Windows ([pkgs/dram-case-display/README.md](../../pkgs/dram-case-display/README.md)) |
| Packages | the `[dram]` builder (`/srv/dram`, chroot `/var/lib/archbuild/dram-x86_64`), signing key `044DFA31C5CD72299A1460B56EF00BFB391BD348` (2026-10-11, expires 2028-10-10) |
| YubiKeys | the primary enrolled for SSH and age; its pam-u2f line and the spare key come next ([YubiKeys](../../docs/security/identity/yubikeys.md)) |

## Monitors

| Output | Monitor | Mode | Position |
|---|---|---|---|
| `DP-1` | NZXT CANVAS 27Q, the left one | 2560x1440 at 165 Hz | `0x0` |
| `HDMI-A-1` | NZXT CANVAS 27Q, the right one | 2560x1440 at 144 Hz | `2560x0` |

`hyprland.lua` names both panels by description from `~/.config/dram/monitors.lua`, which `monitors-pin.sh` wrote on cabin, so the rules follow the panels from port to port.
With no battery, workspaces 1 to 6 go to the left panel and 7 to 9 to the right one; the laptop's panel rule applies only on a machine with a battery.
Windows runs the panels at the same rates.

## The case display, first install

```sh
dram pkgs check dram-case-display && dram pkgs build dram-case-display && dram pkgs publish
dram update       # refreshes pacman's lists, so the new package is seen
dram apply        # installs it from [dram] (packages/host-cabin.txt)
sudo udevadm trigger --action=add --attr-match=idVendor=2022 --attr-match=idProduct=0522   # or reboot
```

pacman's systemd hooks create the group and reload udev, but a panel that is already plugged in gets the new rule only after the trigger or at the next boot.
cabin's panel is revision A: bcdDevice `0006`, one interrupt OUT endpoint `0x03`, no kernel driver.
It has shown both temperatures on Arch and on Windows since 2026-10-12.

## Firmware

The latest BIOS comes from M-Flash, since Windows Update's firmware class is denied and LVFS has nothing for this board.
After a BIOS update, a CMOS clear or "Load Defaults", boot Arch first: the Secure Boot preset and keys may be back at the factory state ([handbook chapter 1](../../docs/records/handbook/01-install.md), §2 and §8).
"MSI Driver Utility Installer" stays off in the BIOS: it hands Windows a bundle of vendor apps on a fresh install.

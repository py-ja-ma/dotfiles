# Windows

[Platforms](../README.md) › Windows

Windows 11 runs on two PCs: cabin-win, alone on cabin's 1 TB SATA SSD beside Arch, and thermos, the travel laptop.
Each PC is declared in the flake like an Arch host: a host file names its roles, the roles carry the settings, and the `packages/winget/` lists carry the apps.
The flake renders that into a committed build, and `dram.ps1` on the PC applies it.
Arch owns the boot order: Windows boots from its own firmware entry and puts rEFInd back in front when its updates move it.

| Branch | What it does | Code | Copy alone |
|---|---|---|---|
| [Renderer](renderer.md) | turns a Windows host file, its roles and lists into winget configuration documents and a manifest of every file the PC needs | `windows/`, `bin/render-windows.sh`, `packages/winget/` | yes, with Nix and your own host file ([windows/README.md](../../../windows/README.md)) |
| [dram.ps1](dram-ps1.md) | `dram` on the PC: receives a release, applies it phase by phase, reports drift, rolls back | `install/windows/dram-windows/dram.ps1`, `converge.ps1`, `apply-live.ps1`, `install/windows/apply-windows.sh` | yes, with a build in the manifest's format ([install/windows/dram-windows/README.md](../../../install/windows/dram-windows/README.md)) |
| [Debloat and autostart](debloat.md) | removes the declared bloat and switches off whatever starts by itself unless it is declared | `install/windows/dram-windows/debloat.ps1`, `autostart.ps1`, the base role's privacy policies | yes, after editing its lists |
| [Boot guard](boot-guard.md) | keeps rEFInd first in the firmware's boot order, gives Windows its own ESP, keeps Windows away from Secure Boot and the firmware | `install/windows/dram-windows/boot-guard.ps1`, `own-esp.ps1`, `system/windows-esp-retire.sh` | only on a PC that dual-boots with rEFInd |
| Case display | drives cabin's case temperature panel from Arch and from Windows | `pkgs/dram-case-display/`, `install/windows/dram-windows/case-display.ps1` | its page: [pkgs/dram-case-display/README.md](../../../pkgs/dram-case-display/README.md) |

## How the branches fit

I edit a host file, a role or a list on the Mac, run `bin/render-windows.sh`, and commit the build in `windows/build/<host>/`.
`bin/push-windows.sh <host> --apply` stages the release in `C:\ProgramData\dram` over Windows' OpenSSH, and `dram.ps1` there checks every file's sha256, switches to the release and converges.
The converge runs in phases: debloat, the machine's settings, the user's settings, the apps, what starts by itself.
The boot guard and the case display are Script units of cabin-win's host file: SYSTEM tasks the converge installs, which run at every start.
Why Windows comes from the flake at all: [decision 0020](../../../decisions/0020-windows-from-the-flake.md).

## The PCs

| PC | Hardware | Roles | State (2026-10-13) |
|---|---|---|---|
| cabin-win | cabin's Crucial MX500 1 TB; Windows 11 Pro, activated, version 26H2 | desktop, chat, gaming, creator, office, college, dev, sysadmin | converged from the flake; `dram doctor` finds no drift |
| thermos | Lenovo ThinkPad L14 Gen 1 AMD: Ryzen 5 PRO 4650U, 32 GB, a 512 GB NVMe; Windows 11 Pro 25H2 | base, desktop, chat, office, college, dev, sysadmin, re-lab, once rendered | not managed yet: reviewed 2026-10-12, reset planned |

The Arch clone in WSL 2 on each PC is the [WSL](../wsl/README.md) division.
How `dram` on Windows differs from Arch's, from the command's side: [dram on Windows](../../operations/dram/windows.md).
cabin-win types in US and Russian, toggled with Left Alt+Shift, as on Arch.

## Install a Windows PC

The answer file `install/windows/autounattend.xml` and the first-logon script `install/windows/dram-windows/firstlogon.ps1` install Windows 11 with the settings Arch needs beside it.
`tests/windows-vm.sh` installs the same ISO with them in a VM on cabin first, in about half an hour:

```sh
sudo install -d -o pj -g pj /data/vm/dram-tests          # once
bash ~/git/dotfiles/tests/windows-vm.sh --iso /run/media/pj/iodd-st400/_pc/_win11.iso
```

Windows Setup must see only its own disk.
Given another disk's ESP, it puts its boot files there instead of making its own; on cabin that was Arch's, so a later Arch reinstall would leave Windows unbootable, and Windows' servicing wrote into Arch's boot partition.
Power off, then:

1. Disconnect every other disk: on cabin, the 2 TB 870 EVO's SATA cable, and both NVMe disks, by disabling their M.2 slots in the firmware or by taking them out.
   Note which slot each was in: the 990 PRO in the CPU's slot, the 990 EVO Plus in the chipset's.
2. Put the ISO on the iODD: `_pc/_win11.iso`, the Media Creation Tool build of 2026-10-10, SHA-256 `9dac63708975d0a063d4444fe20583ce493f2a43c6c69ec1873fbe817e7d0435`.
   Its boot loaders are signed by Microsoft Windows Production PCA 2011, which is in cabin's db, so Secure Boot stays on.
3. Copy `autounattend.xml` and the `dram-windows` folder to a removable FAT32 USB stick.
   Setup reads an answer file only from a removable drive, and the iODD reports itself as a fixed disk: on 2026-10-11 Setup ignored the copy there and ran the plain, interactive install.
   Without the stick nothing is lost, because the first converge applies the same settings.
4. F11 at power-on, the iODD's UEFI CD entry, then a key at "Press any key to boot from CD or DVD".
5. On the product key page choose "I don't have a product key", then the edition this PC was activated with; its digital license activates it again.
6. On the disk page pick the drive that is only "Unallocated Space": on cabin, 931.5 GB, the MX500.
   The iODD's own SSD is the same size and lists its partitions: never that one.
7. The rest runs by itself: the name CABIN-WIN, US Eastern time, the local administrator pj with no password yet, the privacy page answered "off".
   One automatic sign-in runs `firstlogon.ps1`: Fast Startup and hibernation off, the hardware clock read as UTC (Arch keeps it so), no automatic device encryption, privacy defaults, and Steam and Proton Pass through winget.
   Its log is `C:\Windows\Setup\Scripts\dram-windows\firstlogon.log`; without a network, run it again later as administrator from the same folder.
8. Sign out and in: Windows makes pj set a password.
   The NVIDIA driver comes through Windows Update, and the NVIDIA App, which winget doesn't carry, from nvidia.com if wanted.
9. Take the stick out: any Windows ISO booted beside it would follow the answer file.
10. Power off, put the NVMe disks back in their own slots and reconnect the other disks.
11. Boot Arch and put it first again if Windows took the lead:

    ```sh
    dram boot-to list                       # the firmware's entries; "(this Arch)" marks home
    sudo efibootmgr -o <rEFInd>,<Linux Boot Manager>,…
    sudo -v; dram doctor --boot             # rEFInd first, systemd-boot behind it
    dram boot-to windows                    # Windows once; the next boot is Arch again
    ```

12. Open Windows' OpenSSH to the Mac, once, in Terminal (Admin): `Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0`, then `Start-Service sshd; Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private`.
    Put the Mac's public key in `C:\ProgramData\ssh\administrators_authorized_keys`.
13. Converge it from the Mac: `bin/push-windows.sh cabin-win --apply`, which installs `dram` on the first push ([dram.ps1](dram-ps1.md)).
    `install/windows/apply-windows.sh --debloat` stages and converges without `dram`.
    Norton's uninstaller wants clicks: Settings, Apps.
    In the BIOS, turn off "MSI Driver Utility Installer" too.
14. Sign out once after the first converge: an app that was already running sees the house fonts only after a sign-out.
    Converge again after every Windows feature update: one can add sound events, reset the lock-screen picture or bring an app's defaults back, and the next run puts them back and says what it changed.

BitLocker comes last, turned on by hand with its recovery key in Proton Pass, after the boot hardening ([decision log](../../../decisions/log.md#d75)).
If Setup put its boot files on another disk's ESP anyway, `own-esp.ps1` moves them to Windows' own disk without a reinstall ([Boot guard](boot-guard.md)).
The next feature version is a repo change, as an Arch release is: move `TargetReleaseVersionInfo` in the unit `windows-update-feature-pin`, render, converge, let Windows Update install it, then start a game before keeping it.

## thermos

thermos runs the Windows 11 Pro it shipped with, set up by hand with Chris Titus Tech's WinUtil before this repo managed any Windows.
A review on 2026-10-12 found its firewall off for the Private and Public profiles, OpenSSH Server running with password login, BitLocker encrypting with no protector, and a BIOS from 2022.
Its reset from this repo is planned: from a removable stick, converged from a rendered thermos build with the base, desktop, chat, office, college, dev, sysadmin and re-lab roles plus the laptop's settings.
The hardening that comes with it: the firewall on for every profile by policy, sshd Manual and keys-only on Private networks, BitLocker with TPM and PIN, Fast Startup off, hibernation on battery.
Then thermos-wsl ([WSL](../wsl/README.md)).
Never WinUtil on a PC this repo manages: its reset deletes every policy the build sets, and its services tweak once set Riot Vanguard's driver service to Manual ([decision log](../../../decisions/log.md#d134)).

## The case display on Windows

`install/windows/dram-windows/case-display.ps1` sends cabin's case panel the same frame as Arch's daemon, as a HID output report: report ID 0, then the frame, padded to the panel's report length (65 bytes on cabin).
It runs as the SYSTEM task `dram-case-display`, which cabin-win's host file declares (the unit `case-display-task`), and reads the temperatures from LibreHardwareMonitor's library, which the unit `case-display-lhm` installs pinned by SHA-256.
The CPU's temperature needs the PawnIO driver ([decision log](../../../decisions/log.md#d124)); the GPU's falls back to `nvidia-smi`.
`debloat.ps1` removes Antec's own iUnity.
The bench systems leave the panel dark: they would need the same program.
How the panel and the frame work: [pkgs/dram-case-display/README.md](../../../pkgs/dram-case-display/README.md).

## Operating it

- Adding an app, a role or a setting: [renderer](renderer.md#change-something-render-push).
- What a Windows list holds and how the register checks it: [handbook chapter 7](../../records/handbook/07-packages.md).
- The commands on the PC: [dram.ps1](dram-ps1.md#on-windows).

## Status

As of 2026-10-19: cabin-win runs release v2026.10.29; League, Blitz, Marvel Rivals, CurseForge, Overwolf, the native Discord client and Vortex left it, WowUp manages the WoW add-ons, and Defender, the firewall and the kernel guards are declared ([D149](../../../decisions/log.md#d149) to [D152](../../../decisions/log.md#d152)).
Open:

- thermos' reset from this repo;
- the boot hardening on cabin (dbx, the KEK, the keys offline), which [Boot trust](../../security/boot-trust/README.md) tracks;
- DSC 3's own resources in place of `PSDscResources` ([renderer](renderer.md#not-yet)).

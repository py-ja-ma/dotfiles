# Boot guard

[Platforms](../../README.md) › [Windows](../README.md) › Boot guard

Windows on cabin lives at Arch's mercy: Arch owns the boot order, the Secure Boot keys and the firmware, and Windows changes none of them on its own.
Windows boots from its own ESP on its own disk, through its own firmware entry, and a SYSTEM task puts rEFInd back in front whenever Windows' servicing moves itself first.
Arch has the same guard on its side.

| | |
|---|---|
| Code | `install/windows/dram-windows/boot-guard.ps1`, `install/windows/dram-windows/own-esp.ps1`, `system/windows-esp-retire.sh`, the unit `windows/units/boot-guard-task.ps1`, the opt-outs in `windows/hosts/cabin-win.nix` |
| Runs on | cabin-win, and Arch on cabin |
| Needs | bcdedit and Task Scheduler on Windows; diskpart and reagentc for `own-esp.ps1`; efibootmgr and the `WIN-ESP` label on Arch; tested on cabin 2026-10-12 |
| Decided in | [decision 0017](../../../decisions/0017-cabin-bench-layout.md); in the decision log: [Windows' own ESP](../../../decisions/log.md#d65), [its firmware entry](../../../decisions/log.md#d66), [the guard on every OS](../../../decisions/log.md#d67), [the opt-outs](../../../decisions/log.md#d69) |

## How it works

### rEFInd first

Windows' servicing, `bcdboot` during an upgrade, moves "Windows Boot Manager" to the front of the firmware's boot order, and then Arch never boots to put rEFInd back.
`boot-guard.ps1` runs from the SYSTEM task `\dram\boot-guard` at every Windows start, which the unit `boot-guard-task` installs.
It finds the firmware entry for `\EFI\refind\refind_x64.efi`, and when the order is wrong it puts rEFInd first and Windows Boot Manager last, logging the order before and after to `C:\ProgramData\dram\boot-guard.log`.
Windows stays reachable: rEFInd's Windows tile and `dram boot-to windows` start its entry once, by BootNext.
On Arch, `dram-refind-first.service` does the same at every boot ([Boot chain](../arch/boot-chain.md#refind-in-front)).
`dram doctor` on the PC checks the task and the order, and `dram doctor --boot` on Arch checks the order.

### Windows' own ESP

Windows Setup put its boot files on Arch's ESP on 2026-10-11, because it found that ESP before making its own.
Windows' servicing then wrote into Arch's boot partition, and an Arch reinstall would have left Windows unbootable.
`own-esp.ps1` moved them in place, without a reinstall, on 2026-10-12:

1. WinRE off, its partition removed, C: shrunk by 1 GB;
2. WinRE rebuilt right after C:, so it can still grow by shrinking C:, as Microsoft's layout expects;
3. a FAT32 ESP labeled WIN-ESP after it, last on the disk, and `bcdboot C:\Windows /s <ESP> /f UEFI`;
4. the firmware's Windows Boot Manager entry pointed at the new ESP with `bcdedit /set {bootmgr} device`, since `bcdboot` with `/s` leaves the entry alone;
5. WinRE back on, registered in the new ESP's boot configuration.

It refuses unless Windows' disk has no ESP of its own and C: is on it, and it leaves Arch's ESP alone as the way back.
Once Windows had booted from its own ESP, `system/windows-esp-retire.sh` on Arch, an `ask` hook of `dram apply`, finished the move:

- `/efi/EFI/Microsoft` archived to `/var/lib/dram/backup/efi-microsoft-<stamp>.tar`, then removed;
- every other "Windows Boot Manager" entry deleted: MSI's firmware re-adds one for any ESP holding `bootmgfw.efi`, and the old drives had their own;
- `apply-refind.sh` run again, so the Windows tile starts Windows' own entry (`firmware_bootnum`).

Windows never starts through rEFInd: rEFInd's tile hands the firmware Windows' entry, so BitLocker's measurements don't change when rEFInd or Arch's keys do.

### Windows leaves the firmware alone

cabin-win's host file declares the opt-outs, landed 2026-10-12:

| Setting | Effect |
|---|---|
| `HighConfidenceOptOut` | no Secure Boot variable update rolled out by Microsoft: Arch owns the KEK, db and dbx |
| the unit `secureboot-no-revocations` | Windows never queues the PCA 2011 revocation, SVN or SBAT updates; Arch decides those |
| `DenyDeviceClasses` with the Firmware class | no UEFI capsule from Windows Update: the BIOS comes from M-Flash; the NVIDIA driver is Display class and keeps coming |
| `DisableWpbtExecution` | Windows runs nothing a firmware table hands it |

The Secure-Boot-Update task stays on, since Microsoft requires it, and TPM auto-provisioning stays as shipped.
The keys themselves, dbx and the KEK are [Boot trust](../../security/boot-trust/README.md).

## Use it

```powershell
powershell -ExecutionPolicy Bypass -File C:\ProgramData\dram\boot-guard.ps1 -DryRun   # what it would change
Get-Content C:\ProgramData\dram\boot-guard.log -Tail 5
bcdedit /enum firmware                                                                # the firmware's entries
```

```sh
dram boot-to list                              # on Arch: the entries; "(this Arch)" marks home
sudo bash system/windows-esp-retire.sh --dry-run
```

## When it breaks

| Symptom | Check | Fix |
|---|---|---|
| the PC boots straight into Windows | `bcdedit /enum '{fwbootmgr}'` on Windows, `efibootmgr` on Arch | F11, boot Arch: its service puts rEFInd first; on Windows, run `boot-guard.ps1` |
| `boot-guard.log` says there is no rEFInd entry | `efibootmgr` on Arch | `sudo bash system/apply-refind.sh` on Arch |
| the Windows tile does nothing | `dram doctor --boot`: `bcdboot` can recreate Windows' entry under a new number | `sudo bash system/apply-refind.sh`, which finds the entry again |
| a retired copy is needed back | `/var/lib/dram/backup/efi-microsoft-*.tar` | `tar -xf` it into `<ESP>/EFI/`, then `efibootmgr -c` for its entry |

## Limits

- `own-esp.ps1` handles one layout: Windows alone on its disk, C: followed by at most one recovery partition, and room to shrink C: by 1 GB.
- Taking Arch's and the bench's disks offline in Windows, disk by disk, is planned, not built.
- BitLocker is not on yet on cabin-win; it comes after the boot hardening.

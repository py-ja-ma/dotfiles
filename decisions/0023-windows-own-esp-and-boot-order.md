# 0023: Windows boots from its own ESP and Arch owns the boot order

[Platforms › Windows](../docs/platforms/windows/README.md) · accepted 2026-10-12 · amends 0017

Windows keeps its boot files on its own ESP on its own disk and starts only from its firmware entry, while a guard on each OS keeps rEFInd first; the cost is a guard to run on Windows and a one-time move of Windows' boot files.

## Context

cabin runs Windows 11 on the 1 TB Crucial MX500 beside Arch on the NVMe disks ([0017](0017-cabin-bench-layout.md)).
On 2026-10-12 the firmware's boot entries showed Windows Boot Manager on Arch's ESP: Windows Setup had put its boot files there.
So Windows servicing wrote into Arch's boot partition, and Windows could not take that disk offline, because it was its system disk.
Every installer puts itself first in the boot order, Windows included (`bcdboot` on upgrades), and Arch's own guard runs only when Arch boots.
Windows with TPM, Secure Boot and BitLocker should not start through rEFInd: loaded by rEFInd, Windows' measurements would change at every rEFInd update.
I want Windows at the mercy of Arch: Arch owns the boot chain and the firmware's keys, and Windows changes no Secure Boot variable, firmware or boot order of its own accord.

## Decision

- Windows' boot files live only on its own ESP (FAT label `WIN-ESP`), made in place on the MX500 rather than by a reinstall ([D65](log.md#d65)).
  `install/windows/dram-windows/own-esp.ps1` turns WinRE off and removes its partition, shrinks C: by 1 GB, rebuilds WinRE right after C:, makes a FAT32 ESP last on the disk, runs `bcdboot C:\Windows /s <ESP> /f UEFI`, points `{bootmgr}` at the new ESP and turns WinRE back on.
  Once Windows has booted from it, `system/windows-esp-retire.sh` archives `/efi/EFI/Microsoft` under `/var/lib/dram/backup/`, removes it, and deletes every other "Windows Boot Manager" entry in NVRAM.
- Windows starts only from its firmware entry ([D66](log.md#d66)).
  rEFInd's Windows tile uses `firmware_bootnum` (a BootNext and a reboot) and `dram boot-to windows` sets BootNext (`system/apply-refind.sh`); rEFInd never loads `bootmgfw.efi`.
- A guard on every OS keeps rEFInd first, and Arch owns NVRAM ([D67](log.md#d67)).
  On Arch it is `refind-first` (`system/apply-refind.sh`); on Windows, `boot-guard.ps1`, run by the SYSTEM task `\dram\boot-guard` at every start (the unit `boot-guard-task`), which puts rEFInd first and Windows Boot Manager last when the order is wrong.
- Arch's and the bench's disks are offline in Windows, disk by disk by GUID, and never by the SAN policy `offlineAll`, which would also take USB disks such as eva offline ([D68](log.md#d68)).
  This one is not built yet.
- Windows-side opt-outs ([D69](log.md#d69)), in `windows/hosts/cabin-win.nix`: no Microsoft-managed Secure Boot variable rollout (`HighConfidenceOptOut`), the PCA 2011, SVN and SBAT bits kept out of `AvailableUpdates` (the unit `secureboot-no-revocations`), the Firmware device class denied to Windows Update, and nothing run that a firmware table hands Windows (`DisableWpbtExecution`).
  The Secure-Boot-Update servicing task stays on: Microsoft requires it.
- The firmware ([D73](log.md#d73)): the MSI BIOS only by M-Flash, since LVFS has nothing for this board; IOMMU, SVM and NX on; after any BIOS update or CMOS clear, Arch boots first so its Secure Boot scripts can put the keys back.

## Alternatives

| Option | Why not |
|---|---|
| Reinstall Windows alone on the MX500 with the other disks unplugged ([D11](log.md#d11)) | clean partitions, but every drive comes out once and the installed games come back from copies; the move in place keeps everything |
| A new ESP between C: and WinRE | WinRE could no longer grow by shrinking C:, as Microsoft's layout expects |
| rEFInd loads `bootmgfw.efi` | rEFInd joins Windows' measured boot, so BitLocker's measurements change at every rEFInd update |
| The SAN policy `offlineAll` | it also takes USB disks offline, eva included |
| `ExcludeWUDriversInQualityUpdate` against firmware updates | it blocks the NVIDIA driver too; denying the Firmware class is narrower |

## Consequences

- Windows servicing no longer writes to Arch's ESP.
- Arch's Secure Boot and dbx changes do not touch Windows' measured boot while Windows starts from its firmware entry.
- Windows still puts itself first after an update: on the first test boot it did, and `boot-guard` put rEFInd back at the next Windows start.
- MSI's firmware re-adds a "Windows Boot Manager" entry for any ESP that holds `bootmgfw.efi`, so the old files had to leave Arch's ESP; reordering was not enough.
- Rollback: untar the archive under `/var/lib/dram/backup/` into the ESP, then `efibootmgr -c` for its entry.
- Until the disks are offline in Windows ([D68](log.md#d68)), Windows can still read Arch's disks raw.

## How it is checked

On Arch, `dram doctor --boot` warns when Windows' boot files are on Arch's ESP again, when no NVRAM entry starts Windows' own ESP, and when rEFInd's Windows tile starts another entry.
On Windows, `dram doctor` checks that the boot-guard task exists, is enabled and has run, and runs `boot-guard.ps1 -DryRun` to see that the order is right.
The opt-outs are registry units of cabin-win's build, which `dram doctor` tests in their desired state.

## History

- 2026-10-12: Windows' boot manager found on Arch's ESP; the Windows-side opt-outs and the boot guard built ([D69](log.md#d69)).
- 2026-10-12: accepted. `own-esp.ps1` made Windows' own ESP in place; a test boot by BootNext started Windows from the MX500, Windows put itself first, and `boot-guard` put rEFInd back.
- 2026-10-12: `system/windows-esp-retire.sh` archived and removed `/efi/EFI/Microsoft` and deleted the stale entries; rEFInd's Windows tile became `firmware_bootnum`.
- Open: the disks offline in Windows ([D68](log.md#d68)); the BIOS update by M-Flash ([D73](log.md#d73)) not yet run.

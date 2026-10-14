# Secure Boot

[Security](../README.md) › [Boot trust](README.md) › Secure Boot

Each Arch host on its own hardware enforces Secure Boot with keys I made, and keeps Microsoft's keys and the board maker's beside them.
Never enroll mine alone: cabin has no integrated GPU, its RTX 3080 Ti's option ROM is signed by Microsoft, and without Microsoft's keys the screen stays black at POST.
Windows' boot manager is signed by Microsoft too.

| | |
|---|---|
| Code | `system/secureboot-setup.sh`, `system/secureboot-test.sh`, `hosts/cabin/secureboot-baseline-2026-10-12.txt`; on Windows `windows/units/secureboot-no-revocations.ps1` and the registry values in `windows/hosts/cabin-win.nix` |
| Runs on | every Arch host on its own hardware (`ask` hooks of `dram apply`); the Windows half on cabin-win |
| Needs | sbctl 0.18 (in `packages/metal.txt`), a systemd-boot and UKI layout at `/efi` from `install/arch-install.sh`, firmware that offers Setup Mode; tested 2026-10 |
| Decided in | [0011](../../../decisions/0011-disk-boot-secure-boot-snapshots.md), [D16](../../../decisions/log.md#d16), [D69](../../../decisions/log.md#d69), [D73](../../../decisions/log.md#d73) |

## The keys and who keeps them

| Variable | Holds | Kept by | Built |
|---|---|---|---|
| PK | my key; Windows can never change it | the firmware | yes |
| KEK | my key, Microsoft's KEK CAs 2011 and 2023, MSI's | Arch | yes; mine alone is open ([D71](../../../decisions/log.md#d71)) |
| db | my key, Microsoft's five CAs, MSI's | Arch | yes |
| dbx | 291 hashes, Microsoft's x64 list, where the board's own default list (`dbxDefault`) has 431 | Arch | the union, written from Arch, is open ([D70](../../../decisions/log.md#d70)) |
| boot order | rEFInd first, systemd-boot behind it | Arch's `apply-refind.sh`, and Windows' boot guard at every Windows start | yes |
| starting Windows | Windows' own firmware entry, by BootNext; rEFInd never chain-loads Windows' boot manager ([D66](../../../decisions/log.md#d66)) | `apply-refind.sh` (the tile's `firmware_bootnum`) | yes |
| the firmware | MSI's BIOS by M-Flash only; Windows Update's Firmware class denied | by hand; cabin-win's registry | yes |
| the TPM | Windows provisions cabin's fTPM; lantern's TPM2 holds its disk key | Windows; `system/tpm2-enroll.sh` | yes |

sbctl keeps the keys in `/var/lib/sbctl`, a subvolume of its own (`@sbctl`), and they are exported offline.
`hosts/cabin/secureboot-baseline-2026-10-12.txt` is the state read from Windows before any of the Windows-side changes: each variable's sha256 and certificates, the boot order, the TPM, the servicing values and Vanguard's driver.
Compare a later reading against it.

## Set it up

`secureboot-setup.sh` creates the keys if `/var/lib/sbctl` has none, signs systemd-boot at the source (`systemd-bootx64.efi.signed`) and on the ESP, signs and registers the UKIs, and runs `sbctl verify`.
In Setup Mode it then enrolls my keys with Microsoft's, and the board's when the firmware exports a default db (`dbDefault`), after you type `microsoft` to confirm.
Out of Setup Mode it prints the firmware steps instead.
OVMF exports no `dbDefault`, and sbctl refuses `--firmware-builtin` there, so the VM gets mine and Microsoft's only.

```sh
sudo bash system/secureboot-setup.sh --dry-run   # what it would sign and enroll
sudo bash system/secureboot-setup.sh             # in Setup Mode: type 'microsoft' to enroll
sudo bootctl status | grep 'Secure Boot'         # prints: Secure Boot: enabled (user)
sudo sbctl verify                                # every file of ours under /efi: signed
```

Setup Mode on MSI's B550 board is in [handbook chapter 1](../../records/handbook/01-install.md), §2.
Set "Provision Factory Defaults" to Disabled before "Delete All Secure Boot Variables", or the board puts its keys back at the next reboot.
Set the "Secure Boot Preset" to Maximum Security: MSI's default, "Hardware/OS Compatibility", runs unsigned images anyway.

## Prove it is enforced

`sbctl status` and `bootctl` report what the firmware says, which is not proof that it refuses anything.
`system/secureboot-test.sh` proves it for the internal disk:

```sh
sudo bash system/secureboot-test.sh --arm     # an unsigned systemd-boot as a one-time BootNext entry
systemctl reboot                              # an enforcing firmware refuses it and boots the normal entry
sudo bash system/secureboot-test.sh --check   # exit 0: refused (enforcing); 1: the unsigned image ran
```

The removable-media half needs no script: boot the unsigned Arch ISO from the firmware's boot menu, and it must be refused.
Run both again after a BIOS update, a CMOS clear or "Load Defaults", which can reset the preset.
`sbctl status` may still print the MSI quirk `FQ0001`: sbctl infers it from the board model and cannot verify it, and the test above settles the question.

## Windows on cabin

Arch owns the boot trust, so Windows changes no Secure Boot variable, no firmware and no boot order by itself ([D69](../../../decisions/log.md#d69)):

| Setting on cabin-win | Effect |
|---|---|
| `HighConfidenceOptOut` = 1 | no Microsoft-managed rollout of Secure Boot variables |
| `secureboot-no-revocations` | the PCA 2011 revocation (0x80), SVN (0x200) and SBAT (0x400) bits stay out of `AvailableUpdates`: Arch decides those |
| `DenyDeviceClasses` with the Firmware class | no UEFI capsule from Windows Update; the NVIDIA driver is the Display class and keeps coming |
| `DisableWpbtExecution` = 1 | Windows runs nothing a firmware table hands it (MSI's driver bundle arrives that way) |
| the boot guard (`boot-guard.ps1`, a SYSTEM task at every Windows start) | rEFInd first and Windows Boot Manager last in the firmware's order |

Three things stay as Windows ships them.
The Secure-Boot-Update task stays, because Microsoft requires it and its writes fail closed against keys it does not hold.
The TPM's auto-provisioning stays.
The storage policy that would take every other disk offline stays off, since it would also take USB disks such as eva offline.
BitLocker cannot bind to PCR 7 on cabin, because the GPU's option ROM and rEFInd's extra certificate change it.
Its profile is PCR 0, 2, 4 and 11, so key and dbx changes on Arch's side never prompt while Windows starts from its firmware entry.
BitLocker comes last ([D75](../../../decisions/log.md#d75)).

## Firmware rules

These hold for cabin's MSI board ([D73](../../../decisions/log.md#d73)):

- The BIOS comes by M-Flash only: LVFS has nothing for this board, and Windows Update's Firmware class is denied.
- **Never** "Load Defaults" or a Secure Boot mode change on a whim: the factory keys let Windows write the KEK again and stop Arch booting.
- After any BIOS update or CMOS clear, boot Arch first, restore the preset, run `secureboot-setup.sh` again, then `secureboot-test.sh`.
- The AMD fTPM stays on: Riot's anti-cheat accepts only an fTPM for restricted accounts.
- IOMMU, SVM and NX on, for Memory Integrity and Vanguard's on-demand mode: decided, not yet set.

## When it breaks

| Symptom | Fix |
|---|---|
| no picture at POST after a key change | the GPU's option ROM is not trusted. Power off for 30 s and retry, then clear CMOS, then restore the keys from the firmware's key management and run the Arch scripts again |
| Arch refuses to boot after a BIOS update | the update reset the keys: firmware setup, Setup Mode, then `secureboot-setup.sh` from Arch with Secure Boot off for that one boot |
| Windows does not boot after its ESP moved | recreate its entry with `efibootmgr`, or restore the archive `windows-esp-retire.sh` made of `/efi/EFI/Microsoft` |
| BitLocker asks for its recovery key | suspend it before a BIOS, GPU or boot-menu change: `manage-bde -protectors -disable C: -RebootCount 2`. The key is in Proton Pass |
| `dram doctor --boot` says a file on the ESP is unsigned | `sudo sbctl sign -s <file>`, then `secureboot-setup.sh` |

More: [the boot chain](../../platforms/arch/boot-chain.md) and [handbook chapter 11](../../records/handbook/11-troubleshooting.md).

## Open decisions

Each was raised on 2026-10-12 and waits on me.
Until it is ruled, nothing on either OS changes the variable it names.

| ID | Question | Recommendation |
|---|---|---|
| [D70](../../../decisions/log.md#d70), [D117](../../../decisions/log.md#d117) | restore dbx from Arch, through efitools under a Community waiver, before BitLocker and the anti-cheat tests? | yes, after a preflight that checks every ESP binary and the TPM log's driver digests against the new list |
| [D71](../../../decisions/log.md#d71) | the KEK: mine only, so only Arch can change db and dbx, or mine and Microsoft's? | mine only, if League still passes afterwards; else Microsoft's back, with the opt-outs above |
| [D72](../../../decisions/log.md#d72) | `PK.key` and `KEK.key` offline, back only for a db or KEK change? | yes: a kernel driver from a Tencent company runs on cabin's Windows and could read them on Arch's disk |
| [D74](../../../decisions/log.md#d74) | Memory Integrity on cabin-win, so Vanguard runs on demand? | measure two games with it on and off first |
| [D75](../../../decisions/log.md#d75) | BitLocker on cabin-win, its key in Proton Pass, its PCR profile checked | yes, as the last step |
| [D76](../../../decisions/log.md#d76) | the BlackLotus mitigations | later, with 2023-signed Windows media made first |
| [D90](../../../decisions/log.md#d90) | HackBGRT in Windows' boot path, signed from Arch | only if Vanguard accepts it and before BitLocker |

## Limits

Secure Boot here guards the boot chain against tampering at rest, the case where someone has the machine but not the keys.
It does not protect a running system, and the desktops' disks are not encrypted.
The keys sit on the disk they protect until [D72](../../../decisions/log.md#d72) is ruled.

# Boot trust

[Security](../README.md) › Boot trust

What an Arch host on its own hardware trusts between power-on and the greeter: firmware holding my Secure Boot keys next to Microsoft's, a signed rEFInd and systemd-boot, and a signed UKI per kernel.
lantern also unlocks its disk with the TPM2, bound to the Secure Boot state.
On cabin, Windows may not change any of it: the keys, the revocation list, the firmware and the boot order are Arch's.
The WSL clones have no boot of their own and are out of scope.

| Branch | What it does | Code | Copy alone |
|---|---|---|---|
| [Secure Boot](secure-boot.md) | creates the keys, signs systemd-boot and the UKIs, enrolls my keys and Microsoft's in Setup Mode | `system/secureboot-setup.sh` | yes, with sbctl and a systemd-boot and UKI layout at `/efi` |
| [Enforcement test](secure-boot.md#prove-it-is-enforced) | proves the firmware refuses an unsigned image from the internal disk | `system/secureboot-test.sh` | yes |
| TPM2 unlock | binds lantern's LUKS2 volume to PCR 7 and a PIN, adds a recovery key, rebuilds the UKIs | `system/tpm2-enroll.sh` | yes, with `install/lib/luks.sh` and a LUKS2 volume |
| [Windows beside Arch](secure-boot.md#windows-on-cabin) | Windows queues no Secure Boot revocation, installs no firmware from Windows Update, and puts rEFInd back first at every start | `windows/units/secureboot-no-revocations.ps1`, cabin-win's registry values in `windows/hosts/cabin-win.nix`, `install/windows/dram-windows/boot-guard.ps1` | no: it assumes the dual boot |
| Windows' ESP | takes Windows' boot files off Arch's ESP once Windows boots from its own | `system/windows-esp-retire.sh` | only where Windows has its own ESP labeled `WIN-ESP` |
| cabin's baseline | the key and servicing state read from Windows on 2026-10-12, the reference for every later change | `hosts/cabin/secureboot-baseline-2026-10-12.txt` | no: cabin's own |

The TPM2 unlock's other half, a YubiKey as the backup unlock, is on the [YubiKeys](../identity/yubikeys.md#lanterns-disk) page.
The boot chain itself (rEFInd in front, systemd-boot behind it, snapshots as boot entries) is a Platforms page: [the boot chain](../../platforms/arch/boot-chain.md).

## How the branches fit

`dram apply` runs `uki-presets.sh` before `secureboot-setup.sh`, so a new kernel's UKI exists before anything signs it.
sbctl's own pacman and mkinitcpio hooks re-sign every registered file after an update, and systemd-boot is signed at the source, so `bootctl update` stays signed.
`tpm2-enroll.sh` needs Secure Boot on first, because PCR 7 measures the Secure Boot state and means nothing without it.
`fido2-enroll.sh` runs after it and keeps the TPM2 slot at priority `prefer`.
All three are `ask` hooks of `dram apply` (`system/apply-hooks.tsv`): a mistake there costs a boot, so nothing runs them unasked.
Why systemd-boot with signed UKIs, why Microsoft's keys stay, and why only the laptop is encrypted: [decision 0011](../../../decisions/0011-disk-boot-secure-boot-snapshots.md) and [D3](../../../decisions/log.md#d3).

## Operating it

Firmware settings and the first enrolment: [handbook chapter 1](../../records/handbook/01-install.md), §2 and §8.
A host that will not boot: [handbook chapter 11](../../records/handbook/11-troubleshooting.md) and [the boot chain](../../platforms/arch/boot-chain.md).
After a BIOS update, a CMOS clear or "Load Defaults": the [firmware rules](secure-boot.md#firmware-rules).
`dram doctor --boot` checks the live state: Secure Boot enforcing, a UKI per kernel, `sbctl verify`, and Windows' files off Arch's ESP.

## Status

2026-10-13: on cabin, Secure Boot is on with my keys, Microsoft's and MSI's, and the Secure Boot Preset is Maximum Security.
`system/secureboot-test.sh` proved that an unsigned image on the internal disk and an unsigned USB stick are both refused (`hosts/cabin/README.md`).
cabin's disks are not encrypted, and its fTPM serves Windows only.
Windows boots from its own ESP on cabin's MX500, made in place on 2026-10-12 ([D65](../../../decisions/log.md#d65)).
`windows-esp-retire.sh` archives and removes the copy Windows left on Arch's ESP, and `dram doctor --boot` warns while one is there.

Open since 2026-10-12, each waiting on a decision ([Secure Boot](secure-boot.md#open-decisions) has the detail):

- dbx from Arch, through efitools under a Community waiver ([D70](../../../decisions/log.md#d70), [D117](../../../decisions/log.md#d117)).
- The KEK: mine only, or mine and Microsoft's ([D71](../../../decisions/log.md#d71)).
- `PK.key` and `KEK.key` kept offline ([D72](../../../decisions/log.md#d72)).
- Memory Integrity, BitLocker on cabin-win, HackBGRT and the BlackLotus mitigations ([D74](../../../decisions/log.md#d74), [D75](../../../decisions/log.md#d75), [D76](../../../decisions/log.md#d76), [D90](../../../decisions/log.md#d90)).

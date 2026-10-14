# 0024: Secure Boot custody on cabin and the order of Windows' hardening

[Security › Boot trust](../docs/security/boot-trust/README.md) · proposed 2026-10-12

Arch alone would change cabin's Secure Boot keys and revocations, and Windows' own hardening would come last, each step tested against Riot Vanguard; the cost is a game test after every step and a rollback ladder to keep ready.

## Context

cabin's Secure Boot state, read from Windows on 2026-10-12, is in `hosts/cabin/secureboot-baseline-2026-10-12.txt`.
PK is mine.
KEK is mine plus Microsoft's 2011 and 2023 keys and MSI's.
db is mine plus the five Microsoft CAs and MSI's certificate.
dbx was empty when Arch enrolled the keys, and held 291 SHA-256 revocations that day: Microsoft's current x64 list, written by Windows' servicing through Microsoft's KEK before the opt-outs of [0023](0023-windows-own-esp-and-boot-order.md) landed.
Everything cabin boots still boots; the revocations target Windows media and old shims.

Windows cannot change PK or KEK, but while Microsoft's KEK is enrolled it can write db and dbx.
Microsoft's 2011 CA expires 2026-10-19, and the enforcement of KB5025885 will put the PCA 2011 into dbx with no opt-out.
`/var/lib/sbctl/keys` sits unencrypted on Arch's disk, readable by any OS on cabin with raw disk access, Riot Vanguard's kernel driver included.
Vanguard reports some custom key sets as an unverifiable Secure Boot policy (`VAN: STATUS_SB_POLICY`), and Riot's only documented fix is factory keys.
League, which needs Vanguard, stays under a waiver ([0013](0013-software-rules-and-waivers.md), [D92](log.md#d92)).

## Decision (proposed)

- dbx is restored from Arch with a preflight over every binary on the ESPs and the TPM log's driver digests, before BitLocker and the anti-cheat tests ([D70](log.md#d70)).
  The writes go through efitools, under a Community waiver for the boot-trust scripts only ([D117](log.md#d117)).
- KEK is mine only, so only Arch can change db and dbx, or mine plus Microsoft's with the opt-outs and detection ([D71](log.md#d71)).
  The recommendation: mine only, kept if League passes afterwards, and Microsoft's back if Vanguard objects.
- `PK.key` and `KEK.key` go offline: daily signing of the UKIs needs only `db.key` ([D72](log.md#d72)).
  LUKS on cabin is a separate decision.
- Memory Integrity (HVCI) with IOMMU, on cabin-win only for Vanguard's On-Demand mode or a FACEIT wave ([D74](log.md#d74)), after two games are measured with PresentMon with it on and off.
- BitLocker on cabin-win comes last, its recovery key in Proton Pass and its PCR profile checked with `manage-bde` ([D75](log.md#d75)).
  It cannot bind to PCR 7 here (the GPU's option ROM and rEFInd's extra certificate), so the profile is PCR 0, 2, 4 and 11.
- The BlackLotus enforcement comes later, once 2023-signed Windows media exist ([D76](log.md#d76)).
- A boot logo through HackBGRT, built as a signed `[dram]` package and installed from Arch onto `WIN-ESP` with its own NVRAM entry, only if League and Vanguard behave as on a direct boot, not if I play FACEIT, and before BitLocker ([D90](log.md#d90)).

## Alternatives

| Option | Why not |
|---|---|
| Factory keys | Riot's documented fix, but they let Windows write KEK again and stop Arch and NixOS from booting |
| Let Windows and fwupd keep writing dbx | the state stops being known: one writer, Arch, keeps it reviewable |
| New crypto code in the repo for the dbx writes | more code to trust than efitools under a narrow waiver |
| BitLocker first | every later boot-trust step would prompt for the recovery key |

## Consequences

- Vanguard may refuse cabin's keys after a step.
  That step is rolled back (the KEK restored, dbx rolled back, HackBGRT out); the ladder after that: Windows straight from the firmware, Vanguard always on, and as a last resort factory keys with shim and a machine owner key for Arch.
- A dbx write could revoke something cabin boots, the GPU's option ROM above all, which would leave no picture before the OS.
  The preflight and a firmware write test come first; recovery is the F11 menu to Linux Boot Manager, then the firmware's key management or a CMOS clear, then the Arch scripts.
- BitLocker recovery prompts: BitLocker comes last and is suspended before a BIOS, GPU or HackBGRT change (`manage-bde -protectors -disable C: -RebootCount 2`).
- The enforcement of KB5025885 retires the PCA 2011 media, so a 2023-signed Windows USB comes before [D76](log.md#d76).
- With KEK mine only, Windows Security's Secure Boot badge stays yellow and Arch maintains dbx.

## How it is checked

Nothing checks this yet: the scripts it needs, a KEK and a dbx writer on Arch, are not written.
`dram doctor --boot` checks that Secure Boot is enforcing and nothing on the ESP is unsigned, and `hosts/cabin/secureboot-baseline-2026-10-12.txt` is the baseline each step is compared with.

## History

- 2026-10-12: proposed; the baseline read from Windows, with dbx already written by Windows' servicing.
- Open: every decision here but the deferred BlackLotus step waits on my answers ([D70](log.md#d70), [D71](log.md#d71), [D72](log.md#d72), [D74](log.md#d74), [D75](log.md#d75), [D90](log.md#d90), [D117](log.md#d117)).

# Security

[Organization](../README.md) › Security

What each machine trusts: two YubiKeys, its own Secure Boot keys next to Microsoft's, a default-deny firewall, and packages that passed the software register.
The Arch hosts carry all of it.
Each division page says which parts the Windows PCs and the WSL clones carry.

| Division | Covers |
|---|---|
| [Identity](identity/README.md) | the YubiKeys, SSH keys, secrets in sops |
| [Boot trust](boot-trust/README.md) | Secure Boot with my keys and Microsoft's, signed UKIs, lantern's TPM2 unlock, what Windows may change in the firmware |
| [Network](network/README.md) | the nftables firewall, host hardening, DNS over TLS and HTTPS, WireGuard, NetworkManager |
| [Software supply](software-supply/README.md) | the software register, the signed `[dram]` repo, pins, integrity checks |

## Threat model

The hosts sit on a home LAN behind a UniFi gateway and offer nothing to the internet.
The threats that shape this directorate are a compromised device on the LAN, a stolen laptop, leaked credentials, and a malicious update to something installed.
A password typed over SSH all day was the most concrete exposure on 2026-10-05, so credentials come first: keys-only SSH, a YubiKey after the password, secrets that never sit in the repo in plaintext.
Disk encryption is on the laptop only.
cabin is a desktop at home, and its disks stay unencrypted ([D3](../../decisions/log.md#d3)).

## Rules

- sshd accepts keys only, and nftables admits SSH from the LAN only (`system/harden.sh`). `dram doctor --supply` warns when either drifts.
- On Windows, Defender is the only antivirus, hardened by the `defender-hardening` unit, the firewall is Private-only for sshd, and Memory Integrity, the driver blocklist and protected LSA are declared ([debloat](../platforms/windows/debloat.md), [D152](../../decisions/log.md#d152)).
- Every installed package has a verdict in `packages/register.tsv` ([0013](../../decisions/0013-software-rules-and-waivers.md)). `bin/check.sh` §15 fails on a name without one, an expired waiver or a forbidden name.
- Secure Boot keeps Microsoft's keys next to mine: cabin's GPU option ROM and Windows' boot manager are signed by Microsoft ([0011](../../decisions/0011-disk-boot-secure-boot-snapshots.md)).
- Both YubiKeys are enrolled for every job, so losing one is a revocation and not a lockout ([0019](../../decisions/0019-yubikeys.md)). `bin/check.sh` §18 checks the public halves in `keys/` and `.sops.yaml`.

## Decisions

| Record | Decision | Division |
|---|---|---|
| [0011](../../decisions/0011-disk-boot-secure-boot-snapshots.md) | btrfs and snapper, signed UKIs, Secure Boot with sbctl and Microsoft's keys | Boot trust |
| [0013](../../decisions/0013-software-rules-and-waivers.md) | Every package passes three rules or carries a waiver | Software supply |
| [0019](../../decisions/0019-yubikeys.md) | Two YubiKeys for SSH, the second factor, secrets and lantern's disk | Identity |

The smaller decisions are rows of the [decision log](../../decisions/log.md), each with its ID.

## Open

- 2026-10-13: on cabin, the primary YubiKey's pam-u2f line and the spare key are not enrolled yet (`hosts/cabin/README.md`).
- 2026-10-12: Secure Boot custody on cabin is undecided: dbx from Arch, the KEK, `PK.key` and `KEK.key` offline, Memory Integrity, BitLocker on cabin-win, HackBGRT ([D70](../../decisions/log.md#d70) to [D76](../../decisions/log.md#d76), [D90](../../decisions/log.md#d90), [D117](../../decisions/log.md#d117)). [Boot trust](boot-trust/README.md) lists them.
- 2026-10-12: the work-mandated waiver class ([D128](../../decisions/log.md#d128)) is open.
- 2026-10-12: usbipd-win waits for a ruling, and GlazeWM is held ([D131](../../decisions/log.md#d131)).
- 2026-10-11: the Mac and the YubiKeys are paused ([D43](../../decisions/log.md#d43)): lodge keeps its software key.
- 2026-10-11: pam-u2f has had no release since 2025-03; its register row is re-checked monthly.

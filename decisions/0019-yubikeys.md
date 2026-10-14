# 0019: Two YubiKeys for SSH, the second factor, secrets and lantern's disk

[Security › Identity](../docs/security/identity/README.md) · accepted 2026-10-11

Both of my YubiKeys are enrolled for every job, so losing one is a revocation and not a lockout; the cost is a touch at every sudo, login, SSH connection and signed commit, and admin at the machine instead of over SSH.

## Context

I own two YubiKeys and want hardware-backed two-factor authentication on every machine.
Until 2026-10-11 the hosts' SSH keys, git signing keys and sops age keys were software keys, one per host, and sudo, polkit and the greeter asked for the password alone.
Before deciding I read up on the packages, LUKS with FIDO2, PAM, and SSH, git and age with security keys.

## Decision

| Part | Decision |
|---|---|
| Both keys | enrolled for every job, primary and spare alike. The public halves are tracked: `keys/ssh.pub`, `keys/pam-u2f.txt`, and `# yubikey:` recipients in `.sops.yaml`. `dram yubikey enroll <label>` creates them on a host and prints the lines to commit on the Mac. |
| SSH | a resident `ed25519-sk` key per YubiKey, touch only: the FIDO2 PIN guards copying the handle to a new machine, not each use ([D36](log.md#d36)). sshd on every host reads the keys from a root-owned `/etc/ssh/authorized_keys.d/<login>`, rewritten from `keys/ssh.pub` by `system/harden.sh`, and requires the touch (`PubkeyAuthOptions touch-required`). |
| git | signs with the YubiKey's SSH key once one is listed, through the link `~/.ssh/id_ed25519_sk` that `dram yubikey ssh` makes; both keys are in `allowed_signers`. |
| The second factor | everywhere a desktop takes the password ([D35](log.md#d35)): pam_u2f follows the password in sudo, polkit-1 and login (ly, hyprlock and the console include login). One origin, `pam://dram`, for the fleet ([D40](log.md#d40)), and credentials with `+presence` only, because ly answers every hidden prompt with the password, so no PIN may ever be asked there. It switches on per host only after a listed key answers a test touch there. `nouserok` keeps a host without a map line on the password alone, and `module_unknown=ignore` keeps a missing pam-u2f from locking sudo, since root is locked ([D41](log.md#d41)). The line is written into each service and not included, because a missing include file fails the whole stack. |
| sudo over SSH | fails on a desktop, since the key must be at the machine ([D34](log.md#d34)). Headless hosts have no pam_u2f: their sudo takes the password, behind a YubiKey SSH login. |
| Secrets | each YubiKey gets an age identity in a PIV slot (age-plugin-yubikey, whose unclear Origin I accepted: [D38](log.md#d38)) and is an extra sops recipient, so either key can edit and re-key `secrets/pj.yaml` on any machine. Hosts keep their software age key for the unattended decrypt at login, and the YubiKey stubs never go into `keys.txt`. |
| lantern's disk | the YubiKeys are the backup unlock beside the TPM2 with its PIN and the recovery key ([D37](log.md#d37)): `rd.luks.options=tpm2-device=auto,fido2-device=auto,tries=0,discard`, with the TPM2 keyslot at priority `prefer` after every TPM enrolment. |
| OTP | off over USB on both keys: a stray touch would type a password and Enter ([D39](log.md#d39)). |
| Custody | the PINs, the PUK and the LUKS recovery key live in Proton Pass. The break-glass for both keys lost is an empty `/etc/dram/u2f_mappings`, written from the Arch ISO. |

## Alternatives

| Option | Why not |
|---|---|
| pam_u2f as `sufficient`, a touch instead of the password | one factor, not two |
| an exemption for sudo over SSH | no stock PAM module can tell an SSH sudo from a local one; a logind check is only safe once every shell login needs a security key |
| the OpenPGP applet (gpg-agent for SSH and signing) | more moving parts; FIDO2 SSH keys and age-plugin-yubikey cover the same jobs with OpenSSH and age alone |
| challenge-response disk unlock (yubikey-full-disk-encryption) | systemd-cryptenroll's FIDO2 support is built in and maintained with systemd |

## Consequences

- Every sudo, polkit prompt, greeter login and screen unlock on a desktop needs the key, and admin over SSH happens at the machine instead.
- A touch per SSH connection and per signed commit; `yubikey-touch-detector` notifies where nothing is printed (ly, hyprlock, git, an agent-held key).
- The Mac cannot use the keys until it has Homebrew's openssh, and it keeps its software key in the hosts' `~/.ssh/authorized_keys` meanwhile; I paused the Mac's part on 2026-10-11 ([D43](log.md#d43)).
- Snapshots from before the second factor still take the password alone until they age out, and snapshot entries from before libfido2 drop the YubiKey stage.
- A TPM-PIN typo at lantern's first disk prompt with a key plugged in spends one of that key's FIDO2 PIN tries, so keys stay unplugged at boot ([D42](log.md#d42)), and `dram doctor` shows the tries left.

## How it is checked

- `bin/check.sh` §18 checks the formats of `keys/ssh.pub` and `keys/pam-u2f.txt`, one label per key across them and `.sops.yaml`, and runs `tests/yubikey-t0.sh`: the PAM edits, the map's rules, `--register-yubikey`, the LUKS options, and the refusals of `fido2-enroll.sh` and `dram yubikey`.
- `tests/yubikey-t1.sh`, in an amd64 Arch container, proves the PAM outcomes with the real sudo and pam_u2f, the initramfs contents, the LUKS2 header helper and `sshd -T`.
- `dram doctor` ("yubikeys") says on each host whether sshd takes the keys and whether the second factor is on.
- The real keys are checked by hand at each host's first enrolment: [YubiKeys](../docs/security/identity/yubikeys.md#how-it-is-checked).

## History

- 2026-10-11: accepted and built: `keys/`, `system/pam-u2f.conf`, `system/yubikey-setup.sh` with `system/u2f-selftest.py`, the keys file and touch rule in `system/harden.sh`, `system/fido2-enroll.sh` with `install/lib/luks.sh` (shared with `system/tpm2-enroll.sh`), `bin/yubikey.sh` as `dram yubikey`, and the doctor's checks. The guide: [YubiKeys](../docs/security/identity/yubikeys.md).
- By 2026-10-13: the primary key enrolled on cabin for SSH and age; its pam-u2f line and the spare key are still to come.

# Identity

[Security](../README.md) › Identity

Who a host believes: the two YubiKeys, the SSH keys that log in, and the secrets the flake decrypts at login.
Every Arch host takes the SSH half, and a host with the desktop role takes the second factor.
lantern also unlocks its disk with a key.
The WSL clones borrow the keys from Windows, and the Mac keeps its own software key for now.

| Branch | What it does | Code | Copy alone |
|---|---|---|---|
| [YubiKeys](yubikeys.md) | enrols each key for SSH, git signing, the second factor after the password, sops, and lantern's disk | `bin/yubikey.sh`, `system/yubikey-setup.sh`, `system/pam-u2f.conf`, `system/u2f-selftest.py`, `system/fido2-enroll.sh`, `keys/` ([README](../../../keys/README.md)) | yes: the PAM line and the self-test stand alone; the rest wants the repo's layout |
| [SSH](ssh.md) | keys-only sshd on every host, the YubiKeys' keys in a root-owned keys file, an SSH client that offers the YubiKey first | `system/harden.sh` (its sshd part), `keys/ssh.pub`, `dotfiles/.ssh/` ([README](../../../dotfiles/.ssh/README.md)) | yes |
| [Secrets](secrets.md) | sops-nix: one age key per host and per YubiKey, ciphertext in the repo, plaintext only in tmpfs | `modules/secrets.nix`, `.sops.yaml`, `secrets/` ([README](../../../secrets/README.md)), `system/secrets-bootstrap.sh` | yes, with your own recipients |

## How the branches fit

One enrolment puts three credentials on each YubiKey: a resident SSH key, a pam-u2f credential and an age identity.
Their public halves are the repo's: `keys/ssh.pub`, `keys/pam-u2f.txt` and the `# yubikey:` recipients in `.sops.yaml`.
`bin/check.sh` §18 checks that each label appears in all three, so a key enrolled for part of its jobs shows up as a warning.
sshd reads the SSH keys through `system/harden.sh`, PAM reads the credentials through `system/yubikey-setup.sh`, and sops encrypts for every recipient.
Why two keys, and what each protects: [decision 0019](../../../decisions/0019-yubikeys.md).
PINs, the PUK and lantern's recovery key live in Proton Pass, outside every machine they unlock.

## Operating it

Enrolling a key and the first login with it: [handbook chapter 2](../../records/handbook/02-first-login.md).
Keeping and adding a secret: [handbook chapter 8](../../records/handbook/08-secrets.md).
A lost key and the break-glass: [YubiKeys](yubikeys.md).
Removing a host's key and recipient: [handbook chapter 10](../../records/handbook/10-teardown.md).

## Status

2026-10-13: the Arch hosts take keys-only SSH and the YubiKeys' keys.
On cabin the primary key is enrolled for SSH and age; its pam-u2f line and the spare key come next, and until then `bin/check.sh` warns that `primary` is missing from `keys/pam-u2f.txt`.
sops-nix is off on every host (`secrets.enable = false`): the reinstalls of 2026-10-11 made new host keys, which are not in `.sops.yaml` yet ([Secrets](secrets.md) has the way back).
The Mac's use of the keys is paused ([D43](../../../decisions/log.md#d43)).

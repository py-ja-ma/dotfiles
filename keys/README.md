# keys

[Security](../docs/security/README.md) › [Identity](../docs/security/identity/README.md) › [YubiKeys](../docs/security/identity/yubikeys.md)

The public halves of my two YubiKeys: their SSH keys and their pam-u2f credentials.
Every host reads them to let a key log in over SSH and to ask for a touch after the password at sudo, polkit, the greeter and the lock screen.

| | |
|---|---|
| Needs | OpenSSH 8.2 or later with libfido2, pam-u2f 1.4, a YubiKey with FIDO2 (firmware 5.2.3 or later for `ed25519-sk`); tested 2026-10 |
| Copy alone | yes, with your own keys: the formats and the PAM line stand alone, the enrolment script wants this repo |
| License | the scripts and this README MIT; the keys are public facts with no copyright claim (CC0-1.0) |

## What it needs

- OpenSSH 8.2 or later built with libfido2 for resident security keys: Arch's `openssh` with `libfido2`. Apple's `/usr/bin/ssh` cannot use them; Homebrew's openssh can.
- `pam-u2f` for the second factor, and `yubikey-manager` (`ykman`) to set the key's PINs and switch OTP off.
- `system/pam-u2f.conf` for the PAM line, `system/yubikey-setup.sh` to write it, and `system/u2f-selftest.py` to prove a key answers before it is switched on.
- `.sops.yaml` for the third credential, the age recipient, which lives with the other sops recipients.
- Not needed: Nix, Home Manager or `dram` to use the formats; `bin/yubikey.sh` (`dram yubikey`) only creates the lines.

## Copy it alone

1. Create a resident SSH key on each YubiKey: `ssh-keygen -t ed25519-sk -O resident -O application=ssh:<name> -C yubikey:<label>`. Put the `.pub` line in `ssh.pub`, one line per key, the comment `yubikey:<label>`.
2. Create a pam-u2f credential with `pamu2fcfg -o pam://<name> -i pam://<name>`, with no `-N` or `-V`, so it asks for presence only. Keep the part after the user name as `<label>:<KeyHandle>,<UserKey>,<CoseType>,+presence` in `pam-u2f.txt`.
3. sshd: add `/etc/ssh/authorized_keys.d/%u` as a second `AuthorizedKeysFile` and `PubkeyAuthOptions touch-required`, then write your login's file from `ssh.pub`. `system/harden.sh` shows the drop-in.
4. PAM: write `<login>:` and the credentials, colon-separated, into `/etc/dram/u2f_mappings`, and put the line of `system/pam-u2f.conf` after the password line of `/etc/pam.d/sudo`. Test it with `system/u2f-selftest.py --authfile <map> --user <login>` before you rely on it. Keep a root shell open while you test.
5. Change `pam://dram` to your own origin in both the PAM line and the credentials.

It worked when `ssh` asks for a touch, and `sudo -v` asks for the password and then a touch.

## How it is wired here

`bin/yubikey.sh` (`dram yubikey enroll <label>`) creates the three credentials on a key and prints the lines to commit here.
`system/harden.sh` rewrites `/etc/ssh/authorized_keys.d/<login>` from `ssh.pub` on every run, so a deleted line is gone at the next run.
`system/yubikey-setup.sh` writes the host's map from `pam-u2f.txt`, and switches the second factor on only after a listed key answers a test touch at that machine.
`modules/dev.nix` makes the YubiKey's SSH key git's signing key and puts both keys in `allowed_signers`.
`bin/check.sh` §18 checks both formats, one label per key across `ssh.pub`, `pam-u2f.txt` and `.sops.yaml`, and runs `tests/yubikey-t0.sh`.

## Files

| File | What it does |
|---|---|
| `ssh.pub` | the YubiKeys' resident SSH public keys, one line per key, comment `yubikey:<label>` |
| `pam-u2f.txt` | the YubiKeys' pam-u2f credentials, `<label>:<KeyHandle>,<UserKey>,<CoseType>,+presence` |

Revoking a key is deleting its lines here and in `.sops.yaml`: [A key is lost](../docs/security/identity/yubikeys.md#a-key-is-lost).

## License

This README and the scripts named above: MIT, Patrick Jordan.
The key lines are public keys, facts with no copyright claim (CC0-1.0).

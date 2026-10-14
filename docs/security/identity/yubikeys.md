# YubiKeys

[Security](../README.md) › [Identity](README.md) › YubiKeys

I have two YubiKeys: the primary on my keyring and a spare kept somewhere else.
Both are enrolled for every job, so either one works everywhere.
Losing one means deleting its lines, and the other key still opens everything.
Why two, and what they protect: [decision 0019](../../../decisions/0019-yubikeys.md).

| | |
|---|---|
| Code | `bin/yubikey.sh` (`dram yubikey`), `system/yubikey-setup.sh`, `system/pam-u2f.conf`, `system/u2f-selftest.py`, `system/fido2-enroll.sh`, `keys/ssh.pub`, `keys/pam-u2f.txt` |
| Runs on | every Arch host for SSH; hosts with the desktop role for the second factor and age; lantern for its disk; the WSL clones through Windows |
| Needs | `libfido2` (in `packages/base.txt`); on desktop hosts `pam-u2f`, `yubikey-manager`, `age-plugin-yubikey`, `pcsclite` and `ccid` (`pcscd.socket`), `yubikey-touch-detector`; tested 2026-10 |
| Decided in | [0019](../../../decisions/0019-yubikeys.md), [D34](../../../decisions/log.md#d34) to [D43](../../../decisions/log.md#d43) |

## What each key holds

| Job | On the key | In the repo | On each host |
|---|---|---|---|
| SSH logins, git signing | a resident `ed25519-sk` key (`ecdsa-sk` below firmware 5.2.3), application `ssh:dram-<label>` | `keys/ssh.pub` | sshd reads `/etc/ssh/authorized_keys.d/<login>` (`system/harden.sh`); the handle `~/.ssh/id_ed25519_sk_rk_dram-<label>` and the link `~/.ssh/id_ed25519_sk` (`dram yubikey ssh`) |
| The second factor after the password: sudo, polkit, ly, hyprlock, the console | a pam-u2f credential, origin `pam://dram`, `+presence` only | `keys/pam-u2f.txt` | the pam_u2f line of `system/pam-u2f.conf` in `/etc/pam.d/{sudo,login,polkit-1}`, and `/etc/dram/u2f_mappings` (`system/yubikey-setup.sh`) |
| Secrets (sops) | an age identity in a PIV slot: the PIN once, a touch per decryption | `.sops.yaml` (`# yubikey:` recipients) | a stub `~/.config/sops/age/yubikey-<label>.txt`, which is not secret |
| lantern's disk | a FIDO2 credential (PIN and touch) in the LUKS2 header | none | one LUKS2 slot per key, listed in `/etc/dram/luks-fido2` (`system/fido2-enroll.sh`) |

Into Proton Pass go each key's label and serial, its FIDO2 PIN, its PIV PIN and PUK, and lantern's LUKS recovery key.
A wrong FIDO2 PIN spends one of 8 tries, and only a right FIDO2 PIN refills them.
At 0 tries FIDO2 on that key is locked until a reset, and a reset wipes every FIDO2 credential on it: SSH, pam-u2f and LUKS.
`dram yubikey status` and `dram doctor` show the tries left of a key that is plugged in.

## Enrol a key

Do this once per key, on an Arch host with the desktop role, at the machine and not over SSH, with the key plugged in alone, as your login user:

```sh
dram yubikey enroll primary     # then the other key alone: dram yubikey enroll spare
```

It walks five steps and asks before anything it changes on the key:

1. OTP over USB goes off. A touch while nothing waits for one would otherwise type a one-time password and Enter into whatever has focus, and faillock counts it as a wrong password at ly, hyprlock or sudo.
2. The FIDO2 PIN is set, if the key has none.
3. The SSH key is created (the PIN, then a touch).
4. The pam-u2f credential is created (a touch).
5. The age identity: first the PIV PIN and PUK move off the factory values and the management key becomes a random TDES key the PIN protects, then the identity is made. age-plugin-yubikey 0.5.1 handles only that management key, and firmware 5.7 ships AES-192. `--no-age` skips this step.

It then prints the lines to run in `~/git/dotfiles`, on this host (the Mac pulls the commit) or on the Mac.
They hold public halves only:

```sh
printf '%s\n' 'sk-ssh-ed25519@openssh.com AAAA… yubikey:primary' >>keys/ssh.pub
printf '%s\n' 'primary:<KeyHandle>,<UserKey>,es256,+presence' >>keys/pam-u2f.txt
bash system/secrets-bootstrap.sh --register-yubikey primary age1yubikey1…
git add keys .sops.yaml && git commit -m "keys: enrol the primary YubiKey"
```

Release, then on every host run `dram update`, `dram apply` and `dram yubikey ssh`.
`dram apply` asks before `harden.sh`, `yubikey-setup.sh` and, on lantern, `fido2-enroll.sh`.
`dram yubikey ssh` asks for the FIDO2 PIN and a touch, once per key you want on that host.

## What switches on, and when

| Part | Switches on |
|---|---|
| sshd | on every host as soon as `harden.sh` has run: it rewrites `/etc/ssh/authorized_keys.d/<login>` from `keys/ssh.pub` every time, and `PubkeyAuthOptions touch-required` makes every security-key login a touch. The host's own `~/.ssh/authorized_keys` keeps working beside it, which is where the Mac's software key sits. |
| The second factor | per desktop host, the first time `yubikey-setup.sh` runs there with a listed key plugged in: it asks for one touch through pam_u2f itself (`system/u2f-selftest.py`) and only then writes this login's line. Over SSH, or with no key plugged in, it changes nothing and says so. Once on, later runs follow `keys/pam-u2f.txt` without a touch. |
| The SSH client | offers `~/.ssh/id_ed25519_sk` first (`dotfiles/.ssh/config`), then the host's own key; an absent YubiKey fails at once and ssh moves on. |
| git signing | as soon as `keys/ssh.pub` lists a key (`modules/dev.nix`). Run `dram yubikey ssh` on each host first, or commits fail with "Couldn't load public key ~/.ssh/id_ed25519_sk.pub". `dram yubikey use spare` points the link at the spare. |

## Daily use

| You do | You see |
|---|---|
| `sudo …` | the password, then "Please touch the FIDO authenticator." and the key blinks |
| a polkit prompt (hyprpolkitagent) | the password, then the same text in the dialog; touch |
| log in at ly or on a console, unlock hyprlock | the password, then a touch: ly and hyprlock print nothing, the key blinks and a notification says it waits |
| `ssh <host>`, `git commit` | a touch; a rebase of N commits is N touches |
| `SOPS_AGE_KEY_FILE=~/.config/sops/age/yubikey-primary.txt sops secrets/pj.yaml` | the PIV PIN once, then a touch |

sudo over SSH on a desktop host needs the key at that machine, so it fails there ([D34](../../../decisions/log.md#d34)).
Do admin at the keyboard: `dram rollback`, `dram update`, `dram apply`.
Headless hosts (no desktop role) have no pam_u2f, and their sudo asks for the password only.
Their SSH logins take a touch only while `~/.ssh/authorized_keys` there holds no software key, so keep it empty on them once the Mac uses its YubiKey.

## lantern's disk

`system/fido2-enroll.sh` enrols one key per run, from `dram apply` or by hand with the key alone plugged in.
It also keeps the volume in the shape the boot needs: the TPM2 slot at priority `prefer`, libfido2 inside the UKI, and `rd.luks.options=tpm2-device=auto,fido2-device=auto,tries=0,discard`.
The boot then asks:

| Situation | What to do |
|---|---|
| a normal boot | keys unplugged; type the TPM PIN at "Please enter LUKS2 token PIN" |
| the TPM refuses, after a firmware update or a Secure Boot key change | plug in one key before power-on, type that key's FIDO2 PIN at the first prompt, then touch it. Not knowing yet, type the TPM PIN, then the key's PIN at "Please enter security token PIN", then touch promptly: a missed touch there means a reboot |
| no key at hand | at "security token PIN" type anything and wait 30 s; the recovery key prompt follows, as often as needed |
| never | type the recovery key at a PIN prompt: it counts as a wrong PIN on the TPM and on a plugged-in key |
| afterwards | `sudo bash ~/git/dotfiles/system/tpm2-enroll.sh --reenroll`: a TPM slot for the new PCR 7 |

Keys stay unplugged at boot because the first prompt tries the one PIN against every token ([D42](../../../decisions/log.md#d42)).
A TPM-PIN typo with a key plugged in spends one of that key's FIDO2 PIN tries, and only a right FIDO2 PIN refills them.
The `prefer` priority makes the boot ask the TPM first.
The TPM half of this disk: [Boot trust](../boot-trust/README.md).

## A key is lost

1. On the Mac, delete its line from `keys/ssh.pub` and `keys/pam-u2f.txt` and its lines in `.sops.yaml` (`# yubikey: <label>`, `&yk_<label>`, `*yk_<label>`), then run `sops updatekeys secrets/pj.yaml` on a machine that still decrypts. Commit and release.
2. On each host run `dram update` and `dram apply`: sshd and the pam_u2f map drop the lost key with no touch needed. Where `~/.ssh/id_ed25519_sk` pointed at it, run `dram yubikey use spare`.
3. On lantern run `sudo bash ~/git/dotfiles/system/fido2-enroll.sh --wipe <label>`. The slot comes from `/etc/dram/luks-fido2`, and the wipe needs no key and no unlock.
4. Buy a replacement and enrol it under a new label.

## Both keys lost

Root is locked, so with both keys lost no sudo works on a desktop host.
The break-glass is an empty map: with no line in it, pam_u2f asks nobody (`nouserok`).
Boot the Arch ISO with Secure Boot off in the firmware for that one boot, since the ISO is not signed with my keys, then:

```sh
mount -o subvol=@ /dev/disk/by-label/dram-sys /mnt              # a desktop
# lantern: cryptsetup open /dev/disk/by-label/dram-sys dram-sys   (the recovery key, Proton Pass)
#          mount -o subvol=@ /dev/mapper/dram-sys /mnt
: >/mnt/etc/dram/u2f_mappings
umount /mnt
```

Reboot, switch Secure Boot back on, log in with the password alone, and enrol new keys.
While sudo still works, `sudo bash ~/git/dotfiles/system/yubikey-setup.sh --off` does the same.
Snapshots from before the second factor still log in with the password alone until they age out, 12 plus 6 by [decision 0011](../../../decisions/0011-disk-boot-secure-boot-snapshots.md).
To drop them early, list them with `dram rollback --system` and delete each with `sudo snapper -c root delete <n>`.

## The Mac

The Mac keeps its own software key in each host's `~/.ssh/authorized_keys` and does not use the YubiKeys: I paused that on 2026-10-11 ([D43](../../../decisions/log.md#d43)).
Apple's `/usr/bin/ssh` (OpenSSH 10.5) knows the security-key types but has no `SecurityKeyProvider`, so it could not use them anyway.
When the pause ends, Homebrew's openssh, built with libfido2, is the route:

```sh
brew install openssh ykman age age-plugin-yubikey sops
hash -r; ssh -V                                     # prints: OpenSSH_10.6p1 from /opt/homebrew/bin
cd ~/.ssh && ssh-keygen -K -N ''                    # per key: PIN + touch -> id_ed25519_sk_rk_dram-<label>
```

Then name the keys in the Mac's own `~/.ssh/config` by host name, so the launchd jobs that connect by address keep the software key:

```sshconfig
Host cabin lantern campfire
    IdentityFile ~/.ssh/id_ed25519_sk_rk_dram-primary
    IdentityFile ~/.ssh/id_ed25519_sk_rk_dram-spare
    IdentitiesOnly yes
    AddKeysToAgent no              # Apple's agent accepts sk keys and then cannot sign
```

Do not create `~/.ssh/id_ed25519_sk` on the Mac: it would become a default identity of every ssh, the BatchMode jobs included.
macOS needs no pcscd, and GUI apps do not see `/opt/homebrew/bin`.

## The WSL clones

Windows keeps the key ([decision 0021](../../../decisions/0021-wsl-clone.md), [D79](../../../decisions/log.md#d79)).
ssh and git signing in a clone ask Windows' OpenSSH agent through `wsl2-ssh-agent` (`modules/dev.nix`), and the touch is Windows Hello's dialog.
The clone needs only the public half as `~/.ssh/id_ed25519_sk.pub`: ssh and `ssh-keygen -Y sign` find the private half in the agent, and Windows' agent gets the key with `ssh-add -K`.
sshd in the clone listens on `127.0.0.1:2222` only, for VSCodium on the same PC, with the same `/etc/ssh/authorized_keys.d/<login>` and touch rule (`system/wsl-setup.sh`).
A clone has no pam_u2f: Windows' administrator is root of the clone anyway.
On demand, `usbipd attach --wsl` gives the key to the clone alone, and `dram yubikey ssh` then works as on Arch.
The steps: [the WSL page](../../platforms/wsl/README.md).

## How it works

| Choice | Why |
|---|---|
| One origin for the fleet, `pam://dram` ([D40](../../../decisions/log.md#d40)) | a credential works on every host. The price, judged small: root on one host plus your password for another plus a touch you were fooled into could open sudo on the other. |
| Fail open, only through root-owned state ([D41](../../../decisions/log.md#d41)) | the map missing or without your line, or pam-u2f uninstalled, means the password alone; `dram doctor` says "second factor OFF" whenever that is the case. |
| The PAM line written into each service | a PAM `include` of a missing file fails the whole stack, so a missing include would lock sudo. |
| No `/etc/security/pam_u2f.conf` | its options would reach every line; `dram doctor` checks for it, and checks hyprlock's and ly's PAM files and polkit's helper drop-in. |

pam-u2f is quiet upstream: no release since 2025-03, and Yubico answered issues until 2026-04.
It passes the three rules, and its register row is re-checked monthly.

## How it is checked

- `tests/yubikey-t0.sh` runs in `bin/check.sh` §18 with no key: the PAM edits, the map's on and off rules, `+presence` only, `--register-yubikey` with both recipient formats, `install/lib/luks.sh`'s options and priority, `fido2-enroll.sh`'s refusals (no libfido2, two keys, no FIDO2 PIN) and `dram yubikey`'s refusals.
- `bin/check.sh` §18 also checks the formats of `keys/ssh.pub` and `keys/pam-u2f.txt` and warns when a label is missing from one of them or from `.sops.yaml`.
- `tests/yubikey-t1.sh` runs by hand in a throwaway amd64 Arch container, in about 3 minutes, with the real sudo, pam_u2f 1.4.0 and Linux-PAM. It proves the outcomes: no map line gives the password alone; a map line and no key are refused and faillock counts nothing; pam-u2f uninstalled or the map missing gives the password alone. It also shows that the self-test fails in 0.15 s with no key, that mkinitcpio 42 puts libfido2, libcbor and the FIDO2 token plugin into the image by itself, `install/lib/luks.sh` against a real LUKS2 header, and the sshd drop-in through `sshd -T`. sshd cannot accept a login there (its seccomp sandbox fails under Rosetta), so the second keys file is proven on hardware.
- On hardware, with both keys, at a host's first enrolment: `ykman info` on both for the firmware, and a touch at sudo, `sudo -i`, ly, a console, hyprlock (also after suspend) and a polkit prompt. With no key, sudo is refused and `faillock` stays unchanged, and a stray touch types nothing. ssh from the Mac works, a signed commit verifies with `git log --show-signature`, and a sops round trip succeeds. On lantern also a normal boot, each key with the TPM refusing (Secure Boot off changes PCR 7), a wrong PIN, a missed touch, no key, a resume from hibernation, a snapshot entry, and the lost-key drill with the spare.

## Left out

| Not used | Why |
|---|---|
| pam_u2f as `sufficient`, a touch instead of the password | one factor, not two |
| an exemption for sudo over SSH | no stock PAM module can tell an SSH sudo from a local one. A logind check is possible but only safe once every shell login needs a security key; revisit then. |
| the OpenPGP applet (gpg-agent for SSH and signing) | more moving parts: FIDO2 SSH keys and age-plugin-yubikey cover the same jobs with OpenSSH and age alone |
| yubikey-full-disk-encryption (challenge-response) | systemd-cryptenroll's FIDO2 support is built in and maintained with systemd |
| Yubico Authenticator from Flathub | an unverified community repack; `ykman oath` covers TOTP on the key from the command line if it is ever wanted |

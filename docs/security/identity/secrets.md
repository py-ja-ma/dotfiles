# Secrets

[Security](../README.md) › [Identity](README.md) › Secrets

Secrets the flake feeds to a program live in `secrets/pj.yaml` as sops ciphertext, and sops-nix decrypts them into tmpfs at login.
`modules/secrets.nix` is imported on every host and does nothing until that host sets `dram.secrets.enable = true`, so a new machine can `dram switch` before it has a key.
The ciphertext is public in this repo: it opens only with an age key that never leaves a host or a YubiKey.

| | |
|---|---|
| Code | `modules/secrets.nix`, `.sops.yaml`, `secrets/` ([README](../../../secrets/README.md)), `system/secrets-bootstrap.sh` |
| Runs on | any host that sets `dram.secrets.enable`; none does since 2026-10-11 (Status, below) |
| Needs | `sops` and `age` from `~/.nix-profile/bin` (`modules/dev.nix`); sops-nix pinned by `flake.lock`; `age-plugin-yubikey` for the YubiKeys |
| Decided in | [0019](../../../decisions/0019-yubikeys.md) for the YubiKeys as recipients |

## What goes where

| Thing | Where | Tracked |
|---|---|---|
| a host's age private key | `~/.config/sops/age/keys.txt` (file 0600, directory 0700), one per host | never; it is inside the Borg set, since `~/.config` is a source directory (Custody, below) |
| the age public keys | `.sops.yaml`: a `# host: <name>` marker and an `&<name>` anchor per host, `# yubikey: <label>` and `&yk_<label>` per YubiKey | yes |
| the secrets | `secrets/pj.yaml`, sops ciphertext for every recipient in `.sops.yaml` | yes: the flake only sees tracked files |
| decrypted copies | `$XDG_RUNTIME_DIR/secrets.d/<generation>/…` (tmpfs), written by the `sops-nix.service` user unit at login and on every `dram switch`; the stable link `~/.config/sops-nix/secrets/<name>` is `config.sops.secrets.<name>.path`, mode 0400 | no |
| plaintext scratch | `secrets/*.plain`, `*.plain.yaml` | no: gitignored, and `bin/check.sh` §7 refuses them |

The one consumer is the Borg passphrase.
With the flag on, `modules/backup.nix` reads it from the sops-nix secret instead of the hand-placed `~/.config/borgmatic/passphrase`, and the borgmatic user service orders itself after `sops-nix.service`.
With the flag off nothing under `config.sops.*` is evaluated.
`sops.validateSopsFiles` (on by default) checks `secrets/pj.yaml` at evaluation, so the file must exist and be tracked before a host turns the flag on.

## Turn it on

Every step by hand is a mode of `system/secrets-bootstrap.sh`: idempotent, with `--dry-run` on every mode.
The order matters: a key on each host, every key registered on the Mac and committed, the secret written once, then the flag per host.

```sh
# 1. each host: a key for THIS host; prints its public key
bash ~/git/dotfiles/system/secrets-bootstrap.sh
#    re-print it any time: age-keygen -y ~/.config/sops/age/keys.txt

# 2. the Mac: register each public key (refuses a malformed key; a no-op if already set)
bash system/secrets-bootstrap.sh --register cabin   age1...
bash system/secrets-bootstrap.sh --register lantern age1...
git add .sops.yaml && git commit -m "sops: register cabin and lantern"
#    then get the commit onto the hosts (bin/push-host.sh, or a release)

# 3. one host: encrypt the current Borg passphrase into secrets/pj.yaml
bash ~/git/dotfiles/system/secrets-bootstrap.sh --init-borg
#    reads ~/.config/borgmatic/passphrase (0600) into a 0600 temp file, encrypts it for every
#    recipient, verifies, git add; never prints the value
git commit -m "secrets: borg_passphrase"

# 4. the host files: dram.secrets.enable = true; inside the dram = { ... }; block, commit

# 5. each host
dram switch                                        # evaluates pj.yaml, starts sops-nix.service
systemctl --user status sops-nix                   # a oneshot: "inactive (dead)" and Succeeded is the good state
ls -lL ~/.config/sops-nix/secrets/borg_passphrase  # -r-------- (0400), in $XDG_RUNTIME_DIR/secrets.d
dram doctor                                        # the "secrets" section: unit result, secret 0400, key 0600
```

`bash system/secrets-bootstrap.sh --verify` on a host decrypts `borg_passphrase`, compares its sha256 with `~/.config/borgmatic/passphrase`, and prints only match or MISMATCH.
`~/.config/borgmatic/passphrase` stays until you delete it: `--verify` compares against it, and `dram doctor`'s backup section still expects it.

## Custody

The Borg source set includes `~/.config`, so each host's age private key is in its own Borg archive, encrypted with the Borg passphrase.
That lets a dead disk restored from Borg bring the age key back, and with it the host's view of `secrets/pj.yaml`.
The loop: restoring the archive needs the Borg passphrase, and the passphrase is the secret that needs the age key.
It is broken outside the machines: the Borg passphrase, and `borg key export` per repo, live in Proton Pass ([the backups page](../../operations/backups/README.md)).
A full rebuild is then the passphrase from Proton Pass, `borg extract` of `~/.config/sops/age/keys.txt`, and `dram switch`.
Without the archive, `age-keygen` a fresh key, `--register` it, and run `sops updatekeys secrets/pj.yaml` where a key still decrypts.
Backups are paused until the NAS ([decision 0014](../../../decisions/0014-backups-paused-until-nas.md)), so until then Proton Pass alone holds the passphrase.

## The YubiKeys as recipients

Each YubiKey carries an age identity in a PIV slot (age-plugin-yubikey) and is a recipient beside the hosts.
`bash system/secrets-bootstrap.sh --register-yubikey <label> age1yubikey1…`, on the Mac with the line `dram yubikey enroll` prints, adds `# yubikey: <label>` and `&yk_<label>` to `.sops.yaml` and `*yk_<label>` to the creation rule.
Either key then edits and re-keys `secrets/pj.yaml` on any machine with age-plugin-yubikey, with no surviving host needed:

```sh
SOPS_AGE_KEY_FILE=~/.config/sops/age/yubikey-primary.txt sops secrets/pj.yaml              # the PIV PIN, a touch
SOPS_AGE_KEY_FILE=~/.config/sops/age/yubikey-primary.txt sops updatekeys secrets/pj.yaml
```

The identity file is a stub that names the key and slot; the private key never leaves the YubiKey.
It stays out of `keys.txt`: sops-nix decrypts at login with the host's software key and must never wait for a PIN or a touch.
`--init-borg` encrypts for the YubiKeys too.

## Add a secret

```sh
sops secrets/pj.yaml            # add `name: value`; sops encrypts it for every recipient
```

Then declare `sops.secrets.<name> = { };` (with `mode` or `path` if needed) in `modules/secrets.nix`, and read it as `config.sops.secrets.<name>.path`.
Read it behind `config.dram.secrets.enable`, and never as a string in the Nix store.

## Add, re-key or forget a host

A new host: its key (step 1), a new `# host: <name>` and `&<name>` pair in `.sops.yaml` with the anchor under `key_groups`, `--register`, then `sops updatekeys secrets/pj.yaml` from a host that already decrypts, a commit, and the flag on the new host.
`--register` refuses to overwrite a real key, so re-keying is the same edit by hand followed by `updatekeys`.

`bin/forget-host.sh <host> --execute` on the Mac drops the host's `# host:` marker, its `&<host>` anchor and the `*<host>` reference from `.sops.yaml`.
sops is not on the Mac, so it prints the `sops updatekeys -y secrets/pj.yaml` to run on a host that still decrypts.
Every earlier commit of `secrets/pj.yaml` stays readable with the forgotten host's age key.
Destroying that key is the host's own step, `system/decommission.sh --execute --delete-age-key`, and it cannot be undone.
The order of a teardown: [handbook chapter 10](../../records/handbook/10-teardown.md).

## Status

2026-10-13: sops-nix is off on every host (`secrets.enable = false` in each `modules/hosts/<host>.nix`).
The reinstalls of 2026-10-11 made new host keys, and `.sops.yaml` still names the keys of the installs before them.
`secrets/pj.yaml` was last written on 2026-10-06, for those two host keys only; the primary YubiKey became a recipient in `.sops.yaml` later.
To turn sops-nix back on, run the steps above from step 1; step 3 writes `pj.yaml` again from the passphrase in Proton Pass.

## Left out

| Not used | Why |
|---|---|
| a plain secrets file in the repo | the one thing this repo must never contain |
| `programs.ssh` or `config.d/*.conf` in sops | they stay gitignored and placed by hand: sops-nix is for secrets the flake has to feed to a program |
| agenix | fine too; sops-nix won because `sops` and `age` were already in `home.packages`, and sops edits YAML in place |

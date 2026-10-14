# secrets

[Security](../docs/security/README.md) › [Identity](../docs/security/identity/README.md) › [Secrets](../docs/security/identity/secrets.md)

sops-encrypted YAML that sops-nix decrypts into tmpfs at login, on a host that sets `dram.secrets.enable = true`.
Only ciphertext is tracked: it opens with an age key that never leaves a host or a YubiKey, so this directory can be public.

| | |
|---|---|
| Needs | sops 3.13 and age (`modules/dev.nix`), sops-nix through `flake.lock`, age-plugin-yubikey for the YubiKeys; tested 2026-10 |
| Copy alone | yes, with your own recipients and your own `pj.yaml` |
| License | this README and the scripts MIT; `pj.yaml` is ciphertext of my own secret, not for reuse |

## What it needs

- `.sops.yaml` at the repo root: the age recipients (a `# host: <name>` marker and an `&<name>` anchor per host, `# yubikey: <label>` and `&yk_<label>` per YubiKey) and the creation rule for `secrets/*.yaml`.
- `modules/secrets.nix`, the Home Manager side: the host's age key file, `pj.yaml` as the default sops file, and one declaration per secret.
- `system/secrets-bootstrap.sh`, every by-hand step made idempotent: a host key, `--register`, `--register-yubikey`, `--init-borg`, `--verify`.
- Not needed to decrypt by hand: Nix. `sops -d secrets/pj.yaml` works with a recipient's key anywhere sops and age are installed.

## Copy it alone

1. Make an age key per machine: `age-keygen -o ~/.config/sops/age/keys.txt`, with the file 0600 and the directory 0700.
2. Write your own `.sops.yaml` with each machine's public key (`age-keygen -y ~/.config/sops/age/keys.txt`) and a creation rule for `secrets/.*\.yaml`.
3. Delete `pj.yaml`: it is mine, encrypted for my keys. Create yours with `sops secrets/<name>.yaml`.
4. For Home Manager, import `modules/secrets.nix` with your file name, and read each secret as `config.sops.secrets.<name>.path`.

It worked when `sops -d secrets/<name>.yaml` prints the plaintext on a machine whose key is a recipient, and fails on one whose key is not.

## How it is wired here

`modules/secrets.nix` is imported on every host and does nothing until a host sets `dram.secrets.enable = true`.
With the flag on, `modules/backup.nix` reads the Borg passphrase from the decrypted secret.
`bin/check.sh` §7 refuses any tracked file that looks like a decrypted secret or a private key, and allows exactly this README and the `secrets/*.yaml` ciphertext.
`bin/forget-host.sh` removes a host from `.sops.yaml` when the host is retired.
On 2026-10-13 the flag is off on every host: [Secrets](../docs/security/identity/secrets.md) says why and how to turn it on again.

## Files

| File | What it does |
|---|---|
| `pj.yaml` | the one secrets file: `borg_passphrase`, sops ciphertext, last written 2026-10-06. Edit with `sops secrets/pj.yaml` and commit |
| `*.plain`, `*.plain.yaml` | scratch plaintext, never tracked: gitignored, and `bin/check.sh` §7 refuses them |

## License

This README, `modules/secrets.nix` and `system/secrets-bootstrap.sh`: MIT, Patrick Jordan.
`pj.yaml` holds my own secret; copy the layout, not the file.

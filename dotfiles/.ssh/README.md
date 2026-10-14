# .ssh

[Security](../../docs/security/README.md) › [Identity](../../docs/security/identity/README.md) › [SSH](../../docs/security/identity/ssh.md)

An SSH client config with safe defaults: the YubiKey first, keys named explicitly, multiplexed connections, no agent forwarding.
Private host definitions stay out of git in `config.d/`, which the config includes first.

| | |
|---|---|
| Needs | OpenSSH 8.2 or later (built with libfido2 for the YubiKey); tested 2026-10 with Arch's openssh |
| Copy alone | yes |
| License | MIT |

## What it needs

- OpenSSH 8.2 or later; a security key needs it built with libfido2 (Arch's `openssh` and `libfido2`, or Homebrew's openssh on a Mac).
- `~/.ssh/id_ed25519_sk`, a link to a YubiKey's resident key handle, which `dram yubikey ssh` makes; without it ssh skips to the next key.
- `~/.ssh/id_ed25519`, the machine's own key, as the fallback.
- `~/.ssh/sockets/`, mode 0700, for the multiplexed connections: ssh does not create it.
- Not needed: Nix, Home Manager or `dram`.

## Copy it alone

1. Copy `config` to `~/.ssh/config`, mode 0600.
2. `mkdir -m 700 -p ~/.ssh/sockets ~/.ssh/config.d`.
3. Put private host blocks in `~/.ssh/config.d/<name>.conf`, mode 0600: `config.d/README.md` has an example. They load first, so their settings win.
4. Without a YubiKey, delete the `IdentityFile ~/.ssh/id_ed25519_sk` line, or leave it: a missing file is skipped.

It worked when `ssh -G <host> | grep -E '^identityfile|^controlmaster'` shows the two keys and `auto`.

## How it is wired here

`modules/cli.nix` links `config` into `~/.ssh/config` on every host and creates `~/.ssh/sockets`.
`dram yubikey ssh` copies the YubiKey's handles into `~/.ssh` and makes the `id_ed25519_sk` link; `dram yubikey use <label>` points it at the other key.
`modules/dev.nix` makes the same YubiKey key git's signing key.
The server side is `system/harden.sh`: [SSH](../../docs/security/identity/ssh.md).

## Files

| File | What it does |
|---|---|
| `config` | the defaults: the YubiKey, then the machine's key, `IdentitiesOnly`, `accept-new` host keys, keep-alives, multiplexing, no forwarding |
| `config.d/README.md` | how to add private host blocks; only this README is tracked, `*.conf` files there are gitignored |

## License

MIT, Patrick Jordan.

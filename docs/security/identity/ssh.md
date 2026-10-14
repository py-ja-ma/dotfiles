# SSH

[Security](../README.md) › [Identity](README.md) › SSH

sshd on every Arch host takes keys only, and a YubiKey's key needs a touch for every login.
The YubiKeys' public keys reach every host through a second, root-owned keys file that `system/harden.sh` rewrites from `keys/ssh.pub`.
The client offers the YubiKey first and falls back to the machine's own key.

| | |
|---|---|
| Code | `system/harden.sh` (its sshd step), `keys/ssh.pub` ([README](../../../keys/README.md)), `dotfiles/.ssh/config` and `dotfiles/.ssh/config.d/` ([README](../../../dotfiles/.ssh/README.md)), `system/wsl/sshd.conf` for the WSL clones |
| Runs on | every Arch host on its own hardware; the WSL clones listen on `127.0.0.1:2222` only; cabin-win runs Windows' OpenSSH |
| Needs | OpenSSH 8.2 or later with libfido2 for security keys (Arch's `openssh` and `libfido2`, tested 2026-10) |
| Decided in | [0019](../../../decisions/0019-yubikeys.md), [D36](../../../decisions/log.md#d36), [D60](../../../decisions/log.md#d60) |

## The server

`harden.sh` writes this drop-in, `/etc/ssh/sshd_config.d/10-keys-only.conf`, and reloads sshd only after `sshd -t` accepts it:

```sshdconfig
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys /etc/ssh/authorized_keys.d/%u
PubkeyAuthOptions touch-required
```

The first keys file is the host's own: the Mac's software key and any one-off line.
The second, `/etc/ssh/authorized_keys.d/<login>`, holds the YubiKeys' lines of `keys/ssh.pub` and is rewritten on every run, so a key deleted there is gone here at the next `harden.sh`.
`touch-required` makes a security key prove a touch on every login, whatever a key line says.

Two guards keep a host reachable:

- `harden.sh` refuses to switch password logins off while neither keys file holds a key. A fresh host cannot lock itself out; copy a key in from the Mac first (`ssh-copy-id`).
- After the reload it reads `sshd -T` and says so when the second keys file is not in effect. Arch reads `sshd_config.d/` at the top of `sshd_config`, where the first value wins.

The firewall admits port 22 from `$LAN` only ([Firewall](../network/firewall.md)).
`dram doctor --supply` warns when `PasswordAuthentication no` is missing from the files; it reads the files, since `sshd -T` needs root.

## The client

`dotfiles/.ssh/config` is linked into `~/.ssh/config` by `modules/cli.nix` on every host:

- It includes `~/.ssh/config.d/*.conf` first, so private per-host settings override its defaults. That directory stays out of git, and only its README is tracked.
- It offers `~/.ssh/id_ed25519_sk` (the YubiKey handle `dram yubikey ssh` links) and then `~/.ssh/id_ed25519`, with `IdentitiesOnly yes`. An absent YubiKey fails at once and ssh moves on.
- It accepts a new host's key and fails hard on a changed one (`StrictHostKeyChecking accept-new`).
- It multiplexes connections (`ControlMaster auto`, sockets in `~/.ssh/sockets`) and never forwards the agent or X11. Nested hosts are reached with `ProxyJump`.

## Windows and the WSL clones

cabin-win runs Windows' OpenSSH, key-only since 2026-10-12, with the Mac's key in `C:\ProgramData\ssh\administrators_authorized_keys`.
cabin-win answers at the address Arch uses on the same PC, so the Mac checks its host key as `HostKeyAlias cabin-win` on a connection of its own (`bin/push-windows.sh`).
That way Arch answering at the address is refused, not written into `known_hosts`.
On thermos, sshd stays Manual and admits only the Private profile and the local subnet, keys only ([D60](../../../decisions/log.md#d60)).
A WSL clone's sshd (`system/wsl/sshd.conf`) listens on `127.0.0.1:2222` for VSCodium on the same PC, keys only, with the same second keys file and touch rule; the YubiKey there is Windows' ([YubiKeys](yubikeys.md)).

## When it breaks

| Symptom | Check | Fix |
|---|---|---|
| `Permission denied (publickey)` with the key plugged in | `ssh -v <host> 2>&1 \| grep -E 'Offering\|sk-'`; on the host, `dram doctor` | `dram yubikey ssh` restores the handles; on the host, `sudo bash system/harden.sh` when its keys file differs from `keys/ssh.pub` |
| locked out after `harden.sh` | at the console: `grep 'define LAN' system/nftables.conf` against `ip -4 route \| grep -w src` | fix `define LAN` in `system/nftables.conf`, then `sudo bash system/harden.sh` again |
| `Permission denied (publickey)` from a new machine | `dram doctor --supply` shows `PasswordAuthentication no` | a YubiKey needs no host change: `ssh-keygen -K` on the new machine loads the handles every host already accepts. Else append that machine's public key to `~/.ssh/authorized_keys` from a machine that has access |

More symptoms: [handbook chapter 11](../../records/handbook/11-troubleshooting.md).

## Limits

The host's own `~/.ssh/authorized_keys` is not managed: it is the place for the Mac's software key and for one-off lines, and nothing removes a line from it.
A software key there logs in without a touch, so a headless host's SSH takes a touch only while that file holds no software key.

# Host hardening

[Security](../README.md) › [Network](README.md) › Host hardening

`system/harden.sh` hardens an Arch host in one idempotent run: the firewall, keys-only sshd, kernel limits, DNS over TLS, a lockout that recovers by itself, sudo, and the greeter.
It is an `ask` hook of `dram apply` on every host on its own hardware, because a mistake there costs remote access.
`--dry-run` prints every change and needs no root.

| | |
|---|---|
| Code | `system/harden.sh`, `system/nftables.conf`, `keys/ssh.pub` |
| Runs on | every Arch host on its own hardware (`system/apply-hooks.tsv`: role `metal`, mode `ask`) |
| Needs | nftables, openssh, systemd-resolved, sudo, and ly through `system/apply-ly.sh`; tested 2026-10 |
| Decided in | written 2026-10-05, applied 2026-10-06; the YubiKeys' keys file since [decision 0019](../../../decisions/0019-yubikeys.md) |

## What it changes

| Step | Writes | Why |
|---|---|---|
| 1. Firewall | `/etc/nftables.conf` from `system/nftables.conf`, checked with `nft -c` first; nftables enabled and restarted; `/etc/nftables.d/00-none.nft` | default deny, SSH and LocalSend from the LAN only ([Firewall](firewall.md)) |
| 1b. sshd | `/etc/ssh/sshd_config.d/10-keys-only.conf`; `/etc/ssh/authorized_keys.d/<login>` from `keys/ssh.pub` | keys only, a touch for a security key ([SSH](../identity/ssh.md)) |
| 2. sysctl | `/etc/sysctl.d/99-hardening.conf` | kernel pointers and dmesg hidden, unprivileged BPF off and the JIT hardened, ptrace limited, kexec off, protected links, FIFOs and files, ICMP redirects and source routes refused, martians logged |
| 3. DNS | `/etc/systemd/resolved.conf.d/dot.conf` | Quad9 over TLS where offered, LLMNR and mDNS off ([DNS](dns.md)) |
| 4. faillock | `/etc/security/faillock.conf` | 5 tries, then a 10-minute lock |
| 5. sudo | `/etc/sudoers.d/10-hardening`, checked with `visudo -c` first | a 10-minute ticket per terminal, no password echo |
| 6. Greeter | ly through `system/apply-ly.sh` | no empty password at ly, enabled on tty2 |
| 7. Tools | pacman-contrib, arch-audit, rsync | `pacdiff`, the CVE check, the backup transport |

Run it again after editing `system/nftables.conf` or `keys/ssh.pub`.
`dram doctor --supply` warns when password logins or the firewall come back.

## Choices worth knowing

User namespaces stay on: Chromium's and LibreWolf's sandboxes, Flatpak's bubblewrap and Steam's pressure-vessel need them.
The sysctl file says so where the setting would go, so nobody switches them off by mistake.

faillock allows 5 tries with a 10-minute unlock, because the default of 3 once locked me out at hyprlock.
**Never** set `even_deny_root`: with root locked, a locked account would have no way back.
`/run/faillock` is tmpfs, so a reboot clears every counter, and `faillock --user <login> --reset` clears one from any shell that is still logged in.

sudo keeps asking for a password.
There is no `NOPASSWD` rule anywhere: the one for `papirus-folders` left with Papirus on 2026-10-10.

One setting loosens instead of hardening: `system/maintenance.sh` installs `/etc/security/limits.d/20-hyprland.conf`, so the login user may ask for realtime priority and Hyprland's `SCHED_RR` request at start succeeds.
Any process of that user could ask for it, and a runaway realtime process can starve the machine.
Hyprland takes the minimum priority and resets it for every child (`SCHED_RESET_ON_FORK`), and these are single-user desktops.
rtkit would grant the same through D-Bus with a watchdog, and one file won over one more service.

## Use it

```sh
sudo bash system/harden.sh --dry-run    # every change it would make
sudo bash system/harden.sh              # then reboot once
sudo nft list ruleset | head            # the input policy is drop
resolvectl status | grep -i -E 'llmnr|mdns'   # both off
faillock --user "$USER"                 # no failures
```

It refuses to make sshd keys-only while neither the login's `~/.ssh/authorized_keys` nor `keys/ssh.pub` holds a key, and exits with the `ssh-copy-id` line to run from the Mac.

## Left out

| Not used | Why |
|---|---|
| fail2ban, sshguard | sshd takes keys only, and only from the LAN |
| AppArmor, SELinux | upkeep on Arch, with no threat on this LAN to justify it |
| linux-hardened, USBGuard, firejail | more breakage than these desktops gain from them |
| blocking ICMP | it breaks path MTU discovery and the `ping` checks this repo relies on; ICMPv6 carries NDP and MLD, without which IPv6 stops working on a snooping switch |
| automatic upgrades | not on Arch: `dram update` on my schedule, after a look at what is pending |

Disk encryption for the laptop and Secure Boot were on this page's list on 2026-10-05.
The installer of 2026-10-11 does both: [Boot trust](../boot-trust/README.md).

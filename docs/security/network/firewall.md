# Firewall

[Security](../README.md) › [Network](README.md) › Firewall

Each Arch host on its own hardware drops every inbound connection except SSH and LocalSend from the home LAN, ICMP, and what a role opens in a file of its own.
The ruleset is `system/nftables.conf`, written in the repo and installed whole by `system/harden.sh`, so a reinstall reproduces it exactly.
Set `define LAN` to your subnet before `harden.sh` runs, or lose SSH at the next boot.

| | |
|---|---|
| Code | `system/nftables.conf`; installed by `system/harden.sh`; role files from `system/recording-setup.sh`, `system/gaming-setup.sh` and `system/virt-setup.sh` |
| Runs on | every Arch host on its own hardware (`system/files.tsv`: `/etc/nftables.conf`); a WSL clone has Windows' firewall |
| Needs | nftables (in `packages/metal.txt`), tested 2026-10 |
| Decided in | applied 2026-10-06 with the [host hardening](hardening.md); cabin's default-deny and Steam Remote Play's opening ruled 2026-10-12 |

## How it works

| Chain | Policy | Accepts |
|---|---|---|
| input | drop | established and related traffic; loopback; ICMP and ICMPv6; the DHCPv6 reply to the link-local address; TCP 22 and TCP/UDP 53317 (LocalSend) from `$LAN`, with counters; every rule in `/etc/nftables.d/*.nft` |
| forward | drop | established and related traffic; traffic leaving a container bridge; traffic from `$LAN` into a bridge (Docker's published ports) |
| output | accept | everything |

The file starts with `destroy table inet filter` and not `flush ruleset`, as Arch's own example does.
Only this table is reset, so Docker's `ip` and `ip6` tables and wg-quick's `ip wg-quick-<iface>` table survive a reload, and `nft -f` still applies it as one transaction.

ICMP is accepted with `meta l4proto { icmp, ipv6-icmp }`.
An earlier `ip6 nexthdr icmpv6` never matched MLD, which carries a Hop-by-Hop header, so a snooping switch aged the host out of its multicast groups and broke NDP and mDNS towards it.

The DHCPv6 client's Reply comes from the server's own address, which conntrack does not pair with the multicast Solicit, so one rule accepts it to the link-local address.
It is unused while the UniFi router's advertisements set neither M nor O.

Docker is in daily use on the laptop, and a drop in any base chain on the forward hook is final, whatever Docker's own chains accept.
The forward chain therefore lets traffic leave a container bridge and lets the LAN reach published ports, and Docker's `DOCKER-*` chains still enforce isolation and unpublished ports.
The Docker daemon is root-equivalent for anyone in the `docker` group.

## Role openings

`harden.sh` keeps an empty `/etc/nftables.d/00-none.nft`, so the include always matches a file.

| File | Written by | Opens, from `$LAN` or named hosts only |
|---|---|---|
| `recording.nft` | `system/recording-setup.sh` (role recording) | OBS's websocket and SRT from the creator hosts |
| `steam.nft` | `system/gaming-setup.sh` (role gaming) | Steam Remote Play and Steam Link: UDP 27031-27036, TCP 27036-27037 |
| `libvirt.nft` | `system/virt-setup.sh` (role sysadmin) | DHCP and DNS for the VMs on `virbr0` |

## Use it

Edit the repo copy, never `/etc/nftables.conf`, then run the installer again:

```sh
sudo bash system/harden.sh --dry-run    # shows whether /etc/nftables.conf differs
sudo bash system/harden.sh              # checks the repo copy with nft -c, installs it, restarts nftables
sudo nft list ruleset | grep -c 'policy drop'   # prints: 2
sudo nft list ruleset | grep 'dport 22'         # the SSH rule and its counter
```

`harden.sh` checks the repo copy with `nft -c -f` before installing it, so a typo never leaves a host with the old rules or none.
It backs up a differing `/etc/nftables.conf` before replacing it.
To log drops while debugging, uncomment the `limit rate 5/minute log` line at the end of the input chain.

## When it breaks

| Symptom | Check | Fix |
|---|---|---|
| locked out over SSH after `harden.sh` | at the console: `grep 'define LAN' system/nftables.conf` against `ip -4 route \| grep -w src` | fix `define LAN`, run `harden.sh` again |
| `dram doctor --supply`: "nftables is not loaded — no firewall" | `sudo systemctl status nftables`; the unit is a oneshot, so "inactive" alone is normal | `sudo bash system/harden.sh` |
| a container cannot reach the network | `sudo nft list chain inet filter forward` | the bridge accepts are in `nftables.conf`; restart Docker after a reload that ran `flush ruleset` by hand |

## Limits

The output chain accepts everything: the firewall keeps strangers out and does not contain a compromised program.
`$LAN` is one subnet, written in the file; a host that travels takes no SSH from other networks, which is the intent.
The laptop's old SIP and RTP rules for the telephony lab are not in the file; add them under a comment if that work resumes.

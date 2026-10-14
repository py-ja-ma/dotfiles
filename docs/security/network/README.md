# Network

[Security](../README.md) › Network

How a host meets the network: a default-deny firewall that admits SSH and LocalSend from the LAN only, a hardened kernel and sshd, DNS over TLS, WireGuard home from outside, and NetworkManager on the machines I sit at.
Every Arch host on its own hardware takes the firewall and the hardening; hosts with the desktop role take NetworkManager.
cabin-win resolves through Quad9 over DNS-over-HTTPS, and a WSL clone sits behind Windows' firewall.

| Branch | What it does | Code | Copy alone |
|---|---|---|---|
| [Firewall](firewall.md) | default-deny nftables: SSH and LocalSend from the LAN, one file per role opening, Docker's forwarding | `system/nftables.conf` | yes, after setting `define LAN` to your subnet |
| [Host hardening](hardening.md) | installs the firewall, makes sshd keys-only, sets sysctl limits, DNS over TLS, faillock and sudo, the greeter's no-empty-password rule | `system/harden.sh` | yes, on Arch |
| [DNS](dns.md) | Quad9 over TLS on Arch (opportunistic), over HTTPS on Windows; LLMNR and mDNS off | `system/harden.sh`, `windows/units/dns-quad9-doh.ps1` | yes |
| [VPN](vpn.md) | WireGuard to the UniFi gateway, with no account anywhere | the `vpn` and `vpn-down` aliases in `modules/shell.nix` | yes |
| [NetworkManager](networkmanager.md) | NetworkManager on desktops and laptops, systemd-networkd and iwd on headless hosts | `system/network-setup.sh`, `system/networkmanager/dram.conf` | yes |

## How the branches fit

`harden.sh` installs `nftables.conf`, the sshd drop-in and resolved's DNS-over-TLS file in one run, so the firewall and the server it guards change together.
A role that takes traffic in writes its own file into `/etc/nftables.d/` (the recorder's OBS and SRT, Steam Remote Play, libvirt's DHCP and DNS), and the ruleset includes every file there.
NetworkManager hands its DNS servers to systemd-resolved (`dns=systemd-resolved`), so DNS over TLS holds on every network a laptop joins.
The firewall resets only its own table, so WireGuard's and Docker's tables survive a reload.

## Operating it

Running `harden.sh` the first time: [handbook chapter 1](../../records/handbook/01-install.md).
After a move to a new subnet: [handbook chapter 3](../../records/handbook/03-cadence.md) ("After a move").
Locked out, no Wi-Fi, a refused connection: [handbook chapter 11](../../records/handbook/11-troubleshooting.md), §5.

## archlinux.org from the home LAN

Since 2026-10-10 one address refuses this LAN: `archlinux.org` and `www.archlinux.org` (209.126.35.79) accept the TCP connection and close it before any data.
DNS, IPv6 and TLS are not the cause, and every other Arch service answers: the mirrors, the AUR, the wiki, `security.archlinux.org` and the key servers.
The likeliest cause is a ban of the home WAN address at Arch's front end; a test from a phone's hotspot, then the gateway's threat filter, would settle it.
What it costs: reflector cannot fetch the mirror status, so `install/mirrorlist` ships a fixed list and reflector's failure is not fatal; and Arch's news is read from another network before a big update.
`arch-audit` and `pacman-key` keep working.

## Status

2026-10-13: cabin's default-deny was ruled on 2026-10-12, together with Steam Remote Play's opening to the LAN ([Firewall](firewall.md)).
`harden.sh` is an `ask` hook of `dram apply`, so it changes a host only after a yes at that host's terminal.
On a host where it has run, `sudo nft list ruleset | grep 'policy drop'` shows two chains, and `dram doctor --supply` reports sshd keys-only and nftables loaded.
Each host's record under `hosts/` says where it has run.

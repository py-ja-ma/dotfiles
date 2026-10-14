# DNS

[Security](../README.md) › [Network](README.md) › DNS

Every host asks Quad9 for names, encrypted where the server offers it: over TLS on Arch, over HTTPS on Windows.
Both fall back to plain DNS when encryption fails, so a hotel or captive network still resolves.
LLMNR and mDNS answer nothing on Arch.

| | |
|---|---|
| Code | `system/harden.sh` (step 3) writes `/etc/systemd/resolved.conf.d/dot.conf`; `system/networkmanager/dram.conf`; `windows/units/dns-quad9-doh.ps1` |
| Runs on | every Arch host on its own hardware; cabin-win; a WSL clone takes the DNS Windows gives it |
| Needs | systemd-resolved on Arch; Windows 11's DNS-over-HTTPS client (`Get-DnsClientDohServerAddress`) |
| Decided in | written 2026-10-05; Windows' half 2026-10-12, to match Arch |

## Arch

```ini
[Resolve]
DNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 2620:fe::fe#dns.quad9.net 1.1.1.1#cloudflare-dns.com
FallbackDNS=1.0.0.1#cloudflare-dns.com
DNSOverTLS=opportunistic
DNSSEC=no
LLMNR=no
MulticastDNS=no
```

LLMNR and mDNS are spoofing surfaces on a hostile network, and these hosts need neither.
Set `MulticastDNS=resolve` only to reach the homelab by `.local` names.
NetworkManager hands the servers it learns to resolved (`dns=systemd-resolved`), so the same file holds on every network a laptop joins.
In a WSL clone resolved stays masked and WSL writes `resolv.conf` (`system/units.tsv`).

```sh
resolvectl status | grep -E 'DNS Servers|DNSOverTLS'   # Quad9 first, DNSOverTLS=opportunistic
resolvectl query archlinux.org                          # answers through resolved
```

## Windows

`dns-quad9-doh` sets Quad9's four addresses on the Ethernet adapter and registers each with Windows' DNS-over-HTTPS template `https://dns.quad9.net/dns-query`, upgrading automatically and falling back to plain DNS, as Arch's opportunistic TLS does.
An adapter without IPv6 takes the IPv4 pair alone.
A WireGuard or OpenVPN tunnel keeps the DNS its own config names.
The router's DNS is no longer asked, so names that only the LAN knows do not resolve there, as on Arch.

```powershell
powershell -File dns-quad9-doh.ps1 -Mode Test   # True when the adapter and the four DoH entries are in state
Get-DnsClientDohServerAddress -ServerAddress 9.9.9.9
```

## Limits

Opportunistic means a network that blocks port 853, or a server that does not offer TLS, gets plain DNS without a warning.
The host does not validate DNSSEC (`DNSSEC=no`); Quad9 validates on its side.

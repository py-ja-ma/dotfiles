# VPN

[Security](../README.md) › [Network](README.md) › VPN

Each host reaches home through WireGuard to the UniFi gateway.
The gateway is the server, and a host is a plain `wireguard-tools` client.
I tried Tailscale on 2026-10-05 and removed it the same day: it needs an account.

| | |
|---|---|
| Code | the `vpn` and `vpn-down` aliases in `modules/shell.nix`; `system/maintenance.sh` reports whether `wg-quick@home` is set up |
| Runs on | lantern; cabin keeps the config for when it travels |
| Needs | `wireguard-tools` (in `packages/metal.txt`), a WireGuard server on the gateway |
| Decided in | 2026-10-05, no account anywhere |

The client config, `/etc/wireguard/home.conf`, holds the host's private key and stays on the host, never in the repo.

## Set up the server, once

In the UniFi console: Settings › VPN › VPN Server › WireGuard › Create.
Keep the defaults (UDP 51820 and the gateway's WAN hostname).
Add one client per host (cabin, lantern, the phone) and download each client's `.conf`.

## Set up a host

```sh
sudo install -m 600 -o root ~/downloads/<host>.conf /etc/wireguard/home.conf
vpn          # sudo wg-quick up home; vpn-down stops it
sudo wg      # shows the handshake and the transfer counters
```

To keep it up on the laptop: `sudo systemctl enable --now wg-quick@home`.

## Options

UniFi exports `AllowedIPs = 0.0.0.0/0`, which sends all traffic home.
To send only the LAN through the tunnel, set `AllowedIPs` to the LAN's subnet, the one in `/etc/dram/lan.nft`.
Inside the tunnel, DNS is the gateway's LAN address; UniFi fills it in.
With the tunnel up, `kubectl` and `talosctl` work as they do at home, because Home Manager sets `KUBECONFIG` and `TALOSCONFIG`.

## Limits

`bin/harvest.sh` does not collect `/etc/wireguard`, so the key stays on the host.
The firewall's reload leaves wg-quick's own table alone ([Firewall](firewall.md)).
Arch's news page refuses the home WAN address, and the tunnel leaves through that same address, so the VPN does not help there ([Network](README.md#archlinuxorg-from-the-home-lan)).

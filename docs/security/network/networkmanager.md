# NetworkManager

[Security](../README.md) › [Network](README.md) › NetworkManager

Machines I sit at run NetworkManager for Wi-Fi and wired networks; headless hosts keep systemd-networkd and iwd.
DNS stays systemd-resolved's everywhere, and NetworkManager hands it the servers it learns.

| | |
|---|---|
| Code | `system/network-setup.sh`, `system/networkmanager/dram.conf` |
| Runs on | hosts with the desktop role (`system/apply-hooks.tsv`: an `auto` hook); headless hosts and the installer keep networkd and iwd |
| Needs | `networkmanager` and `nm-connection-editor` (the desktop role's list), wpa_supplicant; tested 2026-10 |
| Decided in | 2026-10-11: packages instead of home-made pop-ups |

| Host kind | Manager | Wi-Fi | How you use it |
|---|---|---|---|
| the desktop role (cabin, lantern, the recorder) | NetworkManager | wpa_supplicant, NetworkManager's default backend | the bar: click the network caption for `nmtui connect`, right-click for `nm-connection-editor` (VPNs, 802.1X and eduroam, static addresses); in a terminal `nmcli` and `nmtui` |
| headless (admin boxes, the VM test) | systemd-networkd | iwd (`iwctl`) | `networkctl`, `iwctl station wlan0 connect <ssid>` |

A home-made rofi Wi-Fi picker on top of `iwctl` and the impala TUI came before it, and they were the weak spot: no captive portal or 802.1X handling, no VPN plug-ins, nothing that recovers a dropped link by itself.
NetworkManager is the maintained, packaged answer to all of it, from freedesktop.org in Arch's own repos.
`dram.conf` also turns Wi-Fi power saving off, the usual cause of drop-outs on laptop cards.

## How a host changes over

The installer sets up systemd-networkd and iwd, which is what works inside the ISO and on the first boot.
On a host with the desktop role, `dram apply` runs `network-setup.sh`, which:

1. installs `/etc/NetworkManager/conf.d/dram.conf`;
2. imports every Wi-Fi network iwd knows (`/var/lib/iwd/*.psk`, the ones typed during the install) as a NetworkManager connection, so no password is typed again;
3. switches systemd-networkd and iwd off and NetworkManager on in one step, and gives the network back to networkd and iwd if NetworkManager fails to start.

Over SSH it stops before step 3, since the link drops for a few seconds while the managers swap, and prints the command to run at the machine; `--remote-ok` overrides that.
`dram doctor` ("network") warns when a desktop host is not on NetworkManager, or when both managers run.

## When the Wi-Fi misbehaves

```sh
nmcli device                       # is the card managed and connected?
nmcli device wifi list --rescan yes
journalctl -b -u NetworkManager -u wpa_supplicant
nmcli connection show <name> | grep -E 'powersave|autoconnect'
```

A network that keeps failing: delete it (`nmcli connection delete <name>`) and connect again with `nmtui`.
A desktop still on networkd: `sudo bash system/network-setup.sh` at the machine.
WireGuard home stays `wg-quick@home` ([VPN](vpn.md)).

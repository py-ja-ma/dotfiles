# 9. Move or rename a host

Two procedures that touch the same facts from different sides. A **move** keeps
the hostname and changes where the machine lives: time zone, sun position, LAN
subnet and addresses, the UniFi gateway. A **rename** keeps the house and
changes the one string that the host file, its harvest, a sops anchor and a key comment
are built from. Both end with `dram doctor` clean. Backups are paused until the NAS
(chapter 5), so neither touches a Borg repository today. Depth: `docs/platforms/arch/hooks.md`
("Moving house"), `docs/security/identity/secrets.md` ("Adding or re-keying a host"), `docs/security/network/vpn.md`.

## Before you start

- Every host reachable from the Mac over SSH (`ssh <user>@<address> true` for each host
  file with an `address`), and a clean tree on the Mac (`git status` prints nothing).
- For a rename: the new name, lowercase, no dots — it becomes a Nix attribute
  (`<user>@<name>`), a YAML anchor (`&<name>`) and a directory under `hosts/`.

## Move: same hostname, new house

Three things in this dram know where the machines are: the system time zone,
`dram.location`, and the LAN subnet with the hosts' static addresses. Everything
else (DNS-over-TLS, the firewall policy) is location-free.

### 1. Time zone (each host, root)

```sh
timedatectl | grep 'Time zone'                       # prints the old zone, e.g. US/Eastern
sudo timedatectl set-timezone America/Chicago        # the new one; nothing printed
timedatectl | grep 'Time zone'                       # prints: Time zone: America/Chicago (CST, -0600)
```

The bar clock, the Russian dateline, the welcome toast and hyprlock all read
the system zone; nothing in the repo stores it. The Mac's zone is its own
setting (System Settings → General → Date & Time).

### 2. Sun position (the repo, then `dram switch`)

`dram.location` in `modules/options.nix` is one string `"LAT LON"` (decimal
degrees, east positive), default `"42.36 -71.06"`. It drives `dram-theme-auto`
(`washi-day` by day, `washi` and the night light after sunset).

```sh
# on the Mac
sed -n 's/.*location = lib.mkOption { type = lib.types.str; default = "\([^"]*\)".*/\1/p' modules/options.nix
# prints: 42.36 -71.06
```

Edit the `default = "…"` to the new coordinates (Grand Forks, ND is
`"47.92 -97.03"`), commit, push to every host, then on each host:

```sh
dram switch                                          # ends with the generation number
cat ~/.config/dram/location                          # prints the new pair
dram-theme-auto --print                              # prints today's sunrise/sunset in the new zone
```

### 3. LAN subnet and addresses

The repo holds no address. Each one lives where it is used:

| Where | Holds | Changes when |
|---|---|---|
| the Mac's `~/.ssh/config` | a `Host cabin`, `Host lantern` block with each host's `HostName`: what `bin/release.sh`, `bin/push-host.sh` and `bin/sync-dram-repo.sh` dial, through the names in `modules/hosts/*.nix` (`address = "cabin"`) | a host's address changes |
| `/etc/dram/lan.nft` on each host | `define LAN = <subnet>`: SSH and LocalSend are accepted from this subnet only. `system/nftables.conf` includes it; `system/harden.sh` wrote it once from the subnet it found | the subnet changes |

Two ways through:

**Keep the addresses** — reserve each host's old address for it on the new
gateway (UniFi → Client Devices → the host → Fixed IP) and keep the subnet.
Nothing changes. This is the default.

**Change them** — on each host, **from the host's own keyboard, not over
SSH**, write the new subnet and reload the firewall; the moment it loads, SSH
from the old subnet is dropped:

```sh
sudo sed -i 's|^define LAN = .*|define LAN = <new subnet>|' /etc/dram/lan.nft
sudo systemctl restart nftables
```

On the Mac, the new `HostName` lines in `~/.ssh/config`, and
`ssh-keygen -R <old address>` for each old one; the host keys are unchanged,
so the first connection to the new address only adds a line.

### 4. UniFi: WireGuard and reservations

A new gateway is a new WireGuard server. In the UniFi console (Settings → VPN
→ VPN Server → WireGuard) create one client per host again, download each
`.conf`, and on each host:

```sh
sudo install -m 600 -o root ~/downloads/<host>.conf /etc/wireguard/home.conf
sudo wg-quick down home 2>/dev/null; vpn               # = sudo wg-quick up home
sudo wg                                                 # prints a peer with "latest handshake" a few seconds old
```

cabin stays on the LAN and needs no tunnel; the config is for travelling with
it (`docs/security/network/vpn.md`). Reservations: the same console, Client Devices → each host →
Fixed IP, whatever step 3 decided.

### 5. Verify

```sh
# each host
dram doctor                        # no warnings; the dram section [ok]
# the Mac
bin/release.sh --dry-run           # the push targets list every host at its new address
```

## Rename: same house, new hostname

Everything below is for one host, `OLD` → `NEW`. Each row is a place the hostname lives.

| # | Where | What has it | Set by |
|---|---|---|---|
| 1 | `/etc/hostname` on the host | the name itself; `dram switch` resolves `<user>@$(cat /etc/hostname)`, `dram doctor` compares it with `facts.lua` | `hostnamectl set-hostname` |
| 2 | `modules/hosts/OLD.nix` | the file name (= the flake output `<user>@OLD`, by `readDir`) and `hostName = "OLD"` inside it | `git mv` + edit |
| 3 | `hosts/OLD/` | the harvest directory (`etc/hostname`, `hardware.txt`, the hand-written `README.md`) | `git mv`, then `dram harvest` on the host |
| 4 | `.sops.yaml` | `# host: OLD` marker, `&OLD` anchor, `- *OLD` reference — the age key itself is unchanged, so no `updatekeys` | edit, three lines |
| 5 | `/etc/ly/config.ini` | `box_title = OLD` (the greeter's box) | `sudo bash system/apply-ly.sh --anim none` (default: `hostname`) |
| 6 | `~/.ssh/id_ed25519.pub` | the comment `<user>@OLD`; the key bytes stay | `ssh-keygen -c` |
| 7 | GitHub, UniFi | key titles, the WireGuard client name, the reservation name — cosmetic | by hand |
| 8 | docs | prose naming the host | `git grep -lw OLD -- docs README.md` |

### 1. The repo, on the Mac (one commit, not pushed yet)

```sh
OLD=lantern NEW=laptop                                   # example names
git mv modules/hosts/$OLD.nix modules/hosts/$NEW.nix
sed -i '' "s/hostName = \"$OLD\"/hostName = \"$NEW\"/" modules/hosts/$NEW.nix
git mv hosts/$OLD hosts/$NEW
sed -i '' "s/^  # host: $OLD\$/  # host: $NEW/; s/^  - &$OLD /  - \&$NEW /; s/^          - \*$OLD\$/          - *$NEW/" .sops.yaml
git grep -n -w "$OLD" -- hosts/$NEW docs README.md       # the prose rows; edit by hand
bash bin/check.sh                                        # §2 and §11 pass; §6 lists any doc path still naming hosts/OLD/
git commit -m "rename $OLD -> $NEW"
```

The `sed -i ''` form is the Mac's BSD sed; on a host it is `sed -i`.

### 2. The name, on the host

```sh
sudo hostnamectl set-hostname $NEW
cat /etc/hostname                                  # prints: NEW
grep -n "$OLD" /etc/hosts                          # the installer writes 127.0.1.1 <name>: change it to NEW
```

### 3. Push, switch, re-render

```sh
# the Mac
bin/push-host.sh <user>@<address>
# the host
dram switch                                        # builds <user>@NEW; ends with the generation number
sudo bash system/apply-ly.sh --anim none           # prints: … box_title NEW
ssh-keygen -c -C "$(id -un)@$NEW" -f ~/.ssh/id_ed25519   # prints: Comment '<user>@OLD' changed to '<user>@NEW'
dram harvest                                       # rewrites hosts/NEW/ (etc/hostname now says NEW); commit it, pull it to the Mac
```

GitHub → Settings → SSH and GPG keys: the entries for this key keep working (same key);
rename their titles. UniFi: the WireGuard client and the reservation names, if you care.

### 4. Verify

```sh
# the host
dram doctor                        # dram: "facts.lua: host = NEW"; no warnings
git log -1 --show-signature        # "Good "git" signature" after the harvest commit
# the Mac
bin/release.sh --dry-run           # lists NEW among the push targets, no OLD
```

## Done when

- [ ] Move: `timedatectl` on each host and the Mac show the new zone;
      `cat ~/.config/dram/location` on each host prints the new pair.
- [ ] Move: `git grep -n '192\.168\.82'` lists only addresses that are true
      on the new LAN, or the reservations make the old ones true again.
- [ ] Rename: `ls modules/hosts hosts` show the new name and no old one;
      `grep -c OLD .sops.yaml` prints `0`.
- [ ] Both: `dram doctor` on each host prints no `secrets` or `dram` warnings.
- [ ] Both: `sudo wg` on the laptop shows a recent handshake (if it travels).

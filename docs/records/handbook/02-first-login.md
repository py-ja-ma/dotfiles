# 2. First login

What the greeter and the desktop show on a freshly installed host, and the things done
once per machine because no installer can do them: a key of its own, its state committed
back to the Mac, the YubiKeys, an account login, a GUI's first run. Each has a command that
proves it. Depth: `docs/security/identity/yubikeys.md` (the keys), `docs/toolchain/README.md` (one app per job and where each
is configured), `docs/design/shell-and-bars/keybinds.md` (every bind), `docs/commands.md` (every script's `--help`).

## Before you start

- Chapter 1 is done: the host boots systemd-boot with Secure Boot on, ly logs you in to
  Hyprland, and `dram doctor` shows only chapter 1 §9's expected warnings.
- Both YubiKeys, the Proton account password, and a terminal on the host (`SUPER+Q`).
- Laptops: the WireGuard `.conf` for this host, exported from the UniFi console (`docs/security/network/vpn.md`).

## 1. The greeter

ly on tty2: the house palette (paper background, ink text), a big clock, the date, and the
hostname as the box title. No animation. The sessions are **Hyprland**, or with the gaming
role **Desktop** and **Gaming Mode** (`docs/toolchain/profiles/gaming.md`). One Hyprland entry only; a second
`Hyprland (uwsm)` means the greeter step did not stick:

```sh
ls /usr/share/wayland-sessions/        # hyprland.desktop (plus dram-*.desktop with the gaming role)
grep '^NoExtract' /etc/pacman.conf     # NoExtract = usr/share/wayland-sessions/hyprland-uwsm.desktop
```

Ctrl+Alt+F1 is a plain text console (`getty@tty1`) if the greeter misbehaves.

## 2. What the desktop shows

The quote wallpaper (an English quote; a Russian proverb on a second monitor), the bar with
a Russian dateline and the `EN`/`RU` word, and within ten seconds the welcome toast: the
date, the battery on a laptop, `up since HH:MM`, and the pending-update count. `SUPER+/`
opens the searchable keybind cheatsheet, `SUPER+Q` a terminal, `SUPER+T` the theme picker.
The theme is `washi` (dark) or `washi-day` by the sun; `dram-theme-auto --print` shows
today's sunrise and sunset. Keyboard: left `Alt`+left `Shift`, or `SUPER+ALT+SPACE`, or a
click on the `EN`/`RU` word.

```sh
kb-layout.sh status                    # us  (ru after one toggle); in a terminal on the desktop, not over ssh
```

The home folder uses short lowercase names (`modules/desktop.nix`, `xdg.userDirs`). Apps
find them through `~/.config/user-dirs.dirs` (downloads, the file chooser, the Flatpaks'
folders); the links into `/data` come from `dram apply`'s role hooks.

| Folder | Holds |
|---|---|
| `~/documents` | documents; `vault/` and `finance/` after `office-init` (§11) |
| `~/downloads` | downloads (browsers, LocalSend) |
| `~/games` | → `/data/games`, the gaming role: Steam's library `SteamLibrary/` (§11) |
| `~/git` | this repo (`~/git/dotfiles`) and other clones |
| `~/music` | music |
| `~/pictures` | `screenshots/` (`Print` and friends), `wallpapers/` (the quote wall, `SUPER+SHIFT+W`) |
| `~/projects` | your own projects |
| `~/roms` | → `/data/emulation/roms`, the emulation role |
| `~/videos` | `recordings/` (`SUPER+SHIFT+R`); with the creator role → `/data/recordings`, OBS's folder |

There is no Desktop, Public or Templates folder. `dram doctor` names a capitalised folder
left over from before (move what it holds into the lowercase one, then `rmdir` it).

## 3. This host's own SSH key

git signs every commit (`modules/dev.nix`): with the YubiKey once `keys/ssh.pub` lists one
(§5), until then with this host's own key — and a fresh install has none, so make it before
the first commit. It is also what this host uses to reach the others.

```sh
ssh-keygen -t ed25519 -C "$(id -un)@$(cat /etc/hostname)"   # a passphrase from Proton Pass, or Enter for none
git -C ~/git/dotfiles config --get user.signingkey          # ~/.ssh/id_ed25519.pub (or ~/.ssh/id_ed25519_sk.pub once §5 is done)
```

## 4. Commit this host's state, and bring it to the Mac

`dram harvest` writes `hosts/<name>/`: the installed packages, enabled units, a few `/etc`
copies and a hardware summary — the record `bin/check.sh` compares the manifests with.

```sh
dram harvest                            # prints: [ok] wrote hosts/<name>/ (explicit=N aur=0) and the git status lines
cd ~/git/dotfiles
git add hosts/<name> modules/hosts/<name>.nix
git commit -m "hosts/<name>: first harvest"
```

`modules/hosts/<name>.nix` is new only on a machine the installer wrote it for (chapter 1
§6, `--roles`); a known host's file is already tracked. On the Mac, bring the commit over
— the hosts have no remote; the Mac pulls from them and pushes to them:

```sh
git pull pj@<address>:git/dotfiles master   # on the Mac (ranger@ for lantern); then bash bin/check.sh
```

## 5. The YubiKeys

Once for the fleet (`docs/security/identity/yubikeys.md` has every detail and the reasons), then once per host.

**On the first rebuilt host only — both keys.** At the machine, as your user, each key
plugged in alone:

```sh
ykman info                              # the firmware: 5.2.3+ gets ed25519-sk, older ecdsa-sk; 5.7+ needs a TDES PIV key (handled)
dram yubikey enroll primary             # OTP off, FIDO2 PIN, the SSH key, the pam-u2f credential, the age identity
dram yubikey enroll spare               # then the other key
```

Each run ends with four lines headed "now in ~/git/dotfiles": run them right here, in this
host's checkout (they append the public halves to `keys/` and `.sops.yaml` and commit).
On the Mac, `git pull <user>@<address>:git/dotfiles master` and cut a release (chapter 4)
so every host gets them. PINs and the PUK go into Proton Pass as you set them.

**On every host, after that release** (`dram update` brings it):

```sh
dram apply                              # at the keyboard, a key plugged in: harden.sh (sshd's keys file)
                                        #   and yubikey-setup.sh (a test touch, then the second factor is on)
dram yubikey ssh                        # the SSH handles onto this host (FIDO2 PIN, touch); git signs with the key
dram yubikey status                     # both keys listed; the signing link; "second factor ON"
```

lantern also enrolls each key as a second way into its disk, one key plugged in at a time:
`sudo bash ~/git/dotfiles/system/fido2-enroll.sh` (twice), then read `docs/security/identity/yubikeys.md`
"lantern's disk" once — it says which prompt wants which PIN.

From then on sudo, polkit prompts, ly, the console and the lock screen ask for the password
and then a touch; sudo over ssh on a desktop host fails by design (do admin at its
keyboard).

## 6. Groups (log out and back in afterwards)

The re-lab role puts you in `uucp` itself (`system/re-lab-setup.sh`). Two are by hand, where
the role is present: `wireshark` (sysadmin) and `docker` (the docker role, cabin):

```sh
sudo usermod -aG wireshark,docker "$(id -un)"     # name only the groups whose role this host has
id -nG | tr ' ' '\n' | grep -E '^(wireshark|docker|uucp)$'   # after the next login
```

## 7. Proton Mail Bridge

Run `protonmail-bridge` once from the drawer (`SUPER+R`) or a terminal, sign in, and close
it. The account lands in gnome-keyring; from then on the Home Manager user service serves
Thunderbird on `127.0.0.1:1143` (IMAP) and `127.0.0.1:1025` (SMTP).

```sh
systemctl --user restart protonmail-bridge
systemctl --user is-active protonmail-bridge   # active
ss -ltn | grep -E ':(1143|1025) '              # two LISTEN lines
```

No LISTEN lines means the login did not land in the keyring; `dram doctor`'s `login`
section must say `ly unlocks gnome-keyring via PAM`.

## 8. Browsers: first launch, then the theme

LibreWolf and Thunderbird have no profile until they run once, and `dram theme` links the
Letterpress chrome into each profile's `chrome/`. Open each once, add the Proton account to
Thunderbird (Bridge IMAP/SMTP above; Gmail/Outlook via OAuth2), quit both, then:

```sh
dram theme washi
ls ~/.librewolf/*/chrome/userChrome.css ~/.thunderbird/*/chrome/userChrome.css   # one path each
```

`xdg-mime query default x-scheme-handler/https` prints `librewolf.desktop`.

## 9. Proton Pass

From `[dram]` (desktop role), once the repo is synced (chapter 7). Open it from the drawer and
sign in. Its desktop entry adds `--password-store=gnome-libsecret`, so the session token sits
in the keyring and the app stays signed in across logins.

```sh
grep -c gnome-libsecret ~/.local/share/applications/proton-pass.desktop   # 1
ls -l /opt/proton-pass/chrome-sandbox | cut -c1-10                        # no "s" bit: -rwxr-xr-x
```

## 10. Flatpaks

`system/flatpak-setup.sh` (a `dram apply` hook) installs the apps each role lists in
`packages/flatpak/<role>.txt`: the desktop role's Vesktop, LocalSend and Flatseal; the
emulation role's emulators (`docs/toolchain/profiles/emulation.md`). Sign in to Vesktop once.

```sh
flatpak list --app --columns=application,origin   # every id from flathub
dram doctor --supply | grep flatpak               # every flatpak app comes from flathub; remotes: flathub only
```

Edits made in Flatseal land in `dotfiles/.local/share/flatpak/overrides/<id>` inside the
repo: commit or `git checkout` them (`docs/toolchain/packaging/flatpak.md`).

## 11. The roles' first runs

| Role | Once | Guide |
|---|---|---|
| dev | open VSCodium (`codium`) once; Open Remote-SSH arrives with `dram switch` | `docs/toolchain/development/README.md` |
| office | `office-init` — `~/documents/vault` and `~/documents/finance` as git repos | `docs/toolchain/profiles/office.md` |
| re-lab | `re-lab-tools` — frida-tools, angr and the Ghidra loaders, per user | `docs/toolchain/profiles/re-lab.md` |
| emulation | the BIOS and ROM files you dumped into `/data/emulation` | `docs/toolchain/profiles/emulation.md`, `docs/toolchain/profiles/emulation.md` |
| gaming | Steam: sign in once in the Desktop session; Settings → Storage → Add Drive → `/data/games` → ⋯ → Make Default; Settings → Downloads → *Allow background processing of Vulkan shaders* on; Gaming Mode afterwards | `docs/toolchain/profiles/gaming.md` (where the games live, shader pre-caching) |
| ml | a model from the allowlist under `~/models`, then `systemctl --user restart llama-server` | `docs/toolchain/development/README.md` |
| recording (campfire) | `rec server-setup` — OBS's websocket on, a password for cabin | `docs/toolchain/profiles/creator.md` |

## 12. VPN (laptop)

```sh
sudo install -m 600 -o root ~/downloads/<host>.conf /etc/wireguard/home.conf
vpn                                     # = sudo wg-quick up home
sudo wg                                 # a peer with "latest handshake" and transfer counters
vpn-down                                # = sudo wg-quick down home
```

Always-on: `sudo systemctl enable --now wg-quick@home`. A desktop on the LAN needs no tunnel.

## 13. Backups: paused

Host-to-host Borg backups and the Mac's nightly pull are **off until the NAS arrives**
(`decisions/0014-backups-paused-until-nas.md`): `dram doctor` says `backups are
paused until the NAS`. Until then the data pools (`/data/*`, kept across reinstalls) and the
git repos (this one, `~/documents/vault`, `~/documents/finance`, pulled to the Mac) are what survives a disk.

## Done when

- [ ] `kb-layout.sh status` flips between `us` and `ru` with left Alt+Shift
- [ ] `hosts/<name>/` (and a new host's `modules/hosts/<name>.nix`) committed and pulled to the Mac
- [ ] `dram yubikey status` lists both keys, the signing link and `second factor ON`
- [ ] `sudo true` asks for the password, then a touch
- [ ] `git log --show-signature -1` after a commit here says `Good "git" signature`
- [ ] `ss -ltn` shows `127.0.0.1:1143` and `127.0.0.1:1025` with Bridge running as a user service
- [ ] `ls ~/.librewolf/*/chrome/userChrome.css ~/.thunderbird/*/chrome/userChrome.css` finds both
- [ ] Proton Pass and Vesktop stay signed in across a logout
- [ ] laptop: `sudo wg` shows a handshake after `vpn`
- [ ] `dram version` answers

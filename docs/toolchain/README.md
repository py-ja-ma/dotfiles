# Toolchain

[Organization](../README.md) › Toolchain

Toolchain is the software a machine runs on top of its base system: the developer's kit, the packages I build and sign myself, and the profiles a host takes for a job.
An Arch host gets it through the roles in its host file (`modules/hosts/<host>.nix`), and `install/lib/roles.sh` turns each role into the package lists below.
The Windows PCs take the same role names from `packages/winget/`, and the WSL clones take the terminal half of each role.

| Division | Covers |
|---|---|
| [Development](development/README.md) | the dev role: languages, VSCodium, rootless Podman, the homelab kit, local models |
| [Packaging](packaging/README.md) | the signed `[dram]` repo, `pkgs/`, the AUR policy, Flatpak |
| [Profiles](profiles/README.md) | office, college, re-lab, creator, gaming, emulation, chat |

## The standard app set

One app per job, each configured in one place.
The desktop role (`packages/roles/desktop.txt`) installs most of them on every Arch host with a screen, and `packages/winget/desktop.txt` installs their Windows twins.
The first run of each is a step in [handbook chapter 2](../records/handbook/02-first-login.md).

| Job | App | From | Configured in |
|---|---|---|---|
| Browser | LibreWolf | `extra` | `dotfiles/.librewolf/librewolf.overrides.cfg`, applied at each start; the chrome comes from [Design](../design/README.md) |
| Passwords | Proton Pass, desktop and CLI | `[dram]` | `dotfiles/.local/share/applications/proton-pass.desktop` |
| Mail | Thunderbird with Proton Mail Bridge | `extra` | the Bridge user service in `modules/desktop.nix`; the profile itself is machine state |
| Files | Thunar, file-roller, gvfs, tumbler | `extra` | `xdg.mimeApps` in `modules/desktop.nix` |
| Music | Spotify through `spotify-launcher` | `extra` | `dotfiles/.config/spotify-launcher.conf` |
| Chat | Vesktop (Discord) | Flathub | `dotfiles/.local/share/flatpak/overrides/dev.vencord.Vesktop` |
| File transfer | LocalSend | Flathub | `dotfiles/.local/share/flatpak/overrides/org.localsend.localsend_app` |
| Editor | VSCodium | `[dram]` | `dotfiles/.config/VSCodium/User/settings.json.default`, `dotfiles/.config/codium-flags.conf` |
| Keyboard browser | qutebrowser | `extra` | `dotfiles/.config/qutebrowser/config.py` |
| Headless renders | Chromium | `extra` | `dotfiles/.config/chromium-flags.conf` |
| Settings | pavucontrol, blueman, `dram theme` | `extra`, and this repo | GTK belongs to `dram-theme`; Qt follows GTK through `QT_QPA_PLATFORMTHEME=gtk3` |
| Network | NetworkManager, `nmtui`, `nm-connection-editor` | `extra` | `system/networkmanager/dram.conf` ([Security](../security/network/README.md)) |
| Security keys | two YubiKeys | `extra` | `keys/`, `system/yubikey-setup.sh` ([Security](../security/identity/README.md)) |
| Fonts | Fraunces, Literata, Monaspace, EB Garamond | `extra` and nixpkgs | `modules/desktop.nix` ([Typography](../design/typography/README.md)) |

Each role adds its own tools on top: the [Development](development/README.md) page and each [profile](profiles/README.md) list them.

A few facts the table has no room for:

- Electron apps keep their secrets in gnome-keyring: VSCodium and Proton Pass start with `--password-store=gnome-libsecret`, set in their flags file and desktop entry.
- ly unlocks the login keyring through PAM. Phase 3 of `install/bootstrap.sh` masks the `gnome-keyring-daemon` user units, so PAM owns the daemon, and `dram doctor` checks both.
- Bridge serves Thunderbird on `127.0.0.1:1143` for IMAP and `127.0.0.1:1025` for SMTP. Gmail and Outlook sign in through OAuth2.
- Chromium stays for the headless quote-wallpaper render and as a fallback browser.
- `spotify-launcher` downloads Spotify's own `.deb` and checks the apt Release signature itself.
- I removed `qt6ct` on 2026-10-10 (an Origin fail), `nwg-look` because it rewrote the GTK settings `dram-theme` owns, and `nwg-displays` because `hyprland.lua` never loads the `monitors.conf` it writes.

## Default applications

`xdg.mimeApps` in `modules/desktop.nix` declares the defaults, and Home Manager writes `~/.config/mimeapps.list` from it.

| Type | Opens with |
|---|---|
| `x-scheme-handler/http`, `https`, `text/html` | `librewolf.desktop` |
| `inode/directory` | `thunar.desktop` |
| `x-scheme-handler/mailto` | `thunderbird.desktop` |
| `x-scheme-handler/discord` | `dev.vencord.Vesktop.desktop` |
| `text/plain` | `codium.desktop` |
| `image/png`, `jpeg`, `webp`, `gif` | `imv.desktop` |
| `application/pdf` | `org.pwmt.zathura.desktop` |

A default set by hand with `xdg-mime default` lands in a file Home Manager owns.
The next `dram switch` moves it aside as `mimeapps.list.bak-<stamp>`, and `dram doctor` counts those leftovers.
Change the default in `modules/desktop.nix` and switch.
`BROWSER=librewolf` in `home.sessionVariables` covers the programs that ignore XDG.

## Rules

- A program with a window or a GL context comes from pacman: an Arch repo, or `[dram]` for what the AUR carries. A pure command-line tool may come from nixpkgs, pinned by `flake.lock` ([decision 0003](../../decisions/0003-gui-apps-from-pacman-over-nixpkgs.md)).
- No host runs an AUR helper. An AUR package is vendored into `pkgs/`, built on cabin and signed ([decision 0005](../../decisions/0005-own-package-repo.md)), and `bin/check.sh` §12 checks every recipe.
- Each installed name has a verdict in `packages/register.tsv` ([decision 0013](../../decisions/0013-software-rules-and-waivers.md)). `bin/check.sh` §15 fails on a name without one.
- A name lives in one packages list. `bin/check.sh` §3 fails on a duplicate.
- Flatpak carries only vendor binaries I cannot build and emulators whose Flathub publisher is the upstream project ([decision 0016](../../decisions/0016-emulation-set-and-flatpak.md)).

## Decisions

| Record | Decision |
|---|---|
| [0003](../../decisions/0003-gui-apps-from-pacman-over-nixpkgs.md) | GUI and GL programs from pacman, not nixpkgs |
| [0005](../../decisions/0005-own-package-repo.md) | a signed package repo of my own for everything that came from the AUR |
| [0012](../../decisions/0012-gaming-mode.md) | two gaming modes at the login screen |
| [0015](../../decisions/0015-containers-podman.md) | rootless Podman by default, Docker by opt-in |
| [0016](../../decisions/0016-emulation-set-and-flatpak.md) | an emulator set like EmuDeck's, from Flathub where Arch has none |

The [decision log](../../decisions/log.md) holds the smaller rulings, and each division page links the rows it relies on.

## Open

- 2026-10-13: chat is a Windows role only. No Arch host has a chat role (*packages/roles/chat.txt*) yet ([D45](../../decisions/log.md#d45)).
- 2026-10-13: the recorder (campfire) is not built, so the recording role runs nowhere ([Creator](profiles/creator.md)).
- 2026-10-13: Gaming Mode's gamescope session stays experimental until cabin's hardware test passes ([Gaming](profiles/gaming.md)).
- 2026-10-13: sane-airscan and unpaper wait for an Origin ruling ([Office](profiles/office.md)).

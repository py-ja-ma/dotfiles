# Flatpak

[Toolchain](../README.md) › [Packaging](README.md) › Flatpak

Flatpak carries two kinds of app: vendor binaries I cannot build, where theming does not matter, and emulators whose Flathub publisher is verified as the upstream project.
Each runs in a sandbox with a least-privilege override, and sees only the folders its override names.
Everything with a window still comes from pacman ([decision 0003](../../../decisions/0003-gui-apps-from-pacman-over-nixpkgs.md)); these are the exceptions.

| | |
|---|---|
| Code | `system/flatpak-setup.sh`, `packages/flatpak/<role>.txt`, `dotfiles/.local/share/flatpak/overrides/` |
| Runs on | each Arch host with the desktop role; the emulators with the emulation role (cabin) |
| Needs | `flatpak` and `xdg-desktop-portal-gtk` from `packages/roles/desktop.txt` |
| Decided in | [decision 0016](../../../decisions/0016-emulation-set-and-flatpak.md), [D29](../../../decisions/log.md#d29) |

| App | Flathub id | Publisher | Replaced |
|---|---|---|---|
| Vesktop (Discord) | `dev.vencord.Vesktop` | Vencord, verified as `vencord.dev` | AUR `vesktop`, which ran `pnpm` as my user at build time |
| LocalSend | `org.localsend.localsend_app` | LocalSend, verified as `localsend.org` | AUR `localsend-bin` |
| Flatseal | `com.github.tchx84.Flatseal` | tchx84, the permission editor | — |

The emulation role's Flatpaks are PCSX2, xemu, shadPS4, Cemu, melonDS, Azahar, Rosalie's Mupen GUI and Steam ROM Manager ([Emulation](../profiles/emulation.md)).
Unverified Flatpaks (RPCS3, Flycast, Supermodel, Dolphin's) are not used; those come from `extra` or `[dram]`.
Each emulator's override grants `/data/emulation` and removes host, home and removable media.

Not Flatpak: LibreWolf (its profile, the keyring and extension IPC), VSCodium (Remote - SSH, the keyring, `~/git`), Steam (`pressure-vessel` is its own sandbox) and anything `dram-theme` themes.
The Jagex Launcher stays a `[dram]` package: Flathub has no Jagex Launcher, as of 2026-10-06 ([Gaming](../profiles/gaming.md)).

## How it works

| Piece | Path | Who writes it |
|---|---|---|
| the installer: root, idempotent, `--dry-run` | `system/flatpak-setup.sh` | run once per host, again at any time |
| the override files, user scope | `dotfiles/.local/share/flatpak/overrides/<app-id>` | linked as a directory to `~/.local/share/flatpak/overrides` by `modules/desktop.nix` |
| the same files, system scope | `/var/lib/flatpak/overrides/<app-id>` | copied by the installer on each run; a system override with no repo file is removed |
| `XDG_DATA_DIRS` for `.desktop` files and icons | `xdg.systemDirs.data` in `modules/desktop.nix` | `/var/lib/flatpak/exports/share` and `~/.local/share/flatpak/exports/share` |
| the app lists | `packages/flatpak/<role>.txt` | one Flathub id per line, read for each role the host has |

The apps live in the system installation (`/var/lib/flatpak`), so one download serves each user and `flatpak update` as root updates them with the rest of the system.
The override files exist at user scope and at system scope with the same content.
Flatpak merges both, the user copy wins, and the user copy is the one `git diff` sees.

## Override policy

The Flathub manifest's `finish-args` are the vendor's wish list, and the override file is my answer, in `flatpak-metadata(5)` format (`[Context]`, `[Session Bus Policy]`, `[System Bus Policy]`, `[Environment]`; `!x` removes a grant).
Each file starts with a header that lists what is kept, what is removed and what is never granted.

| Rule | Why |
|---|---|
| never `host`, never `home` | the sandbox sees `~/downloads` and what the header lists, not `~/.ssh`, `~/git`, the keyring or another app's data |
| `wayland` with `fallback-x11`, `!x11`, `!ipc` | X11 only when there is no Wayland display, which never happens under Hyprland |
| audio through `pulseaudio` | pipewire-pulse serves it |
| screen sharing through `xdg-desktop-portal-hyprland` | the portal hands the app a PipeWire node, so Vesktop keeps `xdg-run/pipewire-0`, and the portal's dialog picks the screen |
| no tray names (`org.kde.StatusNotifierWatcher`, `com.canonical.AppMenu.Registrar` set to `none`) | the desktop has no tray |
| `devices=all` for Vesktop and the emulators | Vesktop's webcam, below; the emulators' controllers through evdev and hidraw |

Electron reaches `/dev/video*` only through `devices=all`, because it has no camera portal yet.
Without it Vesktop lists no camera at all; I found that on 2026-10-07 with cabin's Razer Kiyo.
The Kiyo's microphone is a PulseAudio source either way.
Flatpak has no `--device=video`, and `dri` binds only `/dev/dri`, so `dri;!all;` means no camera.
I drop `all` again, one line in the override, once Chromium enables `WebRtcPipeWireCamera` by default and Vesktop's Electron carries that Chromium.
As of 2026-10-07 Chromium disabled it in Cr150 and Cr152 (flag expiry M160), and Electron #42608 (the XDG camera portal) is open.

`dev.vencord.Vesktop`:

```ini
[Context]
shared=network;!ipc;
sockets=wayland;fallback-x11;pulseaudio;!x11;
devices=all;
filesystems=xdg-download;xdg-pictures:ro;xdg-run/pipewire-0;!host;!home;!xdg-videos;!xdg-run/speech-dispatcher;!~/.steam;

[Session Bus Policy]
org.freedesktop.Notifications=talk
org.kde.StatusNotifierWatcher=none
com.canonical.AppMenu.Registrar=none

[Environment]
ELECTRON_OZONE_PLATFORM_HINT=auto
```

`org.localsend.localsend_app`:

```ini
[Context]
shared=network;!ipc;
sockets=wayland;fallback-x11;!x11;
devices=dri;
filesystems=xdg-download;!host;!home;

[Session Bus Policy]
org.kde.StatusNotifierWatcher=none

[System Bus Policy]
org.freedesktop.NetworkManager=none
```

The firewall opens tcp/53317 to the LAN for LocalSend's peers (`system/nftables.conf`).

## Use it

What a sandbox gets, with the manifest, the system override and the user override merged:

```sh
flatpak info --show-permissions dev.vencord.Vesktop
flatpak info --show-permissions org.localsend.localsend_app
```

Flatseal (`flatpak run com.github.tchx84.Flatseal`, "Flatseal" in the drawer) edits the user override of an installed app.
It saves by writing a temporary file and renaming it over `~/.local/share/flatpak/overrides/<id>`.
That is why `modules/desktop.nix` links the overrides directory, not each file: the rename lands in the repo directory and shows up as a change to `dotfiles/.local/share/flatpak/overrides/<id>`.
Commit it, and run the installer again so the system copy matches, or `git checkout` it.
A link per file would have become a plain file, and the next `dram switch` would stop on "existing file is in the way".

`flatpak override --user` behaves the same way.
`flatpak override` as root edits `/var/lib/flatpak/overrides/<id>` directly, and the installer overwrites that on its next run, so put the change in the repo.
The installer also removes a system override whose id has no file in the repo directory: an app dropped from `packages/flatpak/`, or a root override for something else.

To add an app:

1. Check that it has to be a Flatpak: a vendor binary I cannot build, where the theme does not matter.
   Anything else goes in a `packages/*.txt` list.
2. Find its Flathub id and its publisher.
   `https://flathub.org/apps/<id>` shows a verified badge when the upstream project owns it, and `https://flathub.org/api/v2/verification/<id>/status` answers in JSON.
   A community build is acceptable only when its Flathub manifest pins the vendor's own release by hash.
3. Read the manifest's `finish-args` and decide what to remove.
   The default answer to `host`, `home`, `device=all`, `system-bus` and `session-bus` is no.
4. Write `dotfiles/.local/share/flatpak/overrides/<id>` with the header and the four sections above.
5. Add the id to `packages/flatpak/<role>.txt`, a row to `packages/register.tsv` and a row to the table on this page.
   Then run `sudo bash system/flatpak-setup.sh` and `flatpak info --show-permissions <id>`.
6. If the app handles a protocol, declare the default in `xdg.mimeApps` in `modules/desktop.nix`, where `x-scheme-handler/discord` is, and `dram switch`.
   Home Manager owns `mimeapps.list`, so `xdg-mime default` by hand is overwritten at the next switch.

[Handbook chapter 7](../../records/handbook/07-packages.md) has the same checklist with the commit.

Flatpak updates sit outside pacman.
`dram update` runs `sudo flatpak update -y --noninteractive` right after `pacman -Syu` when `flatpak` is installed; the apps are system-wide, so it needs the same sudo.
By hand: `sudo flatpak update`.
`flatpak remote-ls --updates` previews, and `flatpak uninstall --unused` drops orphaned runtimes.

## Desktop integration

- Flatpak exports `<id>.desktop` into `/var/lib/flatpak/exports/share/applications`. `xdg.systemDirs.data` puts both export directories on `XDG_DATA_DIRS`, and nwg-drawer and rofi's drun read it. Log out once after the first `dram switch` that carries it.
- Each app shows its own hicolor icon from the exports directory.
- The Wayland app id is the Flatpak id (`dev.vencord.Vesktop`, `org.localsend.localsend_app`). `hyprland.lua` has no rule for either; `match = { class = "^dev\\.vencord\\.Vesktop$" }` would pin Discord to a workspace.
- `discord://` links (invites, OAuth from the browser) open Vesktop through `x-scheme-handler/discord` in `xdg.mimeApps`.
- Notifications reach swaync through `org.freedesktop.Notifications`, which the Vesktop override sets to `talk`.
- `xdg-desktop-portal-hyprland` does ScreenCast and `xdg-desktop-portal-gtk` the FileChooser, so upload and save dialogs exist. Vesktop's share button opens the portal's picker.

GTK apps inside a Flatpak would need an `org.gtk.Gtk3theme.<name>` runtime extension to see a GTK theme.
None of these three is a GTK app: Vesktop is Electron, LocalSend is Flutter, and Flatseal is libadwaita, which follows the portal's dark or light setting.
So `dram-theme` leaves the sandboxes alone: Vencord themes Discord, and LocalSend has its own setting.
The Vesktop manifest passes the cursor in (`XCURSOR_PATH` into `/run/host/user-share/icons`), so the Adwaita cursor shows.

## When it breaks

| Symptom | Check | Fix |
|---|---|---|
| Vesktop is blurry, or runs under XWayland | `flatpak run --env=ELECTRON_OZONE_PLATFORM_HINT=wayland dev.vencord.Vesktop` looks right | change `[Environment]` in its override |
| Vesktop lists no camera | `flatpak info --show-permissions dev.vencord.Vesktop` lacks `devices=all` | put `devices=all;` back in the override |
| a Flatpak has no launcher entry | `echo $XDG_DATA_DIRS` lacks the export directories | log out and in after `dram switch` |
| a system override drifted | `diff` it against the repo file | `sudo bash system/flatpak-setup.sh` |

## Limits

- Discord's game detection and Steam presence are off: the override removes `~/.steam`, and there is no `arRPC` socket.
- Vesktop keeps its data under `~/.var/app/dev.vencord.Vesktop/` and LocalSend under `~/.var/app/org.localsend.localsend_app/`. `modules/backup.nix` leaves `~/.var/app` out, so the Discord login is a new login after a reinstall.
- Flatpak apps cannot see the fonts in the nix profile.
- Flatseal needs no override: its manifest already reads `~/.local/share/flatpak` and `/var/lib/flatpak`.

> **Historical (2026-07-01) — superseded by `README.md` and `docs/new-machine.md`.** Paths and
> counts here are out of date (bootstrap is `install/bootstrap.sh`, config is split over
> `modules/*.nix`, there are 17 themes, `rice-switch`/`sysupdate` are shims onto `rice`,
> VSCodium became VS Code, Vorta/eva became borgmatic). Kept for the narrative; the live
> keybind list is `docs/keybinds.md`.

# pj's Hyprland rice

Reproducible Arch Linux + Hyprland desktop for a strictly-business daily-driver
laptop: SSH client for the homelab (DNS etc.), simple web dev, browser idle
games — no emulation, no Docker. One repo captures the whole look and feel so it
can be rebuilt on a fresh machine and backed up cleanly.

**Two layers, split on purpose:**

- **User layer — owned by Nix / Home Manager.** Dotfiles + user CLI tools,
  version-pinned by `flake.lock`. This is what this repo *applies*.
- **System layer — owned by Arch, installed by `system/` scripts.** Packages,
  bootloader theme, greeter, initramfs splash. Nix on Arch can't own `/etc`, the
  ESP, or the initramfs, so these live as scripts + package lists, not in Nix.

---

## Architecture

```
flake.nix ──> home.nix ──> mkOutOfStoreSymlink ──> dotfiles/
   │              │                                    │
   │              │         ~/.config/hypr  ─ symlink ─┘  (live-editable + git-tracked)
   │              │         ~/.config/waybar ─ symlink ─┘
   │              └─ user packages (starship, fd, rg, eza, fonts, …) from nixpkgs
   └─ pins nixpkgs + home-manager (flake.lock = historical reproducibility)
```

The trick is `mkOutOfStoreSymlink` (see `home.nix`): instead of copying dotfiles
into the read-only `/nix/store`, Home Manager symlinks `~/.config/hypr` (etc.)
**back to `dotfiles/` in this repo**. So editing `~/.config/waybar/style.css`
edits the repo file directly — live changes *and* git history, no rebuild to see
a config tweak. `home.nix` lists exactly which paths are linked. The full
Nix/Home-Manager story (what it owns, how to change it, troubleshooting) is in
`docs/nix-manager.md`.

The Arch **system layer** is installed separately by the scripts in `system/`
(package lists, rEFInd theme, ly greeter, plymouth). Nix owns **only** the user
layer. This hybrid is deliberate: you keep plain Arch and still get ~all the
reproducibility, without committing to a full NixOS reinstall.

### Repo layout
```
flake.nix / flake.lock   Home Manager flake + pinned inputs
home.nix                 what Nix owns: user packages + which dotfiles are symlinked
dotfiles/                the actual configs + scripts (symlink targets)
  .config/               hypr, waybar, rofi/wofi, swaync, swayosd, kitty, cava,
                         wlogout, gsimplecal, qutebrowser, gtk-3.0/4.0, themes/, …
  .local/bin/            the rice scripts (see below)
  .ssh/config            generic SSH defaults (private hosts are NOT here)
system/                  Arch layer: package lists, scripts, rEFInd + plymouth themes,
                         backup-eva.sh (borg backup of the irreplaceables)
bootstrap.sh             one-shot restore on a fresh Arch install
docs/                    runbooks — backup.md (borg + Vorta on the eva drive),
                         reinstall.md (fresh-machine restore),
                         nix-manager.md (how the Nix/Home-Manager layer works)
```

---

## Applying changes

`~/git/dotfiles` is a Nix **flake**. The ONLY correct way to apply
it is the helper **`rice-switch`**:

```bash
rice-switch          # == home-manager switch --flake ~/git/dotfiles#pj@$(hostname) \
                     #        --extra-experimental-features 'nix-command flakes' -b bak
```

> **NEVER run bare `home-manager switch`.** It ignores the flake and reads a
> stale `~/.config/home-manager/home.nix` (renamed `home.nix.STALE-DO-NOT-USE`),
> which once tore down every dotfile symlink and broke login. Always use
> `rice-switch`. `-b bak` renames any pre-existing real file to `*.bak` instead
> of erroring.

Editing a **dotfile** (anything under `dotfiles/.config`)? No rebuild needed —
it's a live symlink. Just edit and commit:
```bash
nvim ~/.config/waybar/style.css     # edits dotfiles/.config/waybar/style.css in this repo
cd ~/git/dotfiles && git add -A && git commit -m "waybar: tweak"
```
Only re-run `rice-switch` when you change **`home.nix`** (packages) or add/remove
a symlinked path. `sysupdate` runs `paru -Syu` + `rice-switch` together.

---

## The theme system

The whole desktop retheme is one symlink flip. Each theme is a directory under
`dotfiles/.config/themes/<name>/` holding a **12-file contract** — one adapter
per app. Every app is pointed at the *stable* path `~/.config/themes/current/…`,
and switching just repoints `current` at a different theme dir.

**The 12 files each theme must provide:**

| File | Consumed by |
|------|-------------|
| `palette.lua`   | `hyprland.lua` (`dofile` → border/shadow colors) |
| `waybar.css`    | waybar (`@define-color` set) |
| `swaync.css`    | swaync notification daemon |
| `swayosd.css`   | swayosd on-screen volume/brightness |
| `wlogout.css`   | wlogout power menu |
| `kitty.conf`    | kitty terminal |
| `rofi.rasi`     | rofi launcher / menus |
| `hyprlock.conf` | hyprlock lock screen |
| `cava.theme`    | cava audio visualizer (color block spliced into its config) |
| `btop.theme`    | btop (`color_theme` points at this path) |
| `fzf.opts`      | fzf (`FZF_DEFAULT_OPTS_FILE`) |
| `meta.sh`       | `rice-theme` — the non-include bits (GTK theme name, bat theme, color-scheme, papirus accent, yazi flavor) |

**How `rice-theme` works** (`SUPER+T`, or `rice-theme <name>` / `--list`):
1. Repoints `~/.config/themes/current` → the chosen theme dir (the one symlink
   every app includes through).
2. Sources `meta.sh` and applies the things that *aren't* file-includes: GTK
   theme + `color-scheme` via `gsettings`, GTK4 css symlinks, bat theme file,
   btop `color_theme` (sed), cava color block (spliced in via python), yazi
   flavor (sed), optional papirus folder accent.
3. Fires live reloads for everything that can hot-reload: re-renders the quote
   wallpaper in the new colors, `hyprctl reload`, waybar `SIGUSR2`, kitty
   `SIGUSR1`, `swaync-client -rs`, cava/btop `SIGUSR2`, restarts swayosd. rofi /
   wlogout / hyprlock pick it up on next open; Qt + Chromium apps need a restart.

The `current` symlink is **gitignored** (it's machine state, and points into
`$HOME`). Nothing `rice-theme` touches leaves `$HOME`, so the **ly greeter is
untouched by design**.

**Shipped themes (16):**
- **Dark:** `catppuccin-mocha` (default), `tokyo-night`, `gruvbox-dark`, `nord`,
  `rose-pine`, `everforest`, `kanagawa`, `oxocarbon`, and six ported from
  [ryoku-arch](https://github.com/neur0map/ryoku-arch): `aqua` (GitHub-dark + liquid-glass),
  `cassette` (vintage sepia), `crt` (phosphor green/cyan), `mountains` (earthy alpine),
  `soft-color` (pastel on slate), `washi` (vermilion on paper).
- **Light:** `catppuccin-latte`, `solarized-paper`.

The picker enumerates the theme dirs dynamically, so any new directory that follows
the 12-file contract shows up in `SUPER+T` automatically — no list to maintain.

**Add a new theme:**
```bash
cd dotfiles/.config/themes
cp -r catppuccin-mocha my-theme          # start from the closest existing one
$EDITOR my-theme/*.css my-theme/*.conf … # recolor all 12 files (keep the filenames!)
$EDITOR my-theme/meta.sh                 # set GTK/bat/yazi names for this palette
rice-theme my-theme                      # switch to it live
cd ~/git/dotfiles && git add -A && git commit -m "themes: add my-theme"
```
Any GTK theme named in `meta.sh` must be installed separately (AUR); if it's
absent `rice-theme` skips it gracefully.

---

## Scripts (`dotfiles/.local/bin`)

| Script | What it does |
|--------|--------------|
| `rice-switch`            | Apply the Home Manager flake the one correct way (see above). Never run bare `home-manager switch`. |
| `sysupdate`              | Update both software worlds at once: `paru -Syu` (repo + AUR) then `rice-switch`. `--clean` also trims caches / old generations / orphans. |
| `rice-theme`             | Switch the whole desktop between the 10 color themes (`SUPER+T` = rofi menu; `<name>` / `--list` also work). |
| `quote-wallpaper.sh`     | Fetch a random quote and render it to a wallpaper via headless Chromium (no ImageMagick/PIL); displays via awww (falls back to swaybg). Offline-cached. |
| `wlogout-menu.sh`        | Launch wlogout with per-monitor margins computed so the button grid stays square on whatever display is focused (`SUPER+X` / `SUPER+M`). |
| `keybind-cheatsheet.sh`  | Searchable keybind list (`SUPER+/`) parsed live from `hyprland.lua`, so it never goes stale. |
| `gamemode.sh`            | Toggle a performance mode (`SUPER+SHIFT+G`): off = animations/blur/shadows/gaps, on = plain `hyprctl reload` to restore. |
| `ocr-copy.sh`            | OCR a screen region to the clipboard (`SUPER+SHIFT+X`) via grim + slurp + tesseract. |
| `nightlight.sh`          | Toggle a 4000K blue-light filter (`SUPER+SHIFT+N`) via hyprsunset. |
| `waybar-playpause.sh`    | Prints the play/pause glyph for the waybar media module (via playerctl). |
| `waybar-window.sh`       | Waybar active-window module: per-app Nerd Font glyph + title (avoids icon-theme mismatches). |
| `lid.sh`                 | Enable/disable the internal laptop panel on lid open/close while docked (auto-detects the eDP connector). |
| `wallpaper-hotplug.sh`   | Repaints the quote wallpaper when a monitor is hotplugged (docking left new outputs blank). Idles on Hyprland's event socket — zero CPU. |
| `welcome.sh`             | "Welcome back" notification once at login (date, battery %, pending updates). Offline only; disable in `hyprland.lua`'s autostart block. |

---

## Keybind highlights

`SUPER` is the mod key. Full, always-current list: press **`SUPER+/`**.

| Bind | Action |
|------|--------|
| `SUPER+Q`            | terminal |
| `SUPER+C`            | close window |
| `SUPER+R` / `SUPER+SPACE` | app launcher |
| `SUPER+G`            | GNOME-style app grid (browse all apps) |
| `SUPER+E`            | file manager |
| `SUPER+B`            | browser |
| `SUPER+V`            | toggle floating |
| `SUPER+F`            | fullscreen toggle |
| `SUPER+X` / `SUPER+M`| power menu (wlogout) |
| `SUPER+L`            | lock screen (hyprlock) |
| `SUPER+A`            | audio visualizer (cava) |
| `SUPER+T`            | theme switcher |
| `SUPER+/`            | searchable keybind cheatsheet |
| `SUPER+SHIFT+V`      | clipboard history (cliphist) |
| `SUPER+SHIFT+G`      | game mode (eye-candy off/on) |
| `SUPER+SHIFT+X`      | OCR region → clipboard |
| `SUPER+SHIFT+N`      | blue-light filter toggle |
| `SUPER+SHIFT+C`      | color picker → clipboard (hyprpicker) |
| `SUPER+S` / `SUPER+SHIFT+S` | scratchpad / move to scratchpad |
| `Print` / `SUPER+Print` | region screenshot → annotate (satty) / full screen → file |
| `SUPER+←↑↓→`         | focus window in direction |
| `SUPER+CTRL+←↑↓→`    | resize window (repeating) |
| `SUPER+1..9` / `SUPER+SHIFT+1..9` | switch to / move window to workspace |
| `XF86Audio*` / `XF86MonBrightness*` | volume / media / brightness (swayosd OSD, wpctl fallback) |

Every bind in `hyprland.lua` carries a trailing `-- comment` describing it —
**keep that convention**, because `keybind-cheatsheet.sh` reads those comments.

---

## What is deliberately NOT in the repo

- **`~/.ssh/config.d/*.conf`** — private homelab host definitions. The generic
  `~/.ssh/config` *is* tracked; the per-host includes and **private keys** are not
  (gitignored). These are in the eva **backup** instead — see `docs/backup.md`.
- **ly greeter config** (`/etc/ly/config.ini`) — system-owned, tuned by
  `system/fix-ly.sh`, not a dotfile. (`dur_file` animation is BANNED — it crashed
  the boot twice.)
- **The `themes/current` symlink** — machine state, points into `$HOME`.
- **VSCodium settings** (`~/.config/VSCodium/User/settings.json`) — not
  symlinked into the repo (VSCodium rewrites the file, which fights symlinks).
  It's covered by the eva backup instead.
- **Runtime data** — qutebrowser history/bookmarks/cache (only `config.py` is
  tracked), btop/cava state, logs, nix `result` symlinks, caches.
- **Secrets of any kind** — keep it that way if this repo ever goes public.

---

## Restore on a wiped / new machine
```bash
sudo pacman -S --needed git
git clone <this-repo-url> ~/git/dotfiles
cd ~/git/dotfiles && bash bootstrap.sh
systemctl reboot
```
See `docs/reinstall.md` for the full runbook and `docs/backup.md` for backups.
The repo currently has **no git remote** — the one-liner to add a Gitea remote
later is in `docs/backup.md`.

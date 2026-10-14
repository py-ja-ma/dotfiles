> **Historical survey (read-only snapshot of panasonic, 2026-10-05) — superseded.**
> Everything it lists has since changed: editor is VS Code, GTK is adw-gtk3, backups are
> borgmatic (`docs/backups.md`), hardening is applied (`docs/hardening.md`), the CLI is
> `rice` (`docs/rice-cli.md`), AUR builds come from `[rice]` (`docs/packaging.md`),
> `MAINTENANCE.md` lives in `legacy/rice-setup/`. Current truth: `README.md`,
> `docs/apps.md`, `hosts/panasonic/README.md`.

# panasonic — replication brief (read-only survey, 2026-10-05)

Nothing was modified on the remote host. All reads were `cat`/`grep`/`ls`/`systemctl is-enabled`.

## 0. First, a structural finding that changes how you read everything else

**`rice-setup/` is a stale snapshot; `rice/` is the live repo.** They hold near-identical scripts:

- `rice-setup/` — all files dated **Jul 2**, paths reference `~/git/dotfiles/panasonic/rice-setup/...`
- `rice/system/` — same scripts, dated **Jul 2–Jul 4**, paths rewritten to `~/git/dotfiles/panasonic/rice/system/...`

`diff` across the seven shared scripts (`apply-refind.sh`, `fix-ly.sh`, `install-apps.sh`, `plymouth-setup.sh`, `setup.sh`, `system-rice.sh`, `system-tweaks.sh`) shows **only path strings and three comment corrections** — no logic differences:

| File | Only real drift |
|---|---|
| `setup.sh` | comment: "keeping **mako**" → "keeping **swaync**" |
| `system-tweaks.sh` | comment: "wallpaper is handled by **swaybg**" → "by **awww-daemon**" |
| `plymouth-setup.sh` | echo: "ly (Game of Life)" → "ly (plain greeter)" |

**Replicate from `rice/`, not `rice-setup/`.** `rice/` is a git repo (`.git` present); `rice-setup/` is not. Two scripts exist **only** in `rice-setup/`: `install-appgrid-steam.sh` and `fix-eva-and-backup.sh` (both superseded in intent — see §6). Six scripts exist **only** in `rice/system/`: `backup-eva.sh`, `harden.sh`, `nftables.conf`, `pkglist.txt`, `pkglist-aur.txt`, `pkgs-snapshot.sh`, `allow-papirus-folders.sh`.

`rice/bootstrap.sh` **does exist** (requested as conditional).

---

## 1. System layer vs user layer

The split is explicit and documented in three places (`rice/README.md`, `docs/nix-manager.md`, `MAINTENANCE.md`): *"Never let one world own the other's stuff — that's the whole design."*

### System layer — Arch (`pacman`/`paru`), installed by `rice/system/` scripts
Owns anything touching `/etc`, the ESP, or the initramfs — Nix on Arch cannot own those.

- **Kernel & firmware:** `linux`, `linux-firmware`, `intel-ucode`, `sof-firmware`
- **Graphics:** `mesa` (via deps), `vulkan-intel`, `intel-media-driver`, `libva-intel-driver`, `lib32-mesa`, `lib32-vulkan-intel`
- **Compositor & desktop binaries:** `hyprland`, `hyprlock`, `hypridle`, `hyprshot`, `hyprpicker`, `hyprsunset`, `waybar`, `rofi`, `swaync`, `swayosd`, `swaybg`, `awww`, `wlogout` (AUR), `cliphist`, `nwg-drawer`, `nwg-look`, `nwg-displays`, `uwsm`, `xdg-desktop-portal-hyprland`
- **Greeter:** `ly` (+ `/etc/ly/config.ini`)
- **Boot:** `refind`, `plymouth`, `lvm2`, `zram-generator`
- **Audio:** `pipewire` + `-alsa`/`-jack`/`-pulse`, `wireplumber`, `libpulse`, `gst-plugin-pipewire`
- **Network:** `iwd`, `wireless_tools`, `openssh` (client only — no sshd rule in the firewall)
- **Terminal emulator:** `kitty` (the *emulator* is pacman; its *config* is Nix-symlinked)
- **Apps:** `chromium`, `qutebrowser`, `obsidian`, `thunar`, `mpv`, `imv`, `zathura`, `steam`, `yazi`, `btop`-adjacent `htop`, `vorta`, `borg`, `kooha`, `mission-center`, `satty`, `cava`
- **Themes as system assets:** `papirus-icon-theme`, `kvantum`, `qt6ct`, the GTK theme packages (all AUR), `ttf-jetbrains-mono-nerd`, `otf-font-awesome`
- **System config files authored by the repo:** `/etc/nftables.conf`, `/etc/sysctl.d/99-hardening.conf`, `/etc/systemd/resolved.conf.d/dot.conf`, `/etc/security/faillock.conf`, `/etc/sudoers.d/10-hardening`, `/etc/sudoers.d/papirus-folders` (optional)

### User layer — Nix / home-manager flake (`rice/flake.nix` + `rice/home.nix`)
Flake output is `homeConfigurations."pj"` → attr **`#pj`**. Inputs: `nixpkgs/nixos-unstable` + `nix-community/home-manager` (with `inputs.nixpkgs.follows`), `config.allowUnfree = true`, `system = "x86_64-linux"`, `home.stateVersion = "26.05"`.

**Nix-installed packages** (`home.packages`): `playerctl brightnessctl grim slurp wl-clipboard fd ripgrep tealdeer duf dust fastfetch blesh nerd-fonts.symbols-only nerd-fonts.jetbrains-mono dancing-script eb-garamond`

**Nix-managed programs** (`programs.*.enable`): `bat`, `fzf` (+bash integration), `btop`, `eza`, `zoxide`, `atuin` (**`enableBashIntegration = false`** on purpose — hooked manually after ble.sh), `starship`, `bash`, `home-manager`

**Nix glue required on Arch** (both present, both mandatory): `targets.genericLinux.enable = true` and `fonts.fontconfig.enable = true`.

**Dotfiles are `mkOutOfStoreSymlink`, not store copies.** `xdg.configFile` links: `hypr waybar rofi swaync swayosd satty fastfetch themes nwg-drawer wlogout kitty cava gsimplecal qt6ct gtk-3.0 gtk-4.0 iwgtk-gtk/gtk-4.0/gtk.css starship.toml chromium-flags.conf qutebrowser/config.py VSCodium/User/settings.json VSCodium/User/settings.json.default`. `home.file` links `.ssh/config` plus every `.local/bin/*` script.

Note the duplicated-tool pattern: `brightnessctl`, `playerctl`, `grim`, `slurp`, `wl-clipboard` are in **both** `pkglist.txt` and `home.packages`. Harmless (PATH order decides) but worth knowing.

One activation hook: `home.activation.sshSockets` creates `~/.ssh/sockets` mode 700 (ssh won't create a `ControlPath` parent).

---

## 2. Bootloader

### `rice/system/apply-refind.sh` (theme only, idempotent, 1785 bytes)
Header: *"(re)install the Catppuccin rEFInd theme onto the ESP. This build: Arch logo instead of Tux + neutral-grey background. Backs up refind.conf first; does NOT touch ly, kernels, or boot entries."*

Steps:
1. Requires root (`[ "$(id -u)" -eq 0 ]`).
2. ESP discovery loop — first of `/boot/EFI/refind`, `/efi/EFI/refind`, `/boot/efi/EFI/refind` containing `refind.conf`. Aborts if none.
3. `cp -a "$REFIND_DIR/refind.conf" "$REFIND_DIR/refind.conf.bak-$STAMP"`
4. `rm -rf themes/catppuccin` then `cp -r "$THEME_SRC" "$REFIND_DIR/themes/catppuccin"`
5. Guarded include injection:
```bash
if ! grep -q '^include themes/catppuccin/mocha.conf' "$REFIND_DIR/refind.conf"; then
  sed -i '/^include themes\//d' "$REFIND_DIR/refind.conf"
  printf '\ninclude themes/catppuccin/mocha.conf\n' >> "$REFIND_DIR/refind.conf"
fi
```

`system-rice.sh` step 1 does the **same thing** but *unguarded* — it always runs the `sed -i '/^include themes\//d'` + append, so running it twice is still fine (idempotent by delete-then-append) but it is not the `grep`-gated version. `apply-refind.sh` is the safer standalone.

### Theme content (`rice/system/refind-catppuccin/mocha.conf`)
Upstream catppuccin/refind, locally modified. Active directives:
- `hideui singleuser,hints,arrows,label,badges,safemode,hwtest`
- `use_graphics_for osx,linux,elilo,grub,windows`
- `icons_dir themes/catppuccin/assets/mocha/icons`
- `banner themes/catppuccin/assets/mocha/background.png` + `banner_scale fillscreen`
- `selection_big` / `selection_small` from the same asset dir
- `showtools shutdown`

Four flavors ship (`latte/frappe/macchiato/mocha.conf`); scripts hardcode **mocha**.

### Live `/boot/EFI/refind/refind.conf`
Arch's shipped sample, all `menuentry` blocks `disabled`, with real settings:
```
timeout 20
use_nvram false
extra_kernel_version_strings "linux-hardened,linux-rt-lts,linux-zen,linux-lts,linux-rt,linux"
...
include themes/catppuccin/mocha.conf
```
Boot entries therefore come from rEFInd's **auto-detection** of `/boot/vmlinuz-linux` + `refind_linux.conf`, not from manual stanzas.

### `refind_linux.conf` — what generates it, what it contains
**Generated by `refind-install`**, which runs automatically via a pacman hook at `/etc/pacman.d/hooks/99-refind.hook`:
```
[Trigger] Operation=Install, Operation=Upgrade, Type=Package, Target=refind
[Action]  When=PostTransaction  Exec=/usr/bin/refind-install
```
Live content (exactly, two lines):
```
"Arch Linux (linux)" "root=/dev/ArchinstallVg/root zswap.enabled=0 rw rootfstype=ext4 initrd=\initramfs-linux.img quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0"
"Arch Linux (linux-fallback)" "root=/dev/ArchinstallVg/root zswap.enabled=0 rw rootfstype=ext4 initrd=\initramfs-linux-fallback.img"
```
The `quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0` tail was appended by `plymouth-setup.sh`, which edits **only** the line starting `"Arch Linux (linux)"` and deliberately leaves `linux-fallback` verbose. Two `.bak` files sit in `/boot` from Jul 2 runs.

### LVM — and the LUKS claim is aspirational, not current
Live `lsblk -f`:
```
nvme0n1p1  vfat FAT32  -> /boot   (~1G, 6% used)
nvme0n1p2  LVM2_member -> ArchinstallVg-home (ext4, /home)
nvme0n1p3  LVM2_member -> ArchinstallVg-root (ext4, /) + home
zram0      swap (label zram0)  [SWAP]
```
**There is no `crypto_LUKS` and no `cryptdevice=` in `refind_linux.conf`.** `docs/reinstall.md` describes LUKS as the *planned* target layout ("for the planned **LUKS full-disk-encryption** reinstall"). Do not read it as the current state. Also note the live layout has **two** LVM PVs (`p2` and `p3`) where `reinstall.md`'s reference table says "`nvme0n1p2/3 LVM2 ArchinstallVg`" — consistent, but reinstall.md's LUKS plan collapses them into one `p2`.

Live `/etc/mkinitcpio.conf`:
```
MODULES=(i915)
HOOKS=(base udev plymouth autodetect microcode modconf kms keyboard keymap consolefont lvm2 block filesystems fsck)
```
No `encrypt` hook (consistent — no LUKS yet). `reinstall.md` prescribes `HOOKS=(base udev autodetect microcode modeset keyboard keymap consolefont block encrypt lvm2 filesystems fsck)` for the LUKS build — **note that prescription omits the `plymouth` hook**, so following reinstall.md literally would silently drop the splash.

`/etc/systemd/zram-generator.conf` confirmed live: `[zram0]`, `zram-size = 7825`, `compression-algorithm = zstd`.

### Plymouth interaction (`rice/system/plymouth-setup.sh`)
Self-describes as **boot-critical**. Order:
1. `pacman -S --needed --noconfirm plymouth`
2. Backs up **both** `/etc/mkinitcpio.conf` and `/boot/refind_linux.conf` to `.bak-$STAMP`
3. An inline `python3` heredoc that:
   - inserts `plymouth` into `HOOKS` **immediately after `udev`** (fallback: index 1)
   - inserts `i915` at the **front** of `MODULES` (early KMS)
   - appends the splash cmdline to the `"Arch Linux (linux)"` line only, by locating the 4th `"` and inserting before it
4. Installs the custom theme to `/usr/share/plymouth/themes/catppuccin` from `plymouth-catppuccin/` (`catppuccin.plymouth` + `catppuccin.script`, mode 644) — a self-contained "script"-type theme, no image assets
5. `plymouth-set-default-theme -R catppuccin` (falls back to `spinner` if the theme dir is missing); `-R` rebuilds the initramfs
6. Prints the recovery path: *"If anything looks wrong, pick 'Arch Linux (linux-fallback)' in rEFInd — it boots verbose."*

Boot chain intended: **rEFInd (Catppuccin) → Plymouth (Catppuccin orbiting dots) → ly**.

---

## 3. Login / greeter (`ly`)

### How it's meant to be configured
Three different scripts write `/etc/ly/config.ini`, all with the same `set_ly()` idempotent helper (`sed -i -E` if the key exists, else append), all backing up to `$LY.bak-$STAMP` first:

| Script | Role |
|---|---|
| `system/fix-ly.sh [none\|matrix]` | **The canonical one.** Takes a mode argument; refuses anything but `none`/`matrix`. |
| `system/system-rice.sh` step 2 | Hardcodes `animation none` + colors + `hide_key_hints false`. |
| `system/system-tweaks.sh` step 1 | Hardcodes `animation none` + colors. Redundant with the above. |
| `system/harden.sh` step 6 | Only forces `allow_empty_password = false`, then `systemctl enable ly@tty2.service`. |

Common settings written (Catppuccin, 0x00BBGGRR-ish ly format):
```
bg = 0x001e1e2e        fg = 0x00cdd6f4
border_fg = 0x0089b4fa clock = %H:%M
dur_file_path = ""     (+ rm -f /etc/ly/*.dur)
```
`matrix` mode additionally sets `cmatrix_fg = 0x0089b4fa`, `cmatrix_head_col = 0x01b4befe`, `cmatrix_min_codepoint = 0x21`, `cmatrix_max_codepoint = 0x2f`.

### Which tty
**tty2.** Enabled as a template instance: `sudo systemctl enable ly@tty2.service`. Done in three places: `harden.sh` step 6, `bootstrap.sh` step 6, and `reinstall.md` §4d. Verified live:
```
systemctl is-enabled ly.service   -> not-found
systemctl is-enabled ly@tty2.service -> enabled
ly@.service: indirect / disabled preset ; ly-kmsconvt@.service: disabled
```
There is **no plain `ly.service`** on this build — only the `ly@.service` template. That is a real trap when replicating.

### Which session: `hyprland.desktop` vs `hyprland-uwsm.desktop`
Intent (`system-rice.sh` step 3, "Collapse duplicate Hyprland sessions"):
```bash
if [ -f "$SESS/hyprland-uwsm.desktop" ]; then
  mkdir -p "$DIS"; mv "$SESS/hyprland-uwsm.desktop" "$DIS/"
fi
```
`$SESS=/usr/share/wayland-sessions`, `$DIS=/usr/share/wayland-sessions-disabled`. So **`hyprland.desktop` is the intended session; the uwsm variant is moved out.** The script itself warns: *"(a hyprland package update may re-add it; re-run this script if so)"*.

**That has already happened.** Live state:
```
/usr/share/wayland-sessions/:          hyprland-uwsm.desktop (Sep 30), hyprland.desktop (Sep 30)
/usr/share/wayland-sessions-disabled/: hyprland-uwsm.desktop (Jun 11)
```
Both entries are back in the live sessions dir — a hyprland upgrade on Sep 30 re-added uwsm, and the script has not been re-run since. The greeter currently offers two sessions. Also note `uwsm` **is** in `pkglist.txt`, so a fresh install gets the uwsm desktop file and needs `system-rice.sh` to prune it.

### Live `/etc/ly/config.ini` drift from the docs
`animation = matrix`, not `none`. So `fix-ly.sh matrix` was the last thing run, contradicting `reinstall.md` §4d which prescribes `sudo bash .../fix-ly.sh none`. Other live values of note: `allow_empty_password = false` (hardened, good), `auth_fails = 10`, `battery_id = null`, `dur_file_path = ` (empty — correctly scrubbed), `brightness_down_cmd/up_cmd` bound to `brightnessctl` on F5/F6, `custom_sessions = /etc/ly/custom-sessions`.

---

## 4. The helper scripts

### `rice-switch` (761 B, `dotfiles/.local/bin/rice-switch`)
The entire body:
```bash
set -euo pipefail
exec home-manager switch \
  --flake "$HOME/git/dotfiles/panasonic/rice#pj" \
  --extra-experimental-features 'nix-command flakes' \
  -b bak \
  "$@"
```
No destructive behavior of its own. `-b bak` renames a pre-existing real file to `*.bak` instead of erroring. Its entire reason for existing is defensive — see §8.

### `sysupdate` (5447 B) — step by step
Flags parsed into `CLEAN` / `FULL`; unknown flags warn but don't abort. `REPO="$HOME/git/dotfiles/panasonic/rice"`. `set -uo pipefail` (deliberately **not** `-e`, so a failed stage doesn't kill the run).

0. Prints the Arch-news reminder (`https://archlinux.org/news/`). Informational only.
1. `paru -Syu` if paru is on PATH; else warns and falls back to `sudo pacman -Syu` (official repos only). Inline comment: *"NEVER use -Sy alone (partial upgrade = breakage)"*.
2. If `--full`: `cd $REPO && nix --extra-experimental-features 'nix-command flakes' flake update`. On failure, warns and keeps the old pins.
3. `rice-switch`. **Safety guard:** if it fails, prints *"your PREVIOUS generation is still active, nothing broke"*, and if `--full` was given, runs `git checkout -- flake.lock` to restore last-good pins. On `--full` success it prints the commit command rather than committing for you.
4. If `--clean` (all conservative):
   - `sudo paccache -rk2` — keeps last 2 versions. Warns to install `pacman-contrib` if absent.
   - `mapfile -t ORPHANS < <(pacman -Qqdt)` — **lists only, never removes.** Prints the `sudo pacman -Rns ...` command and the note *"'rust' provides cargo, keep it if you compile."*
   - `home-manager expire-generations "-7 days"` **then** `nix-collect-garbage --delete-older-than 7d`. Order matters (expire first, GC second) and both run **as pj, not sudo** — `nix-manager.md` calls out both rules explicitly.
5. Closing reminders: reboot after a kernel update; `find /etc -name '*.pacnew'`.

**Destructive surface:** only `paccache -rk2` and the 7-day nix GC. Both bounded. `sysupdate` plain *"removes nothing"*. Does **not** touch `flake.lock` unless `--full`. Does **not** run `pkgs-snapshot.sh` (pkgs-snapshot's header suggests wiring it in; it isn't wired).

Shell alias in `home.nix`: `upgrade = "sysupdate --clean"`, `backup = "bash ${repo}/system/backup-eva.sh"`.

### `rice-theme` (8253 B) — step by step
Architecture: `~/.config/themes/<name>/` holds per-app adapter files; every app includes through the **stable** path `~/.config/themes/current/...`; switching repoints that one symlink. `set -euo pipefail`.

1. **Enumerate:** `find -L "$THEMES_DIR" -mindepth 1 -maxdepth 1 -type d ! -name current -printf '%f\n' | sort`. `-L` is required because `~/.config/themes` is itself an HM symlink into the repo.
2. **Pick:** no arg → `rofi -dmenu -i -p "theme (now: $active)"` with `|| true` so ESC is a clean no-op. Comment: *"No wofi fallback: it used to fire on rofi's ESC exit and pop a 2nd menu."* `--list` prints and exits. A name arg switches directly; unknown name exits 1.
3. **The one symlink:** `ln -sfn "$THEME" "$CUR"`.
4. **`meta.sh`:** sourced for `GTK_THEME_NAME GTK4_CSS_DIR COLOR_SCHEME BAT_THEME PAPIRUS_ACCENT YAZI_FLAVOR VSCODIUM_THEME`.
5. **gsettings:** `gtk-theme` (only if `/usr/share/themes/$GTK_THEME_NAME` exists), `color-scheme`, and `icon-theme` — `Papirus` on `prefer-light`, `Papirus-Dark` otherwise, so app icons stay legible.
6. **GTK4:** symlinks `assets`, `gtk.css`, `gtk-dark.css` into `~/.config/gtk-4.0/`.
7. **papirus-folders — the big safety guard.** Gated on `$HOME/.local/state/rice/papirus-sudo-ok`. Verbatim from the script:
   > *"Folder-icon accents (papirus-folders) need ROOT because Papirus-Dark lives in /usr/share/icons. This is DANGEROUS if left ungated: papirus-folders re-sudo's itself, and from the modal (or any no-tty context) that sudo FAILS — and every failed sudo counts toward pam_faillock, which LOCKS the account after 3 fails. A locked account then rejects your real password at hyprlock. That actually happened."*
   With the marker present it runs `setsid sudo -n papirus-folders -C "$PAPIRUS_ACCENT" --theme Papirus-Dark` itself (so papirus-folders, already root, won't re-sudo). **No marker → sudo is never invoked at all.**
8. **bat:** overwrites `~/.config/bat/config` with `--theme="$BAT_THEME"`.
9. **btop:** `sed -i` the `color_theme` line in `~/.config/btop/btop.conf` to point at `$CUR/btop.theme` (btop rewrites its own conf, hence sed not include).
10. **Seeds machine-state files from committed templates** if absent: `cava/config` from `config.default`, `VSCodium/User/settings.json` from `settings.json.default`. These are gitignored because rice-theme rewrites them in place.
11. **cava:** inline `python3` regex that splices the theme's `cava.theme` body into cava's `[color]` block (cava has no include support).
12. **yazi:** `sed -i "s|^dark = \".*\"|dark = \"$YAZI_FLAVOR\"|"` on `theme.toml`. Flavor must be pre-installed via `ya pkg add`.
13. **VSCodium:** inline `python3` that regex-patches the single `"workbench.colorTheme"` line. Comment: *"settings.json is JSONC (it has // comments) so we CANNOT json-parse it"*. Guarded with `|| true`.
14. **Reloads:** re-renders the quote wallpaper (`setsid -f quote-wallpaper.sh`), `hyprctl reload`, **`killall waybar` + respawn** (not SIGUSR2 — see §8), `swaync-client -rs`, `pkill -SIGUSR1 -x kitty`, `pkill -SIGUSR2 -x cava`, `pkill -SIGUSR2 -x btop`, restart `swayosd-server` if running. Final `notify-send`: *"rofi/wlogout/hyprlock pick it up on next open. Qt + Chromium apps need a restart."*

**Scope guarantee:** *"The ly greeter is untouched by design (nothing here leaves $HOME)."* The only exception is the gated papirus-folders sudo.

Each theme must provide a **12-file contract**: `palette.lua waybar.css swaync.css swayosd.css wlogout.css kitty.conf rofi.rasi hyprlock.conf cava.theme btop.theme fzf.opts meta.sh`.

---

## 5. Package provenance

### Source of truth: `rice/system/pkgs-snapshot.sh`
Produces two **disjoint** files so neither installer gets names it can't resolve:
```bash
pacman -Qqen > "$DIR/pkglist.txt"      # native + explicit (in a sync repo)
pacman -Qqem > "$DIR/pkglist-aur.txt"  # foreign/AUR + explicit
```
Header: *"these are the live source of truth... They replaced the old hand-curated packages-repo.txt / packages-aur.txt, which were deleted."*

### Official repos — `pkglist.txt`, 103 entries (verbatim)
`7zip arch-audit awww base base-devel blueman bluez bluez-utils borg brightnessctl cava chromium cliphist git grim gsimplecal gst-plugin-pipewire gvfs gvfs-mtp htop hypridle hyprland hyprlock hyprpicker hyprshot hyprsunset imv intel-media-driver intel-ucode iwd jre17-openjdk kitty kooha kvantum less lib32-mesa lib32-vulkan-intel libpulse libva-intel-driver linux linux-firmware lvm2 ly man-pages mission-center mpv nano noto-fonts noto-fonts-emoji ntfs-3g ntfsprogs nwg-displays nwg-drawer nwg-look obsidian openssh otf-font-awesome pacman-contrib papirus-icon-theme pavucontrol pipewire pipewire-alsa pipewire-jack pipewire-pulse plymouth pnpm polkit-kde-agent qt5-wayland qt6-wayland qt6ct qutebrowser refind reflector rofi rsync satty slurp smartmontools sof-firmware sshs steam sudo swaybg swaync swayosd tesseract-data-eng thunar thunar-archive-plugin ttf-jetbrains-mono-nerd tumbler tuned tuned-ppd udiskie unrar unzip uwsm vim vorta vulkan-intel waybar wget wireless_tools wireplumber wl-clipboard woff2-font-awesome xarchiver xdg-desktop-portal-hyprland xdg-utils yazi zathura zathura-pdf-mupdf zram-generator`

`lib32-mesa` + `lib32-vulkan-intel` + `steam` require the **`[multilib]`** repo. Nothing in `rice/system/` enables multilib — only the stale `rice-setup/install-appgrid-steam.sh` does. **This is a gap in the current reinstall path** (see §8).

### AUR — `pkglist-aur.txt`, 20 entries (verbatim)
`bolt-launcher catppuccin-gtk-theme-latte catppuccin-gtk-theme-mocha everforest-gtk-theme-git gruvbox-gtk-theme-git hyprmod informant iwgtk kanagawa-gtk-theme-git localsend-bin nordic-darker-theme papirus-folders paru proton-mail-bin rose-pine-gtk-theme spotify tokyonight-gtk-theme-git vesktop vscodium-bin wlogout`

(`MAINTENANCE.md` §1 lists only **9** AUR packages — it is from Jul 2 and stale. Trust `pkglist-aur.txt`.)

### nixpkgs
See §1. Pinned by `flake.lock` from `nixpkgs/nixos-unstable`.

### AUR helper: `paru`, bootstrapped from source
Three places bootstrap it identically — `git clone https://aur.archlinux.org/paru.git` into a `mktemp -d`, then `makepkg -si`:

`bootstrap.sh`:
```bash
if ! command -v paru >/dev/null; then
  tmp="$(mktemp -d)"; git clone https://aur.archlinux.org/paru.git "$tmp/paru"
  ( cd "$tmp/paru" && makepkg -si --noconfirm ); rm -rf "$tmp"
fi
```
`reinstall.md` §2 has the same as a one-liner. `setup.sh` step 4 prompts interactively and also accepts an existing `yay`. `paru` itself appears in `pkglist-aur.txt` (chicken-and-egg: it must be bootstrapped before that list can be fed to it).

`MAINTENANCE.md` §6 is emphatic there are **no other** managers: *"You do **not** have flatpak, snap, yay, pip, or npm. Don't add another one unless you have a real reason."* (`pnpm` is nonetheless in `pkglist.txt`.)

---

## 6. Backup strategy

### `rice/system/backup-eva.sh` (10164 B) — the current, Borg-based script
Backs up **only the irreplaceable set** — things the repo cannot regenerate:
```
$HOME/git/dotfiles
$HOME/.ssh
$HOME/Pictures
$HOME/.config/VSCodium/User/settings.json
```
Missing paths are warned-and-skipped; if **none** exist it dies.

Flow:
1. `command -v borg` or die.
2. **Locate eva** — `RICE_BACKUP_ROOT` env override wins; else tries `/run/media/$USER/eva`, `/run/media/pj/eva`, `/mnt/eva`, then `findmnt LABEL=eva`; then, if `/dev/disk/by-label/eva` exists, **auto-mounts** via `udisksctl mount -b /dev/disk/by-label/eva` (no sudo). If still unfound it prints the full mount + NTFS-dirty-flag recipe and `exit 1` **without touching anything**.
3. `export BORG_REPO="$EVA/backups/borg-rice"`, `BORG_RELOCATED_REPO_ACCESS_IS_OK=yes`.
4. **Encryption detection:** a repokey repo has `^key *=` in `$REPO/config`. If a legacy **unencrypted** repo is found it warns twice, sets `BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes`, and keeps going — *"a backup now beats no backup"*.
5. **Passphrase** read once per run (`read -rs`). First run asks twice and dies on mismatch or empty: *"nothing was created, just re-run."*
6. `borg init --encryption=repokey-blake2` **only if absent**.
7. `borg create --verbose --stats --compression zstd,6 --exclude-caches` + excludes `**/node_modules **/.cache **/*.tmp **/*.swp **/result **/result-*`. Archive name `rice-$(hostname)-$(date +%Y-%m-%d_%H%M%S)`. Treats borg exit 1 (warnings) as success; `>= 2` dies.
8. `borg prune --glob-archives 'rice-*' --keep-daily 7 --keep-weekly 4 --keep-monthly 6`, then `borg compact`, then `borg list --short`.
9. **Plain browsable mirror** (step 5 in the script): `rsync -rlt --modify-window=1 --delete` of the rice repo to `$EVA/backup/<rel>`. NTFS-safe flags (no perms/owner/group). Excludes `dotfiles/.config/themes/current`, the three `gtk-4.0` machine-state symlinks, `result`, `result-*`. Rationale from the script: *"Safe to leave in the clear: the rice repo holds NO secrets (~/.ssh lives ONLY in the encrypted archive above)."*

### `docs/backup.md`
Adds the policy around the script:
- **Encryption rationale:** the set contains `~/.ssh` private keys; eva is a losable external drive. `repokey` keeps the key inside the repo on eva; only the **passphrase** must be remembered.
- **The one hard rule:** *"put the passphrase in Proton Pass **before** the first backup run, in an entry called **"borg eva backup"**. A lost passphrase means the backup is permanently unreadable — borg cannot recover it, ever."*
- **"A REBUILD RECIPE, not a disk clone."** Explicitly **not** snapshotted: live `/etc` files, the ESP/`/boot` (kernels, initramfs, `refind.conf`, the refind binary), and package binaries. A restore = install Arch base → run `system/` scripts → clone repo → `home-manager switch`.
- **Vorta** is a GUI over the *same* borg repo, left **unconfigured on purpose**: *"its config is a SQLite profile DB whose schema shifts between versions, so hand-seeding it is fragile and not cleanly reversible."* A 7-step click-through is documented (add existing repo, 4 folders + 1 file as sources, daily schedule with *"but only if the repository drive is mounted"*, prune 7/4/6, mirror the excludes). Vorta runs a systemd **user** timer → only fires while logged in.
- **Restore:** `export BORG_REPO=...; borg list; borg list ::<archive>; borg extract ::<archive> home/pj/.ssh/config.d/homelab.conf`. Warns borg paths are **relative to `/` with no leading slash** and extraction lands under the **current directory** — *"cd somewhere safe first"*. Verified end-to-end: *"init → create → prune → compact → extract round-tripped a file byte-identical, and a wrong passphrase was rejected."*
- **eva identity:** `/dev/sda2`, NTFS 3.6 TB, label `eva` / ESD-S1C.
- **Future:** move the borg target to Gitea/backup server, keep eva as the offline second copy (3-2-1).

### `rice-setup/fix-eva-and-backup.sh` (3637 B) — **legacy, superseded, and now broken**
Pre-Borg. Mounts eva RW via `ntfs-3g` (with `ntfsfix -d` as a fallback), copies **`rice` and `rice-setup`** to `$MNT/pana-backup`, writes a `README-pana-backup.txt`, then unmounts cleanly to clear the NTFS dirty flag. Resolves the device by `blkid -L eva` with `/dev/sda2` fallback.

**It will fail as written on the current machine:** it does `cp -r "$USER_HOME/rice"` and `cp -r "$USER_HOME/rice-setup"` — i.e. `/home/pj/rice`, but the repos now live at `/home/pj/git/dotfiles/panasonic/{rice,rice-setup}`. `MAINTENANCE.md` §5.7 still recommends running it. Use `backup-eva.sh` instead; keep `fix-eva-and-backup.sh` only as the documented **NTFS dirty-flag repair** recipe.

---

## 7. Reinstall procedure (`docs/reinstall.md`)

Stated order: **Arch base+LUKS → packages → Nix/Home-Manager → system ricing → post-install checklist.**

**§0 — Before you wipe.** Copy off: `~/.ssh/config.d/*.conf` (gitignored by design), `~/.ssh/id_ed25519*`, `~/Pictures`, `~/Documents`, browser profiles, Obsidian vault. Proton Pass is cloud-synced. *"Confirm the repo itself is pushed to a git remote (as of this writing there may be **no remote** — push it somewhere before wiping, or clone from the `eva` backup at `/run/media/pj/eva/backup/panasonic`)."*

**§1 — Arch + LUKS.** Partition; `cryptsetup luksFormat --type luks2` → `cryptsetup open ... cryptlvm` → `pvcreate`/`vgcreate ArchinstallVg` → `lvcreate -L 60G ... -n root`, `lvcreate -l 100%FREE ... -n home` → `mkfs.ext4` both + `mkfs.fat -F32` the ESP. Then: zram (not a swap partition), `mkinitcpio` HOOKS with `encrypt` before `lvm2` + `mkinitcpio -P`, `intel-ucode`, `pacman -S refind` + `refind-install`, the `cryptdevice=UUID=<luks-UUID>:cryptlvm` line in `/boot/refind_linux.conf` (UUID from `blkid /dev/nvme0n1p2`), keep the verbose `linux-fallback` entry as a recovery net, Intel graphics packages, Secure Boot *"do it **with** this LUKS reinstall if at all"*. Networking: `systemctl enable systemd-networkd systemd-resolved iwd` + three `/etc/systemd/network/20-{ethernet,wlan,wwan}.network` units (route metrics 100/600/700). Monitors and eva covered in §9/§6 here.

**§2 — Packages.**
```bash
sudo pacman -Syu --needed git base-devel
sudo pacman -S --needed - < ~/git/dotfiles/panasonic/rice/system/pkglist.txt
command -v paru || { tmp=$(mktemp -d); git clone https://aur.archlinux.org/paru.git "$tmp/paru"; ( cd "$tmp/paru" && makepkg -si ); rm -rf "$tmp"; }
paru -S --needed - < ~/git/dotfiles/panasonic/rice/system/pkglist-aur.txt
```

**§3 — Nix + Home Manager.** `sh <(curl -L https://nixos.org/nix/install) --daemon --yes` (or the Determinate installer), source `/etc/profile.d/nix.sh` or the nix-daemon profile, optionally enable flakes globally in `~/.config/nix/nix.conf`, **clone to the exact path** `~/git/dotfiles/panasonic/rice`, then:
```bash
nix run home-manager/master -- switch -b backup \
  --flake ~/git/dotfiles/panasonic/rice#pj \
  --extra-experimental-features 'nix-command flakes'
```
Fallback if `home-manager/master` is broken upstream — build from the repo's own pinned HM:
```bash
cd ~/git/dotfiles/panasonic/rice
nix --extra-experimental-features 'nix-command flakes' \
  build .#homeConfigurations.pj.activationPackage && ./result/activate
```

**§4 — Post-install checklist.**
- 4a SSH: `mkdir -p ~/.ssh/config.d ~/.ssh/sockets && chmod 700 ...`, restore `config.d/*.conf`, `ssh-keygen -t ed25519 -C "pj@panasonic"`, enrol the pubkey, `systemctl --user enable --now ssh-agent.service`
- 4b `rice-switch`, then **`systemctl --user mask swaync.service`** (else every rice-switch warns "user systemd session is degraded")
- 4c `sudo bash ~/git/dotfiles/panasonic/rice/system/harden.sh`
- 4d `sudo bash .../system-rice.sh` → `sudo bash .../plymouth-setup.sh` → `sudo bash .../fix-ly.sh none` → `sudo systemctl enable ly@tty2.service`
- 4e Verify: `hyprctl monitors`, `networkctl status`, `rice-theme catppuccin-mocha`
- Then reboot once and re-verify LUKS unlock + greeter + monitors.

**`bootstrap.sh` automates §2–§3 plus the system ricing.** Its actual phases: 0 sanity (`/etc/arch-release` check, `sudo -v`, `pacman -Sy --needed git base-devel curl`) → 1 `pacman -S --needed --noconfirm - < system/pkglist.txt || true` → 2 paru bootstrap + `paru -S --needed --noconfirm - < system/pkglist-aur.txt || true` → 3 Nix install + `nix run home-manager/master -- switch -b backup --flake "$REPO#pj"` → 4 `system-rice.sh || true` → 5 `plymouth-setup.sh || true` → 6 `systemctl enable ly@tty2.service`.

**What `bootstrap.sh` does NOT do** (so reinstall.md's §4 is still required by hand): `harden.sh`, `fix-ly.sh`, `install-apps.sh`, `system-tweaks.sh` (iwd/bluetooth enablement), `setup.sh`, the swaync mask, the SSH setup, and multilib enablement. Every phase is `|| true`, so **bootstrap.sh exits 0 even if the ricing failed** — check its output, don't trust its exit code.

`system/setup.sh` is a separate, older interactive installer (its own curated `REPO_PKGS` list, prompts for paru and for `catppuccin-gtk-theme-mocha`+`glava`, sets `archlinux-java set java-17-openjdk`). It is **not** referenced by `bootstrap.sh` or `reinstall.md` — its package set is a subset of `pkglist.txt`. Treat it as superseded.

---

## 8. Explicit warnings and footguns (exhaustive, quoted)

### A. Never run bare `home-manager switch` — stated in five files
> *"⚠️ **Never run bare `home-manager switch`.** It reads a disarmed old config and once tore down every dotfile symlink, breaking login. Always use `rice-switch`. This is why the stale file is named `home.nix.STALE-DO-NOT-USE`."* — `rice-setup/MAINTENANCE.md` §3

> *"WHY THIS EXISTS: `~/git/dotfiles/panasonic/rice` is a Nix FLAKE. Running bare `home-manager switch` ignores the flake and uses ~/.config/home-manager/home.nix instead — which once silently applied a near-empty config and tore down every dotfile symlink (hypr, kitty, waybar, ...). Always switch via the flake. Always use this script."* — `dotfiles/.local/bin/rice-switch`

> *"**Never bare `home-manager switch`** — it ignores the flake, reads the stale `~/.config/home-manager/home.nix`, and once tore the rice down."* — `docs/nix-manager.md`

> *"After that first run, `home-manager` is on PATH — from then on **always use `rice-switch`** (never bare `home-manager switch`; it reads the stale `~/.config/home-manager/home.nix` and once tore down every dotfile symlink)."* — `docs/reinstall.md` §3

> *"NEVER run bare `home-manager switch` — it reads the stale ~/.config/home-manager/home.nix."* — `rice/flake.nix` comment

> *"!! OBSOLETE STARTER — DO NOT USE, DO NOT COPY INTO ~/.config/home-manager/ !! ... This is the historical starter file. Its descendant lived at ~/.config/home-manager/home.nix and, because a bare `home-manager switch` reads THAT file (ignoring the flake), it once silently applied a near-empty config and tore down every dotfile symlink — breaking the machine."* — `rice-setup/home.nix` header

### B. ly `dur_file` animation is BANNED — broke boot twice, forced ISO recovery
> *"!! The ly "dur_file" animation is BANNED on this machine. !! animation = dur_file (rain.dur) faulted the greeter with a memory/critical error at boot TWICE (2026-07-02) and forced an external-ISO recovery. ly's .dur parser is broken on this build. Never set dur_file here. If you want motion, use "matrix" (below) — it is a completely different, safe code path."* — `system/fix-ly.sh` header

> *"**ly `animation = dur_file` is BANNED** — it crashed the boot twice and forced ISO recovery on this exact hardware. `fix-ly.sh` refuses it. Only `none` (default), `matrix`, or `colormix` are safe. If ly ever crashes at boot, suspect the animation first."* — `docs/reinstall.md` §4 WARNINGS

> *"**The ly login `dur_file` animation is banned** — it has crashed boot twice. Keep ly on `animation = none` (see `fix-ly.sh`)."* — `MAINTENANCE.md` §5.5

> *"(`dur_file` animation is BANNED — it crashed the boot twice.)"* — `rice/README.md`

The ban is **enforced in code**: `fix-ly.sh` accepts only `none|matrix`, exits 1 on anything else with *"dur_file is intentionally NOT allowed"*, and unconditionally does `set_ly dur_file_path ""` + `rm -f /etc/ly/*.dur` in **both** modes so *"the crashing animation can never re-arm."* Note the doc inconsistency: reinstall.md lists `colormix` as safe; `fix-ly.sh` does **not** accept it.

### C. Never remove graphics drivers
> *"**Never remove graphics drivers.** This Intel + Wayland box needs `mesa`, `vulkan-intel`, `intel-media-driver`, `libva-intel-driver`, `linux-firmware`. Removing them previously broke the login screen."* — `MAINTENANCE.md` §5.4

> *"**Graphics = Intel iGPU + Wayland.** MUST install `mesa vulkan-intel intel-media-driver libva-intel-driver intel-ucode linux-firmware` (+ `lib32-mesa lib32-vulkan-intel` for Steam). Removing these has broken the login greeter before. Never strip GPU drivers."* — `docs/reinstall.md` §1

> *"NOTE: do NOT remove graphics drivers here. This box is Intel + Wayland and NEEDS mesa, vulkan-intel, intel-media-driver, libva-intel-driver, linux-firmware. Removing GPU drivers previously broke ly/graphics — they are intentionally kept."* — `system/system-tweaks.sh` trailing comment

> *"We only ADD packages, never remove drivers."* — `rice-setup/install-appgrid-steam.sh`

### D. Never partial-upgrade
> *"**The one rule that matters on Arch:** always upgrade with `-Syu` (sync + refresh + upgrade **together**). Never run `-Sy` on its own or `-Sy somepackage` — that refreshes the package list but installs against a half-old system ("partial upgrade") and is the classic way to break an Arch install."* — `MAINTENANCE.md` §3

> *"full system upgrade — NEVER use -Sy alone (partial upgrade = breakage)"* — `sysupdate` inline comment

### E. papirus-folders sudo → pam_faillock → locked out of hyprlock
> *"This is DANGEROUS if left ungated: papirus-folders re-sudo's itself, and from the modal (or any no-tty context) that sudo FAILS — and every failed sudo counts toward pam_faillock, which LOCKS the account after 3 fails. A locked account then rejects your real password at hyprlock. That actually happened. So this step is OFF unless you opt in via system/allow-papirus-folders.sh... No marker -> we never touch sudo at all, so a theme switch can never lock you out."* — `dotfiles/.local/bin/rice-theme`

Related, in `harden.sh`'s faillock config:
> *"Recovery-safe: 5 tries (not the default 3 that nearly locked this account once), 10-minute auto-unlock. **NEVER set even_deny_root.** /run/faillock is tmpfs, so a reboot always clears counters."*

### F. The repo path is load-bearing — do not move it
> *"Clone the repo to the **exact path** the flake hardcodes (`home.nix` builds every dotfile symlink from the literal string `~/git/dotfiles/panasonic/rice` — a different clone path leaves every symlink dangling)."* — `docs/reinstall.md` §3

> *"The repo **must** live at exactly `~/git/dotfiles/panasonic/rice` (the path is baked into the symlinks). Don't move it."* — `docs/nix-manager.md`

> *"One subtlety done correctly here: with flakes, `mkOutOfStoreSymlink ./file` (a path *literal*) silently points into a store copy that goes stale. This config builds the target from a **string** (`"${config.home.homeDirectory}/git/…"`), which is the correct pattern — keep it that way if you add entries."* — `docs/nix-manager.md`

### G. Borg passphrase must be in Proton Pass before the first run
> *"**The one hard rule:** put the passphrase in Proton Pass **before** the first backup run, in an entry called **"borg eva backup"**. A lost passphrase means the backup is permanently unreadable — borg cannot recover it, ever."* — `docs/backup.md`

> *"Proton Pass lives in the cloud, so the passphrase survives even if both the laptop AND eva die. NEVER store the passphrase only on this laptop. WARNING: no passphrase = the backup is permanently unreadable. Put it in Proton Pass BEFORE the first backup run."* — `system/backup-eva.sh` header

### H. Never bump `home.stateVersion`
> *"Never bump it when updating home-manager/flake.lock — leave it alone."* — `rice/home.nix`

> *"`home.stateVersion = "26.05"`... It only gates backwards-compatibility shims, and it must **never** be bumped when you update HM."* — `docs/nix-manager.md`

### I. Nix GC: as pj, and expire before GC
> *"1. Run it **as pj, not sudo** — root's GC misses your user profiles under `~/.local/state/nix/profiles`. 2. Expire generations *first*, GC *second* — GC can only free what no generation references."* — `docs/nix-manager.md`

### J. Don't try to consolidate the package managers
> *"People sometimes ask "can I just put everything in nix and drop pacman?" On Arch, **no — don't.** Arch *is* pacman; the whole system, kernel, and drivers are pacman packages. Moving your apps into nix on top of Arch means two overlapping systems, more breakage, and fighting the distro."* — `MAINTENANCE.md` §6

> *"You do **not** have flatpak, snap, yay, pip, or npm. Don't add another one unless you have a real reason — every extra manager is another thing to update and secure."* — `MAINTENANCE.md` §1

### K. Reboot after a kernel update
> *"**After a kernel update, reboot before you rely on the machine.** Running kernel modules can stop loading mid-session otherwise."* — `MAINTENANCE.md` §5.3

### L. `.pacnew` files must be merged
> *"**Handle `.pacnew` files.** When an upgrade ships a new default config, it lands as e.g. `mirrorlist.pacnew` so it doesn't clobber your edits. Find and merge: `find /etc -name '*.pacnew'`"* — `MAINTENANCE.md` §5.6 (a pending `/etc/pacman.d/mirrorlist.pacnew` was noted on Jul 2)

### M. sysctl: deliberately NOT hardening user namespaces
> *"## Deliberately ABSENT: kernel.unprivileged_userns_clone = 0 ## (breaks Flatpak/bubblewrap, Chromium sandbox, Steam pressure-vessel)"* — `harden.sh` / `99-hardening.conf`

> *"Deliberately does NOT touch user namespaces (would break Chromium/Flatpak sandboxes)."* — `harden.sh` header

### N. The swaync double-start → "user systemd session is degraded"
> *"Hyprland's `exec-once` starts swaync, but the Arch package also ships a systemd user unit that raced it at login, failed ("already running"), and made every `rice-switch` print "The user systemd session is degraded". Fixed by masking the redundant unit: `systemctl --user mask swaync.service` (2026-07-03; must be re-done on a fresh install — it's in the reinstall checklist)."* — `docs/nix-manager.md`

### O. Session-variable gotcha
> *"a var added to `home.sessionVariables` appears in new terminals after `rice-switch`, but Hyprland itself (and anything it spawned) only sees it after **log out / log in**. If a var "isn't working", that's why."* — `docs/nix-manager.md`

### P. waybar SIGUSR2 does not work for themed colors
> *"waybar: SIGUSR2 does NOT reliably re-read an @import'd color file that lives behind a stable symlink (GTK caches the import by URI, so the colors go stale). Fully restart instead."* — `rice-theme`

> *"only the single-string negation form works in this waybar build"* (`output: "!eDP-1"`) — `docs/reinstall.md` §1

### Q. `hyprctl keyword monitor` is rejected on this build
> *"This Hyprland build uses the Lua config, so monitor changes MUST go through `hyprctl eval 'hl.monitor{...}'` — `hyprctl keyword monitor` is REJECTED here ("keyword can't work with non-legacy parsers. Use eval."), which silently made the old version a no-op."* — `dotfiles/.local/bin/lid.sh`

> *"NOTE: this Hyprland build takes Lua expressions in `hyprctl dispatch`, not the classic "dpms on" string form"* — `hypridle.conf`

### R. ble.sh winch gotcha
> *"ble.sh's default winch handler (redraw-here) miscounts rows for our 2-line prompt and leaves a stray duplicate of the top prompt line. redraw-prev repaints from the panel origin instead... note ble.sh does NOT validate this value, and the widely-cited "redraw-safe" is an EMPTY no-op case in the source — it does not fix it."* — `rice/home.nix`

### S. Package-manager tab-completion must stay disabled
> *"Package-manager commands get NO completion and NO prediction. Their TAB completion runs a command substitution over the package DB (which holds NUL bytes -> bash warns "ignored null byte in input") and ble.sh's live completion re-fires it as you type."* — `rice/home.nix` (`complete -F _pj_no_completion paru pacman yay`)

### T. rice-theme's no-wofi-fallback
> *"(No wofi fallback: it used to fire on rofi's ESC exit and pop a 2nd menu.)"* — `rice-theme`

### U. Vorta must not be hand-seeded
> *"It was left **unconfigured on purpose** — its config is a SQLite profile DB whose schema shifts between versions, so hand-seeding it is fragile and not cleanly reversible."* — `docs/backup.md`

### V. Borg extract lands in the CWD
> *"borg paths are relative to /, no leading slash. extraction lands under the CURRENT directory, so cd somewhere safe first."* — `docs/backup.md`

### W. If it won't boot
> *"**If it won't boot:** you've done this — boot the Arch ISO, mount the disk, fix the offending file (usually ly or a driver), reboot."* — `MAINTENANCE.md` §5.8

Plus `plymouth-setup.sh`: *"If anything looks wrong, pick 'Arch Linux (linux-fallback)' in rEFInd — it boots verbose."* and reinstall.md: *"Keep the rEFInd `linux-fallback`/verbose entry (no `quiet splash`) as a recovery net."*

### X. ly must have `allow_empty_password = false`
> *"Set `allow_empty_password = false` in `/etc/ly/config.ini` before enabling ly."* — `docs/reinstall.md` §4 WARNINGS (enforced by `harden.sh` step 6; verified live)

### Y. A hyprland update re-adds the uwsm session
> *"(a hyprland package update may re-add it; re-run this script if so)"* — `system-rice.sh`. **Confirmed to have already happened** (see §3).

### Z. Doc contradictions and stale content you must not trust blindly
These are not "never do X" warnings but they will bite a replicator:

1. **`rice-setup/` vs `rice/`** — see §0. `rice-setup/README.md` is stale in content too: it documents **wofi** as the launcher (now rofi) and **mako** as the notification daemon (now swaync), and says *"Launcher look: `~/.config/wofi/style.css`"* — there is no wofi config in `home.nix`.
2. **`pkglist.txt` contents.** `reinstall.md` §2 says *"`system/pkglist.txt` — every explicitly-installed package (`pacman -Qeq`), repo + AUR"* and *"AUR names in the file are simply skipped with a warning"*. **Wrong.** `pkgs-snapshot.sh` generates it with `pacman -Qqen` (native only) and its own header says the two lists are *"DISJOINT... no package appears in both"*. `pkglist.txt` contains **no** AUR names. Harmless, but the "skipped with a warning" reassurance is obsolete.
3. **Monitor identification.** `reinstall.md` §1 says *"Both externals are the same model, so you can't disambiguate them by EDID/description — only by port."* The live `hyprland.lua` (newer) does **exactly the opposite** and says the port approach is what broke: *"Matched by EDID/serial (desc:), NOT port name. The dock re-enumerates the DP-* ports across redocks (DP-6/DP-4 have become DP-5/DP-8), which silently breaks port-based rules. Serials are stable."* Trust `hyprland.lua`. The whole monitor table in reinstall.md (eDP-1 main, DP-6 ws4-6, DP-4 ws7-9) is superseded.
4. **VSCodium settings.** `rice/README.md` says settings.json is *"not symlinked into the repo (VSCodium rewrites the file, which fights symlinks)"* — but `home.nix` **does** symlink both `VSCodium/User/settings.json` and `settings.json.default`, and `rice-theme` patches the live file in place. The README is stale here.
5. **Theme count.** `rice/README.md` says *"Shipped themes (16)"* in one place and *"the 10 color themes"* in the scripts table.
6. **waybar reload.** `rice/README.md` says rice-theme fires *"waybar `SIGUSR2`"*; the script actually `killall waybar` + respawns, with a comment explaining why SIGUSR2 doesn't work.
7. **ly animation.** `reinstall.md` §4d prescribes `fix-ly.sh none`; the live config has `animation = matrix`.
8. **`MAINTENANCE.md` §1 lists 9 AUR packages**; `pkglist-aur.txt` has 20.
9. **`fix-eva-and-backup.sh` copies from the wrong paths** (see §6) yet `MAINTENANCE.md` §5.7 still tells you to run it.
10. **Multilib is not enabled by anything in `rice/`.** `pkglist.txt` contains `steam`, `lib32-mesa`, `lib32-vulkan-intel`, but only the stale `rice-setup/install-appgrid-steam.sh` uncomments `[multilib]` in `/etc/pacman.conf`. Following `bootstrap.sh` or `reinstall.md` §2 verbatim on a fresh box, those three will fail to install. Enable multilib first.
11. **`bootstrap.sh` swallows all errors** (`|| true` on every phase) and exits 0 regardless.
12. **`plymouth` hook missing from reinstall.md's prescribed HOOKS** (see §2).

---

## 9. Hardware assumptions that will NOT transfer to an NVIDIA desktop

### Graphics — the single biggest blocker
| Item | Where | Problem on NVIDIA |
|---|---|---|
| `intel-media-driver`, `libva-intel-driver`, `vulkan-intel`, `lib32-vulkan-intel` | `pkglist.txt` | Wrong vendor. Need `nvidia`/`nvidia-open`/`nvidia-dkms` + `nvidia-utils` + `lib32-nvidia-utils` + `egl-wayland`. |
| `intel-ucode` | `pkglist.txt`, reinstall.md §1 | Replace with `amd-ucode` on an AMD CPU; keep if Intel CPU. |
| `MODULES=(i915)` early-KMS insertion | `plymouth-setup.sh` step 3, hardcoded `add_i915()` in the python heredoc | Inserts `i915` unconditionally. For NVIDIA you want `nvidia nvidia_modeset nvidia_uvm nvidia_drm` and `nvidia_drm.modeset=1` on the cmdline. **The script has no vendor detection** — it will put `i915` in your initramfs on an NVIDIA box. |
| Live `MODULES=(i915)` | `/etc/mkinitcpio.conf` | Same. |
| Hyprland Wayland-on-NVIDIA env vars | **absent everywhere** | `hyprland.lua`'s env block sets only `XCURSOR_SIZE`, `HYPRCURSOR_SIZE`, `QT_QPA_PLATFORMTHEME=qt6ct`. There are **no** `LIBVA_DRIVER_NAME`, `GBM_BACKEND`, `__GLX_VENDOR_LIBRARY_NAME`, `WLR_*`/`AQ_*` variables. An NVIDIA box typically needs several of these added. |
| `sof-firmware` | `pkglist.txt` | Laptop Intel SOF audio; usually unneeded on a desktop. |

The one place that *does* handle other GPUs is the stale `rice-setup/install-appgrid-steam.sh`, which `lspci`-detects and would pick `lib32-nvidia-utils`. Nothing in `rice/` does this.

### Battery — hardcoded, and one of them will break
| Item | Where | Note |
|---|---|---|
| **`/sys/class/power_supply/AC/online`** | `hypridle.conf`, third listener: `sh -c '[ "$(cat /sys/class/power_supply/AC/online)" = "0" ] && systemctl suspend'` | **Hard path, no guard.** On a desktop `AC` does not exist → `cat` fails → the test is never `"0"` → the 30-min suspend simply never fires. Fails *safe* but silently. Remove the listener. |
| `/sys/class/power_supply/BAT*/capacity` | `welcome.sh` | Properly guarded by a glob + `[[ -r ]]` loop, so it degrades cleanly. (Live device is **`BAT1`**, not `BAT0` — another reason the glob matters.) |
| waybar `battery` module | `config.jsonc` — in **both** bars' `modules-right`; `modules.jsonc` sets `states warning 30 / critical 15`, `format-icons`, `tooltip-format "{timeTo} ({power}W)"` | Will render empty/broken with no battery. Remove from both bars. |
| waybar battery CSS | `style.css` lines ~183-191 (`#battery.warning/.critical/.charging`, critical pulse animation) | Dead rules; harmless. |
| starship battery segment | `docs/terminal.md`: *"battery — only appears below 30% while discharging, in red"* | Self-hiding; harmless. |
| ly `battery_id = null` | live `/etc/ly/config.ini` | Already null; fine. |

### Lid — remove entirely
| Item | Where |
|---|---|
| `hl.bind("switch:on:Lid Switch", ... lid.sh close, { locked = true })` and `switch:off:` → `lid.sh open` | `hyprland.lua` lines 359-360 |
| `dotfiles/.local/bin/lid.sh` | Detects the first `eDP*` connector dynamically (good), falls back to literal `"eDP-1"`, and on `open` re-enables with **`scale = 1.5`** hardcoded. |
| *"Lid-close while docked disables `eDP-1` via `~/.local/bin/lid.sh`"* | `docs/reinstall.md` §1 |

On a desktop both binds are inert (no Lid Switch device) but should be deleted along with the script from `home.nix`'s `home.file` block.

### Internal panel / monitor layout — must be rewritten
`hyprland.lua` lines 32-40, verbatim:
```lua
local MON_MAIN = "desc:NZXT (PNP same EDID)_ NZXTCANVAS27Q <serial of the left panel>"  -- leftmost
local MON_MID  = "desc:NZXT (PNP same EDID)_ NZXTCANVAS27Q <serial of the middle panel>"  -- middle
local MON_LAP  = "eDP-1"                                                    -- laptop panel

hl.monitor({ output = MON_MAIN, mode = "2560x1440@59.95", position = "0x0",      scale = 1 })
hl.monitor({ output = MON_MID,  mode = "2560x1440@59.95", position = "2560x0",   scale = 1 })
hl.monitor({ output = MON_LAP,  mode = "1920x1200@60",    position = "5120x640", scale = 1.5 })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
```
- **Two serial numbers** (left in the config as `desc:` strings) of specific NZXT CANVAS 27Q units. These will match nothing on another machine.
- **`eDP-1` at 1920x1200 scale 1.5** at offset `5120x640` — a laptop panel that won't exist.
- **Nine `hl.workspace_rule` entries** bind workspaces 1-3 to `MON_LAP`, 4-6 to `MON_MAIN`, 7-9 to `MON_MID`, each `persistent = true` with `default = true` on 1/4/7. All three monitor identities must be replaced or the rules fall through.
- The catch-all `hl.monitor({ output = "" ... })` fallback means an unmatched desktop monitor *will* at least light up, and the lua comment says the workspace rules *"degrade gracefully"*. But workspace-to-monitor assignment will be effectively random.

### Waybar's two-bar split is keyed to `eDP-1`
`config.jsonc`:
```
"external" bar:  "output": "!eDP-1"   -> full module set
"laptop"   bar:  "output": "eDP-1"    -> compact module set (narrow ~1280px)
```
`modules.jsonc` has `#compact` module variants *"used by the narrow laptop bar (eDP-1)"*. On a desktop, the `!eDP-1` bar matches everything (fine) and the `eDP-1` bar never appears (fine) — but the compact variants become dead config, and `docs/reinstall.md` warns *"only the single-string negation form works in this waybar build"*, so don't try to rewrite that match to a list.

### Brightness — laptop-panel only
`brightnessctl` drives: `brightness-slider.sh` (a GTK popup, `brightnessctl get`/`max`/`set`), waybar's `backlight` module (`on-scroll-up/down "brightnessctl -q set 5%±"` in two places), and ly's own `brightness_up_cmd`/`brightness_down_cmd` on F5/F6 (`/usr/bin/brightnessctl -q -n s +10%`). A desktop monitor exposes no backlight device; all of these become no-ops or error. `nightlight.sh` (hyprsunset, 4000K) is fine — it's a software gamma shift.

### Networking — laptop/dock specific
`docs/reinstall.md` §1: *"The daily driver reaches the internet via a **USB-Ethernet dongle** (enumerates as `enp0s13f0u1u1` / `en*`); Wi-Fi is `wl*` via iwd."* The three `20-*.network` units match on globs (`en*`/`eth*`, `wl*`, `ww*`) so they transfer fine, but: `iwd` + `iwgtk` + `wifi-menu.sh` + `iwgtk-rice.sh` + waybar's network click-to-iwgtk assume Wi-Fi hardware, and `20-wwan.network` assumes a WWAN modem. **NetworkManager is deliberately not installed** — if the desktop needs it, that's a real divergence from the whole design.

### Storage / partitioning
`root=/dev/ArchinstallVg/root`, VG name `ArchinstallVg`, `rootfstype=ext4`, ESP at `/boot` (vfat, ~1G), **two** LVM PVs (`nvme0n1p2` + `p3`), `zram-size = 7825` (sized to this box's 15.6 GB RAM → 7.6 G zram). `eva` is `/dev/sda2`, NTFS, label `eva`, 3.6 TB USB. All of this must be re-derived for the new machine. `backup-eva.sh` resolves eva by **label**, so it transfers if you reuse the same drive; `fix-eva-and-backup.sh` falls back to the literal `/dev/sda2`.

### Also hardcoded to this user/host (not hardware, but non-portable)
- `home.nix`: `home.username = "pj"`, `home.homeDirectory = "/home/pj"`, repo path `~/git/dotfiles/panasonic/rice`
- `flake.nix`: output attr `homeConfigurations."pj"` (hence `#pj`)
- `allow-papirus-folders.sh`: `printf 'pj ALL=(root) NOPASSWD:SETENV: %s\n'` and `MARKER_DIR="/home/pj/.local/state/rice"` — literal `pj`
- `harden.sh`: `faillock --user pj --reset` in the comment; archive names use `$(hostname)` → `rice-panasonic-...`
- `nftables.conf`: header *"panasonic laptop firewall"*; policy is **no inbound services, no sshd rule** — if the desktop is ever an SSH *server*, this ruleset will lock you out of it.
- `docs/terminal.md` documents `@panasonic` in the starship prompt.

### What transfers cleanly, unchanged
`harden.sh`'s sysctl/DoT/faillock/sudoers work (all vendor- and form-factor-neutral, modulo the sshd-less firewall), the whole `rice-theme` 12-file theme system (nothing leaves `$HOME`), the rEFInd Catppuccin theme + `apply-refind.sh` (ESP-path-discovering, vendor-neutral), `backup-eva.sh`, the entire Nix user layer (`home.nix` minus the username/path literals), `pkgs-snapshot.sh`, and the bash/starship/atuin/ble.sh stack.

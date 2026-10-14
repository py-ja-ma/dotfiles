{ config, pkgs, lib, dram, ... }:

# The graphical session's user layer: every GUI config and helper-script
# symlink into dotfiles/, fonts, dconf, login-time env, and the user services.
# Host-dependent pieces are in laptop.nix (lid/brightness, waybar battery) and
# gpu.nix (driver env); theme state is in theme.nix; what every host needs with or
# without a session (dram, ~/.ssh/config, starship, yazi, btop, the themes) in cli.nix.
let
  inherit (dram) link;
in {
  # Only on hosts with the desktop role (decisions/0009); a headless admin box skips it.
  config = lib.mkIf (lib.elem "desktop" config.dram.roles) {
  home.packages = with pkgs; [
    # Nerd Fonts come from pacman (ttf-jetbrains-mono-nerd, ttf-nerd-fonts-symbols):
    # one source per family, see docs/toolchain/README.md. These two are not packaged on Arch.
    dancing-script
    eb-garamond
    # Letterpress house fonts (docs/design/typography/README.md): Fraunces is the display face
    # (clock, numerals, headings) and is not packaged on Arch; Literata is the
    # text/UI face (opsz 7-72, Cyrillic + Greek, the serif that survives 11 px);
    # Monaspace (terminal, readouts) comes from pacman's otf-monaspace instead.
    fraunces
    literata
  ];

  fonts.fontconfig.enable = true;
  # One family per role so GTK/Qt/kitty/browsers agree without per-app overrides.
  # Mono + Symbols from pacman's Nerd Font packages, Noto from pacman's noto-fonts*.
  # Letterpress "serif everywhere": serif = Literata (text + UI, Cyrillic),
  # then EB Garamond (hero italic >= 15 px), then Noto Serif; monospace =
  # Monaspace Xenon (slab-serif mono) with JetBrainsMono Nerd Font until the
  # package is installed. sans-serif stays Noto Sans: it is the plain generic
  # for pages that ask for one, and there is no global sans->serif alias.
  # ttf-nerd-fonts-symbols stays the only icon source.
  fonts.fontconfig.defaultFonts = {
    monospace = [ "Monaspace Xenon" "JetBrainsMono Nerd Font" ];
    sansSerif = [ "Noto Sans" ];
    serif     = [ "Literata" "EB Garamond" "Noto Serif" ];
    emoji     = [ "Noto Color Emoji" ];
  };

  # Cyrillic safety net + libadwaita's own font names. Fraunces has no
  # Cyrillic (and no tnum) and EB Garamond's italic is the only cut tracked
  # here, so both get Literata appended as a WEAK fallback: Latin still comes
  # from the named face, Russian text falls through to Literata instead of to
  # whatever fontconfig scores next. libadwaita 1.6+ asks for "Adwaita Sans" /
  # "Adwaita Mono" by name when gsettings is silent; those are bound to the
  # house text and mono faces so no GTK4 surface ever shows Inter/Noto Sans.
  # (The real UI-font lever on Wayland is gsettings
  # org.gnome.desktop.interface font-name, set by dram-theme; GTK's
  # settings.ini gtk-font-name is inert under the portal and only kept in sync.)
  xdg.configFile."fontconfig/conf.d/60-letterpress.conf".text = ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <description>Letterpress house fonts: Literata as the Cyrillic fallback for the display faces; libadwaita's Adwaita Sans/Mono mapped to the house text and mono faces</description>
      <match target="pattern">
        <test name="family" compare="contains"><string>Fraunces</string></test>
        <edit name="family" mode="append" binding="weak"><string>Literata</string></edit>
      </match>
      <match target="pattern">
        <test name="family" compare="contains"><string>EB Garamond</string></test>
        <edit name="family" mode="append" binding="weak"><string>Literata</string></edit>
      </match>
      <match target="pattern">
        <test name="family"><string>Adwaita Sans</string></test>
        <edit name="family" mode="assign" binding="same"><string>Literata</string></edit>
      </match>
      <match target="pattern">
        <test name="family"><string>Adwaita Mono</string></test>
        <edit name="family" mode="assign" binding="same"><string>Monaspace Xenon</string></edit>
      </match>
    </fontconfig>
  '';

  # (EDITOR and VISUAL: cli.nix, every host)
  home.sessionVariables = {
    BROWSER  = "librewolf";
    TERMINAL = "kitty";
    # Ghidra/Java on XWayland: without this Swing windows come up blank under
    # Hyprland (hyprland.lua sets the same var for the compositor's own env).
    _JAVA_AWT_WM_NONREPARENTING = "1";
    # Cursor defaults for apps started outside Hyprland's env (size 24 is set
    # by hyprland.lua). dram-theme sets Adwaita live through gsettings on each
    # switch; these are the login-time fallback - relogin to apply.
    HYPRCURSOR_THEME = "Adwaita";
    XCURSOR_THEME    = "Adwaita";
  };

  # ---- home folders: short lowercase names (handbook 02 §2) -----------------
  # user-dirs.dirs is what apps read for these folders (GTK's file chooser, the
  # browsers' downloads, Flatpak's xdg-* permissions, xdg-user-dir). HM writes it
  # read-only, plus user-dirs.conf `enabled=False`, so xdg-user-dirs-update at login
  # never brings the capitalised set back. null = no such folder. Desktop stays null
  # rather than $HOME: Steam's first run copies steam.desktop into the desktop folder
  # whenever that folder exists, and $HOME always does. The scripts write into fixed
  # subfolders (pictures/screenshots, pictures/wallpapers, videos/recordings); the
  # links into /data (~/games, ~/roms, ~/videos/recordings) come from role hooks
  # (system/apply-hooks.tsv), so videos/recordings is not made here.
  xdg.userDirs = let h = config.home.homeDirectory; in {
    enable = true;
    package = null;            # apps read user-dirs.dirs themselves (pacman's xdg-user-dirs comes with steam)
    createDirectories = true;
    desktop = null;
    publicShare = null;
    templates = null;
    documents = "${h}/documents";
    download = "${h}/downloads";
    music = "${h}/music";
    pictures = "${h}/pictures";
    projects = "${h}/projects";
    videos = "${h}/videos";
  };
  home.activation.dramPictureFolders = lib.hm.dag.entryAfter [ "createXdgUserDirectories" ] ''
    run mkdir -p $VERBOSE_ARG "$HOME/pictures/screenshots" "$HOME/pictures/wallpapers"
  '';

  # ---- dotfiles: editable symlinks into this repo (git-tracked) -------------
  xdg.enable = true;
  xdg.configFile = {
    # (dram/location + dram/facts.lua — the host facts — are written by core.nix)
    "hypr".source       = link ".config/hypr";
    # waybar is linked PER FILE, not as a directory: config.jsonc is host-
    # overridable (a desktop strips the battery module with a plain definition in
    # modules/laptop.nix, which beats this mkDefault) and a directory symlink cannot be partially
    # overridden. The DEFAULT is the shared file as-is (the laptop layout with
    # a battery module), so a new host module needs no waybar line at all.
    # modules.jsonc and style.css are shared.
    "waybar/config.jsonc".source  = lib.mkDefault (link ".config/waybar/config.jsonc");
    "waybar/modules.jsonc".source = link ".config/waybar/modules.jsonc";
    "waybar/style.css".source     = link ".config/waybar/style.css";
    "rofi".source       = link ".config/rofi";
    "swaync".source     = link ".config/swaync";
    "swayosd".source    = link ".config/swayosd";
    "satty".source      = link ".config/satty";
    "nwg-drawer".source = link ".config/nwg-drawer";
    "kitty".source      = link ".config/kitty";
    "cava".source       = link ".config/cava";
    # (btop's template, yazi, starship.toml and the themes: cli.nix, every host)
    "gsimplecal".source = link ".config/gsimplecal";
    # Russian proverb corpus for the second output's wallpaper (docs/design/themes/wallpaper.md)
    "quote-wallpaper".source = link ".config/quote-wallpaper";
    "gtk-3.0".source    = link ".config/gtk-3.0";
    "gtk-4.0".source    = link ".config/gtk-4.0";
    "chromium-flags.conf".source = link ".config/chromium-flags.conf";
    "qutebrowser/config.py".source = link ".config/qutebrowser/config.py";
    "VSCodium/User/settings.json".source = link ".config/VSCodium/User/settings.json";
    "VSCodium/User/settings.json.default".source = link ".config/VSCodium/User/settings.json.default";
    # Electron flag file read by the codium launcher (pkgs/vscodium-bin, one flag per line)
    "codium-flags.conf".source  = link ".config/codium-flags.conf";
    # spotify-launcher ([extra]) reads a TOML config instead of a flags file
    "spotify-launcher.conf".source = link ".config/spotify-launcher.conf";
  };

  # User-level override of the packaged Proton Pass desktop entry: same name and
  # WMClass, but --password-store=gnome-libsecret so the session token lives in
  # gnome-keyring (unlocked by ly via PAM) instead of a plaintext "basic" store.
  # (proton-mail-bin and its override were dropped 2026-10-06: Bridge +
  # Thunderbird is the mail path, docs/toolchain/README.md.)
  xdg.dataFile = {
    "applications/proton-pass.desktop".source = link ".local/share/applications/proton-pass.desktop";
    # Flatpak sandbox overrides, one GKeyFile per app id (docs/toolchain/packaging/flatpak.md).
    # The DIRECTORY is linked, not the files: `flatpak override` and Flatseal
    # save by writing a temp file and renaming it over the target, which would
    # replace a per-file symlink with a plain file — inside a linked directory
    # the rename lands in the repo and shows up in git status instead. User-
    # scope overrides apply to apps from either installation; the system copy
    # under /var/lib/flatpak/overrides is made by system/flatpak-setup.sh.
    "flatpak/overrides".source = link ".local/share/flatpak/overrides";
  };

  # Flatpak exports its .desktop entries and icons under <installation>/exports/
  # share; nwg-drawer and rofi only find them if those dirs are on XDG_DATA_DIRS.
  # targets.genericLinux already prepends the nix profiles through this same
  # option (list options merge), and ly's login shell gives Hyprland the result.
  # Arch's flatpak package ships /etc/profile.d/flatpak.sh with the same two
  # paths; a duplicate entry is harmless, a missing one is a missing launcher.
  xdg.systemDirs.data = [
    "/var/lib/flatpak/exports/share"
    "${config.xdg.dataHome}/flatpak/exports/share"
  ];

  # Default applications (docs/toolchain/README.md, "Default applications"). Home Manager
  # writes ~/.config/mimeapps.list from this — the file becomes HM-managed, so a
  # hand `xdg-mime default …` / `xdg-settings set …` is backed up (*.bak-<stamp>)
  # and overwritten on the next `dram switch`; change it here instead. Desktop ids:
  # librewolf.desktop (extra/librewolf), thunar.desktop, thunderbird.desktop,
  # dev.vencord.Vesktop.desktop (Flatpak export, docs/toolchain/packaging/flatpak.md), codium.desktop
  # (pkgs/vscodium-bin ships codium.desktop + codium-url-handler.desktop),
  # imv.desktop (extra/imv), org.pwmt.zathura.desktop (extra/zathura, PDF via
  # zathura-pdf-mupdf). All of them are in packages/roles/desktop.txt or the Flatpak set.
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http"    = "librewolf.desktop";
      "x-scheme-handler/https"   = "librewolf.desktop";
      "text/html"                = "librewolf.desktop";
      "inode/directory"          = "thunar.desktop";
      "x-scheme-handler/discord" = "dev.vencord.Vesktop.desktop";
      "x-scheme-handler/mailto"  = "thunderbird.desktop";
      "text/plain"               = "codium.desktop";
      "image/png"                = "imv.desktop";
      "image/jpeg"               = "imv.desktop";
      "image/webp"               = "imv.desktop";
      "image/gif"                = "imv.desktop";
      "application/pdf"          = "org.pwmt.zathura.desktop";
    };
  };

  # The session's scripts. Laptop-only ones (lid.sh) are linked by modules/laptop.nix
  # instead; dram-theme + codium-themes-install by modules/theme.nix; `dram`, its shims
  # and ~/.ssh/config by modules/cli.nix; the `dram` completion by modules/shell.nix.
  home.file = {
    # LibreWolf autoconfig: applied on every start, survives upgrades.
    ".librewolf/librewolf.overrides.cfg".source = link ".librewolf/librewolf.overrides.cfg";
    # Letterpress chrome (dotfiles/.librewolf/README.md): the static
    # userChrome.css sheets live here; dram-theme links them into each PROFILE's
    # chrome/ dir (profiles are machine state) next to themes/current/browser.css.
    # Thunderbird also gets its user.js seed (fonts, UI size, density) from here.
    ".librewolf/chrome".source               = link ".librewolf/chrome";
    ".thunderbird-chrome".source             = link ".thunderbird-chrome";
    # EB Garamond variable italic (the quote wallpaper uses the italic cuts the
    # nixpkgs eb-garamond package lacks). Was a hand-copied file on lantern.
    ".local/share/fonts/EBGaramond-Italic.ttf".source = link ".local/share/fonts/EBGaramond-Italic.ttf";
    ".local/bin/quote-wallpaper.sh".source   = link ".local/bin/quote-wallpaper.sh";
    ".local/bin/wallpaper-hotplug.sh".source = link ".local/bin/wallpaper-hotplug.sh";
    ".local/bin/power-menu.sh".source        = link ".local/bin/power-menu.sh";
    ".local/bin/waybar-date.sh".source       = link ".local/bin/waybar-date.sh";
    # the calendar popup, themed the same way (private XDG_CONFIG_HOME; dotfiles/.config/gsimplecal/README.md)
    ".local/bin/gsimplecal-dram.sh".source   = link ".local/bin/gsimplecal-dram.sh";
    ".local/bin/waybar-updates.sh".source    = link ".local/bin/waybar-updates.sh";
    ".local/bin/waybar-cputemp.sh".source    = link ".local/bin/waybar-cputemp.sh";
    ".local/bin/dram-theme-auto".source      = link ".local/bin/dram-theme-auto";
    ".local/bin/keybind-cheatsheet.sh".source = link ".local/bin/keybind-cheatsheet.sh";
    ".local/bin/gamemode.sh".source          = link ".local/bin/gamemode.sh";
    ".local/bin/ocr-copy.sh".source          = link ".local/bin/ocr-copy.sh";
    ".local/bin/nightlight.sh".source        = link ".local/bin/nightlight.sh";
    ".local/bin/welcome.sh".source           = link ".local/bin/welcome.sh";
    ".local/bin/waybar-fullscreen.sh".source = link ".local/bin/waybar-fullscreen.sh";
    # daily-use binds (docs/design/shell-and-bars/keybinds.md): layout toggle, screenshots, recording,
    # calculator / wallpaper pickers, manual bar toggle
    ".local/bin/layout-toggle.sh".source     = link ".local/bin/layout-toggle.sh";
    ".local/bin/kb-layout.sh".source         = link ".local/bin/kb-layout.sh";
    ".local/bin/monitors-pin.sh".source      = link ".local/bin/monitors-pin.sh";
    ".local/bin/screenshot.sh".source        = link ".local/bin/screenshot.sh";
    ".local/bin/record-toggle.sh".source     = link ".local/bin/record-toggle.sh";
    ".local/bin/wallpaper-menu.sh".source    = link ".local/bin/wallpaper-menu.sh";
    ".local/bin/waybar-toggle.sh".source     = link ".local/bin/waybar-toggle.sh";
    # VSCodium: the generated Letterpress colour themes (bin/gen-vscode-themes.py,
    # one per dram theme) as a LOCAL extension — VSCodium loads any folder under
    # ~/.vscode-oss/extensions that has a package.json with contributes.themes, but
    # only once the folder is listed in ~/.vscode-oss/extensions/extensions.json;
    # codium-themes-install writes that entry (dram-theme runs it every switch).
    # The folder name is the extension id; the version lives in package.json.
    # (VSCodium replaced Microsoft's VS Code 2026-10-10: decisions/0013, decisions/log.md#d4.)
    ".vscode-oss/extensions/pj.letterpress-themes".source = link ".vscode/extensions/letterpress-themes";
  };

  # Default icon theme = Adwaita; dram-theme sets it per active theme.
  dconf.settings."org/gnome/desktop/interface" = {
    icon-theme = "Adwaita";
  };

  # Proton Mail Bridge (pacman: protonmail-bridge) as a user service, so
  # Thunderbird can speak IMAP/SMTP to Proton on 127.0.0.1:1143 / 127.0.0.1:1025.
  # FIRST LOGIN IS MANUAL, ONCE PER HOST: run `protonmail-bridge` in the GUI, sign
  # in, let it finish syncing; it stores the account in gnome-keyring. Only then
  # does --noninteractive have credentials to start with. After that this unit
  # follows the graphical session.
  # Hyprland is started by ly without uwsm, so nothing ever started
  # graphical-session.target in the user manager (inactive on both hosts, review
  # 2026-10-07 §7 #8): every unit below that is WantedBy it never ran at login.
  # The conventional fix: a session target that BindsTo graphical-session.target,
  # started by hyprland.lua's autostart after importing the Wayland environment
  # (systemd.special(7) "graphical-session.target": "should be pulled in by the
  # session-specific target"). hyprland-session.target is also what uwsm starts.
  systemd.user.targets.hyprland-session = {
    Unit = {
      Description = "Hyprland session (started by hyprland.lua, pulls in graphical-session.target)";
      BindsTo = [ "graphical-session.target" ];
      Wants = [ "graphical-session-pre.target" ];
      After = [ "graphical-session-pre.target" ];
    };
  };

  systemd.user.services.protonmail-bridge = {
    Unit = {
      Description = "Proton Mail Bridge (IMAP/SMTP for Thunderbird)";
      After  = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      # Skip (not fail) until the one-time GUI login has created the vault,
      # so a fresh host does not crash-loop in journalctl --user.
      ExecCondition = "${pkgs.coreutils}/bin/test -d %h/.config/protonmail/bridge-v3";
      ExecStart  = "/usr/bin/protonmail-bridge --noninteractive";
      Restart    = "on-failure";
      RestartSec = 10;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # A notification while a YubiKey waits for a touch (decisions/0019, docs/security/identity/yubikeys.md):
  # ly, hyprlock, git and an agent-held ssh key print no "touch" line, the key only
  # blinks. It watches the FIDO hidraw devices and pam_u2f's authpending file. Replaces
  # the packaged unit (socket-activated, no notifications) with a notifying one.
  systemd.user.services.yubikey-touch-detector = {
    Unit = {
      Description = "YubiKey touch notifications (yubikey-touch-detector)";
      After  = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart  = "/usr/bin/yubikey-touch-detector --notify --no-socket";
      Restart    = "on-failure";
      RestartSec = 10;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # GnuPG never starts scdaemon (decisions/log.md#d127): the YubiKeys' PIV is reached through
  # pcscd by age-plugin-yubikey and ykman, scdaemon would hold the reader for itself, and
  # nothing here uses an OpenPGP card (decisions/0019). A line added to a real
  # ~/.gnupg/gpg-agent.conf (umask 077, the directory 700: GnuPG distrusts a homedir others
  # can read); nothing else in the file is touched. A running gpg-agent reads it at its next
  # start.
  home.activation.noScdaemon = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ! grep -qx 'disable-scdaemon' "$HOME/.gnupg/gpg-agent.conf" 2>/dev/null; then
      run mkdir -p "$HOME/.gnupg"
      run chmod 700 "$HOME/.gnupg"
      run bash -c 'umask 077; echo disable-scdaemon >>"$HOME/.gnupg/gpg-agent.conf"'
    fi
  '';

  # Day/night: washi-day between sunrise and sunset, washi otherwise, and the
  # night light (hyprsunset over IPC) on the same clock (dram-theme-auto;
  # location from dram.location). Runs once at login and then every 10 minutes
  # (a no-op most ticks). It only touches those two themes, so a hand-picked
  # theme stays put. See docs/design/themes/switcher.md.
  systemd.user.services.dram-theme-auto = {
    Unit = {
      Description = "dram-theme-auto: washi-day by day, washi + night light by night";
      After  = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "%h/.local/bin/dram-theme-auto";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
  systemd.user.timers.dram-theme-auto = {
    Unit.Description = "Day/night theme + night light check (every 10 min)";
    Timer = { OnCalendar = "*:0/10"; Persistent = true; };
    Install.WantedBy = [ "timers.target" ];
  };
};
}

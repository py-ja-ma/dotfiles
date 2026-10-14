{ lib, repo, wlib, ... }:

# desktop - a Windows PC with a screen: the Letterpress desktop (docs/design/README.md; its apps
# are packages/winget/desktop.txt). Dark paper, ink and the vermilion
# accent as a rule; the rEFInd/Plymouth art as wallpaper and lock screen; a clear sign-in, Arch's
# Adwaita pointer, no sounds; a quiet Start and Explorer; the masthead, a Zebar bar across the
# top of every monitor over an auto-hidden taskbar; the house fonts for every account; conhost
# in the scheme's colours. What lives inside the apps is look.ps1's (one line per app), the
# tinted icons icons.ps1's, the "pj" seal account-picture.ps1's, and apply-live.ps1 shows it all
# on the signed-in desktop at once rather than at the next sign-in.
let
  # the theme the generator rendered (bin/gen-windows-look.py writes it beside the files)
  theme = lib.trim (builtins.readFile (repo + "/install/windows/letterpress/theme"));
in
{
  windows.role.desktop = {
    steps = {
      "account-picture.ps1" = { source = repo + "/install/windows/dram-windows/account-picture.ps1"; phase = "20"; };
      "look.ps1" = { source = repo + "/install/windows/dram-windows/look.ps1"; phase = "30"; };
      "icons.ps1" = { source = repo + "/install/windows/dram-windows/icons.ps1"; phase = "30"; };
    };
    # what the units and scripts read, staged under C:\ProgramData\dram: the generated look
    # (letterpress\, with the Zebar pack), the art, the seal, the fonts and cursors as pinned
    # (verified on the Mac or Arch before they are staged, and again here by sha256), and the
    # files Arch shares with Windows, byte for byte
    files = wlib.dir "letterpress" (repo + "/install/windows/letterpress")
      // wlib.dir "avatar" (repo + "/dotfiles/.local/share/dram/avatar")
      // wlib.fonts
      // wlib.cursors
      // {
        # the look on the signed-in desktop at once: converge.ps1 and dram.ps1 start it there
        # after the phases, whenever it is staged
        "apply-live.ps1".source = repo + "/install/windows/dram-windows/apply-live.ps1";
        "letterpress.png".source = repo + "/system/refind-letterpress/background.png";
        # the cursor units read the pin itself (roles and sums); GNOME's licence asks for the NOTICE
        "cursors/cursors.pin".source = repo + "/install/windows/cursors.pin";
        "cursors/NOTICE".source = repo + "/install/windows/cursors.notice";
        "letterpress-colors.css".source = repo + "/dotfiles/.config/themes/${theme}/browser.css";
        "librewolf/userChrome.css".source = repo + "/dotfiles/.librewolf/chrome/userChrome.css";
        "librewolf/librewolf.overrides.cfg".source = repo + "/dotfiles/.librewolf/librewolf.overrides.cfg";
        "thunderbird/userChrome.css".source = repo + "/dotfiles/.thunderbird-chrome/userChrome.css";
        "thunderbird/user.js.default".source = repo + "/dotfiles/.thunderbird-chrome/user.js.default";
        "vscodium/settings.json.default".source = repo + "/dotfiles/.config/VSCodium/User/settings.json.default";
      };
    registry = {
      no-widgets = {
        description = "no widgets board";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Dsh'';
        name = "AllowNewsAndInterests"; type = "Dword"; data = "0";
      };
      start-no-recent-apps = {
        description = "Start shows no recently added apps";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Explorer'';
        name = "HideRecentlyAddedApps"; type = "Dword"; data = "1";
      };
      # --- Start, the taskbar and Explorer, quiet. The four policies are the
      # Start CSP's, documented for Pro (key and values: Learn's Policy CSP - Start; Most used's
      # value name: StartMenu.admx's enum); explorer-quiet's values are the community's (verify in
      # Settings). The taskbar itself auto-hides under the masthead: apply-live.ps1. ---
      taskbar-taskview-policy = {
        description = "no Task View button, its Settings toggle locked (HideTaskViewButton)";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Explorer'';
        name = "HideTaskViewButton"; type = "Dword"; data = "1";
      };
      start-no-recommended = {
        description = "Start shows no Recommended section (HideRecommendedSection)";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Explorer'';
        name = "HideRecommendedSection"; type = "Dword"; data = "1";
      };
      start-no-sites = {
        description = "no personalised website recommendations in Start (HideRecommendedPersonalizedSites)";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Explorer'';
        name = "HideRecommendedPersonalizedSites"; type = "Dword"; data = "1";
      };
      start-no-most-used = {
        description = "no Most used list in Start, its toggle locked (ShowOrHideMostUsedApps 2 = hide)";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Explorer'';
        name = "ShowOrHideMostUsedApps"; type = "Dword"; data = "2";
      };
      lock-widgets-off = {
        description = "no widgets on the lock screen (Microsoft lists this policy for Insider builds; no-widgets already removes the board on released ones)";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Dsh'';
        name = "DisableWidgetsOnLockScreen"; type = "Dword"; data = "1";
      };
      signin-clear = {
        description = "the sign-in screen shows the lock picture as it is, without the acrylic blur";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\System'';
        name = "DisableAcrylicBackgroundOnLogon"; type = "Dword"; data = "1";
      };
      startup-sound-off = {
        description = "no startup sound (policy)";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'';
        name = "DisableStartupSound"; type = "Dword"; data = "1";
      };
      startup-sound-off-logonui = {
        description = "no startup sound (the sign-in screen's own switch)";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation'';
        name = "DisableStartupSound"; type = "Dword"; data = "1";
      };
      zebar-autostart = {
        description = "Zebar starts at sign-in and opens the masthead (autostart.ps1 keeps the Zebar entry on)";
        key = ''HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run'';
        name = "Zebar"; type = "String"; data = ''"C:\Program Files\glzr.io\Zebar\zebar.exe" startup'';
        phase = "40";
      };
    };
    script = {
      # --- the house fonts, for every account -------------------------------------------
      fonts-machine = {
        description = "the house fonts for every account (Windows Fonts folder + HKLM), pinned by install/windows/fonts.pin; one removed from the pin is removed here";
        elevated = true;
      };
      explorer-quiet = {
        description = "Explorer compact, its pane open to the current folder, no Gallery, no sync-provider ads; End task on the taskbar's menu (for a hung game)";
        elevated = false;
      };
      # --- the Letterpress look ----------------------------------------------------------
      letterpress-look = {
        description = "dark, matte, the accent from letterpress/accent.json on title bars, a quiet left taskbar and Start, extensions shown, mouse without acceleration";
        elevated = false;
      };
      letterpress-wallpaper = {
        description = "the Letterpress art (rEFInd's background) on the desktop";
        elevated = false;
      };
      letterpress-lock-screen = {
        description = "the same art on the lock screen";
        elevated = true;
      };
      # the pointer Arch draws: GNOME's Adwaita cursors in GNOME's own Windows build, staged with
      # install/windows/cursors.pin (each line: the role, the URL, the sha256, =the file), which
      # both units read; Windows' smallest pointer size is 32 (Arch draws 24) and each .cur
      # carries a 32 px image, so it is drawn, not scaled. Applying a .theme file or picking a
      # pointer style in Settings rewrites the user's cursors; the next converge puts them back.
      # UNVERIFIED until cabin-win's first converge with them: "Scheme Source" 1 as the mark of a
      # user scheme (community-documented; the cursors apply either way), and an elevated
      # converge creating its own folder under %SystemRoot%\Cursors.
      cursors-machine = {
        description = "the Adwaita cursors (install/windows/cursors.pin, each checked against its sha256 again) in the Windows Cursors folder, Adwaita, with GNOME's licence NOTICE; one dropped from the pin is removed";
        elevated = true;
        package = "manual:adwaita-cursors";
      };
      pointer-adwaita = {
        description = "the user's Adwaita pointer scheme from those files, chosen (Windows Black's cursors for the four roles Adwaita has none for), and a 2 px text caret";
        elevated = false;
        package = "manual:adwaita-cursors";
        dependsOn = [ "cursors-machine" ];
      };
      sounds-off = {
        description = "the No Sounds scheme: every event silent (a feature update that adds events is caught here)";
        elevated = false;
      };
      conhost-letterpress = {
        description = "the classic console (anything outside Windows Terminal) in the scheme's colours, from letterpress/conhost.json";
        elevated = false;
      };
    };
  };
}

{ ... }:

# gaming - cabin-win's launchers (packages/winget/gaming.txt; the rulings from
# decisions/log.md#d92 to #d103): the ones
# winget installs come from the list; these three need a Script unit. Nothing starts at sign-in
# (autostart.ps1); emulation stays on Arch (decisions/log.md#d62).
{
  windows.role.gaming = {
    script = {
      # --- apps: game launchers ---
      battle-net = {
        description = "Battle.net (its package needs an install location, which WinGetPackage cannot pass)";
        elevated = true;
        phase = "30";
        package = "manual:battle.net";
      };
      ubisoft-connect = {
        description = "Ubisoft Connect (accepted with a flag, 2026-10-12): Ubisoft replaces its installer in place, so winget's pinned hash goes stale; its own installer, Ubisoft-signed, silent";
        elevated = true;
        phase = "30";
        package = "manual:ubisoft-connect";
      };
      jagex-launcher = {
        description = "Jagex Launcher (waived; not in winget; its signed installer needs clicks, so it opens on the signed-in desktop)";
        elevated = true;
        phase = "30";
        package = "manual:jagex-launcher";
      };
    };
  };
}

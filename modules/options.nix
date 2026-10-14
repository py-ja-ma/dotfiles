{ config, lib, ... }:

# Every `dram.*` option is declared here and nowhere else. A host module sets
# them; laptop.nix / gpu.nix / backup.nix / secrets.nix read them.
#
# `_module.args.dram` is the one definition of the `link` helper every module
# uses for dotfile symlinks — take it as a module argument (`{ dram, ... }:`)
# and call `dram.link` with a path relative to dotfiles/.
{
  options.dram = {
    hostName = lib.mkOption { type = lib.types.str; description = "This host's name (matches /etc/hostname)."; };
    # The login on this host (install/arch-install.sh --user): pj on cabin and campfire,
    # ranger on the travel laptop (docs/platforms/README.md). The flake names the configuration
    # <user>@<host>; the Mac's tools ssh in as this user. Keep it `user = "…";` on one line.
    user = lib.mkOption { type = lib.types.strMatching "[a-z_][a-z0-9_-]*"; default = "pj"; description = "This host's login user."; };
    # What this machine is for (decisions/0009-roles-and-host-shape.md). Every role is
    # one packages/roles/<role>.txt for pacman (install/lib/roles.sh reads the same
    # line of the host file) and may gate Home Manager config here. The enum is built
    # from that directory, so a role exists for Nix exactly when its manifest exists.
    # Keep `roles = [ … ];` on one line and quoted: install/lib/roles.sh reads it with grep.
    # base is implicit; laptop and the GPU are detected hardware, not roles.
    roles = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (map (lib.removeSuffix ".txt")
        (builtins.attrNames (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".txt" n)
          (builtins.readDir ../packages/roles)))));
      default = [ "desktop" ];
      description = "Roles this host plays (packages/roles/<role>.txt); base is implicit.";
    };
    # Host-to-host backups are PAUSED until the NAS (decisions/0014): off unless a host
    # sets dram.backup.enable = true, and then backupPeer/backupPeerAddr are required.
    backup.enable = lib.mkOption { type = lib.types.bool; default = false; description = "Run borgmatic to backupPeer (paused until the NAS, decisions/0014)."; };
    backupPeer = lib.mkOption { type = lib.types.str; default = ""; description = "Host that stores this host's Borg repository."; };
    # LAN names do not resolve across the two hosts (no mDNS/LLMNR between them), so the
    # repository URL and the reachability probe use the peer's static LAN address.
    backupPeerAddr = lib.mkOption { type = lib.types.str; default = ""; description = "LAN address of backupPeer."; };
    # This host's own static LAN address: what the Mac's tooling ssh-es to
    # (bin/release.sh pushes a release to every modules/hosts/*.nix with one).
    # Read by grep from the host module, so keep it on one line, quoted.
    address = lib.mkOption { type = lib.types.str; default = ""; description = "This host's LAN address, as reached from the Mac (bin/release.sh)."; };
    # Lid switch + panel backlight exist -> lid.sh is linked
    # and the waybar battery module stays (modules/laptop.nix). hyprland.lua detects
    # the same fact at runtime from /sys/class/power_supply; this is the Nix side.
    isLaptop = lib.mkOption { type = lib.types.bool; description = "Laptop (battery, lid switch, backlight) rather than a desktop."; };
    # Drives the session env in modules/gpu.nix. Must agree with install/lib/detect.sh
    # and packages/gpu-<vendor>.txt for the same machine. "none": no driver of this
    # host's own, so no driver env either (the WSL clone: the GPU belongs to Windows).
    gpu = lib.mkOption { type = lib.types.enum [ "intel" "nvidia" "amd" "none" ]; description = "GPU vendor whose driver is installed (VA-API / Wayland env vars); none = no driver of its own."; };
    # Where this host runs (decisions/0021). "metal": its own hardware, kernel and boot
    # chain, as every Arch host so far. "wsl": Arch inside WSL 2 on a Windows PC, the
    # clone of the user layer and the CLI roles (no kernel, boot chain, session, firewall
    # or GPU driver of its own). Platform, not a role: install/lib/roles.sh greps this
    # line too (a WSL host reads base + its roles minus packages/wsl-skip.tsv; a metal
    # one also metal.txt and the hardware lists), and `dram` refuses a host file whose
    # form does not match the platform it detects. Keep it `form = "…";` on one line.
    form = lib.mkOption { type = lib.types.enum [ "metal" "wsl" ]; default = "metal"; description = "metal (own hardware) or wsl (Arch in WSL 2 on a Windows PC)."; };
    # Only for form = "wsl" (decisions/0021, docs/platforms/wsl/README.md). Keep each
    # `key = "…";` on
    # one line: bin/push-host.sh and system/wsl-setup.sh grep them.
    wsl = {
      windowsHost = lib.mkOption { type = lib.types.str; default = ""; description = "The Windows PC the clone runs on; its OpenSSH is reached as HostKeyAlias <windowsHost>-win."; };
      distro = lib.mkOption { type = lib.types.str; default = config.dram.hostName; defaultText = lib.literalExpression "config.dram.hostName"; description = "The WSL distribution's name (wsl.exe -d <distro>)."; };
      # "local": the host's own ssh-agent (modules/dev.nix). "windows": ssh and git
      # signing use Windows' OpenSSH agent through wsl2-ssh-agent, so the YubiKey stays
      # Windows' and the touch comes through Windows Hello (decisions/log.md#d79).
      sshAgent = lib.mkOption { type = lib.types.enum [ "local" "windows" ]; default = "local"; description = "Which ssh-agent SSH_AUTH_SOCK points at: this host's own, or Windows' through wsl2-ssh-agent."; };
    };
    # Where the sun is computed for dram-theme-auto (washi-day by day, night
    # light at night). One string "LAT LON", decimal degrees, east positive.
    # Written to ~/.config/dram/location and dram/facts.lua (modules/core.nix).
    # Boston until the move to Grand Forks, ND (47.92 -97.03) in February 2027
    # — change it here, `dram switch`.
    location = lib.mkOption { type = lib.types.str; default = "42.36 -71.06"; description = "Latitude and longitude for sunrise/sunset (\"LAT LON\")."; };
    # Host-specific additions to the borg source set (modules/backup.nix), on
    # top of the shared list every host backs up. Absolute paths; a missing one
    # is fine (source_directories_must_exist = false).
    backup.extraSources = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "Extra directories this host backs up (absolute paths)."; };
    # Gaming Mode (gamescope, experimental) on this host (decisions/0012, modules/gaming.nix):
    # what ~/.config/gamescope-session-plus/sessions.d/steam tells gamescope-session-plus.
    # Unset = gamescope's own choice. The connector name is the one in /sys/class/drm
    # (card1-DP-1 -> "DP-1"); cabin's comes from its T4 hardware test.
    gaming = {
      output = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Connector gamescope prefers (OUTPUT_CONNECTOR), e.g. \"DP-1\"."; };
      width = lib.mkOption { type = lib.types.nullOr lib.types.ints.positive; default = null; description = "Output width in pixels (SCREEN_WIDTH; also the internal width)."; };
      height = lib.mkOption { type = lib.types.nullOr lib.types.ints.positive; default = null; description = "Output height in pixels (SCREEN_HEIGHT; also the internal height)."; };
      adaptiveSync = lib.mkOption { type = lib.types.bool; default = false; description = "VRR in gamescope (ADAPTIVE_SYNC); off until tested on this driver."; };
      hdr = lib.mkOption { type = lib.types.bool; default = false; description = "HDR in gamescope (ENABLE_GAMESCOPE_HDR); off — gamescope#1593 on NVIDIA."; };
      forceComposition = lib.mkOption { type = lib.types.bool; default = false; description = "GAMESCOPE_COMPOSITE_FORCE=1, the first workaround for overlay corruption on NVIDIA (gamescope#1964)."; };
    };
    # Off by default so a brand-new host can `dram switch` before its age key is
    # registered in .sops.yaml (docs/security/identity/secrets.md).
    secrets.enable = lib.mkOption { type = lib.types.bool; default = false; description = "Decrypt secrets/pj.yaml with sops-nix (needs ~/.config/sops/age/keys.txt)."; };
  };

  config._module.args.dram = rec {
    # Built from a STRING, not a path literal. With flakes, mkOutOfStoreSymlink
    # on a path literal silently points into a stale store copy. Keep it a string
    # (home-manager#2660).
    repo = "${config.home.homeDirectory}/git/dotfiles";
    link = path: config.lib.file.mkOutOfStoreSymlink "${repo}/dotfiles/${path}";
  };

  # What a WSL clone can never be (decisions/0021, docs/platforms/wsl/README.md): its GPU is Windows'
  # (an NVIDIA or VA-API env breaks WSLg's d3d12 path) and Hyprland cannot be its
  # session. The Windows agent bridge only exists inside WSL.
  config.assertions = let d = config.dram; in [
    { assertion = d.form != "wsl" || d.gpu == "none";
      message = "dram.form = \"wsl\" needs dram.gpu = \"none\" (the GPU belongs to Windows; modules/hosts/${d.hostName}.nix)"; }
    { assertion = d.form != "wsl" || !(lib.elem "desktop" d.roles);
      message = "dram.form = \"wsl\" cannot take the desktop role: Hyprland cannot be the session in WSL (decisions/0021)"; }
    { assertion = d.form != "wsl" || d.wsl.windowsHost != "";
      message = "dram.form = \"wsl\" needs dram.wsl.windowsHost (the Windows PC it runs on; modules/hosts/${d.hostName}.nix)"; }
    { assertion = d.wsl.sshAgent != "windows" || d.form == "wsl";
      message = "dram.wsl.sshAgent = \"windows\" needs dram.form = \"wsl\" (Windows' agent is reached only from inside WSL)"; }
  ];
}

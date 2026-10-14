{ config, lib, ... }:

# Gaming Mode (decisions/0012), the user half: the per-host settings gamescope-session-plus
# reads for "Gaming Mode (gamescope, experimental)". The system half — the three ly
# sessions, switching, the vendored session pair — is pkgs/dram-gaming-mode and
# packages/roles/gaming.txt. The Hyprland "Gaming Mode" config is
# dotfiles/.config/hypr/gaming.lua (linked with the rest of hypr/ by desktop.nix).
#
# Why sessions.d/steam and not ~/.config/environment.d: the session sources both, but
# environment.d also feeds every systemd user unit of the desktop session, and these
# names (OUTPUT_CONNECTOR, SCREEN_WIDTH …) belong to Gaming Mode only.
let
  g = config.dram.gaming;
  line = name: value: "${name}=${toString value}";
  settings =
    lib.optional (g.output != null) (line "OUTPUT_CONNECTOR" g.output)
    ++ lib.optionals (g.width != null && g.height != null) [
      (line "SCREEN_WIDTH" g.width)
      (line "SCREEN_HEIGHT" g.height)
      (line "INTERNAL_WIDTH" g.width)
      (line "INTERNAL_HEIGHT" g.height)
    ]
    ++ lib.optional g.adaptiveSync (line "ADAPTIVE_SYNC" 1)
    ++ lib.optional g.hdr (line "ENABLE_GAMESCOPE_HDR" 1)
    ++ lib.optional g.forceComposition (line "GAMESCOPE_COMPOSITE_FORCE" 1);
in
{
  config = lib.mkIf (lib.elem "gaming" config.dram.roles) {
    assertions = [{
      assertion = (g.width == null) == (g.height == null);
      message = "dram.gaming: set width and height together, or neither.";
    }];
    # sourced as shell by gamescope-session-plus after the package's own sessions.d/steam
    xdg.configFile."gamescope-session-plus/sessions.d/steam".text = ''
      # Written by modules/gaming.nix from dram.gaming.* (modules/hosts/${config.dram.hostName}.nix).
      # Sourced by gamescope-session-plus for "Gaming Mode (gamescope, experimental)" only.
    '' + lib.concatMapStrings (l: l + "\n") settings;
    # The session runs as a systemd user service, which inherits the user manager's
    # environment — and a Hyprland session left WAYLAND_DISPLAY/DISPLAY there (imported at
    # login, never removed). gamescope then starts NESTED inside that dead compositor and
    # exits at once: "Failed to connect to wayland socket: wayland-1" (cabin, 2026-10-11).
    # gamescope sets its own displays once it runs.
    xdg.configFile."systemd/user/gamescope-session-plus@.service.d/10-dram-fresh-env.conf".text = ''
      # Written by modules/gaming.nix: start gamescope on the GPU, not nested in an old session.
      [Service]
      UnsetEnvironment=WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP
    '';
    # Steam's shader pre-caching (docs/toolchain/profiles/gaming.md): fossilize_replay turns a game's
    # downloaded pipeline cache into the driver's. With background processing on (a Steam
    # setting; dram doctor checks it) it runs while Steam idles, and Steam starts minimised at
    # login on a gaming desktop (hyprland.lua), so a launch never waits for it. Out of the box
    # it gets a quarter of the threads (8 of cabin's 32); this gives it half of them, and
    # all of them when a launch does wait. Steam reads steam_dev.cfg at start and never writes
    # it; written here, not linked, because the thread count is this host's (nproc).
    home.activation.dramSteamDevCfg = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "$HOME/.local/share/Steam"
      run bash -c 'n=$(nproc 2>/dev/null || echo 4); printf "unShaderBackgroundProcessingThreads %s\nunShaderHighPriorityProcessingThreads %s\n" $(( n > 1 ? n / 2 : 1 )) "$n" > "$HOME/.local/share/Steam/steam_dev.cfg"'
    '';
  };
}

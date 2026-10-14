{ config, lib, ... }:

# Identity and the Home Manager plumbing every host needs before anything else,
# plus the host facts file the runtime side reads.
let
  # The host's dram.* flags, as data. One value set feeds both files below so
  # the Lua side (hyprland.lua, dram doctor) and the sun clock (dram-theme-auto)
  # can never disagree about where they are running.
  facts = {
    inherit (config.dram) hostName location backupPeer gpu roles;
    laptop = config.dram.isLaptop;
  };
in
{
  home.username = config.dram.user;
  home.homeDirectory = "/home/${config.dram.user}";

  # stateVersion = the HM release that was current when this config was BORN
  # (July 2026 -> 26.05). It gates backwards-compat shims, NOT features.
  # Never bump it when updating home-manager/flake.lock — leave it alone.
  home.stateVersion = "26.05";

  # non-NixOS (Arch) integration: session vars, XDG dirs, desktop entries
  targets.genericLinux.enable = true;

  # Flakes on by default on EVERY host. Without this, cabin (single-user nix, no
  # /etc/nix/nix.conf) can only run dram-switch (which passes the flag) - bare
  # `nix flake check` / `nix run` fail there while working on lantern. Managing
  # it here makes the nix command set identical across hosts.
  xdg.configFile."nix/nix.conf".text = "experimental-features = nix-command flakes\n";

  # ~/.config/dram/facts.lua: `return { backupPeer, gpu, host, laptop, location, roles }`
  # for hyprland.lua (laptop layout, dofile with a fallback to its own probes)
  # and `dram doctor` (asserts gpu/host against lspci and /etc/hostname).
  # ~/.config/dram/location: the same dram.location, one line "LAT LON", for
  # dram-theme-auto (a Python script; it does not read Lua).
  xdg.configFile."dram/facts.lua".text = "return " + lib.generators.toLua { } {
    host = facts.hostName;
    inherit (facts) laptop gpu location backupPeer roles;
  };
  xdg.configFile."dram/location".text = facts.location + "\n";

  home.sessionPath = [ "$HOME/.local/bin" ];

  programs.home-manager.enable = true;

  # `dram update` prints what matters; the Home Manager news digest on every
  # switch is noise in a script's output (read it with `home-manager news`).
  news.display = "silent";
}

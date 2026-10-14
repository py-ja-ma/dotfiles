{ config, pkgs, lib, dram, ... }:

# dram.isLaptop decides the two things a battery changes in the user layer:
# which helper scripts are installed, and whether waybar shows a battery module.
# hyprland.lua reads the same flag from ~/.config/dram/facts.lua (modules/core.nix;
# DRAM_LAPTOP=0/1 overrides, battery probe as the fallback).
let
  inherit (dram) link;
in {
  config = lib.mkMerge [
    (lib.mkIf config.dram.isLaptop {
      # Laptop-only scripts. A desktop has no lid switch and no panel backlight,
      # so these are linked here rather than in desktop.nix.
      home.file = {
        ".local/bin/lid.sh".source               = link ".local/bin/lid.sh";
      };

      # waybar: inherits desktop.nix's default (the shared two-bar config.jsonc,
      # full bar on externals + compact bar on eDP-1, battery module included).
    })

    # the bar is the desktop role's: a headless box or the WSL clone writes no waybar config
    (lib.mkIf (!config.dram.isLaptop && lib.elem "desktop" config.dram.roles) {
      # Deliberately NOT linked on a desktop (see the laptop branch above):
      #   lid.sh                 - no "Lid Switch" device exists
      #
      # hyprland.lua's `switch:on:Lid Switch` binds are inert without the device, so
      # they are harmless; the scripts aren't installed.

      # waybar: generated from the SHARED config.jsonc with the battery module
      # stripped from both bars (a desktop has no battery; the module renders empty).
      # Single source of truth, no drift. Trade-off: this is a store copy, not a
      # live symlink - edit dotfiles/.config/waybar/config.jsonc and dram-switch.
      # The "!eDP-1" bar matches both cabin monitors, which is the correct outcome;
      # the "eDP-1" compact bar never renders here. A plain definition
      # beats the mkDefault live-symlink in desktop.nix; every desktop host gets
      # this block.
      xdg.configFile."waybar/config.jsonc".source = pkgs.writeText "waybar-config.jsonc"
        (builtins.replaceStrings [ ", \"battery\"" ] [ "" ]
          (builtins.readFile ../dotfiles/.config/waybar/config.jsonc));
    })
  ];
}

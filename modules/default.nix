{ ... }:

# Shared user layer for every host, split by concern. A host module
# (modules/hosts/<name>.nix) only sets the `dram.*` flags declared in
# options.nix; laptop.nix and gpu.nix turn those flags into config with
# lib.mkIf, so nothing host-specific is copied between host files
# (decisions/0004-module-split.md).
#
# Dotfiles are symlinked back to this git repo (mkOutOfStoreSymlink) so you can
# keep editing them live AND have every change tracked in git history.
#
# The Arch SYSTEM layer (kernel, bootloader, ESP, initramfs, hyprland/waybar/ly/
# refind/plymouth packages, AUR builds) is installed by install/bootstrap.sh and
# the scripts in system/. Nix on Arch does not own /etc, the ESP, or the
# initramfs — that boundary is deliberate. See decisions/0001-approach.md.
#
#   options.nix  dram.* option declarations + the one `link` helper (_module.args.dram)
#   core.nix     identity, stateVersion, nix.conf, genericLinux, PATH
#   shell.nix    bash + atuin (bash-preexec) + starship + fzf/eza/zoxide/bat/btop, aliases
#   cli.nix      every host, session or not: dram + its shims, ~/.ssh/config, starship.toml,
#                yazi, btop's template, ~/.config/themes + its `current` seed, EDITOR/VISUAL
#   dev.nix      git (SSH-signed), delta, lazygit, direnv, ripgrep, homelab CLI kit
#   desktop.nix  every GUI dotfile link + script link, fonts, dconf, user services
#   theme.nix    dram-theme, codium-themes-install, the editor's first-switch seed
#   laptop.nix   dram.isLaptop: lid/brightness scripts vs the no-battery waybar
#   gpu.nix      dram.gpu: NVIDIA env + shader cache + gamemode, or Intel VA-API
#   gaming.nix   role gaming: gamescope Gaming Mode settings (dram.gaming.*, decisions/0012)
#   office.nix   role office: office-init (vault, hledger)
#   ml.nix       role ml: llama-server on loopback (docs/toolchain/development/README.md)
#   creator.nix  roles creator/recording: `rec` (obs-websocket), OBS templates seeded if absent
#   backup.nix   borgmatic host-to-host, paused (docs/operations/backups/README.md)
#   secrets.nix  sops-nix behind dram.secrets.enable (docs/security/identity/secrets.md)
# Every module and the page that documents it: modules/README.md
{
  imports = [
    ./options.nix
    ./core.nix
    ./shell.nix
    ./cli.nix
    ./dev.nix
    ./desktop.nix
    ./theme.nix
    ./laptop.nix
    ./gpu.nix
    ./gaming.nix
    ./creator.nix
    ./ml.nix
    ./office.nix
    ./backup.nix
    ./secrets.nix
  ];
}

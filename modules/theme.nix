{ config, lib, dram, ... }:

# Runtime theming on the desktop: the switcher scripts and the editor's
# first-switch seed. ~/.config/themes itself (the palette dirs dram-theme switches
# between) and its `current` seed are every host's: modules/cli.nix.
let
  inherit (dram) link;
in {
  # The switcher belongs to the desktop role (decisions/0009).
  config = lib.mkIf (lib.elem "desktop" config.dram.roles) {
  home.file = {
    ".local/bin/dram-theme".source           = link ".local/bin/dram-theme";
    ".local/bin/codium-themes-install".source = link ".local/bin/codium-themes-install";
  };

  # ~/.config/VSCodium/User/settings.json is RUNTIME state (gitignored):
  # dram-theme rewrites "workbench.colorTheme" in place on every switch, and the
  # tracked settings.json.default is the template. dram-theme copies the
  # template into place when the live file is missing (the seed-if-absent
  # guard next to cava's); do the same here so the editor has its settings on
  # the first switch, before dram-theme has ever run. Never overwrite an
  # existing file.
  #
  # Written at the repo path: ~/.config/VSCodium/User/settings.json
  # is a dangling symlink into the repo until the file exists, and GNU cp
  # refuses "not writing through dangling symlink" (only POSIXLY_CORRECT
  # changes that). The repo path is a plain missing file; once it exists the
  # desktop.nix links (VSCodium/ and Code/) resolve to it.
  home.activation.seedEditorSettings =
    let
      dir = "${dram.repo}/dotfiles/.config/VSCodium/User";
    in lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      if [ ! -e "${dir}/settings.json" ] && [ -e "${dir}/settings.json.default" ]; then
        run cp $VERBOSE_ARG "${dir}/settings.json.default" "${dir}/settings.json"
      fi
    '';
};
}

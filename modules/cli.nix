# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT
{ config, lib, dram, ... }:

# The command-line layer every host gets, desktop or not: the `dram` CLI and its two
# shims, the ssh client config, the prompt, the file manager and the monitor templates,
# the theme directory the CLI tools read their colours from, and EDITOR. Moved out of
# desktop.nix and theme.nix (2026-10-12, decisions/0021): a host without the desktop
# role (a headless box, the WSL clone) had no `dram` on PATH, stock prompts, and an fzf
# that exits at once on the FZF_DEFAULT_OPTS_FILE modules/shell.nix exports. The
# desktop's own scripts, dram-theme and the session stay in desktop.nix and theme.nix.
let
  inherit (dram) link;
in
{
  xdg.configFile = {
    # btop is linked PER FILE: btop rewrites btop.conf on exit, so only the template
    # is tracked; dram-theme seeds the live file from it (docs/design/shell-and-bars/README.md).
    "btop/btop.conf.default".source = link ".config/btop/btop.conf.default";
    # yazi is linked PER FILE because dram-theme rewrites theme.toml (seeded
    # from the .default) and that live file must not be in the repo. The
    # flavors are OURS, generated (bin/gen-yazi-flavors.py -> flavors/
    # letterpress-<theme>.yazi) and linked as a whole directory; `ya pkg` is no
    # longer used, package.toml declares no deps. A host that once ran
    # `ya pkg install` has a REAL ~/.config/yazi/flavors/ dir, which this link
    # would clobber — home-manager refuses, so remove it first (once):
    #   rm -rf ~/.config/yazi/flavors && dram switch
    # See docs/design/themes/README.md.
    "yazi/yazi.toml".source          = link ".config/yazi/yazi.toml";
    "yazi/init.lua".source           = link ".config/yazi/init.lua";
    "yazi/package.toml".source       = link ".config/yazi/package.toml";
    "yazi/theme.toml.default".source = link ".config/yazi/theme.toml.default";
    "yazi/flavors".source            = link ".config/yazi/flavors";
    "starship.toml".source = link ".config/starship.toml";
    # The palette directories dram-theme switches between; fzf (FZF_DEFAULT_OPTS_FILE,
    # modules/shell.nix), bat and btop read the active one through themes/current.
    "themes".source = link ".config/themes";
  };

  # ~/.config/themes/current is RUNTIME state (gitignored): dram-theme repoints
  # it on every switch, and hyprland.lua does dofile() on current/palette.lua at
  # line ~136. A fresh clone therefore has no `current`, and Hyprland refuses to
  # start until dram-theme has run once (and fzf, everywhere, until it exists). Seed
  # it to washi if absent, exactly as dram-theme would. Never overwrite an existing choice.
  home.activation.seedTheme = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if [ ! -e "${config.home.homeDirectory}/.config/themes/current" ]; then
      run ln -sfn $VERBOSE_ARG washi "${config.home.homeDirectory}/.config/themes/current"
    fi
  '';

  # The editor the terminal tools open: Taskwarrior's `task edit` and vit, zk, crontab -e,
  # sudoedit (git's own is core.editor, modules/dev.nix). Moved from desktop.nix
  # (2026-10-12): without it `task edit` runs `vi`, which Arch's vim does not ship, and zk
  # refuses to open a note, so a host without the desktop role (the WSL clone) had neither.
  home.sessionVariables = {
    EDITOR = "vim";
    VISUAL = "vim";
  };

  # ssh ControlPath is ~/.ssh/sockets/%C — ssh won't create the parent dir, so
  # multiplexing silently fails on a fresh machine unless it exists.
  home.activation.sshSockets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p $VERBOSE_ARG "${config.home.homeDirectory}/.ssh/sockets"
    run chmod 700 "${config.home.homeDirectory}/.ssh/sockets"
  '';

  home.file = {
    ".ssh/config".source            = link ".ssh/config";
    # `dram` updates, applies, themes and checks the host; dram-switch and sysupdate
    # are shims onto it, kept for muscle memory (docs/operations/dram/README.md)
    ".local/bin/dram".source        = link ".local/bin/dram";
    ".local/bin/dram-switch".source = link ".local/bin/dram-switch";
    ".local/bin/sysupdate".source   = link ".local/bin/sysupdate";
  };
}

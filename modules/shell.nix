{ config, pkgs, dram, ... }:

# Interactive shell: bash + atuin + starship, the CLI staples, every
# alias, and the fzf wiring. Theming is runtime (dram-theme), not nix.
{
  home.packages = with pkgs; [
    # playerctl brightnessctl grim slurp wl-clipboard come from pacman (ADR 0003:
    # Wayland-facing tools track the compositor); starship via programs.starship
    fd tealdeer dust           # CLI staples (tealdeer = fast tldr); ripgrep via programs.ripgrep
    # fastfetch and ble.sh left 2026-10-10 (decisions/0013: Origin; Community)
  ];

  # ---- CLI tools (theming handled by dram-theme via ~/.config/themes) -------
  # catppuccin/nix was dropped: it pins one flavor per rebuild, which defeats
  # runtime theme switching. bat/btop/fzf get their colors from the active
  # theme dir instead (see dotfiles/.local/bin/dram-theme).
  programs.bat.enable = true;
  programs.fzf = { enable = true; enableBashIntegration = true; };
  programs.btop.enable = true;
  # eza's HM bash integration would add its own ls/ll/la/lt/lla (mkDefault); the
  # aliases below are the whole family we want, so keep HM's out (no stray `lt`/`lla`).
  programs.eza = { enable = true; enableBashIntegration = false; };
  programs.zoxide.enable = true;

  # atuin: enableBashIntegration is off, because atuin's hook is sourced by
  # hand at the end of programs.bash.initExtra, after bash-preexec (which
  # atuin needs in bash now that ble.sh is gone) and after fzf's bindings, so
  # atuin's Ctrl-R wins over fzf's.
  programs.atuin = {
    enable = true;
    enableBashIntegration = false;
    settings = {
      style = "compact";
      inline_height = 15;
      search_mode = "fuzzy";
      show_preview = true;
      update_check = false;
      enter_accept = false;
    };
  };

  programs.starship = { enable = true; enableBashIntegration = true; };
  programs.bash = {
    enable = true;
    historyControl = [ "ignoredups" "ignorespace" ];
    historySize = 50000;
    historyFileSize = 100000;
    shellAliases = {
      grep = "grep --color=auto";
      cat  = "bat --paging=never";
      ls   = "eza --group-directories-first";
      ll   = "eza -l --git --group-directories-first";
      la   = "eza -la --git --group-directories-first";
      tree = "eza --tree";
      ".." = "cd ..";
      vpn = "sudo wg-quick up home";                       # docs/security/network/vpn.md (UniFi WireGuard client)
      vpn-down = "sudo wg-quick down home";
      backup = "borgmatic --verbosity 1";                 # daily timer does the same; this is the manual run
      backup-eva = "bash ${dram.repo}/system/backup-eva.sh";    # optional offline copy when eva is plugged in
      upgrade = "dram update --clean";                     # sysupdate/dram-switch are shims onto `dram` (docs/operations/dram/README.md)
      # homelab (kubectl/kubectx/talosctl from home.packages, modules/dev.nix)
      k  = "kubectl";
      kx = "kubectx";
      kn = "kubens";
      t  = "talosctl";
    };
    initExtra = ''
      # Package-manager commands get NO completion and NO prediction. Their TAB
      # completion runs a command substitution over the package DB (which holds
      # NUL bytes -> bash warns "ignored null byte in input").
      _pj_no_completion() { COMPREPLY=(); return 0; }
      complete -F _pj_no_completion pacman 2>/dev/null || true

      # atuin needs a preexec hook in bash: bash-preexec (ble.sh did this until
      # 2026-10-10). Last in initExtra, so atuin's Ctrl-R binding beats fzf's.
      if [[ $- == *i* ]]; then
        source ${pkgs.bash-preexec}/share/bash/bash-preexec.sh
        eval "$(${pkgs.atuin}/bin/atuin init bash --disable-up-arrow)"
      fi
    '';
  };

  home.sessionVariables = {
    FZF_DEFAULT_OPTS_FILE = "${config.home.homeDirectory}/.config/themes/current/fzf.opts";
    FZF_CTRL_T_COMMAND = "fd --type f --hidden --exclude .git";
    FZF_ALT_C_COMMAND  = "fd --type d --hidden --exclude .git";
    FZF_CTRL_T_OPTS    = "--preview 'bat --color=always --style=numbers {}'";
    FZF_ALT_C_OPTS     = "--preview 'eza --tree --color=always --level=2 {} | head -200'";
    FZF_DEFAULT_OPTS   = "--height=40% --layout=reverse --border";
  };

  # bash-completion (pacman) loads this lazily on the first `dram <TAB>`
  home.file.".local/share/bash-completion/completions/dram".source = dram.link ".local/share/bash-completion/completions/dram";
}

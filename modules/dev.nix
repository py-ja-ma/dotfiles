{ config, pkgs, lib, dram, ... }:

# Developer tooling: git (SSH-signed commits), delta, lazygit, direnv, ripgrep,
# the homelab CLI kit, and the per-host ssh-agent (or, in a WSL clone, the bridge to
# Windows' agent).
let
  # The SSH keys on my YubiKeys (keys/ssh.pub, decisions/0019): the lines
  # that start with a security-key type (bin/check.sh 18 allows no others).
  yubikeySsh = lib.filter (lib.hasPrefix "sk-")
    (lib.splitString "\n" (builtins.readFile ../keys/ssh.pub));
  # the address commits carry (the same as the Mac's), never a personal mailbox
  email = "github.project@pseudoaddress.com";
in
{
  home.packages =
    # homelab CLI kit — pure CLI, pinned by flake.lock (ADR 0003); the sysadmin role
    # (decisions/0009). jq is pacman's (packages/base.txt): systemd user units see /usr/bin only
    lib.optionals (lib.elem "sysadmin" config.dram.roles) (with pkgs; [
      kubectl kubernetes-helm k9s kubectx talosctl
      yq-go sops age step-cli
      opentofu lazydocker kind ansible
    ])
    # mkcert: dev TLS CA; the CA itself lives in ~/.local/share/mkcert and is
    # tool-independent (replaces the pacman copy on lantern, 2026-10-07)
    ++ [ pkgs.mkcert ];

  # ---- git / dev ------------------------------------------------------------
  # Commits are SSH-signed. Once keys/ssh.pub lists a YubiKey, the signing key is the
  # one on the YubiKey (a touch per commit) through the handle `dram yubikey ssh`
  # links as ~/.ssh/id_ed25519_sk on each host (docs/security/identity/README.md); until then it is
  # the host's own ed25519 key (`ssh-keygen -t ed25519 -C "<user>@$(hostname)"` on a
  # new box BEFORE the first commit). Register the public keys on GitHub as both
  # authentication and signing keys when the repo is pushed. The pinned HM rev
  # names this block `settings`, not `extraConfig`.
  programs.git = {
    enable = true;
    signing = {
      format = "ssh";
      key = if yubikeySsh != [ ] then "~/.ssh/id_ed25519_sk.pub" else "~/.ssh/id_ed25519.pub";
      signByDefault = true;
    };
    settings = {
      user = { name = "Patrick Jordan"; inherit email; };
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      push.followTags = true;
      rerere.enabled = true;
      diff.algorithm = "histogram";
      diff.colorMoved = "default";
      merge.conflictStyle = "zdiff3";
      commit.verbose = true;
      branch.sort = "-committerdate";
      column.ui = "auto";
      fetch.prune = true;
      rebase = { autoStash = true; autoSquash = true; updateRefs = true; };
      core.editor = "vim";
      gpg.ssh.allowedSignersFile = "~/.config/git/allowed_signers";  # lets `git log --show-signature` verify my own commits
    };
    # written to ~/.config/git/ignore by HM (no tracked dotfile for this)
    ignores = [
      ".direnv/" "result" "result-*" ".envrc.local"
      "__pycache__/" "*.pyc" ".DS_Store"
    ];
  };
  # Public keys only: the hosts' own keys (their private halves never leave the host)
  # and the YubiKeys' (keys/ssh.pub; the private halves never leave the YubiKey).
  xdg.configFile."git/allowed_signers".text = ''
    ${email} ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPN/0O3XM0ycGNv6du9Xx1CETOT0kwDdgPX2INFV+sQn pj@cabin
    ${email} ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID6VrO+UM/LHVuxHCC+966sqLZmrVu0oUdMp0nIe/yMD pj@lantern
  '' + lib.concatMapStrings (l: "${email} ${l}\n") yubikeySsh;

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = { navigate = true; line-numbers = true; };
  };
  programs.lazygit = {
    enable = true;
    shellWrapperName = "lg";
    settings.git.paging = { colorArg = "always"; pager = "delta --dark --paging=never"; };
  };
  programs.direnv = { enable = true; nix-direnv.enable = true; silent = true; };
  programs.ripgrep = { enable = true; arguments = [ "--smart-case" "--hidden" "--glob=!.git/*" ]; };

  home.sessionVariables = {
    # homelab: both hosts point at the same cluster configs (not tracked — secrets)
    KUBECONFIG  = "${config.home.homeDirectory}/.kube/config";
    TALOSCONFIG = "${config.home.homeDirectory}/.talos/config";
  };

  # One ssh-agent per host, managed (lantern had a hand-made socket; cabin none) —
  # except a WSL clone with dram.wsl.sshAgent = "windows", below.
  services.ssh-agent.enable = config.dram.wsl.sshAgent == "local";

  # The WSL clone (decisions/0021, docs/platforms/wsl/README.md, decisions/log.md#d79): Windows keeps the YubiKey, and ssh and
  # git signing (`ssh-keygen -Y sign` asks the agent first) reach Windows' OpenSSH agent
  # through wsl2-ssh-agent (MIT; nixpkgs, never the AUR package): a Unix socket relayed to
  # the `openssh-ssh-agent` pipe by a powershell.exe child, which it finds under /mnt/c when
  # appendWindowsPath=false keeps Windows off PATH. The touch prompt is Windows Hello's. Same
  # shape as NixOS-WSL's wsl.ssh-agent; SSH_AUTH_SOCK through Home Manager's sshAuthSock, as
  # services.ssh-agent sets it (a forwarded agent still wins).
  sshAuthSock = lib.mkIf (config.dram.wsl.sshAgent == "windows") {
    enable = true;
    initialization = {
      bash = ''export SSH_AUTH_SOCK="''${XDG_RUNTIME_DIR:-/run/user/$UID}/wsl2-ssh-agent.sock"'';
      fish = ''set -x SSH_AUTH_SOCK "$XDG_RUNTIME_DIR/wsl2-ssh-agent.sock"'';
      nushell = ''$env.SSH_AUTH_SOCK = $"($env.XDG_RUNTIME_DIR)/wsl2-ssh-agent.sock"'';
    };
    systemd.socketProviderUnit = "wsl2-ssh-agent.service";
  };
  # sshAuthSock sets it for login shells; VSCodium's terminal in the clone (an ssh session
  # from Windows, no agent forwarded) is not one, so interactive shells set it too
  programs.bash.initExtra = lib.mkIf (config.dram.wsl.sshAgent == "windows") (lib.mkBefore ''
    if [ -z "$SSH_AUTH_SOCK" ] || [ -z "$SSH_CONNECTION" ]; then
      export SSH_AUTH_SOCK="''${XDG_RUNTIME_DIR:-/run/user/$UID}/wsl2-ssh-agent.sock"
    fi
  '');
  systemd.user.services.wsl2-ssh-agent = lib.mkIf (config.dram.wsl.sshAgent == "windows") {
    Unit = {
      Description = "SSH agent bridge to Windows' OpenSSH agent (wsl2-ssh-agent; docs/platforms/wsl/README.md)";
      Documentation = "https://github.com/mame/wsl2-ssh-agent";
    };
    Service = {
      ExecStart = "${pkgs.wsl2-ssh-agent}/bin/wsl2-ssh-agent --foreground --socket=%t/wsl2-ssh-agent.sock";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };

  # re-lab role: the per-user tools (uv tools, Ghidra extensions), docs/toolchain/profiles/re-lab.md
  home.file.".local/bin/re-lab-tools" = lib.mkIf (lib.elem "re-lab" config.dram.roles) {
    source = dram.link ".local/bin/re-lab-tools";
  };

  # dev role: Open Remote-SSH (jeanp413, MIT, Open VSX — accepted 2026-10-11) in VSCodium,
  # installed once if missing; offline or before codium exists it says so (docs/toolchain/development/README.md)
  home.activation.codiumRemoteSsh = lib.mkIf (lib.elem "dev" config.dram.roles)
    (lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      if [ -x /usr/bin/codium ]; then
        /usr/bin/codium --list-extensions 2>/dev/null | grep -qix jeanp413.open-remote-ssh \
          || run /usr/bin/codium --install-extension jeanp413.open-remote-ssh >/dev/null 2>&1 \
          || echo "Open Remote-SSH not installed (offline?) — codium --install-extension jeanp413.open-remote-ssh"
      fi
    '');

  # dev role: Rust's stable toolchain as rustup's default, once, when none is chosen. rustup
  # alone leaves cargo refusing to run ("could not choose a version"), as on the new WSL clone
  # (2026-10-12), where it used to be a step by hand. Offline it says so.
  home.activation.rustupDefault = lib.mkIf (lib.elem "dev" config.dram.roles)
    (lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      if [ -x /usr/bin/rustup ] && ! /usr/bin/rustup default >/dev/null 2>&1; then
        run /usr/bin/rustup default stable >/dev/null 2>&1 \
          || echo "rustup has no default toolchain (offline?) — rustup default stable"
      fi
    '');
}


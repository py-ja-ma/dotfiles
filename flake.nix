{
  description = "pj's Arch Linux dram — multi-host Home Manager config (dotfiles + user packages)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Secrets scaffold (modules/secrets.nix, docs/security/identity/secrets.md). Inert until a host
    # sets dram.secrets.enable; the module is imported on every host so the
    # option set is identical everywhere.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Lint hooks (statix, deadnix, shellcheck) as `checks.<system>.pre-commit`
    # and the devShell's git hook (decisions/0006-flake-layout.md).
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, git-hooks, ... }:
    let
      inherit (nixpkgs) lib;

      # The hosts run x86_64 Arch; the Mac (aarch64-darwin) only evaluates,
      # formats and runs the hooks. `forAll` gives every per-system output
      # (checks / formatter / devShells) the same two keys.
      hostSystem = "x86_64-linux";
      systems = [ hostSystem "aarch64-darwin" ];
      forAll = lib.genAttrs systems;

      # the same instance `formatter`/`devShells` use for this system; no `config`
      # is needed (nothing unfree, ADR 0006 §2) — switch back to `import nixpkgs
      # { system = …; config = …; }` if that ever changes
      pkgs = nixpkgs.legacyPackages.${hostSystem};

      # One host = one file in modules/hosts/. The file only sets the `dram.*`
      # flags (hostName, backup peer, isLaptop, gpu); modules/default.nix turns
      # them into config (decisions/0004-module-split.md). Adding a host is
      # adding that file — nothing here changes (decisions/0006-flake-layout.md).
      hosts = map (lib.removeSuffix ".nix") (builtins.attrNames (lib.filterAttrs
        (name: type: type == "regular" && lib.hasSuffix ".nix" name)
        (builtins.readDir ./modules/hosts)));

      mkHost = host:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [ sops-nix.homeManagerModules.sops ./modules (./modules/hosts + "/${host}.nix") ];
        };

      configs = lib.genAttrs hosts mkHost; # host name -> its Home Manager configuration

      # Windows (decisions/0020, docs/platforms/windows/renderer.md): one windows/hosts/<host>.nix
      # per Windows PC,
      # its roles on one line, lowered with lib.evalModules and rendered by bin/render-windows.sh
      # into windows/build/<host>/ (committed; install/windows/apply-windows.sh applies it).
      # Nothing of the Arch side reads windows/. A committed build that is not what this flake
      # renders fails `nix flake check` at evaluation.
      windows = import ./windows { inherit lib; };
      windowsCheck = system: h: w:
        if w.stale != [ ] then throw "windows/build/${h} is stale (${toString w.stale}): bin/render-windows.sh ${h}"
        else nixpkgs.legacyPackages.${system}.runCommand "windows-${h}-render-current" { } "touch $out";

      # statix + deadnix on *.nix, shellcheck on every bash script, with the same
      # exclusions as bin/check.sh §4 and treefmt.toml: superseded files, harvested
      # machine state, vendored theme dirs. nixfmt/shfmt/stylua are NOT hooks yet:
      # the shell scripts are shfmt-clean (bin/check.sh §4 enforces it) but *.nix
      # and the Lua files are not formatted (treefmt.toml says so) and formatting them is a
      # commit of its own. shellcheck runs at the same severity as check.sh §4.
      preCommit = system:
        git-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            statix.enable = true;    # lints disabled in statix.toml
            deadnix.enable = true;
            shellcheck = {
              enable = true;
              args = [ "-S" "warning" "-s" "bash" ];
              # identify tags *.sh as `shell` only (the shebang is read just for
              # extensionless executables, which get shell+bash), so `bash` matched
              # 11 scripts and skipped every *.sh; `shell` covers both, -s bash keeps
              # the dialect. Excluded: vendored PKGBUILDs (reviewed sources, not our
              # scripts — pkgs/README.md) and the sourced themes/*/meta.sh fragments.
              types = [ "shell" ];
              excludes = [ "^pkgs/" "^dotfiles/\\.config/themes/[^/]+/meta\\.sh$" ];
            };
          };
          excludes = [ "^legacy/" "^hosts/" "^system/plymouth-catppuccin/" "^system/refind-catppuccin/" ];
        };
    in {
      # Apply with the helper:  dram switch
      #   == home-manager switch --flake ~/git/dotfiles#<user>@<hostname> \
      #        --extra-experimental-features 'nix-command flakes' -b bak
      #
      # NEVER run bare `home-manager switch`. It ignores the flake and reads
      # ~/.config/home-manager/home.nix, which once applied a near-empty config
      # and tore down every dotfile symlink. dram switch resolves the host for
      # you from /etc/hostname, so there is no wrong-host footgun either.
      # named <user>@<host> from each host's dram.user (pj, or ranger on the travel laptop);
      # the WSL clones are hosts like any other (form = "wsl": pj@cabin-wsl, pj@thermos-wsl,
      # decisions/0021), so `nix flake check` builds home-cabin-wsl and home-thermos-wsl too
      homeConfigurations = lib.mapAttrs' (h: c: lib.nameValuePair "${c.config.dram.user}@${h}" c) configs;

      # cabin-win's build: `nix eval .#windowsConfigurations.cabin-win.files`
      windowsConfigurations = windows;

      # `nix flake check` instantiates EVERY host's module tree (home-<host>), so
      # a typo in one host's file surfaces on any machine, plus the lint hooks
      # (pre-commit) for the system it runs on, and every Windows build against its
      # render (windows-<host>). CI runs it --all-systems --no-build.
      checks = forAll (system:
        { pre-commit = preCommit system; }
        // lib.optionalAttrs (system == hostSystem)
          (lib.mapAttrs' (h: c: lib.nameValuePair "home-${h}" c.activationPackage) configs)
        // lib.mapAttrs' (h: w: lib.nameValuePair "windows-${h}" (windowsCheck system h w)) windows);

      # `nix fmt` -> treefmt preconfigured with nixfmt (nixpkgs' nixfmt-tree).
      # It formats *.nix only; `treefmt` (pacman) reads treefmt.toml and also
      # runs shfmt + stylua. Nothing is formatted automatically: run it by hand.
      formatter = forAll (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

      # `nix develop`: the lint tools on PATH and the pre-commit hook installed
      # into .git (it writes .pre-commit-config.yaml, gitignored).
      devShells = forAll (system:
        let pc = preCommit system;
        in {
          default = nixpkgs.legacyPackages.${system}.mkShellNoCC {
            inherit (pc) shellHook;
            packages = pc.enabledPackages;
          };
        });
    };
}

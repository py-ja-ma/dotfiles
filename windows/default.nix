{ lib }:

# The flake's windowsConfigurations (decisions/0020, docs/platforms/windows/renderer.md): one per
# windows/hosts/<host>.nix, each a lib.evalModules over the option set, every role file,
# windows/packages.nix and that host file. `files` is the build bin/render-windows.sh writes to
# windows/build/<host>/ and commits; `stale` names the committed files that differ from it,
# which the flake's checks refuse. Nothing here changes Arch: homeConfigurations never read it.
#
#   options.nix   every windows.* option         lower.nix  roles + lists + host -> units
#   lib.nix       lists, pins, staged dirs       render.nix units -> documents, manifest, inputs
#   packages.nix  what a list line cannot say    roles/     settings by role; hosts/ one per PC
#   units/        each Script unit's PowerShell, one file per unit (Get, Test, Set)
let
  repo = ../.;
  wlib = import ./lib.nix { inherit lib repo; };
  nixFiles = d: map (n: d + "/${n}") (lib.attrNames (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".nix" n) (builtins.readDir d)));
  hosts = map (p: lib.removeSuffix ".nix" (baseNameOf p)) (nixFiles ./hosts);

  configure = host:
    let
      eval = lib.evalModules {
        modules = [ ./options.nix ./lower.nix ./render.nix ./packages.nix (./hosts + "/${host}.nix") ] ++ nixFiles ./roles;
        specialArgs = { inherit repo wlib; };
      };
      failed = lib.filter (a: !a.assertion) (eval.config.assertions
        ++ [{ assertion = eval.config.windows.host == host; message = "windows.host is ${eval.config.windows.host}, not ${host}"; }]);
      files =
        if failed != [ ] then throw "windows/hosts/${host}.nix:\n${lib.concatMapStringsSep "\n" (a: "- ${a.message}") failed}"
        else eval.config.windows.build;
      dir = ./build + "/${host}";
      committed = if builtins.pathExists dir then lib.attrNames (builtins.readDir dir) else [ ];
      stale = lib.filter (n: !(lib.elem n committed) || builtins.readFile (dir + "/${n}") != files.${n}) (lib.attrNames files)
        ++ lib.subtractLists (lib.attrNames files) committed;
    in
    { inherit (eval) config; inherit files stale; };
in
lib.genAttrs hosts configure

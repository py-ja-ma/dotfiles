{ lib, wlib, ... }:

# Every `windows.*` option is declared here and nowhere else (decisions/0020,
# docs/platforms/windows/renderer.md).
# A host file (windows/hosts/<host>.nix) sets host, roles and hold, and its own settings as
# windows.role.host-<host>; a role file (windows/roles/<role>.nix) sets windows.role.<role>;
# windows/packages.nix says what a packages/winget line cannot. windows/lower.nix turns the
# host's roles, their lists and its own settings into units; windows/render.nix writes them out
# as one build (windows/build/<host>/).
#
# Settings are typed data. A registry value is { key, name, type, data }, and its hive decides
# where it runs: HKEY_LOCAL_MACHINE in the machine documents (elevated), HKEY_CURRENT_USER in
# pj's. A Script unit is a description and its context; its PowerShell is windows/units/<id>.ps1
# (Get, Test and Set), so the documents hold data, not code. A null entry leaves that setting
# unmanaged, so a host can take one setting of a role back:
#   windows.role.desktop.registry.no-widgets = lib.mkForce null;
let
  inherit (lib) mkOption types;
  # 00 debloat · 10 system · 20 user · 30 apps · 40 autostart · 50 ask: documents
  # and scripts run phase by phase, in this order
  phase = types.enum [ "00" "10" "20" "30" "40" "50" ];

  registry = types.submodule {
    options = {
      description = mkOption { type = types.str; description = "What the value does (the unit's description)."; };
      key = mkOption { type = types.strMatching ''HKEY_(LOCAL_MACHINE|CURRENT_USER)\\.+''; description = "The key, from its hive."; };
      name = mkOption { type = types.str; description = "The value's name."; };
      type = mkOption { type = types.enum [ "String" "ExpandString" "MultiString" "Dword" "Qword" "Binary" ]; description = "PSDscResources' ValueType."; };
      data = mkOption { type = types.str; description = "The value, as PSDscResources' ValueData takes it."; };
      phase = mkOption { type = types.nullOr phase; default = null; description = "null: 10 for a machine value, 20 for pj's."; };
    };
  };

  script = types.submodule {
    options = {
      description = mkOption { type = types.str; description = "What the unit does."; };
      # securityContext: elevated <-> the machine document; false: pj's own context
      elevated = mkOption { type = types.bool; description = "Needs an administrator (the machine document) rather than pj's context."; };
      phase = mkOption { type = types.nullOr phase; default = null; description = "null: 10 elevated, 20 otherwise (a unit that installs an app says 30)."; };
      # the packages/winget name this unit installs or puts in place: holding that name
      # (windows.hold) drops the unit too
      package = mkOption { type = types.nullOr types.str; default = null; description = "The manual:<name> this unit installs."; };
      dependsOn = mkOption { type = types.listOf types.str; default = [ ]; description = "Units that must converge first: the same document, or an earlier phase."; };
    };
  };

  # one of the converge's own scripts (install/windows/dram-windows/), run between documents in
  # the converge's elevated session (apply-live.ps1, on pj's desktop, is no step: converge.ps1
  # and dram.ps1 both start it after the phases when the build stages it)
  step = types.submodule {
    options = {
      source = mkOption { type = types.path; description = "The script in the repo."; };
      phase = mkOption { type = phase; description = "Runs after this phase's documents."; };
      args = mkOption { type = types.listOf types.str; default = [ ]; description = "Its arguments."; };
      dryRun = mkOption { type = types.nullOr types.str; default = "-DryRun"; description = "The flag it takes for a dry run; null: it has none, and a dry run skips it."; };
      when = mkOption { type = types.enum [ "always" "debloat" ]; default = "always"; description = "debloat: only when converge.ps1 is asked to debloat (dram.ps1 runs phase 00 unless -Phase leaves it out)."; };
    };
  };

  # a file the build stages under C:\ProgramData\dram (the attribute name is its path there)
  file = types.submodule {
    options = {
      source = mkOption { type = types.nullOr types.path; default = null; description = "A file of the repo (its sha256 is computed)."; };
      pin = mkOption { type = types.nullOr types.str; default = null; description = "A pinned download, as <pin file>#<id>: the stager fetches and checks it."; };
      sha256 = mkOption { type = types.nullOr types.str; default = null; description = "A pinned file's sha256."; };
      dir = mkOption { type = types.nullOr types.str; default = null; description = "The repo directory it was taken from whole: a file added there makes the render stale."; };
    };
  };

  role = types.submodule {
    options = {
      registry = mkOption { type = types.attrsOf (types.nullOr registry); default = { }; description = "Registry values, by unit id."; };
      script = mkOption { type = types.attrsOf (types.nullOr script); default = { }; description = "Script units, by unit id."; };
      steps = mkOption { type = types.attrsOf (types.nullOr step); default = { }; description = "The converge's scripts, by their path under C:\\ProgramData\\dram."; };
      files = mkOption { type = types.attrsOf (types.nullOr file); default = { }; description = "Files the units and scripts read, by their path under C:\\ProgramData\\dram."; };
    };
  };

  package = types.submodule {
    options = {
      id = mkOption { type = types.nullOr types.str; default = null; description = "The unit id; null: made from the package id."; };
      description = mkOption { type = types.nullOr types.str; default = null; description = "null: the package id."; };
      elevated = mkOption { type = types.nullOr types.bool; default = null; description = "null: winget packages machine-wide (elevated), Store apps in pj's context."; };
      version = mkOption { type = types.nullOr types.str; default = null; description = "A pinned version."; };
      byHand = mkOption { type = types.nullOr types.str; default = null; description = "For a manual:<name> no unit installs: how it gets there."; };
    };
  };
in
{
  options = {
    # what windows/default.nix refuses to render with (NixOS' convention)
    assertions = mkOption {
      type = types.listOf (types.submodule {
        options = {
          assertion = mkOption { type = types.bool; };
          message = mkOption { type = types.str; };
        };
      });
      default = [ ];
      internal = true;
    };
    windows = {
      host = mkOption { type = types.strMatching "[a-z][a-z0-9-]*"; description = "The Windows host: its file in windows/hosts/, its build in windows/build/."; };
      # how the Mac reaches the PC's OpenSSH: bin/push-windows.sh and apply-windows.sh read these
      # lines with sed (as bin/release.sh reads dram.address), so keep each on one line, quoted
      address = mkOption { type = types.str; default = ""; description = "The PC's LAN address, as reached from the Mac."; };
      user = mkOption { type = types.strMatching "[a-z_][a-z0-9_-]*"; default = "pj"; description = "The administrator the Mac signs in as."; };
      # what this PC is for: Arch's role names (decisions/log.md#d52), each a
      # packages/winget/<role>.txt; the enum is built from that directory, so a role exists
      # exactly when its list does. One line in
      # the host file. base is implicit, as on Arch; host-<host>.txt and windows.role.host-<host>
      # come with the host itself (its own list, as packages/host-<host>.txt on Arch).
      roles = mkOption { type = types.listOf (types.enum wlib.roles); description = "Roles (packages/winget/<role>.txt); base is implicit."; };
      # names of its roles' lists this host does not install yet: removing one installs it
      hold = mkOption { type = types.listOf types.str; default = [ ]; description = "Listed names this host does not install yet."; };
      # installed by hand and kept out of the build: dram harvest leaves them out
      unmanaged = mkOption { type = types.listOf types.str; default = [ ]; description = "winget:<id> or msstore:<id> names installed by hand and left alone: dram harvest skips them."; };
      role = mkOption { type = types.attrsOf role; default = { }; description = "Each role's settings; only the host's roles are used."; };
      packages = mkOption { type = types.attrsOf package; default = { }; description = "What a packages/winget line cannot say, by its name."; };

      # set by windows/lower.nix and windows/render.nix
      units = mkOption { type = types.listOf types.attrs; internal = true; description = "Every unit of the host, lowered."; };
      steps = mkOption { type = types.listOf types.attrs; internal = true; description = "The converge's scripts, in order."; };
      staged = mkOption { type = types.attrsOf types.attrs; internal = true; description = "Every staged file: path -> { sha256, source }."; };
      byHand = mkOption { type = types.listOf types.attrs; internal = true; description = "Listed names no unit installs."; };
      inputs = mkOption { type = types.listOf types.path; internal = true; description = "Repo files the render reads, besides windows/ and packages/winget/."; };
      build = mkOption { type = types.attrsOf types.str; internal = true; description = "The build: file name under windows/build/<host>/ -> its text."; };
    };
  };
}

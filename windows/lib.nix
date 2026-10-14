{ lib, repo }:

# Helpers the Windows modules take as `wlib` (windows/default.nix passes them): reading the
# package lists and the pin files, and staging a repo directory whole. Everything is read from
# the flake's own source, so a render is a function of the repo alone.
let
  # a path inside the repo -> "install/windows/letterpress/theme"
  rel = p: lib.removePrefix "${toString repo}/" (toString p);
  # the meaningful lines of a list or pin file: no comments, no blank lines, words split
  lines = file: lib.filter (l: l != "" && !lib.hasPrefix "#" l)
    (map lib.trim (lib.splitString "\n" (builtins.readFile file)));
  words = l: lib.filter (w: w != "") (lib.splitString " " (builtins.replaceStrings [ "\t" ] [ " " ] l));
  fontsPin = repo + "/install/windows/fonts.pin";
  fontsLock = repo + "/install/windows/fonts.lock";
  cursorsPin = repo + "/install/windows/cursors.pin";
in
rec {
  inherit rel;

  # every packages/winget/<name>.txt; the roles a host can name are those but base (every host
  # has it, as on Arch) and the host-<host> lists (each host has its own)
  lists = map (lib.removeSuffix ".txt") (builtins.attrNames (lib.filterAttrs
    (n: t: t == "regular" && lib.hasSuffix ".txt" n) (builtins.readDir (repo + "/packages/winget"))));
  roles = lib.filter (n: n != "base" && !lib.hasPrefix "host-" n) lists;
  # what a host plays, in order: base, its roles line, its own list and settings
  active = host: roles': [ "base" ] ++ roles' ++ [ "host-${host}" ];
  # packages/winget/<name>.txt: one winget:/msstore:/manual: name per line, own-line comments
  # (bin/check-register.py holds the format); a list that does not exist is empty
  listNames = name:
    let f = repo + "/packages/winget/${name}.txt"; in
    if builtins.pathExists f then lines f else [ ];

  # a repo directory staged whole under `to`: { "<to>/<path inside it>" = { source; dir; }; }
  dir = to: from: lib.listToAttrs (map
    (p: lib.nameValuePair "${to}/${lib.removePrefix "${toString from}/" (toString p)}" { source = p; dir = rel from; })
    (lib.filesystem.listFilesRecursive from));

  # the house fonts: install/windows/fonts.lock names each file fonts.pin stages and its sha256
  # (bin/render-windows.sh --lock writes it from the downloads, which Nix never makes); a lock
  # whose pin sums are not fonts.pin's is refused, so a bumped pin cannot render stale fonts
  fonts =
    let
      pins = lib.listToAttrs (map (l: let w = words l; in lib.nameValuePair (lib.elemAt w 0) (lib.elemAt w 2)) (lines fontsPin));
      locked = map words (lines fontsLock);
      lockPins = lib.unique (map (w: lib.elemAt w 0) locked);
      stale = lib.filter (w: (pins.${lib.elemAt w 0} or null) != lib.elemAt w 1) locked
        ++ lib.filter (id: !lib.elem id lockPins) (lib.attrNames pins);
    in
    if stale != [ ] then
      throw "install/windows/fonts.lock does not match install/windows/fonts.pin (${toString (map (w: if builtins.isList w then lib.head w else w) stale)}): bin/render-windows.sh --lock"
    else lib.listToAttrs (map (w: lib.nameValuePair "fonts/${lib.elemAt w 3}" {
      pin = "install/windows/fonts.pin#${lib.elemAt w 0}";
      sha256 = lib.elemAt w 2;
    }) locked);

  # the pointer: install/windows/cursors.pin, one file per line (<role> <url> <sha256> =<name>)
  cursors = lib.listToAttrs (map (l: let w = words l; in lib.nameValuePair "cursors/${lib.removePrefix "=" (lib.elemAt w 3)}" {
    pin = "install/windows/cursors.pin#${lib.elemAt w 0}";
    sha256 = lib.elemAt w 2;
  }) (lines cursorsPin));

  # what the two helpers above read, for the render's inputs
  pinFiles = [ fontsPin fontsLock cursorsPin ];
}

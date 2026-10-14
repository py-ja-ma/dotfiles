{ config, lib, repo, wlib, ... }:

# The build of one Windows host (decisions/0020): its units as winget configuration documents,
# one per phase and scope, manifest.json for the converge (and dram.ps1) and inputs.json for
# bin/check.sh, each a file of windows/build/<host>/. Deterministic: sorted, no timestamps;
# release and commit are filled in when a build is staged, not here.
#
# A document holds the units of one phase and one scope: machine (every unit elevated, none
# writing HKCU) or user (pj's own context: HKCU is pj's, never SYSTEM's) - two documents per
# phase. Inside a document the host's roles come in the order of its roles line (base first),
# the host's own settings last, each role's units by id.
let
  w = config.windows;
  active = wlib.active w.host w.roles;
  rank = lib.listToAttrs (lib.imap0 (i: r: lib.nameValuePair r i) active);
  scope = u: if u.elevated then "machine" else "user";
  docName = u: "${u.phase}-${scope u}.winget";
  docs = lib.groupBy docName w.units;
  docNames = lib.sort (a: b: a < b) (lib.attrNames docs);
  sortUnits = lib.sort (a: b: if a.role != b.role then rank.${a.role} < rank.${b.role} else a.id < b.id);
  byId = lib.listToAttrs (map (u: lib.nameValuePair u.id u) w.units);

  # The emitter: block YAML in which every string is double-quoted - a JSON string is a YAML
  # one - so no value turns into another type and no ": " or ", " in a description starts a new
  # key. A map's keys come in its _order, then by name. No empty map or list is ever emitted.
  keys = m: let o = lib.filter (k: m ? ${k}) (m._order or [ ]); in o ++ lib.subtractLists o (lib.attrNames (removeAttrs m [ "_order" ]));
  scalar = x:
    if builtins.isString x then builtins.toJSON x
    else if builtins.isBool x then lib.boolToString x
    else throw "windows/render.nix: no YAML for ${builtins.toJSON x}";
  node = i: x: if builtins.isAttrs x then lib.concatMap (k: entry i k x.${k}) (keys x) else lib.concatMap (item i) x;
  entry = i: k: x: if builtins.isAttrs x || builtins.isList x then [ "${i}${k}:" ] ++ node "${i}  " x else [ "${i}${k}: ${scalar x}" ];
  item = i: x:
    if builtins.isAttrs x then let ls = node "${i}  " x; in [ "${i}- ${lib.removePrefix "${i}  " (lib.head ls)}" ] ++ lib.tail ls
    else [ "${i}- ${scalar x}" ];

  settingsOrder = {
    "PSDscResources/Registry" = [ "Key" "ValueName" "ValueType" "ValueData" "Force" ];
    "PSDscResources/Script" = [ "GetScript" "TestScript" "SetScript" ];
    "Microsoft.WinGet.DSC/WinGetPackage" = [ "id" "source" "version" ];
  };
  # winget 0.2 resolves dependsOn inside one document; one on a document that runs earlier is
  # kept by that order instead (windows/lower.nix refuses one on a document that runs later)
  depsIn = u: lib.filter (d: docName byId.${d} == docName u) u.dependsOn;
  unitYaml = u: {
    _order = [ "resource" "id" "dependsOn" "directives" "settings" ];
    inherit (u) resource id;
    directives = { _order = [ "description" "allowPrerelease" "securityContext" ]; inherit (u) description; allowPrerelease = true; }
      // lib.optionalAttrs u.elevated { securityContext = "elevated"; };
    settings = u.settings // { _order = settingsOrder.${u.resource}; };
  } // lib.optionalAttrs (depsIn u != [ ]) { dependsOn = depsIn u; };

  phases = {
    "10" = "system, the machine's settings";
    "20" = "user, pj's settings";
    "30" = "apps";
    "40" = "autostart, what starts by itself";
    "50" = "ask, what needs pj at the desktop";
  };
  scopes = {
    machine = "every unit elevated, none writing HKCU";
    user = "pj's own context (HKCU is pj's; never run it as SYSTEM)";
  };
  sources = r:
    if r == "host-${w.host}" then "windows/hosts/${w.host}.nix, packages/winget/${r}.txt"
    else lib.concatStringsSep ", " (lib.optional (builtins.pathExists (./roles + "/${r}.nix")) "windows/roles/${r}.nix" ++ [ "packages/winget/${r}.txt" ]);
  docText = name:
    let
      us = sortUnits docs.${name};
      u0 = lib.head us;
    in
    lib.concatStringsSep "\n" ([
      "# yaml-language-server: $schema=https://aka.ms/configuration-dsc-schema/0.2"
      "#"
      "# windows/build/${w.host}/${name} - rendered by bin/render-windows.sh from"
      "# windows/hosts/${w.host}.nix and what it names; edit those, never this (decisions/0020)."
      "# Phase ${u0.phase}, ${phases.${u0.phase}}; scope ${scope u0}: ${scopes.${scope u0}}."
      "# dram.ps1 (or converge.ps1) applies the documents in manifest.json's order, from build\\:"
      "#   winget configure -f C:\\ProgramData\\dram\\build\\${name} --accept-configuration-agreements --disable-interactivity"
      "properties:"
      "  configurationVersion: \"0.2.0\""
      "  resources:"
    ] ++ lib.concatMap
      (r: [ "    # --- ${r} (${sources r}) ---" ] ++ lib.concatMap (u: item "    " (unitYaml u)) (lib.filter (u: u.role == r) us))
      (lib.filter (r: lib.any (u: u.role == r) us) active)) + "\n";
  texts = lib.genAttrs docNames docText;

  # manifest.json: what to run in which order, and every file to stage with its sha256 -
  # the documents, the unit scripts, the rice (letterpress, the Zebar pack, fonts, cursors,
  # the art) and the converge's own scripts. The contract dram.ps1 is built against.
  manifest = {
    _order = [ "format" "host" "release" "commit" "roles" "documents" "scripts" "files" "byHand" "unmanaged" ];
    format = 1;
    inherit (w) host roles unmanaged;
    release = "unstaged";
    commit = "unstaged";
    documents = map (n: let us = sortUnits docs.${n}; in { file = n; inherit (lib.head us) phase; scope = scope (lib.head us); units = map (u: u.id) us; }) docNames;
    scripts = map (s: { inherit (s) file phase args dryRun when; }) w.steps;
    # the documents are the render's: they live in build\ beside this manifest, where dram.ps1
    # keeps a release's render (and converge.ps1 reads it)
    files = lib.sort (a: b: a.path < b.path) (lib.mapAttrsToList (path: s: { inherit path; inherit (s) sha256 source; }) w.staged
      ++ map (n: { path = "build/${n}"; sha256 = builtins.hashString "sha256" texts.${n}; source = "render:windows/build/${w.host}/${n}"; }) docNames);
    byHand = map (b: { inherit (b) name role how; }) w.byHand;
  };
  # pretty JSON, one array element per line, so a changed file is a changed line in git
  json = m:
    let
      value = v:
        if builtins.isList v && v != [ ] && builtins.isAttrs (lib.head v)
        then "[\n${lib.concatMapStringsSep ",\n" (e: "    ${builtins.toJSON e}") v}\n  ]"
        else builtins.toJSON v;
    in
    "{\n${lib.concatMapStringsSep ",\n" (k: "  ${builtins.toJSON k}: ${value m.${k}}") (keys m)}\n}\n";

  # inputs.json: every repo file the render read, with its sha256, and the directories read
  # whole: bin/render-windows.sh --check (bin/check.sh §19) hashes them again, without Nix, and
  # calls the build stale when a file changed, went or was added. The Markdown pages beside the
  # code (windows/README.md) are documentation, never inputs; the check skips them too.
  windowsFiles = lib.filter (p: !lib.hasPrefix "${toString ./build}/" (toString p) && !lib.hasSuffix ".md" (toString p))
    (lib.filesystem.listFilesRecursive ./.);
  inputFiles = lib.unique (windowsFiles ++ map (n: repo + "/packages/winget/${n}.txt") wlib.lists ++ w.inputs);
  dirs = lib.sort (a: b: a < b) (lib.unique ([ "packages/winget" "windows" ] ++ lib.filter (d: d != null) (lib.mapAttrsToList (_: s: s.dir) w.staged)));
  inputs = "{\n  \"dirs\": ${builtins.toJSON dirs},\n  \"exclude\": [\"windows/build\"],\n  \"files\": {\n"
    + lib.concatMapStringsSep ",\n" (p: "    ${builtins.toJSON (wlib.rel p)}: ${builtins.toJSON (builtins.hashFile "sha256" p)}")
      (lib.sort (a: b: wlib.rel a < wlib.rel b) inputFiles)
    + "\n  }\n}\n";
in
{
  config.windows.build = texts // {
    "manifest.json" = json manifest;
    "inputs.json" = inputs;
  };
}

{ config, lib, wlib, ... }:

# The host's roles, their packages/winget lists and the host's own settings, lowered to units
# (decisions/0020). A host plays its roles in the order of its roles line, then host-<host>
# (its own list and settings, decisions/log.md#d52). Every listed winget: or msstore: name becomes a
# WinGetPackage unit (windows/packages.nix names it; otherwise its id is made from the package
# id), unless the host holds it; a manual: name is a Script unit's (its `package`) or is
# installed by hand (windows/packages.nix says how). The render refuses a plan it cannot
# trust: two units with one id, two units writing one registry value, a held or
# claimed name no list has, a dependency on a later phase, a manual name nobody installs.
let
  w = config.windows;
  active = wlib.active w.host w.roles;
  data = r: w.role.${r} or { registry = { }; script = { }; steps = { }; files = { }; };
  defined = lib.filterAttrs (_: v: v != null);
  orElse = v: d: if v == null then d else v;

  listed = lib.concatMap (r: map (name: { inherit name; role = r; }) (wlib.listNames r)) active;
  names = map (p: p.name) listed;
  installed = lib.filter (p: !lib.elem p.name w.hold) listed;
  installedNames = map (p: p.name) installed;
  kindOf = name: lib.head (lib.splitString ":" name);
  noMeta = { id = null; description = null; elevated = null; version = null; byHand = null; };
  meta = name: w.packages.${name} or noMeta;
  # a unit id from a package id: lowercase, anything else a dash ("Proton.ProtonPass.CLI" ->
  # "proton-protonpass-cli"); winget ids are unique, so these are too
  slug = s: lib.concatStringsSep "-" (lib.filter (x: x != "") (lib.splitString "-" (lib.concatStrings
    (map (c: if builtins.match "[A-Za-z0-9]" c != null then lib.toLower c else "-") (lib.stringToCharacters s)))));

  packageUnit = p:
    let
      kind = kindOf p.name;
      ident = lib.removePrefix "${kind}:" p.name;
      m = meta p.name;
    in
    {
      id = orElse m.id (slug (if kind == "winget" then ident else "${kind}-${ident}"));
      inherit (p) role;
      resource = "Microsoft.WinGet.DSC/WinGetPackage";
      description = orElse m.description ident;
      elevated = orElse m.elevated (kind == "winget");
      phase = "30";
      dependsOn = [ ];
      package = p.name;
      settings = { id = ident; source = kind; } // lib.optionalAttrs (m.version != null) { inherit (m) version; };
    };

  registryUnits = lib.concatMap (r: lib.mapAttrsToList (id: v:
    let elevated = lib.hasPrefix "HKEY_LOCAL_MACHINE\\" v.key; in {
      inherit id elevated;
      role = r;
      resource = "PSDscResources/Registry";
      inherit (v) description;
      phase = orElse v.phase (if elevated then "10" else "20");
      dependsOn = [ ];
      package = null;
      settings = { Key = v.key; ValueName = v.name; ValueType = v.type; ValueData = v.data; Force = true; };
    }) (defined (data r).registry)) active;

  # A Script unit's PowerShell is windows/units/<id>.ps1, staged as units\<id>.ps1: Get, Test
  # and Set each run its text as the unit's script block, as the scripts inside the documents ran -
  # a script block from text, not a script file, so no execution policy stands in between. A
  # Script unit whose app the host holds goes with it.
  scripts = lib.concatMap (r: lib.mapAttrsToList (id: v: v // { inherit id; role = r; }) (defined (data r).script)) active;
  kept = lib.filter (v: v.package == null || lib.elem v.package installedNames) scripts;
  unitFile = id: ./units + "/${id}.ps1";
  call = id: mode: "& ([scriptblock]::Create([IO.File]::ReadAllText('C:\\ProgramData\\dram\\units\\${id}.ps1'))) -Mode ${mode}";
  scriptUnits = map (v: {
    inherit (v) id role description elevated dependsOn package;
    resource = "PSDscResources/Script";
    phase = orElse v.phase (if v.elevated then "10" else "20");
    settings = { GetScript = call v.id "Get"; TestScript = call v.id "Test"; SetScript = call v.id "Set"; };
  }) kept;

  units = registryUnits ++ scriptUnits
    ++ map packageUnit (lib.filter (p: kindOf p.name != "manual") installed);
  byId = lib.listToAttrs (map (u: lib.nameValuePair u.id u) units);
  docOf = u: "${u.phase}-${if u.elevated then "machine" else "user"}";

  claimed = lib.unique (lib.filter (x: x != null) (map (v: v.package) scripts));
  byHand = map (p: { inherit (p) name role; how = (meta p.name).byHand; })
    (lib.filter (p: kindOf p.name == "manual" && !lib.elem p.name claimed) installed);

  steps = lib.concatMap (r: lib.mapAttrsToList (file: s: s // { inherit file; role = r; }) (defined (data r).steps)) active;
  # the staged files: each role's, every step's script and every kept Script unit's file
  fileDefs = lib.concatMap (r: lib.mapAttrsToList (path: f: f // { inherit path; role = r; }) (defined (data r).files)) active
    ++ map (s: { path = s.file; inherit (s) source role; pin = null; sha256 = null; dir = null; }) steps
    ++ map (v: { path = "units/${v.id}.ps1"; source = unitFile v.id; inherit (v) role; pin = null; sha256 = null; dir = null; })
      (lib.filter (v: builtins.pathExists (unitFile v.id)) kept);
  staged = lib.listToAttrs (map (f: lib.nameValuePair f.path (if f.source != null
    then { sha256 = builtins.hashFile "sha256" f.source; source = "repo:${wlib.rel f.source}"; inherit (f) dir; }
    else { inherit (f) sha256; source = "pin:${f.pin}"; dir = null; })) fileDefs);

  # where the scripts keep their own state under C:\ProgramData\dram (downloads, the tinted
  # icons and their originals, the case display's library, a repo checkout), and what dram.ps1
  # keeps there (the engine, the live and previous render, its shim, state and log): never
  # staged into, since apply-windows.sh replaces a staged directory whole and the render goes
  # to build\ by itself
  runtime = [ "cache" "case-display" "icons" "repo" "start-tidy" "state" "build" "build.previous" "incoming" "bin" "state.json" "dram.ps1" "dram.log" ];
  dupes = xs: lib.unique (lib.filter (x: lib.count (y: y == x) xs > 1) xs);
  regValues = map (u: lib.toLower "${u.settings.Key}\\${u.settings.ValueName}") registryUnits;
  allListed = lib.concatMap wlib.listNames wlib.lists;
in
{
  config = {
    windows = {
      inherit units byHand;
      steps = lib.sort (a: b: if a.phase != b.phase then a.phase < b.phase else a.file < b.file) steps;
      inherit staged;
      inputs = wlib.pinFiles ++ lib.concatMap (f: lib.optional (f.source != null) f.source) fileDefs;
    };
    assertions = [
      {
        assertion = lib.subtractLists (wlib.active w.host wlib.roles) (lib.attrNames w.role) == [ ];
        message = "windows.role sets roles that have no packages/winget list: ${toString (lib.subtractLists (wlib.active w.host wlib.roles) (lib.attrNames w.role))}";
      }
      {
        assertion = lib.all (n: lib.elem (kindOf n) [ "winget" "msstore" "manual" ]) names;
        message = "a packages/winget line is not winget:<id>, msstore:<id> or manual:<name>: ${toString (lib.filter (n: !lib.elem (kindOf n) [ "winget" "msstore" "manual" ]) names)}";
      }
      {
        assertion = dupes names == [ ];
        message = "listed twice for ${w.host}: ${toString (dupes names)}";
      }
      {
        assertion = lib.subtractLists names w.hold == [ ];
        message = "windows.hold names what none of ${w.host}'s lists has: ${toString (lib.subtractLists names w.hold)}";
      }
      {
        assertion = lib.all (v: v.package == null || lib.elem v.package names) scripts;
        message = "a Script unit installs a name none of ${w.host}'s lists has: ${toString (map (v: "${v.id} (${v.package})") (lib.filter (v: v.package != null && !lib.elem v.package names) scripts))}";
      }
      {
        assertion = lib.all (v: builtins.pathExists (unitFile v.id)) kept;
        message = "Script units without their windows/units/<id>.ps1: ${toString (map (v: v.id) (lib.filter (v: !builtins.pathExists (unitFile v.id)) kept))}";
      }
      {
        assertion = lib.all (b: b.how != null) byHand;
        message = "manual names no unit installs and windows/packages.nix gives no byHand for: ${toString (map (b: b.name) (lib.filter (b: b.how == null) byHand))}";
      }
      {
        assertion = lib.subtractLists allListed (lib.attrNames w.packages) == [ ];
        message = "windows/packages.nix describes names no packages/winget list has: ${toString (lib.subtractLists allListed (lib.attrNames w.packages))}";
      }
      {
        assertion = dupes (map (u: u.id) units) == [ ];
        message = "two units share an id: ${toString (dupes (map (u: u.id) units))}";
      }
      {
        assertion = dupes regValues == [ ];
        message = "two registry units write one value: ${toString (dupes regValues)}";
      }
      {
        assertion = dupes (map (f: f.path) fileDefs) == [ ];
        message = "two roles stage one path: ${toString (dupes (map (f: f.path) fileDefs))}";
      }
      {
        assertion = lib.all (f: f.path != "manifest.json" && !lib.elem (lib.head (lib.splitString "/" f.path)) runtime) fileDefs;
        message = "staged as manifest.json, or into a directory the scripts keep state in (${toString runtime}): ${toString (map (f: f.path) (lib.filter (f: f.path == "manifest.json" || lib.elem (lib.head (lib.splitString "/" f.path)) runtime) fileDefs))}";
      }
      {
        assertion = lib.all (f: (f.source != null) != (f.pin != null && f.sha256 != null)) fileDefs;
        message = "a staged file needs a source, or a pin and its sha256: ${toString (map (f: f.path) (lib.filter (f: (f.source != null) == (f.pin != null && f.sha256 != null)) fileDefs))}";
      }
      {
        # winget 0.2 resolves dependsOn inside one document; a document that runs earlier (an
        # earlier phase, or this phase's machine document before its user one) runs first anyway
        assertion = lib.all (u: lib.all (d: byId ? ${d} && docOf byId.${d} <= docOf u) u.dependsOn) units;
        message = "a unit depends on one that is missing or not converged before it: ${toString (lib.concatMap (u: map (d: "${u.id}->${d}") (lib.filter (d: !(byId ? ${d}) || docOf byId.${d} > docOf u) u.dependsOn)) units)}";
      }
    ];
  };
}

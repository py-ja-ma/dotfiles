# 0020: Windows from the flake, roles rendered to winget configuration

[Platforms › Windows](../docs/platforms/windows/README.md) · accepted 2026-10-12 · amends 0018 · amended 2026-10-13

Each Windows PC is a host file in the flake, rendered to winget configuration documents and a manifest that `dram.ps1` applies; the cost is a committed render, made on the Mac through a container.

## Context

I want Windows declared the way Arch is, in the flake, so the riced setup can be rebuilt.
Until 2026-10-12 cabin-win was declared by hand in two `winget configure` documents, `common.winget` (what
every Windows PC shares: fonts, privacy, the Letterpress look, the prompt, the keyboard) and
`cabin.winget` (the machine beside Arch, and its apps), 98 units in all, 28 of them Script
units carrying their PowerShell inline. `install/windows/apply-windows.sh` staged them with the
rice they read (the generated look, the Zebar pack, pinned fonts and cursors, the art, the
seal, files shared with Arch) and `dram-windows/converge.ps1` applied them.

The gap: winget's configuration format cannot compose roles
(no includes, no parameters), so every PC would need its own hand-merged copy; and it fetches
each unit's module from PSGallery at apply time. Native Nix on Windows evaluates flakes but
cannot build (NixOS/nix #15471, #10822), the Mac has no Nix at all ([D26](log.md#d26)), and
nobody publishes a Nix-to-Windows renderer to adopt: the pieces exist apart
(nix-darwin's typed defaults, jwnmulder's machine/user document pair, system-manager's render
here, apply there).

## Decision

- **`winget configure` stays the engine** (MIT, on the host, proven on cabin-win; [D63](log.md#d63)). Ansible,
  Chocolatey and Boxstarter, Scoop (an Origin fail), WinUtil (never run on cabin-win, [D134](log.md#d134))
  and LGPO are rejected.
- **Nix renders the documents.** `windows/` is a module tree under `lib.evalModules`, beside
  the Home Manager one and read by nothing of it: one host file per Windows PC
  (`windows/hosts/<host>.nix`) with its roles on **one line**, Arch's role names ([D52](log.md#d52)), base
  implicit; each role's settings in `windows/roles/<role>.nix`; its apps from
  `packages/winget/<role>.txt` and the host's own `host-<host>.txt`, the same lists the
  register checks; what a list line cannot say (a unit id, a description, a pinned
  version, how a `manual:` name is installed) in `windows/packages.nix`. An app added to a
  role's list is installed by every host with the role at the next render; a host holds back
  a listed name it does not install yet (`hold`). The host's own settings beside Arch are its
  host file's ([D52](log.md#d52)).
- **Settings are typed data.** A registry value is `{ key, name, type, data }`, and its hive
  decides where it runs; a Script unit is a description, its context and
  `windows/units/<id>.ps1`, whose Get, Test and Set the unit runs as its script block, so the
  YAML holds data, not code; a null entry leaves a setting unmanaged.
- **Phases and scopes.** 00 debloat, 10 system, 20 user, 30 apps, 40 autostart, 50 ask,
  and one document per phase and scope: *machine* (every unit elevated, none
  writing HKCU) and *user* (pj's own context; never SYSTEM's); within a phase the
  machine document runs first. A dependency on a document that runs earlier is kept by that
  order; one on a document that runs later stops the render.
- **One render is the whole riced setup.** A small emitter writes the documents as block YAML
  with every string double-quoted. `manifest.json` lists the documents and the converge's
  scripts in order, and every file a build stages under `C:\ProgramData\dram` (documents,
  unit scripts, the generated look and Zebar pack, fonts, cursors, art, seal, files shared
  with Arch) with its sha256; `install/windows/fonts.lock` pins each font file, since Nix
  downloads nothing. No timestamps; the stager fills in `release` and `commit`. `dram.ps1`
  is built against this manifest, and keeps the render (the documents and the manifest)
  in `C:\ProgramData\dram\build\`.
- **Renders are committed** under `windows/build/<host>/` by `bin/render-windows.sh`: local
  Nix on Arch, the `nixos/nix` container on the Mac ([D26](log.md#d26)). `nix flake check` refuses a build
  that differs from its render (at evaluation); `bin/check.sh` §19 refuses one whose inputs
  changed (`inputs.json`, no Nix needed). The render itself refuses a plan it cannot trust:
  two units with one id, two units writing one registry value, a held or claimed
  name no list has, a `manual:` name nobody installs.
- **Applying.** `bin/push-windows.sh` puts a committed, current build on the PC and `dram.ps1`
  receives and applies it ([D64](log.md#d64): explicit pushes, channel `main` while the engine settles,
  then `stable`); `install/windows/apply-windows.sh` stages it and `converge.ps1` applies it directly,
  the way in until the push was proven. Both stage through `install/lib/windows-stage.sh`, each
  file from the source the manifest names, every sha256 checked on the Mac or Arch and again on
  the host. Both scopes run from pj's elevated SSH session, as before (HKCU is pj's).
- **Amends `decisions/0018`:** Windows is no longer "nothing"; it is
  `windowsConfigurations.<host>`.
- **Apps kept by hand** (amended 2026-10-13, [D144](log.md#d144)): a host may name apps installed by hand and
  kept out of the build (`windows.unmanaged`); `dram harvest` leaves them out.

## Consequences

- Arch is untouched: `pj@cabin`, `ranger@lantern` and `pj@campfire` (and the two WSL clones)
  evaluate to the same Home Manager generations before and after.
- The hand-written documents are gone; the first render held exactly their 98 units
  (`bin/winget-diff.rb`: same ids, resources, settings and directives, 0 differences; one
  `dependsOn` kept by phase order), and the same again after each Script unit's PowerShell
  moved to its own file; merged with the work roles and the WCH ban on the integration branch,
  all 121 units of their last state, the same way.
- Every change under `windows/`, to a `packages/winget` list or to a staged rice file needs
  `bin/render-windows.sh` and the build committed with it; `bin/check.sh` names the input
  that moved.
- Still the 0.2 schema and `PSDscResources` (archived, 2019): its modules come from
  PSGallery at apply time until they are vendored with `--module-path` or the units
  move to DSC 3's built-in resources. Six documents per converge instead of two.
- Not yet: DSC 3's settings resources, apps after a VM proof, the autostart phase as data,
  thermos's host file, the clone as a renderer, undo stored with each unit, and drift checks
  after Windows Update.

## As built

`windows/{default,options,lib,lower,render,packages}.nix`, `windows/roles/{base,desktop,
gaming,creator,dev}.nix`, `windows/hosts/cabin-win.nix`, `windows/units/*.ps1` (29 on
2026-10-12), `windows/build/cabin-win/`; `flake.nix` (`windowsConfigurations`,
`checks.*.windows-<host>`); `bin/render-windows.sh`, `bin/winget-diff.rb`;
`install/lib/windows-stage.sh` (manifest-driven, shared with `bin/push-windows.sh`),
`install/windows/fonts.lock`, `install/windows/cursors.notice`, `apply-windows.sh` and
`dram-windows/converge.ps1` on the build; `bin/check.sh` §19, `bin/check-register.py`,
`tests/push-windows.sh`; `docs/platforms/windows/README.md`.

## How it is checked

`bin/check.sh` §19 runs `bin/render-windows.sh --check`: each committed build is current, every input its `inputs.json` lists hashed again.
The same section runs `bin/gen-windows-look.py --check`, holds every Windows source and build file to ASCII, and runs `tests/push-windows.sh` against a stand-in ssh and scp.
`nix flake check` compares each committed build with its render, and `bin/check-register.py` (§15) fails a WinGetPackage unit no list names.
On the PC, `dram doctor` tests every document in its desired state.

## History

- 2026-10-12: accepted ([D63](log.md#d63)) and built the same day: the render, the per-file Script units, and `dram.ps1` with the push ([D140](log.md#d140)).
- 2026-10-12: the work roles and the WCH ban merged into the render.
- 2026-10-13: amended: apps kept by hand outside the build ([D144](log.md#d144)).

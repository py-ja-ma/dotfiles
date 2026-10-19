# Renderer

[Platforms](../../README.md) › [Windows](../README.md) › Renderer

The flake renders each Windows PC into a build: winget configuration documents, one per phase and scope, plus a manifest of every file the PC needs, each with its sha256.
The build is committed in `windows/build/<host>/`, so the Mac and the PC never need Nix to read it.
`winget configure` applies the documents on the PC, through [dram.ps1](dram-ps1.md).

| | |
|---|---|
| Code | `windows/default.nix`, `windows/options.nix`, `windows/lower.nix`, `windows/render.nix`, `windows/lib.nix`, `windows/packages.nix`, `windows/roles/`, `windows/hosts/`, `windows/units/`, `windows/build/`, `packages/winget/`, `bin/render-windows.sh`, `bin/winget-diff.rb` |
| Runs on | the Mac, in the `nixos/nix` container under Colima, or any machine with Nix; the build goes to cabin-win |
| Needs | Nix with flakes (or Docker and Colima on the Mac), python3, bsdtar, curl; on the PC, winget 1.28 or later with Microsoft.WinGet.DSC and PSDscResources; tested 2026-10 |
| Decided in | [decision 0020](../../../decisions/0020-windows-from-the-flake.md); roles on Windows: [decision log](../../../decisions/log.md#d52) |

## How it works

| What | Where |
|---|---|
| the host: its roles on one line, its address, apps held back, its own settings beside Arch | `windows/hosts/cabin-win.nix` |
| a role's settings: registry values, Script units, staged files, the converge's scripts | `windows/roles/<role>.nix`; base is implicit |
| a role's apps, one `winget:`, `msstore:` or `manual:` name per line, each with a register row | `packages/winget/<role>.txt`, `packages/winget/host-cabin-win.txt` |
| what a list line can't say: unit id, description, pinned version, how a manual app arrives | `windows/packages.nix` |
| each Script unit's PowerShell: Get, Test and Set | `windows/units/<id>.ps1` |
| the build, committed: six documents, `manifest.json`, `inputs.json` | `windows/build/cabin-win/` |
| the font files the pins stage, each with its sha256 | `install/windows/fonts.lock` |

`flake.nix` evaluates each host file with `lib.evalModules` over the option set, every role file and `windows/packages.nix`, as `windowsConfigurations.<host>`.
`windows/lower.nix` turns the host's roles, their lists and its own settings into units, and `windows/render.nix` writes them out: a document holds the units of one phase and one scope, quoted YAML in which every string is a JSON string.
Nothing on the Arch side reads `windows/`.

The render refuses what it can't trust: two units with one id or one registry value, a held or claimed name no list has, a manual name nobody installs.
It also refuses a dependency on a document that runs later, and a file staged where the scripts or `dram` keep state.
`bin/check.sh` §19 says when the build is stale: it hashes every file `inputs.json` lists and lists the directories it read again, without Nix.
`nix flake check` compares the build with a fresh render.

### Roles

A Windows role carries Arch's role name: its apps are `packages/winget/<role>.txt`, and its settings, if any, `windows/roles/<role>.nix`.
The settings that exist because a PC dual-boots with Arch (the UTC clock, Fast Startup off, no automatic device encryption, no firmware-pushed installers) are cabin-win's own, in its host file.

| Profile | Role on Windows | Native on Windows | In the WSL clone |
|---|---|---|---|
| every PC | base | privacy policies, the firewall, sshd, PowerShell 7, Windows Terminal, WireGuard, Proton Pass, the YubiKey tools, WSL | Arch's base userland |
| desktop | desktop | the Letterpress look, LibreWolf, Thunderbird with Proton Mail Bridge, Spotify, LocalSend, PowerToys, Notepad++, VLC, nomacs, SumatraPDF, Qalculate, WinDirStat | none |
| gaming | gaming, creator | Steam, Battle.net, the Epic and Ubisoft launchers, the EA app, PrismLauncher, the Jagex Launcher, WowUp; OBS with its virtual camera and background removal | none |
| work | office, college | LibreOffice, Zettlr, PDF Arranger, QPDF, calibre; KiCad, Octave, Typst, draw.io, Xournal++, Anki, Arduino CLI, PuTTY, Rufus | Taskwarrior, zk, hledger, TeX Live, the HDL toolchains |
| coding | dev | VSCodium with Open Remote - SSH | Arch's dev list: Podman, rustup, Go, Node LTS, npm, pnpm, uv, clang |
| homelab | sysadmin | Wireshark without Npcap, WireGuard, PuTTY, Rufus | nmap, tcpdump, mtr, iperf3, kubectl, helm, k9s, kind, talosctl |
| re-lab (thermos) | re-lab | usbipd-win, x64dbg, System Informer | Ghidra, radare2, pwntools, flashrom, openocd |
| chat | chat | Mumble, Halloy, TeamSpeak 3, Vesktop | none |

Never on Windows: the docker, builder, dump-kit, telephony and ml-cuda roles, and emulation ([decision log](../../../decisions/log.md#d62)).
Machine learning stays on cabin's Arch, where the GPU is.
git lives only in the clone: Git for Windows carries mingw-w64, whose committer of record is in China ([decision log](../../../decisions/log.md#d108)).
What each profile is for, on every OS: [Toolchain](../../toolchain/profiles/README.md).

## Change something, render, push

```sh
$EDITOR windows/hosts/cabin-win.nix             # or a role, a list, a unit
bin/render-windows.sh                           # Nix in the nixos/nix container on the Mac (about 5 s), or local Nix
git add -A windows packages install && git commit
bin/push-windows.sh cabin-win --apply           # the release to dram on the PC, then dram apply
```

- Add an app: its line in the role's list, its row in `packages/register.tsv`, then render.
  Every Windows host with that role installs it, unless the host's `hold` list names it; removing the line from `hold` installs it.
- Give a host a new role: its `packages/winget/<role>.txt`, then the role's name on the host's roles line, and `windows/roles/<role>.nix` if it has settings.
- Turn one role setting off on one host: `windows.role.<role>.registry.<id> = lib.mkForce null;` in the host file, and the same for `script`, `files` and `steps`; null leaves it unmanaged.
- A registry value is `{ description; key; name; type; data; }`, and its hive decides where it runs: `HKEY_LOCAL_MACHINE` in the machine documents, elevated; `HKEY_CURRENT_USER` in pj's.
- A Script unit is `{ description; elevated; }` plus `windows/units/<id>.ps1`: three functions run as the unit's script blocks, Test printing one bool, Windows PowerShell 5.1 and ASCII only.
  A unit that installs an app says `phase = "30"` and `package = "manual:<name>"`, so holding the name drops it.
  `dependsOn` may name a unit of a document that runs earlier.
- A font or the pointer: move `install/windows/fonts.pin` or `cursors.pin`; the render locks the fonts again before it renders, downloading them once into `~/.cache/dram/fonts`.

## The build

Phases run in order, each phase's documents first, machine then user, then its scripts, then the look on the signed-in desktop (`apply-live.ps1`):

| Phase | Documents | Scripts |
|---|---|---|
| 00 debloat | none | `debloat.ps1`: `converge.ps1` runs it only with `-Debloat`; `dram apply` unless `-Phase` leaves 00 out |
| 10 system | `10-machine.winget`: policies, privacy, fonts and cursors for every account, the lock screen, the dual-boot and Windows Update settings, DNS, the Secure Boot opt-outs, no WCH driver, the boot guard | none |
| 20 user | `20-user.winget`: pj's look, pointer, sounds, Explorer, privacy, prompt, keyboard | `account-picture.ps1` |
| 30 apps | `30-machine.winget` (winget, machine-wide), `30-user.winget` (the Store, VSCodium's Open Remote - SSH) | `icons.ps1`, `look.ps1` |
| 40 autostart | `40-machine.winget` (the case display's task), `40-user.winget` (Zebar's Run entry) | `autostart.ps1` |
| 50 ask | none | none; `dram apply` runs 50 only when it is named |

A machine document's units all run elevated and none writes HKCU; a user document runs in pj's own context, never as SYSTEM.

## The manifest

`windows/build/<host>/manifest.json`, format 1, is the contract `converge.ps1` and `dram.ps1` apply and the pushers stage from:

```json
{ "format": 1, "host": "cabin-win", "release": "unstaged", "commit": "unstaged",
  "roles": ["desktop", "chat", "gaming", ...],
  "documents": [ { "file": "10-machine.winget", "phase": "10", "scope": "machine", "units": ["..."] } ],
  "scripts":   [ { "file": "look.ps1", "phase": "30", "args": [], "dryRun": "-DryRun", "when": "always" } ],
  "files":     [ { "path": "fonts/MonaspaceXenon-Regular.otf", "sha256": "...", "source": "pin:install/windows/fonts.pin#monaspace" },
                 { "path": "build/10-machine.winget", "sha256": "...", "source": "render:windows/build/cabin-win/10-machine.winget" } ],
  "byHand":    [ { "name": "manual:nvidia-app", "role": "host-cabin-win", "how": "..." } ] }
```

`files[].path` is relative to `C:\ProgramData\dram`, and `source` is `repo:<path>`, `render:<path>` or `pin:<pin file>#<line>`.
The documents and the manifest live in `build\`, the scripts at the top; a document's or script's `file` is looked up in `build\` first.
One render is the whole setup: the documents, the unit scripts, the generated look and Zebar pack, the fonts, the cursors, the art, the seal and the files Arch shares, each by sha256.
`release` and `commit` are filled in when a build is staged (`git describe` and the commit), and say `unstaged` in the repo.
The push refuses what the PC would: an unknown phase or scope, a path outside `C:\ProgramData\dram` or into `dram`'s own records (`incoming`, `bin`, `build.previous`, `state.json`), a file in neither the render nor `files[]`.
`tests/fixtures/cabin-win.manifest.json` is a small manifest in this shape for the push test.

`inputs.json` lists every repo file the render read with its sha256, and the directories it read whole.
Markdown files are never inputs, so a README under `windows/` doesn't make the build stale.

## Merging an older branch

The hand-written `common.winget` and `cabin.winget` that lived in `install/windows/` are gone; the first render held their 121 units exactly.
Port a branch that still edits them.
Its apps go in the lists, and out of `hold` if the host should install them at once.
Its settings go in a role or the host file, and a Script unit's PowerShell in `windows/units/`.
Render, then compare the branch's version of the old files with the build:

```sh
git show <branch>:install/windows/cabin.winget >/tmp/cabin.winget
git show <branch>:install/windows/common.winget >/tmp/common.winget
bin/winget-diff.rb /tmp/common.winget /tmp/cabin.winget --build cabin-win   # 0 differences, or what is missing
```

## Not yet

- DSC 3's own resources instead of `PSDscResources`, which is archived upstream; until the modules are vendored, each converge loads `PSDscResources` and `Microsoft.WinGet.DSC` from PSGallery.
- Apps through the same resources only after a VM proof.
- The autostart phase as data instead of `autostart.ps1`'s lists.
- thermos' host file ([Windows](README.md#thermos)).
- The WSL clone rendered by the same machinery.

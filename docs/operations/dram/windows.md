# dram on Windows

[Operations](../README.md) › [dram CLI](README.md) › dram on Windows

A Windows PC runs `install/windows/dram-windows/dram.ps1` as `dram`, so `ssh cabin-win dram doctor` works as it does on Arch.
It takes a release that `bin/push-windows.sh` staged, checks every file by sha256, and converges the PC to it with `winget configure` and the release's scripts.

| | |
|---|---|
| Code | `install/windows/dram-windows/dram.ps1`; the shim `C:\ProgramData\dram\bin\dram.cmd` it writes |
| Runs on | cabin-win, since 2026-10-12; thermos once it has a host file |
| Needs | Windows PowerShell 5.1, winget (App Installer), Windows' OpenSSH server; an elevated session for `receive`, `update`, `apply` and `channel` |
| Decided in | [decision 0020](../../../decisions/0020-windows-from-the-flake.md), [D64](../../../decisions/log.md#d64) |

## How it works

The flake renders a Windows host into `windows/build/<host>/`: the winget documents and `manifest.json` ([Platforms › Windows](../../platforms/windows/README.md)).
`bin/push-windows.sh` on the Mac stages that render and every file its manifest lists in `C:\ProgramData\dram\incoming` ([Pushes](../releases/pushes.md)).
It then runs `receive` with the incoming copy of `dram.ps1`, so the first push installs `dram` and a release can change it.
`receive` checks each file's sha256 and parses each `.ps1` with PowerShell 5.1's own parser before it switches `C:\ProgramData\dram` to the release.
`apply` converges the PC phase by phase: each phase's documents through `winget configure`, then its scripts, then the look on the signed-in desktop (`apply-live.ps1`).

What differs from Arch:

- A release arrives as the render plus the files its manifest lists, because Windows has no git checkout.
- `apply` is `winget configure` and the scripts, phase by phase.
- `channel stable` makes `receive` refuse a push that is not a tagged release.
- `rollback` prints the way back and the uninstall lines, and runs none of them.
- There is no `switch`, `theme`, `pkgs` or `backup`.

## Use it

| Command | Does |
|---|---|
| `dram status` | the live release, its last apply, what the last doctor saw, the files against their sha256 |
| `dram version [-Json]` | version, build, commit, channel, received, applied, the render's own release and commit, Windows' build |
| `dram channel [stable\|main]` | which pushes `receive` takes: `stable` takes tagged releases only, `main` any commit; `main` is the default ([D64](../../../decisions/log.md#d64)) |
| `dram receive [-DryRun] [-Force]` | checks what the push staged and switches to it; `-Force` takes a push the channel or the computer name would refuse |
| `dram update [-Force]` | receives what is staged, then applies |
| `dram apply [-DryRun] [-Phase <list>]` | the converge, phase by phase: 00 debloat, 10 system, 20 user, 30 apps, 40 autostart; 50 ask runs only when named |
| `dram doctor [-Json] [-Brief]` | drift: `winget configure test` per document, the scripts' `-DryRun` lines that would change something, each file's sha256, the boot guard's task and the firmware order, the case panel's task, Zebar on the desktop |
| `dram harvest` | installed winget and Store packages that no document of the release declares; read-only |
| `dram rollback` | the release before: its apply plan, the `winget uninstall` lines going back would need, and the way back from the Mac |

`-DryRun` on `apply` runs `winget configure test` and the scripts' `-DryRun`, and applies nothing.
The output follows Arch's: `[ok]`, `[!]` with a `fix:` line, `[x]`, `==>`.
Exit 0 is success, 1 a failure (for `doctor`, a warning), 2 bad usage.
Options are spelled `-Name` or `--name`.
`doctor` skips its elevated checks in a session that is not elevated.
`apply` refuses to run as SYSTEM, because the user-scope documents write HKCU and winget is the signed-in user's App Installer.

### C:\ProgramData\dram

| Path | What |
|---|---|
| `dram.ps1`, `bin\dram.cmd` | the engine and its shim; `bin` is on the machine `PATH`, where cmd.exe, which Windows' OpenSSH runs, finds `dram` |
| `build\` | the live render: `manifest.json` and the documents, plus `packages.tsv` and `push.json` from the push, and `files.sha256` |
| `build.previous\` | the render before, which `rollback` reads; a second push of the same commit keeps it |
| `state.json` | the release's version, build and commit, when it was received and applied, the channel, the last doctor's result |
| `incoming\` | what a push staged, until a receive takes it |
| the release's files | scripts at the top, `units\`, `fonts\`, `cursors\`, `letterpress\`, `avatar\`, the files Arch shares |
| everything else | the scripts' own state (logs, `icons\`, `start-tidy\`, `cache\`, the WSL bundle), which a receive leaves alone |

A receive copies what arrived and deletes what the release before listed and this one does not.
A font dropped from `install/windows/fonts.pin` leaves the folder, so the fonts unit removes it from Windows too.
`install/windows/apply-windows.sh` writes the same layout, without `dram`'s own records.

## When it breaks

| Symptom | Check | Fix |
|---|---|---|
| cmd.exe says `dram` is not recognized | the ssh session started before the `PATH` entry existed | `ssh cabin-win C:\ProgramData\dram\bin\dram.cmd version -Json`, then a new session |
| `receive` refuses the push | the channel is `stable` and the push is not a tagged release, or the computer name differs from the host file | push a release, or `dram receive -Force` |
| a script fails to parse | `receive` names the file and the first parse error | fix the script on the Mac and push again: nothing switched |
| `doctor` reports drift | `dram doctor` lists the units out of state and the scripts' would-change lines | `dram apply`, or the phase named with `-Phase` |

These rules keep it working, each learned on cabin-win:

- Windows' OpenSSH runs cmd.exe, so a push sends plain cmd lines and one `powershell -File …` with nothing after it: `;` is no separator there, and the rest once became `wsl.ps1`'s arguments.
- The scripts are Windows PowerShell 5.1 and ASCII, with no `??`, ternary or `&&`; `bin/check.sh` §19 fails on a non-ASCII byte.
- A font named `EBGaramond[wght].ttf` goes through .NET or `-LiteralPath`, because `-Path` reads the brackets as wildcards.
- Each `.ps1` of a release parses before it is switched to: a merge once left `look.ps1` a brace short.
- The PC stays awake while `apply` runs (`SetThreadExecutionState`), and `apply` exits 0 or 1, not winget's own code, because ssh hands the Mac only the low byte.

## Proven

On 2026-10-12, `bin/push-windows.sh cabin-win --apply` delivered v2026.10.27.
`receive` checked 187 files by sha256 and parsed 40 scripts, and `apply` ran phases 00 to 40 with exit 0.
`dram doctor` then found the six documents in state and no drift.

To prove a new PC the same way, from the Mac, signed in at the PC with its OpenSSH up and the render committed:

1. `install/windows/apply-windows.sh --dry-run`, then without `--dry-run`: the converge from the render, without `dram`.
2. `bin/push-windows.sh <host> --dry-run`: `dram receive -DryRun` reports every sha256 and parse, and "dry run: nothing switched".
3. `bin/push-windows.sh <host> --apply --dry-run`: received for real, then what converging would change.
4. `ssh <host> dram version -Json` prints one JSON object.
5. `bin/push-windows.sh <host> --apply`, then `ssh <host> dram doctor -Json` shows `"drift":0`.
6. Change a role line in `windows/hosts/<host>.nix`, render, commit and push with `--apply`: the app comes or goes, `dram rollback` prints its uninstall line, and `dram harvest` lists what no document declares.

## Limits

- `dram.ps1` has no PowerShell to run on the Mac: `tests/push-windows.sh` plays its receive with a stand-in.
- Until the modules are vendored, each converge loads `PSDscResources` and `Microsoft.WinGet.DSC` from PSGallery ([decision 0020](../../../decisions/0020-windows-from-the-flake.md)).
- thermos has no host file yet (2026-10-13), so cabin-win is the only Windows host `dram` runs on.

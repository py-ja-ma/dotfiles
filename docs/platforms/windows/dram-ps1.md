# dram.ps1

[Platforms](../../README.md) › [Windows](../README.md) › dram.ps1

`install/windows/dram-windows/dram.ps1` is `dram` on a Windows PC: it receives a release pushed from the Mac, applies it phase by phase, reports drift and shows the way back.
Its commands, options and exit codes mirror Arch's `dram`, so `ssh cabin-win dram doctor` works as it does on Arch.
`install/windows/apply-windows.sh` with `converge.ps1` is the other way in: it stages the same build and converges it directly, without `dram`'s records.

| | |
|---|---|
| Code | `install/windows/dram-windows/dram.ps1`, `converge.ps1`, `apply-live.ps1`, `install/windows/apply-windows.sh` |
| Runs on | cabin-win; thermos after its reset |
| Needs | Windows PowerShell 5.1, winget 1.28 or later with `winget configure`, Task Scheduler, Windows' OpenSSH server with the Mac's key; tested on cabin-win 2026-10-12 |
| Decided in | [decision 0020](../../../decisions/0020-windows-from-the-flake.md); channels: [decision log](../../../decisions/log.md#d64) |

## How it works

On the Mac, `bin/push-windows.sh <host>` stages the committed render and every file its manifest lists in `C:\ProgramData\dram\incoming`, sending only what changed, then runs the receive with the incoming copy of `dram.ps1`.
The receive checks every file's sha256 against the manifest, parses every `.ps1` with PowerShell 5.1's own parser, and only then switches `C:\ProgramData\dram` to the release.
So the first push installs `dram`, and a release can change it.
The push itself, its address rules and its checks are on [Pushes](../../operations/releases/pushes.md).

`apply` converges the PC to the live release: each phase's documents through `winget configure --accept-configuration-agreements --disable-interactivity`, machine before user, then the phase's scripts, then `apply-live.ps1`, which makes the signed-in desktop reread what changed.
The phases and what each holds are on the [renderer](renderer.md#the-build) page.

## On Windows

| Command | Does |
|---|---|
| `dram status` | the live release, its last apply, what the last doctor saw, the files against their sha256 |
| `dram version [-Json]` | version, build, commit, channel, received, applied, the render's own release and commit, Windows' build |
| `dram channel [stable\|main]` | which pushes `receive` takes: `stable` tagged releases only, `main` any commit pushed from the Mac (the default) |
| `dram receive [-DryRun] [-Force]` | checks what the push staged and switches to it; `-Force` takes a push the channel or the PC's name would refuse |
| `dram update [-Force]` | receives what is staged, after a `--dry-run` push, then applies |
| `dram apply [-DryRun] [-Phase <list>]` | the converge, phase by phase: 00 debloat, 10 system, 20 user, 30 apps, 40 autostart; 50 ask only when named; `-DryRun` runs `winget configure test` and the scripts' own dry runs |
| `dram doctor [-Json] [-Brief]` | drift: `winget configure test` per document, the scripts' dry-run lines that would change something, every file's sha256, the boot guard's task and the firmware order, the case panel's task, Zebar on the signed-in desktop; exit 1 on a warning |
| `dram harvest` | installed winget and Store packages that no document of the release declares, minus the host's `unmanaged` list; read-only |
| `dram rollback` | the release before: its apply plan, what going back would undo (the `winget uninstall` lines printed, never run), and the way back from the Mac |

Output is Arch's: `[ok]`, `[!]` with a `fix:` line, `[x]`, `==>`.
Exit 0 is ok, 1 is failed (for `doctor`, a warning), 2 is bad usage.
Options are spelled `-Name` or `--name`.
`receive`, `update`, `apply` and `channel` need an elevated PowerShell, which an administrator's ssh login is; `doctor` skips its elevated checks without one.
`apply` never runs as SYSTEM: the user documents write HKCU, and winget is the signed-in user's App Installer.
What differs from Arch: a release arrives as the flake's render plus the files its manifest lists, not a git bundle, since Windows has no git ([decision log](../../../decisions/log.md#d108)).
`rollback` only prints, and there is no `switch`, `theme`, `pkgs` or `backup`.

## C:\ProgramData\dram

| Path | What |
|---|---|
| `dram.ps1`, `bin\dram.cmd` | the engine and its shim; `bin` is on the machine PATH, so cmd.exe, which Windows' OpenSSH runs, finds `dram` |
| `build\` | the live render: `manifest.json` and the documents, plus what the push adds: `packages.tsv` (the winget and Store ids the documents declare) and `push.json` (the commit pushed); `files.sha256`, every file the release put here |
| `build.previous\` | the render before, which `rollback` reads; a push of the same commit again keeps it |
| `state.json` | version, build, commit, tagged, received; the last apply (version, commit, time, exit code, user, phases); the previous release; the channel; the last doctor's warnings and drift; the render's own release and commit |
| `incoming\` | what the push staged, until a receive takes it |
| the release's files | scripts at the top, where their scheduled tasks find them; `units\`, `fonts\`, `cursors\`, `letterpress\`, `avatar\`, the files Arch shares |
| everything else | the scripts' own state: logs, `icons\`, `start-tidy\`, `cache\`, `fonts.installed`, the WSL bundle; a receive never touches it |

A receive copies what arrived, deletes what the release before listed and this one doesn't, and nothing else.
A font dropped from `install/windows/fonts.pin` leaves the folder, so the fonts unit removes it from Windows too.
`apply-windows.sh` writes the same layout, copying the render over `build\` without `dram`'s records.

## Rules it keeps

- Windows' OpenSSH runs cmd.exe, so the push sends plain cmd lines and one `powershell -File …` with nothing after it.
  `;` is no separator there: on 2026-10-12 the rest of such a line became `wsl.ps1`'s arguments, and a dry run ran for real.
- Windows PowerShell 5.1 and ASCII only: no `??`, ternary or `&&`; a font named `EBGaramond[wght].ttf` goes through .NET or `-LiteralPath`, never `-Path`, which reads the brackets as wildcards.
- Every `.ps1` of a release parses before the receive switches to it, and every script an apply starts parses before the first one runs: a merge once left `look.ps1` a brace short.
- The PC stays awake while `apply` runs (`SetThreadExecutionState`): a sleep cut an SSH session mid-install on 2026-10-12.
- `apply` exits 0 or 1, never winget's own code, since ssh hands the Mac only the exit code's low byte.

## Use it

Bring a PC under `dram`, with someone signed in at it, its OpenSSH up and the build committed:

1. `install/windows/apply-windows.sh --dry-run`, then without `--dry-run`: the converge from the render, every document in its desired state.
2. `bin/push-windows.sh cabin-win --dry-run`: the counts, then `dram receive -DryRun` on the PC, every sha256 checked, every script parsed, "dry run: nothing switched".
3. `bin/push-windows.sh cabin-win --apply --dry-run`: received for real, which installs `dram`, then what converging would change.
4. `ssh cabin-win dram version -Json`: one JSON object.
   If cmd.exe says `dram` is not recognized, that ssh session predates the PATH entry: `ssh cabin-win C:\ProgramData\dram\bin\dram.cmd version -Json`.
5. `bin/push-windows.sh cabin-win --apply`: the converge; then `ssh cabin-win dram doctor -Json` shows `"drift":0`, and `ssh cabin-win dram status` the release.
6. A role line changed in `windows/hosts/cabin-win.nix`, rendered, committed and pushed with `--apply`: the app comes or goes, `ssh cabin-win dram rollback` prints its uninstall line, and `ssh cabin-win dram harvest` lists what no document declares.

For `ssh cabin-win …` by hand, the Mac's own `~/.ssh/config` (not in this repo) holds a block ahead of any shared `Host *` that multiplexes; one master connection to cabin's Arch must never carry a Windows command:

```
Host cabin-win
    HostName cabin
    User pj
    HostKeyAlias cabin-win
    ControlMaster no
    ControlPath none
```

## When it breaks

| Symptom | Check | Fix |
|---|---|---|
| `dram` is not recognized over ssh | the session started before the PATH entry | `C:\ProgramData\dram\bin\dram.cmd`, or a new ssh session |
| the receive refuses a push | its message names the file, the sha256 or the channel | render and commit again, `dram channel main`, or `-Force` for a push from another branch |
| `dram doctor` reports drift after a Windows feature update | the documents named out of state | `dram apply`; the update brought defaults back |
| the push stops on the Mac with a stale build | `bin/render-windows.sh --check` | render, commit, push again |

## Limits

- `dram rollback` prints the way back and the uninstall lines; it never uninstalls.
- The converge still loads `PSDscResources` and `Microsoft.WinGet.DSC` from PSGallery ([renderer](renderer.md#not-yet)).

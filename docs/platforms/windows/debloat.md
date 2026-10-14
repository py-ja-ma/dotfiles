# Debloat and autostart

[Platforms](../../README.md) › [Windows](../README.md) › Debloat and autostart

Two declared lists keep a Windows PC clean: what must not be installed, and what may start by itself.
`debloat.ps1` removes everything on the first list that is still there, and `autostart.ps1` switches off everything that starts by itself unless the second list names it.
Both run again on every converge and change only what drifted.
The privacy settings sit beside them in the base role, as Microsoft's own policies.

| | |
|---|---|
| Code | `install/windows/dram-windows/debloat.ps1`, `install/windows/dram-windows/autostart.ps1`, `windows/roles/base.nix`, the units `windows/units/{edge-policies,explorer-quiet,privacy-user,sounds-off,windows-ai-off,windows-ai-fabric-manual}.ps1` |
| Runs on | cabin-win; every Windows PC this repo renders |
| Needs | Windows 11 Pro, winget, the Appx cmdlets, an administrator; tested on cabin-win 2026-10-12 |
| Decided in | [decision log](../../../decisions/log.md#d59) (the lists), [decision log](../../../decisions/log.md#d134) (never WinUtil), [decision log](../../../decisions/log.md#d136) (no AutoHotkey) |

## How it works

### What must not be there

`debloat.ps1` is phase 00 of the build: `dram apply` runs it unless `-Phase` leaves 00 out, and `converge.ps1` only with `-Debloat`.
It removes what it declares for every user and from the image new users get:

| Kind | What |
|---|---|
| Windows' consumer apps | Clipchamp, the Bing apps, Copilot, Dev Home, Feedback Hub, Family, Maps, Movies & TV, Office Hub, Outlook, Phone Link, Power Automate, Quick Assist, Solitaire, Sticky Notes, Teams, To Do, the widgets board, Cross Device; and Clock, Sound Recorder, Media Player and Camera, unused here, whose Store icons can't take the Letterpress tint |
| MSI's bundle | MSI Center and its game bar, Norton 360, AiPPT, Dropbox, Chrome, Google Play Games, AIDA64, CPU-Z: the firmware hands them to a fresh install through WPBT |
| swapped or dropped apps | XSplit VCam (replaced by OBS's virtual camera), qBittorrent (Transmission), File Converter, GeForce NOW, EVGA Precision X1, Antec's iUnity (`case-display.ps1` drives the panel instead), AutoHotkey |
| what no uninstaller removes | MSI Center's services and its `MsIo64` driver, which gives any program raw port and physical-memory access; EVGA's kernel driver; Norton's remains after its restart |

Kept: the Store, winget, Terminal, Notepad, Paint, Photos, Snipping Tool, Calculator, Game Bar and the Xbox sign-in pieces games use, the codecs, Edge, the drivers and their consoles.
A Win32 uninstaller that only works with clicks, Norton's, opens on the signed-in user's desktop and is reported.
An NSIS uninstaller runs in place and silent, for at most two minutes: winget hands it to a copy in `%TEMP%` that returns at once, which left qBittorrent installed on 2026-10-12.
`DisableWpbtExecution`, in cabin-win's host file, stops Windows running anything a firmware table hands it, whatever the BIOS says; turn off "MSI Driver Utility Installer" in the BIOS too.
The log is `debloat.log` beside the script.

### What may start by itself

`autostart.ps1` is phase 40, run as the user whose sign-in it governs.
Every entry in the Run keys and the Startup folders, every packaged app's startup task and every third-party task started by sign-in, boot, unlock or connect is switched off unless it is declared:

| Allowed | Why |
|---|---|
| `SecurityHealth` | Windows Security's tray icon |
| `RtkAudUService` | Realtek audio: jack detection and its console |
| PowerToys' logon task | its shortcuts and FancyZones need it running |
| `Zebar` | the masthead across the top of each monitor |
| services: the NVIDIA driver's, Realtek's, AMD's chipset drivers, `sshd`, Riot Vanguard's `vgc` | the drivers; how the Mac converges the PC; League won't start without Vanguard |
| tasks: Edge's and the NVIDIA App's updaters, `dram-*` | updaters, and this repo's own jobs |

Run keys and Startup folders use the switch Task Manager's Startup tab uses, so nothing is deleted, and an app that writes its entry back stays off.
PowerToys and Proton Mail Bridge flip that switch back themselves, so they are set off in their own settings.
Third-party services that start automatically and aren't declared go to Manual; one without a readable signature is reported, not changed.
Steam is off on Windows and starts when a game does.
RunOnce entries, an installer finishing its job, are left alone.
Each run writes `autostart-report.csv`: everything that can start by itself, and its state.

### Privacy

The base role sets Microsoft's own switches, each documented to work on Pro:

| Setting | What it does |
|---|---|
| diagnostic data | "required" only |
| activity history | neither kept nor uploaded |
| suggestions | no advertising ID, tailored experiences, web results or suggestions in Start, and no silently installed apps |
| Windows AI | off by policy: Recall removed at the next restart, no snapshots, no Click to Do, no AI in Notepad or Paint, the AI Fabric service on Manual |
| delivery | updates and Store apps from Microsoft alone, never from or for other PCs |
| device metadata | no companion apps fetched for new hardware, the way MSI's and Lenovo's helpers arrive; drivers still come from Windows Update |
| Edge | stays; only its preload, nags and data sharing go |
| network | LLMNR off, as on Arch |
| Defender | blocks potentially unwanted apps |
| PowerShell 7 | no telemetry |

The desktop role adds the quiet: no event sounds (`sounds-off`), and Start and Explorer without suggestions or news (`explorer-quiet`).

Nothing is uninstalled for these, and Windows AI goes by policy instead of by removing its packages: Click to Do lives in the CoreAI package, and removing that has left Explorer on its old ribbon.
No service is touched except the AI Fabric's, and Defender keeps its cloud protection as shipped.

## Use it

```powershell
powershell -ExecutionPolicy Bypass -File C:\ProgramData\dram\debloat.ps1 -DryRun     # what it would remove
powershell -ExecutionPolicy Bypass -File C:\ProgramData\dram\autostart.ps1 -DryRun   # what it would switch off
```

From the Mac, `ssh cabin-win dram apply -Phase debloat,autostart` runs both, and `dram doctor` lists their dry-run lines as drift.
To keep an app, add it to `$AllowStart` or `$AllowServices` in `autostart.ps1`, or take it off `$Appx` or `$Win32` in `debloat.ps1`, then render and push.

## When it breaks

| Symptom | Check | Fix |
|---|---|---|
| an app starts at sign-in again | `autostart-report.csv` | run a converge; if the app flips its own switch, set it off in its settings |
| an uninstaller sits waiting | the signed-in desktop | answer it there; it was opened there because it wants clicks |
| something is still installed after `debloat.ps1` | `debloat.log` | Norton's remains go at the first run after its restart |

## Limits

- Never WinUtil, Chris Titus Tech's tool, on a PC this repo manages: its reset deletes every policy the build sets, the firmware block included, and its services tweak once set Vanguard's `vgc` to Manual. Its useful items are in the build.
- Riot Vanguard's kernel driver loads at boot whatever the lists say; only its tray icon is off.
- A Windows feature update can bring an app or a default back; the next converge removes it again and says so.

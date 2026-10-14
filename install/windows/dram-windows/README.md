# dram-windows

[Platforms](../../../docs/platforms/README.md) › [Windows](../../../docs/platforms/windows/README.md) › [dram.ps1](../../../docs/platforms/windows/dram-ps1.md)

The PowerShell that runs on a Windows PC: `dram.ps1`, which receives and applies a release, the converge and its phase scripts, and the tasks the build installs.
Each is a Windows PowerShell 5.1 script in ASCII, safe to run again, and every one that changes something takes `-DryRun`.

| | |
|---|---|
| Needs | Windows 11 with Windows PowerShell 5.1, winget 1.28 or later, Task Scheduler, an administrator; tested on cabin-win 2026-10-12 |
| Copy alone | `debloat.ps1`, `autostart.ps1` and `boot-guard.ps1` yes, after editing their lists; `dram.ps1` and `converge.ps1` need a build in this repo's manifest format |
| License | MIT |

## What it needs

- `C:\ProgramData\dram`, where `bin/push-windows.sh` or `install/windows/apply-windows.sh` stages a release: the render in `build\`, the unit scripts in `units\`, and every file the manifest lists.
- winget's configuration feature with the `Microsoft.WinGet.DSC` and `PSDscResources` modules, which the converge loads from PSGallery.
- Not needed: PowerShell 7, git, or any tweak suite.

## Copy it alone

1. Copy the script and read its header: what it declares and what it changes.
2. Edit its lists: `$Appx` and `$Win32` in `debloat.ps1`, `$AllowStart` and `$AllowServices` in `autostart.ps1`.
3. Run it elevated with `-DryRun`: `powershell -ExecutionPolicy Bypass -File .\debloat.ps1 -DryRun`.
4. Run it without `-DryRun`; its log lands beside it.

## How it is wired here

| Script | Run by | What it does | Branch |
|---|---|---|---|
| `dram.ps1` | the push, then you over ssh | `dram` on Windows: status, version, channel, receive, update, apply, doctor, harvest, rollback | [dram.ps1](../../../docs/platforms/windows/dram-ps1.md) |
| `converge.ps1` | `install/windows/apply-windows.sh` | applies a staged build phase by phase, without `dram`'s records | [dram.ps1](../../../docs/platforms/windows/dram-ps1.md) |
| `apply-live.ps1` | the converge, on the signed-in desktop | makes the desktop reread the pointer, keyboard toggle, colors, fonts, refresh rates, the taskbar's auto-hide and the masthead | [dram.ps1](../../../docs/platforms/windows/dram-ps1.md) |
| `firstlogon.ps1` | the answer file, at the first sign-in | Fast Startup and hibernation off, the UTC clock, privacy defaults, Steam and Proton Pass | [Windows](../../../docs/platforms/windows/README.md#install-a-windows-pc) |
| `debloat.ps1` | phase 00 | removes the declared apps and what their uninstallers leave | [Debloat](../../../docs/platforms/windows/debloat.md) |
| `autostart.ps1` | phase 40 | switches off whatever starts by itself unless it is declared | [Debloat](../../../docs/platforms/windows/debloat.md) |
| `boot-guard.ps1` | the SYSTEM task `\dram\boot-guard`, at every start | rEFInd first, Windows Boot Manager last in the firmware's order | [Boot guard](../../../docs/platforms/windows/boot-guard.md) |
| `own-esp.ps1` | you, once | gives Windows its own ESP on its own disk, in place | [Boot guard](../../../docs/platforms/windows/boot-guard.md) |
| `case-display.ps1` | the SYSTEM task `dram-case-display`, from startup | cabin's case panel: the CPU and GPU temperatures | [Case display](../../../pkgs/dram-case-display/README.md) |
| `wsl.ps1` | you, once per clone | builds the Arch clone in WSL 2 from the staged bundle | [WSL](../../../docs/platforms/wsl/README.md) |
| `look.ps1`, `icons.ps1`, `account-picture.ps1` | phases 20 and 30 | the Letterpress look inside the apps, the tinted icons, the "pj" seal at sign-in | [Design](../../../docs/design/README.md) |

The renderer stages each script the build needs, by name, with its sha256; `dram.ps1`, `firstlogon.ps1`, `own-esp.ps1` and `wsl.ps1` are not part of a build.
The receive parses every `.ps1` of a release with PowerShell 5.1's own parser before it switches, and `bin/check.sh` §19 fails a non-ASCII byte in any of them.
Windows' OpenSSH runs cmd.exe, so a remote call is `powershell -File <script>` with nothing after it: `;` is no separator there.

## License

MIT, Patrick Jordan.

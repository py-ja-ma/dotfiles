# windows

[Platforms](../../docs/platforms/README.md) › [Windows](../../docs/platforms/windows/README.md)

Everything a Windows PC takes from this repo besides its rendered build: the answer file that installs it, the scripts that converge it, the WSL clone's settings, and the pinned fonts and pointer.
The build itself is rendered from `windows/` ([renderer](../../docs/platforms/windows/renderer.md)).

| | |
|---|---|
| Needs | a Windows 11 ISO and a removable USB stick for the install; Windows' OpenSSH and an administrator login for the converge; bash, python3, curl and bsdtar on the Mac or Arch; tested on cabin-win 2026-10-12 |
| Copy alone | the answer file yes, after changing its names and locale; `apply-windows.sh` needs a build in this repo's manifest format |
| License | MIT; `upstream/` holds third-party theme sources under their own licenses |

## What it needs

- For the install: `autounattend.xml` and the `dram-windows` folder on a removable FAT32 stick beside a Windows 11 ISO; Setup reads an answer file only from a removable drive.
- For the converge: a committed build in `windows/build/<host>/`, the staging library `install/lib/windows-stage.sh`, and Windows' OpenSSH with the Mac's key in `C:\ProgramData\ssh\administrators_authorized_keys`.
- Not needed: Nix on the Mac or on the PC; the build is committed.

## Copy it alone

1. Copy `autounattend.xml` and `dram-windows/firstlogon.ps1`.
2. Change the computer name (CABIN-WIN), the time zone (Eastern Standard Time), the local administrator (pj) and the locales; the first-logon script's app list is at its section 3.
3. Put both on a removable FAT32 stick, with `firstlogon.ps1` in a `dram-windows` folder, and boot the Windows ISO beside it.
4. Setup asks only for the edition and the disk; the first sign-in runs `firstlogon.ps1`, whose log is `C:\Windows\Setup\Scripts\dram-windows\firstlogon.log`.

## How it is wired here

| File | What it does | Branch |
|---|---|---|
| `autounattend.xml` | installs Windows 11: English (US), the name, US Eastern time, the UTC clock, Fast Startup off, no automatic device encryption, the local administrator pj, one automatic sign-in that runs `firstlogon.ps1` | [Windows](../../docs/platforms/windows/README.md#install-a-windows-pc) |
| `dram-windows/` | `dram.ps1`, the converge and its phase scripts ([dram-windows/README.md](dram-windows/README.md)) | [dram.ps1](../../docs/platforms/windows/dram-ps1.md) |
| `apply-windows.sh` | stages a build over SSH from the Mac or Arch, checks every file's sha256, and runs `converge.ps1` on the PC | [dram.ps1](../../docs/platforms/windows/dram-ps1.md) |
| `wslconfig` | the PC's `%UserProfile%\.wslconfig` for the WSL clone, one host's sizes per `#:` row | [WSL](../../docs/platforms/wsl/README.md) |
| `fonts.pin`, `fonts.lock` | the house fonts the build stages, pinned by sha256 | [Design](../../docs/design/README.md) |
| `cursors.pin`, `cursors.notice` | Arch's Adwaita pointer for Windows, pinned, with its license notice | [Design](../../docs/design/README.md) |
| `letterpress/` | the generated per-app themes and the Zebar pack, written by `bin/gen-windows-look.py` | [Design](../../docs/design/README.md) |
| `upstream/` | the third-party theme sources the generator starts from | [Design](../../docs/design/README.md) |

`tests/windows-vm.sh` installs the ISO with the answer file in a VM on cabin first; its replacement of the windowsPE block between the `dram:pe` markers is the only change it makes.
`tests/push-windows.sh` checks `apply-windows.sh` and the push against a stand-in ssh, in `bin/check.sh` §19.
`letterpress/` takes no hand-written file: `bin/gen-windows-look.py --check` fails on any file it didn't write, and a plain run deletes it.

## License

MIT, Patrick Jordan, for what I wrote here.
`upstream/` holds Mumble's dark theme (Unlicense, with its LICENSE), and Notepad++'s and Wireshark's default theme files, under the GPL as their projects ship them.

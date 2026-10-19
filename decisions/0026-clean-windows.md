# 0026: Clean Windows, a declared list of what it must not have

[Platforms › Windows](../docs/platforms/windows/README.md) · accepted 2026-10-12

Windows' bloat and autostarts are removed by two scripts that declare what must not be there, run by every converge, never by a cleanup tool run by hand; the cost is two lists to keep current.

## Context

cabin's Windows 11 came with two sources of bloat: Windows' own consumer apps, and the bundle MSI's firmware pushes on a fresh install through WPBT (MSI Center, Norton, AiPPT, Dropbox, Chrome, Google Play Games, AIDA64, CPU-Z).
Apps switch their autostart back on between converges, and some uninstallers work only with clicks.
WinUtil, the common tool for this, has a Reset that deletes `HKLM\SOFTWARE\Policies`, and its services tweak once set Vanguard's `vgc` service to Manual.
Riot Vanguard, and the anti-cheat of other games I play, treat injectors and some automation tools as cheats.

## Decision

- `install/windows/dram-windows/debloat.ps1` declares the apps cabin's Windows must not have; they are removed for every user and from the image new users get ([D59](log.md#d59)).
  What no uninstaller removes is declared as leftovers and removed directly; a click-only uninstaller is opened on the signed-in desktop and reported.
- `install/windows/dram-windows/autostart.ps1` declares what may start by itself.
  Everything else in the Run keys, the Startup folders, packaged apps' startup tasks and third-party tasks started by sign-in, boot, unlock or connect is switched off, with the switch Task Manager uses, and undeclared third-party automatic services go to Manual ([D59](log.md#d59)).
- Steam does not start at Windows sign-in ([D51](log.md#d51)).
- WinUtil is never run on cabin-win; its useful items are units of the build instead ([D134](log.md#d134)).
- No injectors or shell patchers: Windhawk is a register `fail`, because its engine injects into every process and Vanguard errors beside it ([D133](log.md#d133)).
- AutoHotkey is off cabin-win: ARC Raiders' anti-cheat counts a running AutoHotkey as a detection, and nothing in the build uses it ([D136](log.md#d136)).
- WCH's USB-serial driver never reaches cabin-win: the build denies the device IDs of the CH340, CH340K, CH341, CH342, CH343 and CH9102 (vendor 1A86).
  thermos keeps them for the re-lab profile through usbipd, and Arch's kernel driver serves them ([D142](log.md#d142)).
- Instances of the list: Clock, Sound Recorder, Media Player and Camera removed ([D139](log.md#d139)); GeForce NOW dropped ([D100](log.md#d100)); Antec's iUnity removed, since the case display runs its own code ([0027](0027-case-display.md)).

## Alternatives

| Option | Why not |
|---|---|
| WinUtil, run by hand | its Reset deletes every policy the build sets, the firmware block included, and its services tweak once set Vanguard's service to Manual |
| Deleting the Run entries | apps write them back; the switch Task Manager uses keeps them off and deletes nothing |
| Windhawk mods for the shell | its engine injects into every process, beside Vanguard |
| `ExcludeWUDriversInQualityUpdate` to keep WCH's driver out | it blocks the NVIDIA driver too; a ban by device ID is narrower |

## Consequences

- An app that writes its autostart back stays off; PowerToys and Proton Mail Bridge flip their own switch, so they are set in their own settings.
- A new WCH product needs a new entry in the deny list.
- Defender runs in its normal mode once Norton is gone.
- Each run of `autostart.ps1` writes `autostart-report.csv`, everything that can start by itself and its state.

## How it is checked

On the PC, `dram doctor` runs `debloat.ps1` and `autostart.ps1` with `-DryRun` and warns when either would change something.
The deny list and the policies are registry units that `dram doctor` tests in their desired state.
`bin/check.sh` §15 keeps Windhawk and AutoHotkey as `fail` rows: a list that declares either fails the check.

## History

- 2026-10-12: accepted ([D51](log.md#d51), [D59](log.md#d59)); WinUtil, Windhawk and AutoHotkey ruled out the same day ([D133](log.md#d133), [D134](log.md#d134), [D136](log.md#d136)).
- 2026-10-12: the WCH ban built ([D142](log.md#d142)); four unused Store apps removed ([D139](log.md#d139)).
- 2026-10-19: League and Vanguard removed from cabin-win ([D149](log.md#d149)); Vanguard's `vgc` service leaves `autostart.ps1`'s allowed services.

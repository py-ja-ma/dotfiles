# 0027: The case display runs my own code on both OSes

[Design › Shell & bars](../docs/design/shell-and-bars/README.md) · accepted 2026-10-12

The temperature panel on cabin's case is driven by a small daemon of my own on Arch and a SYSTEM task on Windows, never by the vendor's app; the cost is a USB protocol to maintain, and a kernel driver of unclear origin on Windows for the CPU reading.

## Context

cabin's case, an Antec Flux Pro (Noctua edition), has a two-field seven-segment panel on an internal USB header (`2022:0522`) with no sensors of its own.
A program must send both temperatures about once a second as one 12-byte frame, or the panel stays dark, and it blanks itself a few seconds after the frames stop.
Antec's iUnity is Windows-only and proprietary: 175 MB with a driver, a firmware updater and a service anyone may stop, and reported to freeze.
Nothing in Arch's repos drives the panel, and `nvidia-open` exposes no hwmon sensor, so only NVML reads the RTX 3080 Ti.

## Decision

- Arch: `pkgs/dram-case-display/`, a `[dram]` package of my own ([D123](log.md#d123)).
  It is Python with the standard library and `ctypes`: `Tctl` from k10temp and the GPU through NVML, written to the panel through usbfs.
  A udev rule starts it, and it runs as a dynamic user in the panel's group, with no capabilities; `packages/host-cabin.txt` lists it.
- Windows: `install/windows/dram-windows/case-display.ps1`, run by the SYSTEM task `dram-case-display` from startup (the unit `case-display-task`).
  It reads both temperatures from LibreHardwareMonitor's library (pinned by the unit `case-display-lhm`), the GPU from `nvidia-smi` when the library has none, and sends the frame as a HID output report.
- PawnIO, the kernel driver LibreHardwareMonitor needs for the CPU temperature, is accepted as `pass-flag` ([D124](log.md#d124)).
  Its license file and its maintainer's location are unclear and its community is thin; without it the Windows panel shows only the GPU.
- iUnity is removed by `debloat.ps1` ([0026](0026-clean-windows.md)).

## Alternatives

| Option | Why not |
|---|---|
| Antec's iUnity | Windows-only and proprietary, 175 MB with a driver and a firmware updater, reported to freeze |
| The Arch daemon as root without capabilities | it could still read `/etc/shadow`, the ssh host keys and sbctl's Secure Boot keys, and signal root's processes |
| `uaccess` on the panel's device node | it grants the user at the seat, not a service |
| Windows without PawnIO | the CPU field shows `--.-` |

## Consequences

- Both OSes show the same two numbers, and switching OSes leaves no stale reading, since the panel blanks itself.
- The protocol was learned from the decompiled iUnity service; no code was copied.
- The bench OSes leave the panel dark unless they get the script.
- A kernel driver of unclear origin runs on cabin-win for one temperature.

## How it is checked

`bin/check.sh` §20 runs `tests/case-display.py` (T0): the frame's test vectors, the usbfs ioctls, the sysfs lookup, NVML and the loop against fakes.
On Arch, `dram doctor`'s "case display" section warns when the panel is plugged in and the daemon is missing or stopped; on Windows, `dram doctor` checks the `dram-case-display` task the same way.
`bin/check.sh` §15 holds PawnIO's `pass-flag` row.

## History

- 2026-10-12: accepted ([D123](log.md#d123), [D124](log.md#d124)).
- 2026-10-12: a HID output report from Windows lit the panel with the GPU's temperature; the CPU field waited for PawnIO.
- 2026-10-12: the Arch package built, published to `[dram]` and started by udev on cabin, with both temperatures on the panel.

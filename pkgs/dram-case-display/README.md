# dram-case-display

[Design](../../docs/design/README.md) › [Shell & bars](../../docs/design/shell-and-bars/README.md) › Case display

CPU and GPU temperatures on the Antec Flux Pro's case panel, from Arch and from Windows.
The panel is a two-field 7-segment display on the PSU shroud, fed over an internal USB header (USB `2022:0522`), with no sensors of its own.
A program must send it both temperatures about once a second, or it stays dark, and it blanks itself a few seconds after the last frame, so switching OSes never leaves stale numbers.

| | |
|---|---|
| Needs | Arch: python3, systemd, udev, nvidia-utils for the GPU (NVML); Windows: LibreHardwareMonitor 0.9.6's library and the PawnIO driver; tested on cabin 2026-10-12 |
| Copy alone | yes: the Arch daemon is this directory and the Windows script one file; nothing in either names cabin |
| License | MIT |

## What it needs

- On Arch: Python 3 with the standard library only (ctypes for usbfs and NVML), systemd and udev.
  The CPU's `Tctl` comes from the k10temp hwmon, so an AMD CPU; the GPU's temperature from NVML (`libnvidia-ml.so.1`, in nvidia-utils), because nvidia-open registers no hwmon sensor.
- On Windows: `install/windows/dram-windows/case-display.ps1`, Windows PowerShell 5.1, LibreHardwareMonitor's library (MPL-2.0), PawnIO for the CPU's temperature, and `nvidia-smi` as the GPU's fallback.
- Not needed: Antec's own iUnity, which is Windows-only and proprietary, or Nix, Home Manager and `dram`.

## Copy it alone

On Arch, as a package:

1. Copy this directory and build it: `makepkg -si`.
2. Trigger udev for a panel that is already plugged in: `sudo udevadm trigger --action=add --attr-match=idVendor=2022 --attr-match=idProduct=0522`, or reboot.
3. `systemctl status dram-case-display` shows it running, and the panel lights.

Without packaging it, install the four files where `PKGBUILD`'s `package()` puts them, then reload udev and systemd.

On Windows, copy `case-display.ps1` to a folder of its own, put LibreHardwareMonitor's `LibreHardwareMonitorLib.dll` where `$lhm` at the top of the script expects it, and run it as SYSTEM from a startup task; `-Once` sends one frame to test.

## How it is wired here

`packages/host-cabin.txt` installs the package on cabin from the signed `[dram]` repo, so only cabin takes it.
On cabin-win, the host file `windows/hosts/cabin-win.nix` stages `case-display.ps1`, installs the library pinned by SHA-256 (the unit `case-display-lhm`), takes PawnIO from `packages/winget/host-cabin-win.txt`, and registers the SYSTEM task `dram-case-display` (the unit `case-display-task`).
`debloat.ps1` removes iUnity.
`dram doctor` checks the service on Arch wherever the panel is plugged in, and the task on Windows.
`tests/case-display.py` checks the frame's test vectors and the usbfs sequence against a fake device; `bin/check.sh` §20 runs it, on the Mac too.
Why own code on both systems: [decision log](../../decisions/log.md#d123).

## On Arch

| Piece | What it does |
|---|---|
| `/usr/lib/dram/case-display` | every second, reads the CPU's `Tctl` and the GPU's core temperature, and writes both as one 12-byte frame through usbfs to the panel's interrupt OUT endpoint |
| `60-dram-case-display.rules` | gives the panel's usbfs node to the group `dram-case-panel`, and starts the service when the panel appears |
| `dram-case-display.service` | a dynamic user in that group, with no capabilities and in a sandbox; no `[Install]`: udev starts it, and the panel's removal stops it |
| `dram-case-display.sysusers` | the group `dram-case-panel` |

A reading the service can't get shows as `--.-`: the GPU field in the first seconds of a boot, before the NVIDIA driver is up; NVML is retried every 10 s.

```sh
systemctl status dram-case-display          # active (running)
journalctl -u dram-case-display -b          # the panel's revision, the sensors, the first frame
/usr/lib/dram/case-display --print          # both sensors and the frame; any user, the panel untouched
systemd-analyze security dram-case-display  # prints: 0.7 SAFE
```

A good start in the journal:

```
panel 2022:0522 at /dev/bus/usb/001/004: revision A (bcdDevice 0006), OUT endpoint 0x03, kernel driver none: claimed
CPU: Tctl from /sys/class/hwmon/hwmon2/temp1_input
GPU: NVIDIA GeForce RTX 3080 Ti, through NVML
sending a frame a second, the first: CPU 41.3, GPU 36.0 (55 aa 01 01 06 04 01 03 03 06 00 18)
```

After that the service logs only when something changes.

## Two revisions of the panel

| | Revision A | Revision B |
|---|---|---|
| bcdDevice | 0.06 | 1.00 |
| iProduct | none | `DINK_HID_DEVICE` |
| Endpoints | `0x03` interrupt OUT only | `0x81` interrupt IN and `0x02` interrupt OUT |
| Linux driver | none: usbhid refuses a device with no IN endpoint, so there is no hidraw node | usbhid, with a hidraw node |

`sudo lsusb -v -d 2022:0522 | grep -E 'bcdDevice|iProduct|bEndpointAddress|Transfer Type'` tells them apart, and so does the service's first journal line.
The service handles both: it writes through usbfs, which reaches either revision, reads the OUT endpoint from sysfs, and on revision B detaches usbhid and gives the interface back when it stops.

## If the panel stays dark

1. Press Temp on the top I/O.
   The button cycles through CPU and GPU, CPU, GPU and off in the panel's own firmware, and no program can override it.
2. Read `journalctl -u dram-case-display -b`:

   | The journal says | Meaning |
   |---|---|
   | `no panel (USB 2022:0522) in sysfs` | check the internal USB header: `lsusb -d 2022:0522` |
   | `cannot claim it: Permission denied` | the node is not the group's yet: run the trigger above, or reboot; or `--once` ran without sudo |
   | `cannot claim it: Device or resource busy` | another program holds the panel, such as a `--once` in a terminal |
   | `the panel refused a 12-byte frame` | nothing to do: the service pads to 64 bytes by itself from then on |

3. Frames go out but nothing lights: Windows sends 64-byte reports, so try those with `sudo systemctl edit dram-case-display`, an empty `ExecStart=`, then `ExecStart=/usr/lib/dram/case-display --pad`.
4. Try by hand, with the service stopped, since it holds the panel:

   ```sh
   sudo systemctl stop dram-case-display
   sudo /usr/lib/dram/case-display --once    # one frame; the panel shows it for a second or two
   sudo systemctl start dram-case-display
   ```

   `--once --pad` sends 64 bytes instead.
5. The GPU field stays blank:
   - the journal keeps saying `GPU: NVML not ready …`: check that `nvidia-smi` works;
   - `nvidia-smi` works: `sudo systemctl restart dram-case-display`, since the device ACL is read when the service starts, so an NVIDIA module that loaded later isn't in it;
   - `--print` shows the GPU but the service doesn't: the sandbox is in the way; `systemctl show dram-case-display -p DeviceAllow` must allow `/dev/nvidiactl` and `/dev/nvidia0`.

## Why it is built this way

- The service runs as a `DynamicUser` whose only grant is the `dram-case-panel` group, which can write the panel's usbfs node and nothing else; every other USB node stays root's.
- The group isn't named after the service: systemd names the dynamic user after the unit and refuses to start it (EILSEQ) when a static group already has that name.
- No root: detaching usbhid and claiming the interface need write access to that node, and the sensors are open to every user (k10temp's sysfs files, NVML's `/dev/nvidia*` at `0666`).
- Not root without capabilities: such a service still passes the owner check on root's files, so it could read `/etc/shadow` and sbctl's Secure Boot keys, and signal root's processes.
- Not `uaccess`: it grants the person logged in, not a service.
- Devices are allowed by group (`char-usb_device`, `char-nvidia*`), not by path: nvidia-modprobe may create `/dev/nvidia*` after the service starts, and a path missing at the start would stay denied.
- The claim never steals the panel: `USBDEVFS_DISCONNECT_CLAIM` refuses with EBUSY when another usbfs program holds it.
- One frame a second: the panel's watchdog blanks it 1 to 2 s after the last frame.

## The protocol

One 12-byte frame, learned from Antec's decompiled iUnity service, the open Linux daemons and a hardware probe; no code was copied:

| Byte | Value | Notes |
|---|---|---|
| 0–1 | `55 AA` | header |
| 2–4 | `01 01 06` | the firmware checks bytes 2 and 3 and ignores byte 4 |
| 5–7 | CPU tens, ones, tenths | raw digits 0 to 9, not ASCII; `EE EE EE` shows `--.-` |
| 8–10 | GPU tens, ones, tenths | NVML gives whole degrees, so the tenth is 0 |
| 11 | the low byte of the sum of bytes 0 to 10 | checksum |

Values are clamped to 0.0 to 99.9, since a digit above 9 would show as 9.

| CPU, GPU | Frame |
|---|---|
| 24.0, 16.0 | `55 aa 01 01 06 02 04 00 01 06 00 14` |
| 24.0, none | `55 aa 01 01 06 02 04 00 ee ee ee d7` |
| 44.3, 52.0 | `55 aa 01 01 06 04 04 03 05 02 00 19` |
| both blank | `55 aa 01 01 06 ee ee ee ee ee ee 9b` |

On Arch the frame goes as an interrupt transfer of the 12 bytes to the OUT endpoint, after claiming interface 0; the usbfs bulk ioctl sends an interrupt transfer when the endpoint is an interrupt endpoint.
On Windows it goes as a HID output report: report ID 0, then the frame, padded to the panel's report length, 65 bytes on cabin.

## Files

| File | What it does |
|---|---|
| `PKGBUILD`, `.SRCINFO` | the package: four files into `/usr/lib` |
| `case-display` | the daemon, Python |
| `dram-case-display.service` | the sandboxed service |
| `60-dram-case-display.rules` | the udev rule: the node's group and the service's start |
| `dram-case-display.sysusers` | the group |
| `UPSTREAM`, `PIN` | own code: where the sources are, and how to bump the version |
| `REVIEW.md` | the review of the package's build and install behavior |

## License

MIT, Patrick Jordan.
LibreHardwareMonitor, which the Windows half downloads, is MPL-2.0; PawnIO's source is GPL-2.0 or later.

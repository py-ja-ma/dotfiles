# dram-case-display — review

- **What**: my own code for the temperature panel on the side of cabin's Antec Flux Pro
  (Noctua Edition), USB `2022:0522` (decisions/log.md#d123; `pkgs/dram-case-display/README.md`). It is
  Arch's half; `install/windows/dram-windows/case-display.ps1` sends the same frame from
  Windows. No third-party code. Files:
  - `/usr/lib/dram/case-display` (Python 3, standard library and `ctypes`). Every second it
    reads two temperatures and writes them to the panel as one 12-byte frame through usbfs.
    - **CPU**: `Tctl` from the `k10temp` hwmon.
    - **GPU**: the core temperature through NVML (`libnvidia-ml.so.1`). nvidia-open registers
      no hwmon sensor.
    - **Finding the panel**: by `idVendor`/`idProduct` in sysfs.
    - **Claiming it**: `USBDEVFS_DISCONNECT_CLAIM` on interface 0, which detaches usbhid on
      revision B. It is never taken from another usbfs program: the claim answers `EBUSY`.
    - **Writing**: `USBDEVFS_BULK` to the interrupt OUT endpoint read from sysfs (`0x03` on
      revision A, `0x02` on B). The kernel sends it as an interrupt transfer. If the panel
      refuses 12 bytes, it pads to 64 from then on.
    - **Errors**: after any error it finds the panel again. On SIGTERM it sends a blank frame,
      releases the interface and gives usbhid its interface back.
    - **Manual runs**: `--print` reads the sensors only; `--once` sends one frame.
  - `/usr/lib/udev/rules.d/60-dram-case-display.rules`:
    - gives the panel's usbfs node to the group `dram-case-panel` (`0664`)
    - tags it for systemd, as `dev-dram_case_display.device`
    - `SYSTEMD_WANTS` the service
  - `/usr/lib/systemd/system/dram-case-display.service`: no `[Install]`; it `BindsTo` the
    device, so udev starts it and the panel's removal stops it.
  - `/usr/lib/sysusers.d/dram-case-display.conf`: the group `dram-case-panel`, and no user.
    It is not named like the unit: systemd names the dynamic user after the unit, and
    `DynamicUser=` refuses to start (EILSEQ) when a static group already carries that name.
- **Privileges** (least that works):
  - The service runs as a `DynamicUser` in `SupplementaryGroups=dram-case-panel`, with no
    capabilities.
  - The group can write to the panel's node only. Every other USB node stays `root:root
    0664`, and usbfs refuses every ioctl on a node opened read-only.
  - Detaching usbhid and claiming the interface need write access to the node, not root
    (`proc_disconnect_claim` checks no capability).
  - k10temp's files and `/dev/nvidia*` (`0666`) are open to every user.
  - `uaccess` would not do: it grants the logged-in user, not a service.
  - Root without capabilities, the first sketch, would still pass the owner check on root's files.
    It could read `/etc/shadow`, the ssh host keys and sbctl's Secure Boot keys
    (`ProtectSystem` makes them read-only, not hidden), and it could signal root's processes.
  - Device ACL `char-usb_device` + `char-nvidia*`, by group rather than path: a
    `/dev/nvidia0` that nvidia-modprobe creates after the start would stay denied.
  - `systemd-analyze security`: 0.7, "SAFE".
- **Runs at build/install time**: `package()` installs the four files; there is no
  `.install` and no hook of ours. pacman's systemd hooks create the group, reload udev and
  reload systemd. The rule reaches a panel that is already plugged in at the next boot, or
  after `udevadm trigger` (`hosts/cabin/README.md`).
- **Tests**:
  - **T0**: `tests/case-display.py` (`bin/check.sh` §20), on the Mac and on Linux. It covers
    the four test vectors, the ioctl numbers and both revisions in a fake sysfs. It runs NVML
    through a fake library and the loop against a fake usbfs (claim, frames, a stall, an
    unplug, a busy panel, the stop).
  - **T1**, 2026-10-12, in the amd64 Arch container with makepkg 7.1, systemd 262 and
    Python 3.14:
    - `--printsrcinfo` (byte-identical to `.SRCINFO`) and `--verifysource`
    - a build as `nobody`, then `pacman -U`: pacman's hooks create `dram-case-panel` before
      udev reloads; `pacman -Qkk` is clean
    - `udevadm verify`
    - `systemd-analyze verify` (no warning about the unit) and `security --offline`
    - `--print`, `--once` (no panel: exit 1) and the T0 test, on Arch's Python
  - **namcap** reports only what `dram-gaming-mode` also has: no `url` or Maintainer, and
    `LicenseRef-dram` without a licence file. It also says `systemd` "may not be needed",
    but the unit, the rule and sysusers need it. Its "python3 is an uninstalled dependency"
    appears for Arch's own namcap package in that container too.
  - **T4**, on cabin's panel: `pkgs/dram-case-display/README.md` → "On Arch".
- **Origin / Community**: own code. `python` and `systemd` pass. NVML is part of
  `nvidia-utils`, under the signed NVIDIA userspace waiver (re-check 2027-10-10), so there is
  no new waiver. Register: pass.

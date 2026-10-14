# xpadneo-dkms review

[Toolchain](../../docs/toolchain/README.md) › [Packaging](../../docs/toolchain/packaging/README.md) › [The `[dram]` repo](../README.md) › xpadneo-dkms

xpadneo 0.10.4, the Linux driver for Xbox One and Series controllers over Bluetooth: rumble, battery, the share button and correct mappings.

| | |
|---|---|
| Needs | Arch with makepkg; DKMS and each kernel's headers, BlueZ; tested 2026-10 |
| Copy alone | yes: `makepkg -si` in this directory |
| License | GPL-2.0-only for the driver, GPL-3.0-or-later for the rest (`LICENSE.md`); the recipe: its AUR repository's terms, unstated |

## What it is

The kernel's own `hid-microsoft` and `xpad` cover USB and basic Bluetooth only.
The DKMS source module `hid-xpadneo` is built against each installed kernel's headers.
`/usr/lib/modprobe.d/xpadneo.conf` holds aliases that bind seven Microsoft and ASUS Bluetooth ids to it.
`/usr/lib/udev/rules.d/60-xpadneo.rules` rebinds to xpadneo, sets `uaccess` on the joystick and tells libinput to ignore it.
`70-xpadneo-disable-hidraw.rules` sets these pads' hidraw to mode 0000, so Steam reads xpadneo's evdev device instead of raw HID.

## Runs at build and install time

`build()` runs `make build`, which only writes `hid-xpadneo/dkms.conf` from `VERSION`.
`check()` builds the module once with DKMS in a private tree, changing nothing on the system.
`package()` runs `make install` with `PREFIX` set, which turns the Makefile's `udevadm control --reload` and `dkms add` into no-ops, and copies the module source to `/usr/src/hid-xpadneo-v0.10.4`.
At install, pacman's own DKMS hook builds it.
`dkms.post_install` and `post_remove` only delete a stale `/etc/modprobe.d/99-xpadneo-bluetooth.conf` that old versions left.

## Changed from the AUR

At AUR commit `ae15a8d` (2026-08-31): `checkdepends` names `linux-headers` instead of the AUR's placeholder `LINUX-HEADERS`, which no repo provides, so a clean-chroot build could not resolve it; and header comments.
`pkgver`, `pkgrel` and the b2sum are the AUR's, the sum checked again from my own download.

## Origin and community

143 of the last 147 commits are Kai Krakow's (`kakra`, "Bremerhaven, Germany").
GitHub releases v0.10.2 (2026-04), v0.10.3.1 and v0.10.4 (2026-07), with an active tracker.
It is only in the AUR, hence vendored, and the register holds it as `pass`.

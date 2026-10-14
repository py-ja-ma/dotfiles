# refind-letterpress

[Design](../../docs/design/README.md) › [Shell & bars](../../docs/design/shell-and-bars/README.md) › Boot screens

A rEFInd theme in the house palette: the boot menu set like a title page.
Dark paper runs from `#1c140f` down to `#100c09`, the icons are printed in pale ink and gray with each name under its icon, and a 1 px vermilion frame marks the selected entry.
My initials sit small in the bottom-left corner.
The palette and the design behind it are in [Boot screens](../../docs/design/shell-and-bars/boot-screens.md).

| | |
|---|---|
| Needs | rEFInd 0.14.2, tested 2026-10; Python 3 with Pillow only to render the images again |
| Copy alone | yes, after replacing the mark in `background.png`; keep two license notices with the icons |
| License | MIT, except the icons: Catppuccin's are MIT, rEFInd's own are mostly CC-BY-SA-3.0 |

## What it needs

- rEFInd 0.14.2 from Arch's `extra` repo, tested on cabin in 2026-10.
- A screen of any size: `banner_scale fillscreen` stretches the 2560×1440 background to fit.
- No fonts.
  rEFInd sets the labels in its built-in font, and the mark is part of the background image.
- To render the images again: Python 3 with Pillow, `system/gen-boot-assets.py`, the five colors in `system/house-palette.sh`, the source icons in `system/refind-catppuccin/assets/mocha/icons/`, and a serif for the mark.
- Not needed: Nix, Home Manager or `dram`.
  Secure Boot checks rEFInd's binary, and rEFInd reads the theme's files without a signature.

## Copy it alone

1. Copy this directory into rEFInd's own directory on the ESP, beside `refind.conf`, as `themes/letterpress/`: for example `/boot/EFI/refind/themes/letterpress/`.
   `theme.conf` names its files as `themes/letterpress/…`, so keep that name, or change its four paths to match yours.
2. Add one line to `refind.conf`, below your own global options and below any other theme's `include`:

   ```text
   include themes/letterpress/theme.conf
   ```

   rEFInd reads the included file in place.
   A `banner` or `showtools` line after it replaces the theme's, and a later `hideui` line hides more on top of the theme's list.
3. Replace the mark, since `background.png` carries my initials.
   Draw your own 2560×1440 background and keep its top-left pixel plain paper: rEFInd takes the menu's background color from that pixel.
   Or copy `system/gen-boot-assets.py` and `system/house-palette.sh` into one directory, change `"pj"` in the script's two `text_image("pj", …)` calls, and run `python3 gen-boot-assets.py --font <a serif .ttf>`.
   It writes `refind-letterpress/` and `plymouth-letterpress/` next to itself and leaves the icons alone when it finds no source icons.
4. Keep the icons' notices with them.
   Copy `system/refind-catppuccin/LICENSE` into the theme's directory as `LICENSE.catppuccin`, and rEFInd's `icons/README` as `README.icons.txt`.
   Arch's `refind` package installs the second as `/usr/share/doc/refind/README.icons.txt`.
5. Point your own `menuentry` stanzas at the icons by path, for example `icon /EFI/refind/themes/letterpress/icons/os_arch.png`.
   Scanned entries find theirs in the icons directory by the operating system's name.
6. Reboot.
   The menu opens on dark paper with your mark in the corner, each tile in pale ink with its name under it, a thin vermilion frame around the selected tile, and one power-off tile on the second row.

## How it is wired here

`system/apply-refind.sh` copies this directory whole to `<ESP>/EFI/refind/themes/letterpress/` whenever `diff -rq` finds a difference, so this README travels to the ESP as well.
rEFInd reads only the files `theme.conf` names.
The script writes `refind.conf` itself: `timeout 3`, `use_nvram false`, `scanfor manual`, `default_selection "Arch Linux"`, the `include` line, and one entry for each boot target it finds on the ESP.

| Entry | Icon | Starts |
|---|---|---|
| Arch Linux | `os_arch.png` | `/EFI/Linux/arch-linux.efi`, a signed UKI |
| Arch Linux LTS | `os_arch.png` | `/EFI/Linux/arch-linux-lts.efi` |
| Windows | `os_win.png` | Windows' own firmware entry when Windows has its own ESP, else `bootmgfw.efi` on this one |
| Snapshots & recovery | `os_systemd.png` | systemd-boot, whose menu holds the fallback and snapshot UKIs |

`system/system-dram.sh` runs `apply-refind.sh` on hosts with the desktop role, as a `dram apply` hook that asks first.
cabin has booted through this menu since 2026-10-12.
`sudo bash system/apply-refind.sh --theme catppuccin` installs the old Catppuccin theme from `system/refind-catppuccin/` instead.
`dram doctor --boot` checks that rEFInd boots first with systemd-boot behind it, and that the Windows tile starts Windows' own entry.
It does not look at the theme.
The chain itself, its signing and its recovery: [Boot chain](../../docs/platforms/arch/boot-chain.md).

`theme.conf` leaves rEFInd's editor on: F2 or Insert on an entry.
With Secure Boot on, a signed UKI ignores an edited command line, as systemd-stub(7) documents, so an edit does not reach the kernel of the Arch entries on cabin.

`system/gen-boot-assets.py` rendered the images here on 2026-10-06, and `--check` lists them with their sizes.
The mark is "pj" in Fraunces at 112 px, in the subtext gray, with the variable axes at `opsz` 144, `wght` 600, `SOFT` 100 and `WONK` 1.
The repo does not keep Fraunces, so a new render needs the font file passed with `--font`.
The grain is seeded, and a run with the same font writes the same bytes.

`background.png` is also cabin-win's desktop wallpaper and lock screen.
`windows/roles/desktop.nix` stages it as `C:\ProgramData\dram\letterpress.png`, so a changed background is a Windows render input too (`bin/render-windows.sh`).

## The icons

The 90 icons are `system/refind-catppuccin/assets/mocha/icons/` recolored by `gen-boot-assets.py`.
Catppuccin drew 39 of them.
The other 51 come from rEFInd's own stock icons: the vendored set holds byte-for-byte copies of them beside Catppuccin's.

A single-tone icon is printed flat: an operating system's in ink, `#e6d6cb`, and a tool's or function's in the subtext gray, `#a89484`.
A full-color icon is printed in one tone, mapped by brightness from paper to ink.
`os_linux.png` is a copy of `os_arch.png`, so a loader that rEFInd knows only as Linux shows the Arch logo.

The menu on cabin shows four of them: `os_arch.png`, `os_win.png`, `os_systemd.png` and `func_shutdown.png`.
`hideui` hides the scroll arrows and the volume badges, so `arrow_*.png` and `vol_*.png` stay unused.
The rest are there for a copier's menu, where rEFInd picks an icon by the operating system's name.

## Files

| File | What it does |
|---|---|
| `theme.conf` | the settings: labels kept; hints, arrows, badges and the single-user option hidden; the icons, the background, the two frames; a power-off tile as the only tool |
| `background.png` | 2560×1440 paper from `#1c140f` to `#100c09`, a faint seeded grain, the mark 96 px in from the bottom-left corner |
| `selection_big.png` | the 144 px frame around a selected entry: 1 px of vermilion, `#c0442b`, on transparent |
| `selection_small.png` | the same frame at 64 px, around a selected tool |
| `icons/` | the 90 icons, in ink and gray ([The icons](#the-icons)) |
| `system/gen-boot-assets.py` | renders the images and recolors the icons |
| `system/house-palette.sh` | the boot chain's five colors |
| `system/apply-refind.sh` | installs the theme and writes `refind.conf` |

## License

| Files | License | Holder |
|---|---|---|
| `theme.conf`, `background.png`, `selection_big.png`, `selection_small.png`, this README | MIT | Patrick Jordan |
| 39 icons drawn by Catppuccin: `func_about`, `func_exit`, `func_firmware`, `func_hidden`, `func_reset`, `func_shutdown`, `tool_mok_tool`, `os_android`, `os_antergos`, `os_arch`, `os_centos`, `os_debian`, `os_deepin`, `os_elementary`, `os_fedora`, `os_freebsd`, `os_gentoo`, `os_kali`, `os_kubuntu`, `os_linux`, `os_linuxmint`, `os_mac`, `os_manjaro`, `os_mx`, `os_neon`, `os_nixos`, `os_openbsd`, `os_parabola`, `os_solus`, `os_systemd`, `os_ubuntu`, `os_ubuntugnome`, `os_unknown`, `os_void`, `os_win`, `os_win10`, `os_win8`, `os_win8_official`, `os_zorin` | MIT | Catppuccin, 2021; the notice is `system/refind-catppuccin/LICENSE` |
| 34 of rEFInd's icons, from the AwOken 2.5 set and Canonical's Ubuntu artwork: `arrow_left`, `arrow_right`, `boot_linux`, `func_bootorder`, `func_install`, `os_artful`, `os_bionic`, `os_chakra`, `os_chrome`, `os_clover`, `os_crunchbang`, `os_frugalware`, `os_hwtest`, `os_lubuntu`, `os_mageia`, `os_mandriva`, `os_network`, `os_opensuse`, `os_slackware`, `os_suse`, `os_trusty`, `os_uefi`, `os_xenial`, `os_xubuntu`, `os_zesty`, `tool_netboot`, `tool_part`, `tool_shell`, `tool_windows_rescue`, `vol_efi`, `vol_external`, `vol_internal`, `vol_net`, `vol_optical` | CC-BY-SA-3.0 | Alessandro Roncone for AwOken and Canonical for the Ubuntu releases, with Roderick W. Smith's changes |
| 15 of rEFInd's icons drawn by its author: `boot_win`, `func_csr_rotate`, `mouse`, `os_gummiboot`, `os_haiku`, `os_legacy`, `os_netbsd`, `os_redhat`, `os_refind`, `os_refit`, `tool_apple_rescue`, `tool_fwupdate`, `tool_memtest`, `tool_rescue`, `transparent` | LGPL-3.0-or-later OR CC-BY-SA-3.0 | Roderick W. Smith |
| `os_devuan` | CC-BY-SA-4.0 | Dyne.org foundation |
| `os_endeavouros` | GPL-3.0 | the EndeavourOS team |

The icon names in the table leave out `.png`.
rEFInd's `icons/README` gives each stock icon's source and license, and it is the notice to copy for those 51.
Recoloring keeps each icon's license: the recolored CC-BY-SA icons stay CC-BY-SA, and `os_endeavouros.png` stays GPL-3.0.
The operating systems' logos are their owners' trademarks.
The mark in `background.png` is my initials, set in Fraunces.

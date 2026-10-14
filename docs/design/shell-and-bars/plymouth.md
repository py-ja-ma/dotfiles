# Plymouth themes

[Design](../README.md) › [Shell & bars](README.md) › Plymouth themes

The boot splash in the house palette: "pj" on dark paper, over a vermilion rule that grows as the boot goes on.
`system/plymouth-letterpress/` holds it, a Plymouth `script` theme of two text files and three images, shown between rEFInd's menu and the ly greeter.
`system/plymouth-catppuccin/` holds the splash from before Letterpress.
The palette and the design behind both are in [Boot screens](boot-screens.md).

The two directories keep no README of their own.
`system/plymouth-setup.sh` copies each file of a theme's directory, and the initramfs hook packs that directory into each UKI, so a README there would ride in every boot image, and each edit to it would rebuild the UKIs.

| | |
|---|---|
| Needs | Plymouth 26.134.222 with its script plugin, tested 2026-10; `splash` on the kernel command line; Plymouth in the initramfs |
| Copy alone | yes, after replacing `wordmark.png`, which carries my initials |
| License | MIT |

## What it needs

- Plymouth 26.134.222 from Arch's `extra` repo, tested on cabin in 2026-10, with the `script` plugin it ships.
- Plymouth in the initramfs.
  With mkinitcpio, `plymouth` goes in `HOOKS` right after `systemd`, and dracut adds it by itself.
- `splash` on the kernel command line, and `quiet` for a silent boot.
- Early kernel mode setting for the GPU, or the splash comes up late or not at all.
- One sans-serif font for the messages and the password prompt.
  Arch's initramfs hook copies the system's match for `Sans` in as `Plymouth.ttf`, and the splash can use no other face, which is why the mark is an image.
- Not needed: Nix, Home Manager or `dram`.

## Copy it alone

1. Copy the five files into `/usr/share/plymouth/themes/letterpress/`:

   ```sh
   sudo install -Dm644 -t /usr/share/plymouth/themes/letterpress/ letterpress.plymouth letterpress.script wordmark.png bar.png track.png
   ```

   `letterpress.plymouth` names that directory in `ImageDir` and `ScriptFile`, so change both lines if you rename it.
2. Replace `wordmark.png`, which carries my initials.
   Use any PNG with an alpha channel: the script centers it above the rule at its own pixel size.
   `system/gen-boot-assets.py` renders this one in the house ink from the font you pass with `--font`, after you change `"pj"` in its two `text_image("pj", …)` calls.
3. Make it the default theme and rebuild the initramfs:

   ```sh
   sudo plymouth-set-default-theme -R letterpress
   ```

4. Try it without a reboot, as root on a text console (Ctrl+Alt+F3):

   ```sh
   plymouthd; plymouth --show-splash; sleep 5; plymouth --quit
   ```

   For five seconds the screen turns to dark brown paper with your mark at the center and a faint gray rule under it.
5. Reboot.
   The splash holds from the end of the boot menu to the greeter.
   Its vermilion rule grows from the middle as the boot goes on and is full at the hand-off.

## How it is wired here

`system/plymouth-setup.sh` installs the theme's directory into `/usr/share/plymouth/themes/letterpress/` and makes it the default theme.
It puts `plymouth` after `systemd` in the mkinitcpio file that sets `HOOKS`.
It adds `quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0` to `/etc/kernel/cmdline`, and writes `/etc/kernel/cmdline.fallback` without those words, so the fallback UKIs boot verbose.
When something changed, it rebuilds the UKIs with `mkinitcpio -P` and checks that sbctl signed them again.
`system/system-dram.sh` runs it after `apply-refind.sh` on hosts with the desktop role, as a `dram apply` hook that asks first.
`sudo bash system/plymouth-setup.sh --theme catppuccin` installs [the old theme](#the-catppuccin-theme) instead.
`dram doctor --boot` warns when `splash` is missing from the kernel command line, or when the fallback command line has gone stale.

`system/gen-boot-assets.py` rendered the three images on 2026-10-06 from the colors in `system/house-palette.sh`.
The mark is "pj" in Fraunces at 260 px, in the house ink, with the variable axes at `opsz` 144, `wght` 600, `SOFT` 100 and `WONK` 1.
The script draws it at its own size, without scaling it.
`letterpress.script` writes the house colors out as numbers, so a change to the palette means changing them there too.

## The scene

| Element | Where | Color |
|---|---|---|
| background | the whole screen, a vertical gradient | `#1c140f` at the top to `#100c09` at the bottom |
| `wordmark.png` | centered, its foot 14 px above the middle of the screen | ink, `#e6d6cb` |
| `track.png` | a rule 240 px wide and 1 px high, 14 px below the middle, at 35 % opacity | subtext gray, `#a89484` |
| `bar.png` | over the track, `progress` × 240 px wide, grown from its center | vermilion, `#c0442b` |
| messages from fsck and errors | centered, 60 px above the bottom edge, Sans at 12 | ink |
| password prompt | `password` and one star per typed character, 48 px under the rule, Sans at 14 | ink |

Plymouth's script API has no call that returns the progress.
The rule redraws from the `progress` value that Plymouth passes to the function set with `Plymouth.SetBootProgressFunction`.
At quit the rule fills to its full width, so the greeter takes over from a whole line.
A script error does not stop the boot: Plymouth keeps the background, and the kernel carries on.
The message and password handlers come from the old Catppuccin theme.

## Limits

- The password prompt is untried on hardware.
  As of 2026-10 neither cabin nor lantern has an encrypted disk, and [decision 0011](../../../decisions/0011-disk-boot-secure-boot-snapshots.md) gives LUKS2 to the laptop alone.
- With mkinitcpio's `systemd` hook, the ArchWiki's Plymouth page notes that a script theme's password prompt may not redraw as you type.
  This repo builds its UKIs with that hook.
- The messages and the prompt are set in the initramfs's one Sans font, outside the house faces.

## Files

| File | What it does |
|---|---|
| `system/plymouth-letterpress/letterpress.plymouth` | names the theme and its `script` module, and the directory its files live in |
| `system/plymouth-letterpress/letterpress.script` | draws [the scene](#the-scene) and answers Plymouth's callbacks |
| `system/plymouth-letterpress/wordmark.png` | "pj" in ink on transparent, 281 × 267 px |
| `system/plymouth-letterpress/bar.png` | 240 × 1 px of vermilion: the progress |
| `system/plymouth-letterpress/track.png` | 240 × 1 px of the subtext gray: the rule's track |
| `system/plymouth-setup.sh` | installs the theme, the hook and the two command lines, and rebuilds the UKIs |
| `system/gen-boot-assets.py` | renders the three images |

## The Catppuccin theme

The splash from before Letterpress: three marks in Catppuccin Mocha's colors circling the middle of the screen.
It is a `script` theme in two text files, `catppuccin.plymouth` and `catppuccin.script`, that draws its marks as text and loads no image.
It was the laptop's splash from 2026-07-02 until the letterpress theme replaced it on 2026-10-06, and it is untried with Plymouth 26.134.222.
It needs what the letterpress theme needs, and one sans-serif font in the initramfs for its marks, which are asterisks drawn as text.

To copy it, install the two files into `/usr/share/plymouth/themes/catppuccin/` and run `sudo plymouth-set-default-theme -R catppuccin`.
`catppuccin.plymouth` names that directory in `ImageDir` and `ScriptFile`, so change both lines if you rename it.
Tried as above, three asterisks, mauve, blue and peach, circle the middle of a dark blue-gray screen.

Here, `sudo bash system/plymouth-setup.sh --theme catppuccin` installs it, makes it the default and rebuilds the UKIs.
`sudo bash system/apply-refind.sh --theme catppuccin` installs the matching rEFInd theme from `system/refind-catppuccin/`.
`dram apply` runs both scripts with their default, letterpress, so this theme is installed only on request.

| Element | Where | Color |
|---|---|---|
| background | the whole screen, a vertical gradient | Mocha's base `#1e1e2e` at the top to crust `#11111b` at the bottom |
| first mark | an asterisk in Sans Bold 22, on a 30 px orbit, clockwise | mauve, `#cba6f7` |
| second mark | the same on a 47 px orbit, counterclockwise and slower | blue, `#89b4fa` |
| third mark | the same on a 64 px orbit, clockwise and slowest | peach, `#fab387` |
| messages | centered, 60 px above the bottom edge, Sans 12 | text, `#cdd6f4` |
| password prompt | `password` and one star per typed character, 130 px below the middle, Sans 14 | text, `#cdd6f4` |

The marks move on each refresh, by 0.055, 0.037 and 0.024 radians, and start a third of a turn apart.
The theme sets no progress function, so it does not show how far the boot has come.
It has no handler for hiding a message either, so a message stays up until the next one replaces it.

I wrote this theme in this repo on 2026-07-02, the repo's first day, and its two files are unchanged since.
Catppuccin's own Plymouth theme, catppuccin/plymouth (MIT), is a different design: a `two-step` theme built from PNG frames, with no script.
No line here comes from it, and only the palette is Catppuccin's.

## License

MIT, Patrick Jordan, for both themes.
`wordmark.png` is my initials, set in Fraunces.
`letterpress.script` follows the API as Plymouth's example theme, `themes/script/script.script`, uses it, and shares only the API's own calls with that file.
The Catppuccin theme's colors are Catppuccin Mocha's, from the palette Catppuccin publishes under MIT.

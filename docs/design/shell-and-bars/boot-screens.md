# Boot screens

[Design](../README.md) › [Shell & bars](README.md) › Boot screens

rEFInd's menu, the Plymouth splash and the ly greeter come before the desktop, and the three share one fixed house palette.
It is washi's dark paper with its vermilion accent, and `dram theme` does not change it.
The chain itself, from the firmware to Hyprland, and its recovery are on [Boot chain](../../platforms/arch/boot-chain.md).

| | |
|---|---|
| Code | `system/house-palette.sh`, [`system/refind-letterpress/`](../../../system/refind-letterpress/README.md), `system/plymouth-letterpress/` ([Plymouth themes](plymouth.md)), `system/apply-ly.sh`, `system/gen-boot-assets.py`; the old themes in `system/refind-catppuccin/` and `system/plymouth-catppuccin/` |
| Runs on | the Arch hosts with the desktop role (cabin, lantern, campfire) |
| Needs | rEFInd 0.14.2, Plymouth 26.134.222 and ly 1.4.1 from pacman, tested 2026-10; Python 3 with Pillow and a Fraunces font file to render the images again |
| Decided in | rEFInd in front of the UKIs and Plymouth on them ([decision 0011](../../../decisions/0011-disk-boot-secure-boot-snapshots.md), amended 2026-10-12); the labels kept under rEFInd's icons, 2026-10-05 |

## How it works

| Screen | Drawn by | Its look |
|---|---|---|
| the boot menu | rEFInd | `system/refind-letterpress/`: a background, two selection frames and 90 icons, as PNGs |
| the splash | Plymouth's script plugin | `system/plymouth-letterpress/`: the wordmark and the rule as PNGs, the gradient and the text colors in the script |
| the greeter | ly on tty2 | `/etc/ly/config.ini`, which `system/apply-ly.sh` writes from the house palette |

Neither rEFInd nor Plymouth can set the wordmark in Fraunces, so `system/gen-boot-assets.py` renders it and the other images, and the PNGs are committed.
`system/system-dram.sh` applies the three in boot order: `apply-refind.sh`, then `plymouth-setup.sh`, which rebuilds the UKIs, then `apply-ly.sh`.
`dram apply` runs it as a hook on hosts with the desktop role, and asks first.

## The house palette

`system/house-palette.sh` holds five colors as `HP_NAME=rrggbb` lines.
`apply-ly.sh` sources it, and `gen-boot-assets.py` reads the same lines for the PNGs.
The Plymouth script and the comment at the top of rEFInd's `theme.conf` repeat the values by hand.

| Name | Variable | Color | Used for |
|---|---|---|---|
| paper | `HP_PAPER` | `#1c140f` | the top of each background gradient, rEFInd's menu background, ly's `bg` |
| paper bottom | `HP_PAPER_BOTTOM` | `#100c09` | the bottom of the gradients, the dark end of the full-color icons' one-tone print |
| ink | `HP_INK` | `#e6d6cb` | the splash's wordmark and text, the operating systems' icons, ly's `fg` and the heads of its matrix rain |
| subtext | `HP_SUBTEXT` | `#a89484` | the mark in the corner of rEFInd's background, the other icons, the splash's rule track, ly's matrix rain |
| accent | `HP_ACCENT` | `#c0442b` | the splash's progress rule, rEFInd's selection frames, ly's `border_fg` and `error_fg` |

Paper, paper bottom, ink and accent are washi's `base`, `crust`, `text` and `accent`.
The subtext, `#a89484`, is a little darker than washi's `#ac9c92`.

The palette does not follow `dram theme`, for two reasons.
`dram theme` runs without sudo, and the boot screens live on the ESP, in `/etc` and in the initramfs, so following the desktop would make each switch a root job and a UKI rebuild.
The boot screens are also what I see when the desktop is broken, so they look the same on each host: I debugged the pam_faillock lockout and the ly `dur` crash from them.
Nothing checks that the three screens match `house-palette.sh`.

## The rEFInd theme

`system/refind-letterpress/` follows the layout of the rEFInd-minimal theme.
`apply-refind.sh` copies it to `<ESP>/EFI/refind/themes/letterpress/`, and the `refind.conf` it writes includes `theme.conf`.
`banner` puts `background.png` behind the menu, and `banner_scale fillscreen` stretches it to the screen.
The image is 2560 × 1440 px of the paper gradient with a faint grain, and a small "pj" in subtext at the bottom left.
rEFInd takes the menu's background color from the banner's top-left pixel, so that pixel is plain paper.
`selection_big.png` and `selection_small.png` draw a 1 px accent frame on transparent, 144 px around the chosen entry and 64 px around the chosen tool.
The entries show `os_arch.png` for both Arch kernels, `os_win.png` for Windows and `os_systemd.png` for "Snapshots & recovery", and `showtools shutdown` leaves one tool, power off.
`hideui singleuser,hints,arrows,badges` keeps the label under each icon: on 2026-10-05, `hideui label` left five icons on cabin without names.
`theme.conf` sets no `font`, so the labels are in rEFInd's built-in font.

The 90 icons are those of `system/refind-catppuccin/assets/mocha/icons/`, recolored.
A one-tone icon becomes flat ink for an operating system (`os_*`) and flat subtext for the rest.
A full-color icon is printed in one tone, its brightness mapped from the bottom paper to ink.
[Iconography](../iconography/README.md) has the icon rule, and [the theme's README](../../../system/refind-letterpress/README.md) has its files, which icons Catppuccin drew, and their licenses.

## The Plymouth splash

`system/plymouth-letterpress/` is a script theme, which `plymouth-setup.sh` installs as `/usr/share/plymouth/themes/letterpress/` and makes the default.
The script paints the paper gradient, `#1c140f` at the top to `#100c09` at the bottom, and centers `wordmark.png`: "pj" in ink, 281 × 267 px, shown at its own size.
A 1 px rule runs 28 px under the wordmark.
It is `bar.png`, a 240 × 1 accent strip scaled to the boot's progress and growing from the center, over `track.png`, a subtext strip at 35 % opacity.
The progress comes from the callback of `Plymouth.SetBootProgressFunction`, because the script API has no `Plymouth.GetProgress()`.
When Plymouth quits, the script fills the rule, so the hand-off to ly shows a full line.

Messages, such as fsck's, appear in ink in Sans at 12, 60 px above the bottom edge.
A LUKS prompt shows `password` and a star per typed character in Sans at 14, 48 px under the rule.
Both handlers come from the Catppuccin script.
An error in the script costs the splash and leaves the boot alone: Plymouth keeps the background, and the kernel carries on.
The colors are written into the script, so a palette change means editing its two background calls and the ink of its two text handlers.
[Plymouth themes](plymouth.md) has its files and how to copy it.

## ly's look

`system/apply-ly.sh` writes the whole of `/etc/ly/config.ini`, or `config.lua` where the installed ly ships one, from the house palette.
ly takes a color as `0xSSRRGGBB`, where `SS` is a style byte: `00` plain, `01` bold.
Which file ly reads, and the keys that are not about the look, are on [Boot chain](../../platforms/arch/boot-chain.md).

| Key | Value | What it does |
|---|---|---|
| `bg` | `0x001c140f` | paper behind the whole screen |
| `fg` | `0x00e6d6cb` | ink for the text |
| `border_fg` | `0x00c0442b` | the accent for the box's border, which `hide_borders` hides |
| `error_fg` | `0x01c0442b` | errors in the accent, bold |
| `hide_borders` | `true` | no border around the box |
| `blank_box` | `true` | the box filled with paper, so an animation does not show through it |
| `bigclock`, `bigclock_12hr` | `en`, `false` | a large 24-hour clock |
| `clock` | `%A, %-d %B` | the date as "Tuesday, 13 October" |
| `box_title` | the hostname | the name over the box |
| `text_in_center` | `true` | the text centered in the box |
| `lang` | `en` | English labels |
| `animation` | `none` | no motion; `apply-ly.sh --anim matrix` writes `matrix` |
| `cmatrix_fg`, `cmatrix_head_col` | `0x00a89484`, `0x01e6d6cb` | with `matrix`: the rain in subtext, its heads in bold ink |
| `cmatrix_min_codepoint`, `cmatrix_max_codepoint` | `0x21`, `0x2f` | with `matrix`: the characters `!` to `/` |
| `dur_file_path` | empty | no `.dur` animation file |

**Never** set `animation = dur`: it faulted the greeter at boot twice on lantern on 2026-07-02 and forced a recovery from an ISO.
`apply-ly.sh` refuses it, and on each run it blanks `dur_file_path` and deletes `/etc/ly/*.dur`, so the animation cannot come back.
`matrix` runs in ly's own process, a different code path, and it is the only motion the script allows.
The greeter shows a change at the next logout.

## The boot assets

`system/gen-boot-assets.py` renders the PNGs from `house-palette.sh` and a serif font.
The committed files date from 2026-10-06 and are set in Fraunces (OFL), the variable font from the Google Fonts repository.
I fetched it into a scratch directory for the render: the Mac I render on has no Fraunces, and the repo does not keep it.
The script sets the font's axes to `opsz` 144, `wght` 600, `SOFT` 100 and `WONK` 1, each held within the font's range.
Without `--font`, it asks `fc-list` for Fraunces, then EB Garamond, Hoefler Text, Iowan Old Style, Baskerville, Charter, Noto Serif and DejaVu Serif.
It prefers a semibold file, then a regular one, and prints the file it used.
With none of them installed, it falls back to Pillow's bitmap font and prints a warning.

| File | Pixels | What |
|---|---|---|
| `plymouth-letterpress/wordmark.png` | 281 × 267 | "pj" at 260 px in ink, on transparent |
| `plymouth-letterpress/bar.png`, `track.png` | 240 × 1 | the rule in the accent, and its track in subtext |
| `refind-letterpress/background.png` | 2560 × 1440 | the gradient, the grain, and "pj" at 112 px in subtext, 96 px in from the bottom-left corner |
| `refind-letterpress/selection_big.png`, `selection_small.png` | 144 × 144, 64 × 64 | 1 px accent frames on transparent |
| `refind-letterpress/icons/*.png` | as the source | the mocha icons, recolored; `--icons-from` names another source directory |

The grain moves about 1.5 % of the background's pixels 4 or 6 levels lighter or darker, picked by a random generator seeded with 1.
It leaves the top-left 4 × 4 pixels alone and sets the first one to paper, since rEFInd samples it.
With the same font file, a second render writes byte-identical PNGs.
`--check` lists the main files and their sizes, and it exits 1 when one is missing or larger than 300 KB.
`background.png` is also cabin-win's wallpaper and lock screen (`windows/roles/desktop.nix`), so a new render is a Windows render input as well.

## The Catppuccin themes

The themes from before Letterpress stay in the repo, and each apply script installs its own on request.
`system/refind-catppuccin/` is catppuccin/refind as of commit e92ad6f (2025-03-01), with its `LICENSE` (MIT, Catppuccin, 2021) and its four flavors.
Three of its files differ from that commit: `os_linux.png`, a copy of `os_arch.png`, and `mocha.conf` and `background.png`.
`apply-refind.sh --theme catppuccin` installs it with `mocha.conf`, and its mocha icons are the source of the Letterpress icons.
51 of those 90 icons are rEFInd's own stock icons, unchanged, under rEFInd's licenses: mostly CC-BY-SA-3.0, with `os_devuan` under CC-BY-SA-4.0 and `os_endeavouros` under GPL-3.0.
[The rEFInd theme's README](../../../system/refind-letterpress/README.md) lists each icon's license.
`system/plymouth-catppuccin/` is the splash I wrote in Catppuccin Mocha's colors on 2026-07-02, and `plymouth-setup.sh --theme catppuccin` installs it ([Plymouth themes](plymouth.md#the-catppuccin-theme)).

## Use it

```sh
bash system/system-dram.sh --dry-run                      # each screen's diff; writes nothing, needs no root
python3 system/gen-boot-assets.py --check                 # the committed PNGs and their sizes
python3 system/gen-boot-assets.py --font <Fraunces.ttf>   # renders them again and prints the font file it used
sudo bash system/system-dram.sh                           # rEFInd, Plymouth with a UKI rebuild, ly, one Hyprland session
```

To change the palette:

1. Change the five lines of `system/house-palette.sh`.
2. Change the same colors in `system/plymouth-letterpress/letterpress.script`, in its two background calls and the ink of its message and password text, and in the comment at the top of `system/refind-letterpress/theme.conf`.
3. Render the PNGs again with `gen-boot-assets.py --font`, and commit them with the two files.
4. Render cabin-win again with `bin/render-windows.sh cabin-win`, since `background.png` is its wallpaper.
5. On each host, answer yes when `dram apply` asks about the boot look, or run `sudo bash system/system-dram.sh`.

To go back to the Catppuccin themes:

```sh
sudo bash system/apply-refind.sh --theme catppuccin
sudo bash system/plymouth-setup.sh --theme catppuccin
```

## Limits

- The boot screens keep washi's colors under each desktop theme.
- The Plymouth script and the comment in `theme.conf` repeat the palette by hand, and nothing compares them with `house-palette.sh`.
- Only the wordmark is Fraunces: rEFInd sets its labels in its built-in font, and Plymouth sets its messages in the initramfs's one Sans font.
- `system-dram.sh` installs the Letterpress themes and runs `apply-ly.sh --anim none`, so the Catppuccin themes and the matrix last until the next `dram apply` that runs the hook.
- The WSL clones have no boot screens, and cabin-win's Windows tile hands over to Windows' own boot screens.

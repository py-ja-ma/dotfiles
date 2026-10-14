# gsimplecal

[Design](../../../docs/design/README.md) › [Shell & bars](../../../docs/design/shell-and-bars/README.md) › Calendar

A month calendar that opens under the bar's clock: gsimplecal, styled as a Letterpress card of paper.
The month is in Fraunces over a hairline, the days are in Literata, and today has a 1 px accent ring with no fill.
gsimplecal has no stylesheet option, so a wrapper script hands it a private GTK user stylesheet.

| | |
|---|---|
| Needs | gsimplecal 2.5.3, tested 2026-10; Fraunces, Literata; a palette file; `dotfiles/.local/bin/gsimplecal-dram.sh` |
| Copy alone | yes, with the wrapper script and a palette |
| License | MIT |

## What it needs

- gsimplecal 2.5.3 from Arch's `extra` repo, tested 2026-10.
  It is a GTK 3 program.
- adw-gtk3, from adw-gtk-theme 6.5, as the GTK 3 theme: `gtk.css` takes away the frame it draws around the month title.
- The fonts Fraunces for the month and Literata for the days ([Typography](../../../docs/design/typography/README.md)).
- A palette at `~/.config/themes/current/waybar.css` that defines the GTK colors `base`, `text`, `subtext` and `accent`.
  The card reads the bar's palette file, and each theme has one.
- `dotfiles/.local/bin/gsimplecal-dram.sh`, a bash script that gives gsimplecal its stylesheet.
  It writes under `$XDG_RUNTIME_DIR`, which systemd sets at login, or under `/tmp` without it.
- Hyprland 0.56.2, for the window rule that floats the card and places it under the clock.
  Another compositor opens the card where it places new windows.
- Not needed: Nix, Home Manager or `dram`.

## Copy it alone

1. Copy `config` and `gtk.css` to `~/.config/gsimplecal/`.
2. Copy `dotfiles/.local/bin/gsimplecal-dram.sh` to `~/.local/bin/` and make it executable.
3. Give it a palette.
   Copy one theme's `waybar.css` to `~/.config/themes/current/`, or set `PAL` in the script to your own file with the four colors above.
4. Under Hyprland's Lua config, add the window rule:

   ```lua
   hl.window_rule({
       name     = "place-gsimplecal",
       match    = { class = "gsimplecal" },
       float    = true,
       move     = "monitor_w/2-170 46",
       rounding = 4,
   })
   ```

   A `hyprland.conf` takes the same float, move and rounding in its own window-rule syntax.
5. Point your bar's clock at the script, in Waybar with `"on-click": "$HOME/.local/bin/gsimplecal-dram.sh"`.
6. Click the clock.
   The card shows the month in Fraunces over a hairline, the days in Literata and today in a 1 px accent ring.
   A filled pill on today and a sans-serif face mean the stylesheet did not load: read `$XDG_RUNTIME_DIR/gsimplecal-dram/gtk-3.0/gtk.css`, which imports both files.

## How it is wired here

`modules/desktop.nix` links `dotfiles/.config/gsimplecal` whole to `~/.config/gsimplecal`, and the script into `~/.local/bin/`, on hosts with the desktop role.
`packages/roles/desktop.txt` installs gsimplecal.
`packages/register.tsv` passes it with a flag: its author's location is not public, which I accepted on 2026-10-11 ([software rules](../../../decisions/0013-software-rules-and-waivers.md)).

A click on Waybar's clock or date runs the script ([Waybar](../waybar/README.md)).
A second click closes the card, because a second gsimplecal closes the running one, and the card also closes when focus moves to another window (`close_on_unfocus = 1`).
The script rebuilds its files on each click and gsimplecal starts fresh, so the card follows a theme switch (SUPER+T) with no reload.

The `place-gsimplecal` rule in `hyprland.lua` floats the window, rounds it to 4 px, which GTK 3 cannot do for its own window, and moves it to `monitor_w/2-170 46`.
That centers the card under the clock, 46 px from the top of the monitor and below the 44 px bar.
With the house fonts the card measured 339 px wide (`hyprctl clients`, lantern, 2026-10-06), so half is 170: measure again after changing a font or a size.
`monitor_w` counts logical pixels, so the card stays centered at any scale.

## How the stylesheet gets in

gsimplecal 2.5.3 reads 19 keys from its config, and none of them is CSS.
The `maincss_file` line the config once carried was ignored, and the card came up in bare Adwaita: Noto Sans, a filled pill on today and a 2 px frame.
GTK 3 loads `$XDG_CONFIG_HOME/gtk-3.0/gtk.css` into each GTK 3 program as the user stylesheet, at priority 800, above the theme's 200.
Pointing `XDG_CONFIG_HOME` at a private directory for gsimplecal alone gives it a stylesheet that no other program sees.

On each click, `gsimplecal-dram.sh`:

1. Makes `gtk-3.0/` and `gsimplecal/` under `$XDG_RUNTIME_DIR/gsimplecal-dram/`.
2. Links `~/.config/fontconfig` beside them.
   fontconfig reads `$XDG_CONFIG_HOME` too, and without the link the fonts from the Nix profile vanish and each glyph falls back to Noto Sans.
3. Writes `gtk-3.0/gtk.css` with two `@import` lines: the palette, then `~/.config/gsimplecal/gtk.css`.
   Both paths are absolute, since a relative import would resolve against the private directory.
4. Links the real `gtk-3.0/settings.ini`, which keeps the GTK theme, the font and the dark preference, and the real `gsimplecal/config`, which gsimplecal also reads from `$XDG_CONFIG_HOME`.
5. Starts gsimplecal with `XDG_CONFIG_HOME` pointing there.

Only that process sees the private directory.
Its `gtk-3.0/gtk.css` stands in for `~/.config/gtk-3.0/gtk.css`, so the card takes its colors from the palette import and not from the generated GTK 3 stylesheet.
The window keeps its class, `gsimplecal`, so the window rule still matches.

## The card

GTK 3.24's `gtkcalendar.c` draws one `calendar` node and tells its parts apart by style classes and states:

| Part | Selector in `gtk.css` | Look |
|---|---|---|
| the card | `calendar` | `@base`, a 1 px hairline of `@text` at 18 %, a 3 px radius, 8 px padding, Literata 13 px |
| the month and year | `calendar.header` | Fraunces 15 px at weight 600 over a hairline, with adw-gtk3's frame taken away |
| the arrows | `calendar.button` | `@subtext` with no box, the accent under the pointer |
| the day names | `calendar.highlight` | `@subtext` at normal weight |
| today | `calendar:active`, from `mark_today = 1` | the accent at weight 600 |
| the selected day | `calendar:selected` | a 1 px accent ring with a 3 px radius and no fill |
| days of other months | `calendar:indeterminate` | `@text` at 40 % |

GTK 3 draws no frame for today: the ring is the `:selected` border, and the selected day is today when the card opens.
The days can be Literata, a proportional face, because GtkCalendar sizes each cell from its widest day and centers the figure in it.
The month name follows the process's `LANG`, which is English on cabin and lantern, so Fraunces can set it.
A Russian `LANG` would need the heading moved to Literata, since Fraunces has no Cyrillic.

## The tooltip alternative

The clock's own tooltip shows a month calendar too, in Monaspace Xenon with a Fraunces month, and it needs no second program.
It shows only on hover and vanishes when the pointer moves, so I kept gsimplecal and the click.

## Files

| File | What it does |
|---|---|
| `config` | gsimplecal's options: the calendar alone, today marked, closed when focus leaves |
| `gtk.css` | the card's rules, which name colors and define none, so the palette import comes first |
| `dotfiles/.local/bin/gsimplecal-dram.sh` | builds the private config directory and starts gsimplecal |
| `dotfiles/.config/hypr/hyprland.lua` | the `place-gsimplecal` window rule |
| `dotfiles/.config/waybar/modules.jsonc` | the clicks on the clock and the date |

## License

MIT, Patrick Jordan.

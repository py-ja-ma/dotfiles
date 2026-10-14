# swaync

[Design](../../../docs/design/README.md) › [Shell & bars](../../../docs/design/shell-and-bars/README.md) › Notifications

The Letterpress margin notes for swaync: each toast is a slip of paper with a 2 px accent rule down its left edge.
The control center is a column of the same 340 px down the right of the screen, cut off from the page by one hairline.
Captions are set in Literata Italic, the only heading in Fraunces, and the body of each note in Monaspace Xenon.

| | |
|---|---|
| Needs | swaync 0.12.6, tested 2026-10; Fraunces, Literata, Monaspace Xenon; a palette file |
| Copy alone | yes, after giving `style.css` a palette |
| License | MIT |

## What it needs

- swaync 0.12.6 from Arch's `extra` repo, tested 2026-10.
  It is a GTK 4 program on the layer-shell protocol, which Hyprland 0.56.2 has.
- The fonts Fraunces, Literata and Monaspace Xenon ([Typography](../../../docs/design/typography/README.md)).
  EB Garamond stands behind Literata in each font list, and Symbols Nerd Font Mono behind Monaspace Xenon for an icon glyph inside a note.
- A palette at `~/.config/themes/current/swaync.css` that defines the GTK colors `base`, `mantle`, `text`, `subtext`, `red` and `accent`.
  Each of the 17 themes in `dotfiles/.config/themes/` has one, with ten names.
- The `ru_RU.UTF-8` locale, for swaync's own words in Russian.
  Without it they stay English, and the words that `config.json` sets are Russian either way.
- `notify-send` from libnotify, to send a test note.
- Not needed: Nix, Home Manager or `dram`.

## Copy it alone

1. Copy `config.json` and `style.css` to `~/.config/swaync/`.
2. Give it a palette.
   Copy one theme's `swaync.css` to `~/.config/themes/current/`, for example from `dotfiles/.config/themes/washi/`.
   Or point the `@import` at the top of `style.css` at your own file with the six colors above.
   The import is relative, so it resolves against `~/.config/swaync/`.
3. Stop any other notification daemon, since one program at a time owns the notification bus.
4. Start swaync with `env LANG=ru_RU.UTF-8 swaync`, or with plain `swaync` for its own words in English.
5. Bind `swaync-client -t -sw`, which opens and closes the column, and `swaync-client -d -sw`, which turns do-not-disturb on and off.
6. Send three notes:

   ```sh
   notify-send -a mail "Письмо" "одна"
   notify-send -a mail "Письмо" "две"
   notify-send -u critical "проверка" "red rule"
   ```

   Three slips appear at the top right, and the critical one has a red rule and stays until you close it.
   In the column the two letters are one collapsed group, which Home and then Return expand.
   Run `swaync-client --close-all` and open the column again: it shows the empty state, italic words with no icon, «Нет уведомлений» under the Russian locale.

## How it is wired here

`modules/desktop.nix` links `dotfiles/.config/swaync` whole to `~/.config/swaync` on hosts with the desktop role, and `packages/roles/desktop.txt` installs swaync.
`hyprland.lua` starts it at login as `env LANG=ru_RU.UTF-8 swaync`, so swaync's own words come out in Russian: the empty state reads «Нет уведомлений», and a new note shows «Сейчас» for its time.
Only swaync gets that `LANG`, and the rest of the desktop keeps `en_US.UTF-8`.
`system/locale-setup.sh` generates the Russian locale ([Russian](../../../docs/design/typography/README.md#russian)).

SUPER+N opens and closes the column, and SUPER+SHIFT+N turns do-not-disturb on and off ([Keybinds](../../../docs/design/shell-and-bars/keybinds.md)).
Waybar's ¶ does the same on a click and a right click, and turns `@yellow` while a note waits ([Waybar](../waybar/README.md)).
`dram theme` reloads the stylesheet with `swaync-client -rs` after each switch.

`bin/check.sh` §14 runs `bin/check-themes.py`, which holds each theme's `swaync.css` to the same ten names and its `accent` to the theme's accent.
The same section fails on a hardcoded home directory under `dotfiles/.config`, which is why the `@import` is relative.
`hyprland.lua` has a `paper-swaync` layer rule that would blur swaync's layers, and it is inert while Hyprland's blur is off ([Blur](../hypr/README.md#blur)).

`welcome.sh`, also started at login, sends the first toast.
It waits up to 10 s for swaync, so the toast lands themed, and then sends one line: the date, the battery, the boot time and anything pending.
For example: «Вторник, 6 октября · Battery 87% · up since 08:12».
The date is Russian when the locale exists and English otherwise, by the same test hyprlock uses.
The pending parts are the update count when `checkupdates` answers within 2 s, a newer `dram` build on the host's channel, and a reboot left waiting by an update.
To turn the toast off, comment out its line in `hyprland.lua`.

## The slip and the column

A toast is 340 px wide and sits at the top right, under the bar.
Its paper is `@base` at 96 %, with a 1 px hairline of `@text` at 18 %, a 3 px radius and no shadow.
The rule down its left edge is 2 px of the accent, `@red` for a critical note and `@text` at 35 % for a low one.
A note stays 6 s, a low one 4 s, and a critical one until it is closed.
Toasts sit on the overlay layer, above a fullscreen window.

The column has the same width and runs down the right edge, with one hairline on its left and no card, radius, shadow or blur.
Its paper is `@base` at 96 %.
A note's rule in the column is `@text` at 35 % until the pointer is over it, and then the accent, while a critical note keeps its red.
Top to bottom, the column holds the inhibitors, the title and its clear button "очистить", the do-not-disturb switch, the notes, the media player and a calendar that waits for a later swaync ([The calendar widget](#the-calendar-widget)).

### Type

GTK CSS matches `label` nodes directly, so a bare `* { font-family }` would win over each label.
`style.css` scopes the mono to the two windows, `.control-center` and `.floating-notifications`, and names the face on each label node:

| Node | Face |
|---|---|
| `.widget-title > label`, the word "notifications" | Fraunces 15 px at weight 600, over a hairline |
| `.widget-title > button label` ("очистить"), `.widget-dnd > label` ("не беспокоить"), `.widget-inhibitors > label`, `.notification-group-header`, the empty state's words | Literata Italic 14 px in `@subtext` |
| `.summary` | Literata 14 px at weight 600 in `@text`, or `@red` when the note is critical |
| `.body` | Monaspace Xenon 12 px in `@text` |
| `.time` | Monaspace Xenon 11 px in `@subtext` |
| a note's action buttons | Monaspace Xenon 11 px |

The buttons are hairline ghosts with a 3 px radius at normal weight, because libadwaita bolds each button, and the accent marks the one under the pointer.
The do-not-disturb switch is a hairline box whose slider is the cursor: `@text` at 35 % when off, the accent when on.
A progress bar inside a note, for a download or a timer, is a 2 px accent rule.
A note's image is a 32 px square with a 3 px radius, and its app icon is 12 px.

### Groups and the empty state

swaync stacks the notes of one app into a group.
Its default stylesheet paints a gray slab behind a focused group and an opaque card under each collapsed row, which show as ghost frames under the top slip.
Here a focused group is transparent, the rows behind the top slip are invisible, and an open group shows one italic header over a hairline with ghost buttons to collapse and close it.
The invisible rows also give up their margin, which had left a 27 px gap where 14 px is usual.

With no notes the column shows the words alone, in italic.
swaync's 96 px placeholder icon keeps its size whatever the CSS says, so it is faded out, and a 108 px bottom margin balances it so the words sit in the middle.

### The media player

The `mpris` widget is a hairline card on the paper, without the blurred album art that swaync puts behind it by default.
The title is Literata 14 px at weight 600, the line under it Monaspace Xenon 11 px in `@subtext`, and the cover 48 px with a 3 px radius.
Its buttons are bare and take the accent under the pointer.

### The calendar widget

`config.json` lists a `calendar` widget that no swaync release has: on 2026-10-13 it exists only on swaync's main branch.
swaync 0.12.6, the newest release, logs `Could not find widget: calendar` and skips it.
The CSS waits for it: the month heading `calendar > header > label` in Fraunces 15 px, the current day as a 1 px accent ring on `label.day-number.today` with no fill, and the grid in Monaspace Xenon.

## Files

| File | What it does |
|---|---|
| `config.json` | where the toasts and the column sit, their 340 px width, the timeouts, the widgets and their Russian words |
| `style.css` | the palette import, the face of each label, the slips, the column and the widgets |
| `dotfiles/.config/themes/<theme>/swaync.css` | the ten colors of each theme |
| `dotfiles/.local/bin/welcome.sh` | the login toast |

## License

MIT, Patrick Jordan.

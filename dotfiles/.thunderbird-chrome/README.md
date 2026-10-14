# thunderbird-chrome

[Design](../../docs/design/README.md) › [Themes](../../docs/design/themes/README.md) › Browser and mail

Thunderbird's half of the Letterpress browser and mail chrome: its stylesheet and the seed of its prefs.
The [librewolf](../.librewolf/README.md) README covers both apps: the look, the palette, the prefs, how to copy them and how they are wired.

| | |
|---|---|
| Needs | Thunderbird 157.0.1, tested 2026-10; Literata and Monaspace Xenon; one theme's `browser.css` |
| Copy alone | yes: `userChrome.css` and a theme's `browser.css`, renamed `letterpress-colors.css`, in the profile's `chrome` folder; `user.js.default` as its `user.js` |
| License | MIT |

## Copy it alone

Follow [Copy it alone](../.librewolf/README.md#copy-it-alone) in the librewolf README, with `userChrome.css` and `user.js.default` from here.
It worked when the selected tab's tab line is in the accent and a selected message sits on a paper shade.

## How it is wired here

`modules/desktop.nix` links this folder whole to `~/.thunderbird-chrome/`, on hosts with the desktop role.
`dram-theme` links `userChrome.css` into each Thunderbird profile beside the theme's colors, and copies `user.js.default` into a profile that has no `user.js`.
Thunderbird applies `user.js` at each start, so a pref listed there cannot be changed in Settings: edit the profile's `user.js` instead.

## Files

| File | What it does |
|---|---|
| `userChrome.css` | the chrome on Thunderbird's `--layout-*` scale, its `--color-*` tokens and the variables of its `variables.css`, colored from `letterpress-colors.css` |
| `user.js.default` | the seed of a profile's `user.js`: the switch that loads `userChrome.css`, the chrome at 13 px and compact, Literata and Monaspace Xenon for message text |
| `README.md` | this file; it lands in `~/.thunderbird-chrome/` with the others, and `dram-theme` uses only the two above |

## License

MIT, Patrick Jordan.

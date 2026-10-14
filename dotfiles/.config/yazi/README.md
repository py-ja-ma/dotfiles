# yazi

[Design](../../../docs/design/README.md) › [Themes](../../../docs/design/themes/README.md) › yazi

The yazi file manager's configuration, with one generated Letterpress flavor for each of the 17 themes.
A flavor sets the file list as a printed page: the terminal's own paper, the ink, hairline rules, and one accent ink for the cursor row, the working directory and the mode word.
`dram theme` points yazi at the active theme's flavor.

| | |
|---|---|
| Needs | yazi 26.9.1, tested 2026-10; a terminal in the theme's colors; Python 3 only to regenerate the flavors |
| Copy alone | yes: copy the configuration and one flavor, and name the flavor in `theme.toml` |
| License | MIT; `init.lua` follows a function of yazi's own MIT-licensed `status.lua` |

## What it needs

- yazi 26.9.1 from Arch's `extra` repo, tested 2026-10.
  `init.lua` replaces a function of that version's status bar, and the flavors use that version's key names.
- A terminal that draws its own background in the theme's colors.
  The flavors leave yazi's background unset wherever yazi allows it, so a dark flavor needs a dark terminal.
  kitty with the theme's `kitty.conf` is the pair I use, and kitty's paper grain shows through ([kitty](../kitty/README.md#paper-grain)).
- No icon font: the flavors empty yazi's `[icon]` tables.
- To regenerate the flavors: Python 3 and each theme's `waybar.css` and `palette.lua` in `dotfiles/.config/themes/`, which `bin/gen-yazi-flavors.py` reads.
- Not needed: `ya pkg`, Nix, Home Manager or `dram`.
  `package.toml` declares no flavors or plugins for it to fetch.

## Copy it alone

1. Copy `yazi.toml` and `init.lua` to `~/.config/yazi/`.
   If you have an `init.lua` already, add its `Status:mode()` function to yours.
2. Copy one flavor directory, for example `flavors/letterpress-washi.yazi/`, to `~/.config/yazi/flavors/`.
3. Copy `theme.toml.default` to `~/.config/yazi/theme.toml` and name that flavor on both lines:

   ```toml
   [flavor]
   dark = "letterpress-washi"
   light = "letterpress-washi"
   ```

   yazi picks `dark` or `light` from the terminal's background, and with one name on both lines its pick makes no difference.
4. Give the terminal the same theme: for kitty, include the theme's `kitty.conf` from `dotfiles/.config/themes/<id>/`.
5. Start `yazi`.
   It worked when the status line spells out `NORMAL` in the accent, the row under the cursor is a tinted line in accent ink, and directories show in the dim accent with no icons.

For another palette, change the hex values in `flavor.toml` and `tmtheme.xml`.
On a yazi other than 26.9.1, `Status:mode()` may have changed: delete `init.lua`, and the mode reads `NOR` again.

## How it is wired here

`modules/cli.nix` links `yazi.toml`, `init.lua`, `package.toml` and `theme.toml.default` into `~/.config/yazi/` one by one, and `flavors/` as one directory, on each host.
The files are linked one by one because `~/.config/yazi/theme.toml` is machine state that `dram-theme` writes, and it stays out of the repo.
`dram-theme` seeds `theme.toml` from `theme.toml.default` on its first run and names the theme's flavor in it on each switch, as described under [The flavors](#the-flavors).
`dram-theme` sends yazi no signal, so start yazi again after a switch.
`dram-theme` belongs to the desktop role (`modules/theme.nix`), so on a host without that role, such as the WSL clones, `theme.toml` is not written and yazi shows its preset colors.

`bin/check.sh` §14 runs `bin/check-themes.py`, which fails when a theme's `YAZI_FLAVOR` in `meta.sh` is not `letterpress-<id>` or its flavor directory is missing.
`dram doctor` reports that `package.toml` declares no `ya pkg` dependencies, and warns about one added without a `rev` pin.
`bin/check.sh` does not compare the committed flavors with a fresh run of the generator (2026-10), so run the generator after a palette change and commit what it writes.

A host that once ran `ya pkg install` has a real `~/.config/yazi/flavors/` directory, and Home Manager refuses to replace it with the link.
Remove it once:

```sh
rm -rf ~/.config/yazi/flavors && dram switch
```

## The flavors

`bin/gen-yazi-flavors.py` writes `flavors/letterpress-<id>.yazi/` for each theme, from its `waybar.css` palette and the `accent` and `accent_dim` of its `palette.lua`.
Each directory holds `flavor.toml`, `tmtheme.xml` for the code preview, a short `README.md` and an MIT `LICENSE`.
On 2026-10-06 these flavors replaced the eight third-party ones that `ya pkg` used to clone, so yazi's colors come from this repo alone.

| Page element | yazi key | Ink |
|---|---|---|
| the paper | no `bg` except for the tinted rows and the marks; `[status] overall = {}` | the terminal's own background |
| the cursor row | `[indicator] current` | the accent, bold, on `surface0`: a tinted line in place of reversed video |
| the parent and preview rows | `[indicator] parent`, `preview` | the directory ink on `surface0`; the preview row takes the tint alone |
| working directory, find hits | `[mgr] cwd`, `find_keyword` | the accent, bold; find hits underlined too |
| the mode word | `[mode] normal_main`, `select_main`, `unset_main`; empty separators in `[status]` and `[tabs]` | `NORMAL` in the accent, `SELECT` in `yellow`, `UNSET` in `red`, bold, with no powerline pill |
| margin marks | `[mgr] marker_selected`, `marker_copied`, `marker_cut`, `marker_marked` | one cell of the accent, `yellow`, `red` or the directory ink |
| counts | `[mgr] count_selected`, `count_copied`, `count_cut` | the same inks, bold, on `surface0`: figures with no filled badge |
| rules | each `border` and `border_style` | `mix(base, subtext, 0.40)`, the hairline gray of btop's boxes |
| directories | the `[filetype]` rule for `*/` | `accent_dim`, bold, mixed toward the accent in 5 % steps until it reads at 3:1 on the paper |
| executables | `is = "exec"` | `green` |
| symlinks | `is = "link"` | italic in the ink they would have; a linked directory in the directory ink |
| images, audio and video, archives | the `mime` rules | `subtext`, `subtext` italic, `overlay` |
| broken links, missing files | `is = "orphan"`, `is = "dummy"` | `red`, italic |
| icons | `[icon]` with empty `globs`, `dirs`, `files`, `exts` and `conds` | none; notifications mark with `·`, `!` and `×`, completion with `·`, `/` and `:` |
| code preview | `tmtheme.xml` | comments `subtext` italic, strings `yellow`, keywords the accent, functions bold ink, types `blue`, numbers `peach`, no background |

The generator stops on a private-use codepoint in a flavor, so no Nerd Font glyph gets in.
Each key in `letterpress-washi.yazi/flavor.toml` exists in yazi's `yazi-config/preset/theme-dark.toml` at the v26.9.1 tag (checked 2026-10-13).

yazi's own `Status:mode()` cuts the mode to three letters, `NOR`.
`init.lua` is that function from yazi 26.9.1's `yazi-plugin/preset/components/status.lua` without its `:sub(1, 3)`, so the mode is a whole word.

`theme.toml` names two flavors, `dark` and `light`, and yazi picks one by the terminal's background.
`theme.toml.default` seeds them with washi's and washi-day's flavors.
The theme already decides the terminal's background, so `dram-theme` writes the active theme's `YAZI_FLAVOR` on both lines.
A `theme.toml` that lacks one of the lines gets it added under `[flavor]` first.

To regenerate after a palette change:

```sh
python3 bin/gen-yazi-flavors.py           # each theme
python3 bin/gen-yazi-flavors.py washi     # one theme
```

It prints `wrote <path>` for each file it changed.

## Files

| File | What it does |
|---|---|
| `yazi.toml` | the manager's options: hidden files off, natural sort with directories first, sizes in the line mode, preview limits |
| `init.lua` | the mode word in full: `NORMAL` where yazi shows `NOR` |
| `package.toml` | declares no `ya pkg` flavors or plugins |
| `theme.toml.default` | the seed of `~/.config/yazi/theme.toml`, naming washi's and washi-day's flavors |
| `flavors/letterpress-<id>.yazi/` | one flavor per theme: `flavor.toml`, `tmtheme.xml`, `README.md`, `LICENSE`; generated |
| `bin/gen-yazi-flavors.py` | writes the flavors from the theme palettes |
| `dotfiles/.local/bin/dram-theme` | seeds `theme.toml` and names the active theme's flavor in it |

## License

MIT, Patrick Jordan, for the configuration and the generated flavors; each flavor directory carries its own MIT `LICENSE`.
`init.lua` mirrors `Status:mode()` from yazi 26.9.1's `yazi-plugin/preset/components/status.lua`, less its `:sub(1, 3)`.
yazi is MIT-licensed, Copyright (c) 2023 sxyazi, and the function keeps that license.

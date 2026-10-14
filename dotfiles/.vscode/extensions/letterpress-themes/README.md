# letterpress-themes

[Design](../../../../docs/design/README.md) › [Themes](../../../../docs/design/themes/README.md) › Editor

A VSCodium extension with one color theme per dram theme: paper, ink, one accent and hairlines.
Its 17 themes are named `Letterpress — <bar name>`, from `Letterpress — Boulevardier` to `Letterpress — Bellini`, and each comes from the same palette files as the desktop, so the editor follows `dram theme`.

| | |
|---|---|
| Needs | VSCodium 1.135 (tested 2026-10) or VS Code 1.90 or later; Python 3 only to regenerate |
| Copy alone | yes: install the packed VSIX, or copy this folder into the extensions directory and register it |
| License | MIT |

## What it needs

- VSCodium, tested with vscodium-bin 1.135.06055 on cabin in 2026-10.
  `package.json` asks for an editor engine of 1.90 or later, so Microsoft's VS Code loads it too.
- Nothing at run time: the themes are plain JSON.
- To regenerate the themes: Python 3 and the theme directories in `dotfiles/.config/themes/`, which `bin/gen-vscode-themes.py` reads.
- The fonts are not part of the extension.
  Monaspace Xenon and Symbols Nerd Font Mono come from the editor settings in `dotfiles/.config/VSCodium/User/settings.json.default`.
- Not needed: a marketplace account, Nix, Home Manager or `dram`.

## Copy it alone

The simplest way is the VSIX that `bin/gen-windows-look.py` packs from this folder for Windows:

```sh
codium --install-extension install/windows/letterpress/pj.letterpress-themes-2026.10.6.vsix
```

To use the folder itself:

1. Copy it to `~/.vscode-oss/extensions/pj.letterpress-themes/` for VSCodium, or `~/.vscode/extensions/pj.letterpress-themes/` for VS Code.
2. If that extensions directory has no `extensions.json` yet, start the editor: it scans the folder and lists the extension itself.
3. If `extensions.json` exists, the editor ignores a folder it does not list.
   Add an entry to the array in that file, with the folder's absolute path:

   ```json
   {"identifier": {"id": "pj.letterpress-themes"}, "version": "2026.10.6", "location": {"$mid": 1, "path": "<home>/.vscode-oss/extensions/pj.letterpress-themes", "scheme": "file"}, "relativeLocation": "pj.letterpress-themes"}
   ```

   Or run `dotfiles/.local/bin/codium-themes-install` (bash and Python 3), which writes that entry for both editors and changes nothing else.
4. Restart the editor, or run *Developer: Reload Window*.

It worked when `codium --list-extensions` prints `pj.letterpress-themes` and the theme picker (Ctrl+K Ctrl+T) lists 17 `Letterpress` themes.

## How it is wired here

`bin/gen-vscode-themes.py` writes every file in this folder from each theme's `waybar.css`, `palette.lua`, `meta.sh` and `kitty.conf`.
`modules/desktop.nix` links the folder at `~/.vscode-oss/extensions/pj.letterpress-themes`.
`codium-themes-install`, linked by `modules/theme.nix`, registers the link in `extensions.json`, and `dram-theme` runs it on each switch.
`dram-theme` also sets `workbench.colorTheme` in `settings.json` to the theme's `VSCODIUM_THEME`, and pins the font keys from `settings.json.default`.
`bin/check-themes.py`, run by `bin/check.sh` §14, fails when a theme's `VSCODIUM_THEME` is not `Letterpress — <MENU_NAME>`.
On Windows, `bin/gen-windows-look.py` imports the generator, packs `package.json` and `themes/` into the VSIX, and `look.ps1` installs it with `codium --install-extension`.
`package.json`'s version, 2026.10.6, is bumped by hand in the generator when the mapping changes: a run date would rewrite the file each day.

To regenerate after a palette change:

```sh
python3 bin/gen-vscode-themes.py           # every theme, and package.json
python3 bin/gen-vscode-themes.py washi     # one theme's JSON; package.json stays as it is
```

## The page in the editor

Every surface of the workbench is the paper (`base`): the editor, the side bar, the activity bar, the status bar, the title bar, the tabs, the panel and the terminal.
Inputs, dropdowns, the find, suggest and hover widgets, the command palette, menus, notifications and peek views sit on the `mantle`.
No bar is colored: hairlines in `alpha(text, .18)` cut the chrome through each `*.border` key, and indent guides and rulers use `.12`.

The one accent carries `focusBorder`, the cursor, links, buttons, badges, the active tab's top rule, the activity-bar and panel-title rules, the progress bar, the peek-view border and the find match.
The find match is an alpha tint of the accent, and `list.activeSelectionBackground` is the accent at 20 %.
The editor's selection is a neutral `alpha(text, .14)` and never an accent fill.
Line numbers are `subtext`, and disabled text and placeholders are `overlay`.
`editorError`, `editorWarning`, `editorInfo` and the gutter, overview-ruler, diff and git decorations take the palette's `red`, `yellow`, `blue` and `green`.

Syntax is set in five inks, with no bold:

| Scope | Ink |
|---|---|
| comments | `subtext`, italic |
| strings | `yellow`, the second tone |
| keywords and storage | the accent |
| types and classes | `blue` |
| built-in types, namespaces, HTML tags | `teal` |
| numbers, constants, booleans, decorators | the accent's second step: `accent_dim` on a light page, the accent mixed 30 % toward the ink on a dark one |
| functions, variables, operators | the body ink |
| punctuation | `subtext` |
| bracket pairs | `text`, `subtext` and `overlay` in turn |

Each syntax ink is raised toward the body ink in 5 % steps until it reads at 4.5:1 or better on the paper, and the accent itself is never changed.
`semanticHighlighting` is on, with the same inks.
The integrated terminal takes `color0` to `color15` from the theme's `kitty.conf`.

## The loading rule

VSCodium reads an extension folder from `~/.vscode-oss/extensions/` only through the `extensions.json` there.
I checked this on Microsoft's VS Code 1.138, which shares the code, with `--extensions-dir` and `--list-extensions`.
With no manifest the editor scans the directory and writes the file itself.
With a manifest present, a folder it does not list is ignored.
A hand-written entry pointing at a symlinked folder without a version in its name loads, and `package.json`'s version wins over the entry's.
A window already open sees a new entry after *Developer: Reload Window*.
Edits to a theme's JSON show when the theme is selected again.

## Files

| File | What it does |
|---|---|
| `package.json` | the manifest: publisher `pj`, version, and the 17 themes under `contributes.themes`; generated |
| `themes/letterpress-<id>-color-theme.json` | one color theme per dram theme, 17 in all; generated |
| `README.md` | this file; the editor shows it in the extension view, and the VSIX leaves it out |

## License

MIT, Patrick Jordan, as `package.json` states.
The colors come from the theme palettes, whose sources and licenses are listed in `dotfiles/.config/themes/README.md`.
A copy of this extension keeps the publisher id `pj`: change `publisher` in `package.json` and the folder name together if you publish your own.

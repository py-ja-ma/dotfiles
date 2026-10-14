# upstream

[Design](../../../docs/design/README.md) › [Themes](../../../docs/design/themes/README.md) › Windows look

Three files from other projects that `bin/gen-windows-look.py` recolors into Letterpress themes for Windows apps.
Each is the upstream file at a release tag, pinned by URL and sha256 in the generator's `VENDORED` table, and the generator stops when a file differs from its pin.
The [Windows look](../../../docs/design/themes/windows.md) covers the rest of the theme on Windows.

| | |
|---|---|
| Needs | Python 3 and `bin/gen-windows-look.py` to use them; the PC gets only the generated files |
| Copy alone | yes: each file is upstream's own at its tag, and each Letterpress version copies on its own |
| License | the GPL version 2 for Notepad++'s theme, the Unlicense for Mumble's stylesheet, GPL-2.0-or-later for Wireshark's rules |

## What it needs

- Python 3 to run `bin/gen-windows-look.py`, on the Mac or any machine with this repo.
  The generator reads each file as ASCII, and the three are plain ASCII at their pinned tags.
- No file of this folder goes to the PC: the Windows build carries the generated files from `install/windows/letterpress/`, and `windows/build/cabin-win/inputs.json` lists none of these.

## Copy it alone

Each file here is the upstream file, byte for byte, so a copy is the file at its pinned URL under [The pins](#the-pins).
To check one, compare its hash with the table:

```sh
sha256sum wireshark/colorfilters     # shasum -a 256 on macOS
```

The Letterpress versions, made from washi's palette, copy to another Windows PC without this repo:

1. Take the app's file from `install/windows/letterpress/`:

   | App | Letterpress file | Copy to |
   |---|---|---|
   | Notepad++ | `notepad++/Letterpress.xml` | `%APPDATA%\Notepad++\themes\` |
   | Mumble | the folder `mumble/Letterpress/`, with `theme.ini` and `Letterpress.qss` | `%APPDATA%\Mumble\Mumble\Themes\` |
   | Wireshark | `wireshark/colorfilters` | `%APPDATA%\Wireshark\`, over the old file |

2. Copy it there, and keep a copy of Wireshark's old `colorfilters` if you edited its rules.
3. Select it: in Notepad++ under Settings › Style Configurator, and in Mumble as the theme in its settings (`look.ps1` sets `ui.theme` in `mumble_settings.json`).
   Wireshark reads `colorfilters` at start.
4. Restart the app.
   It worked when the editor or the Mumble window shows washi's dark paper and vermilion accent, and Wireshark's packet list shows its rows in tints of that paper.

## How it is wired here

`bin/gen-windows-look.py` reads the three files through `vendored()`, which stops the run when a file is missing or its sha256 differs from `VENDORED`, and names the URL.
It writes the Letterpress versions into `install/windows/letterpress/` from washi's palette, the theme recorded in `install/windows/letterpress/theme`.
`bin/check.sh` §19 runs the generator with `--check`, which fails while a committed output differs from what the generator would write.
`windows/roles/desktop.nix` stages `install/windows/letterpress/` for the PC, and `install/windows/dram-windows/look.ps1` installs each file and selects it in its app.

## The pins

| File | From | Pinned URL | sha256 |
|---|---|---|---|
| `notepad++/DarkModeDefault.xml` | Notepad++ v8.9.8.1 | `https://raw.githubusercontent.com/notepad-plus-plus/notepad-plus-plus/v8.9.8.1/PowerEditor/installer/themes/DarkModeDefault.xml` | `978b086b70368aee5e7f530103242485e581ae98b571a55217927ca56fff9a70` |
| `mumble/Dark.qss` | Mumble v1.5.939 | `https://raw.githubusercontent.com/mumble-voip/mumble/v1.5.939/themes/Default/Dark.qss` | `2218e729c5f20162e875d29818643aa39e30200f903c475e069144f8cfc041c7` |
| `wireshark/colorfilters` | Wireshark v4.6.9 | `https://raw.githubusercontent.com/wireshark/wireshark/v4.6.9/resources/share/wireshark/colorfilters` | `0db519d9bb85865c4c7f4b5145af7b2ee47809c42b34e1d86b7c8cd7cdaa372b` |

Each URL served these exact bytes on 2026-10-13.
`mumble/LICENSE` is the `LICENSE` beside `Dark.qss` in Mumble's `themes/Default/` at v1.5.939, byte for byte, and the generator neither reads nor pins it.

## What the generator derives

### Notepad++

`notepad++/Letterpress.xml` keeps the 92 lexers of `DarkModeDefault.xml` with their 1,755 styles, and its 53 global styles, and changes only colors and font styles.
A lexer style takes its ink from its name, and the first matching rule of `NPP_RULES` wins.
Comments are `subtext` italic, and keywords are the accent.
Strings, numbers, types and built-ins take the syntax inks of the [letterpress-themes](../../../dotfiles/.vscode/extensions/letterpress-themes/README.md) editor themes.
Errors are `red`, and the rest is the body ink, on the paper.
Bold is set only where the markup asks for it: the headings and strong text of the txt2tags lexer, and the bold colors of the escape-sequence lexer.
A global style maps by its name through `npp_globals()`, and one the generator does not know stops it.
The default style and the global override take Monaspace Xenon at 11.
The header comment is replaced by the generator's, which keeps the attribution: "based on Zenburn" and "License: GPL2".
`modelDate` becomes the one of v8.9.8.1's `stylers.model.xml`, 20260525, so Notepad++ does not merge its model's styles into the theme at startup.
`notepad++/darkmode.json`, with Notepad++'s own dark-mode colors and its updater off, is the generator's own and is not derived from the upstream file.

### Mumble

`mumble/Letterpress/Letterpress.qss` is `Dark.qss` with each of its 38 colors replaced through `mumble_map()`, and a color the map does not know stops the generator.
The window and lists go on the paper and `mantle`, selection and hover become paper shades, and links take `blue`.
Two of Mumble's blues and its status colors take the accent, `yellow`, `red` and `green`.
Two rules are added at the end: focused fields and check boxes get an accent border, and the selected tab a 2 px accent rule.
Images still come from Mumble's own skin (`skin:controls/...`).
`mumble/Letterpress/theme.ini` names the theme Letterpress with one style, Dark for a dark theme and Lite for a light one.

### Wireshark

`wireshark/colorfilters` keeps Wireshark's 21 coloring rules and their filters as they are, and recolors each rule by its name through `WS_RULES`.
The error rules keep Wireshark's look, colored ink on the darkest paper (`crust`), and the other rows are faint tints of the paper under the body ink.
Each ink must read at 4.5:1 on its row, or the build fails.
A rule that Wireshark adds or drops also fails the build until `WS_RULES` maps it.
`wireshark/preferences.json`, with the scheme, the font, and the selection and stream colors, is the generator's own.

## Bumping a pin

1. Download the new tag's file over the one here.
2. In `bin/gen-windows-look.py`, set its URL and sha256 in `VENDORED`, and the tag in `NPP_TAG`, `MUMBLE_TAG` or `WIRESHARK_TAG`.
   For Notepad++, also set `NPP_MODEL_DATE` to the `modelDate` of that tag's `PowerEditor/src/stylers.model.xml`.
3. Update the table under [The pins](#the-pins).
4. Run `python3 bin/gen-windows-look.py`.
   It stops on a global style, a color or a rule it has no mapping for, and on a file that is not ASCII.
5. Review the diff of `install/windows/letterpress/`, and run `bin/render-windows.sh` before the next push to the PC.

## Files

| File | What it does |
|---|---|
| `notepad++/DarkModeDefault.xml` | Notepad++'s dark-mode theme, the source of `notepad++/Letterpress.xml` |
| `mumble/Dark.qss` | Mumble's dark stylesheet, the source of `mumble/Letterpress/Letterpress.qss` |
| `mumble/LICENSE` | the Unlicense, as it sits beside `Dark.qss` in Mumble's repository |
| `wireshark/colorfilters` | Wireshark's default coloring rules, the source of the Letterpress `wireshark/colorfilters` |
| `README.md` | this file |

## License

The files here keep their upstream licenses, and the Letterpress files made from them carry the same ones.

| File here | Its license | Made into | That file's license |
|---|---|---|---|
| `notepad++/DarkModeDefault.xml` | the GPL, version 2: its header says "License: GPL2", and it is based on the Zenburn theme | `notepad++/Letterpress.xml` | the GPL, version 2 |
| `mumble/Dark.qss` | the Unlicense, from the `LICENSE` beside it; its own header names the WTFPL | `mumble/Letterpress/Letterpress.qss` | the Unlicense, or the WTFPL |
| `wireshark/colorfilters` | GPL-2.0-or-later: Wireshark's README puts most of Wireshark under "GPL version 2 or later" | `wireshark/colorfilters` | GPL-2.0-or-later |

The Letterpress `Letterpress.xml` for Notepad++ and `colorfilters` for Wireshark are derived from GPL files, so they are under the GPL too.
Copy them under the GPL's terms, not under the MIT license of the rest of this repo.
Notepad++ as a whole is GPL-3.0 (its `LICENSE` at v8.9.8.1), and the theme file's own header states version 2.
The generator's own files beside them, `notepad++/darkmode.json`, `mumble/Letterpress/theme.ini` and `wireshark/preferences.json`, are MIT, Patrick Jordan, as is this README.

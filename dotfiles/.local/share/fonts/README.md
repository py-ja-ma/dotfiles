# fonts

[Design](../../../../docs/design/README.md) › [Typography](../../../../docs/design/typography/README.md) › House fonts

EB Garamond Italic as one tracked font file: the italic voice of the Letterpress desktop, set at 15 px and up.
It sets the bar's window title, date and track, the lock screen's date, rofi's prompt and the quote wallpaper.
The other house faces come from packages, and [Typography](../../../../docs/design/typography/README.md#house-fonts) lists each face with the surfaces it sets.

| | |
|---|---|
| Needs | fontconfig 2.18.3, tested 2026-10, or any system that installs a TrueType font |
| Copy alone | yes: copy the font together with `OFL.txt` |
| License | OFL-1.1, The EB Garamond Project Authors |

## What it needs

- A font system that reads `~/.local/share/fonts/`: fontconfig 2.18.3 on cabin, tested 2026-10.
  Windows and macOS install the same file from its context menu or Font Book.
- Not needed: Nix, Home Manager or `dram`.

## Copy it alone

1. Copy `EBGaramond-Italic.ttf` and `OFL.txt` to `~/.local/share/fonts/`, or to `/usr/local/share/fonts/` for each account on the machine.
2. Rebuild the font cache:

   ```sh
   fc-cache -f
   ```

3. Check that fontconfig finds it:

   ```sh
   fc-match -f '%{file}\n' 'EB Garamond:italic'
   ```

   On a machine with no other EB Garamond, it prints the path of `EBGaramond-Italic.ttf`.
   An app that asks for "EB Garamond" in italic then sets it in this face, at any weight from 400 to 800.

## How it is wired here

`modules/desktop.nix` links this one file into `~/.local/share/fonts/` on hosts with the desktop role.
`OFL.txt` and this README stay in the repo.
The module tracks the font because the quote wallpaper uses italic cuts that the nixpkgs `eb-garamond` package lacks.
That package is Georg Duffner's 0.016 build, with its italic in one weight at two optical sizes, 08 and 12.
This file is the 2017 continuation by Octavio Pardo, version 1.003, with the italic from weight 400 to 800.
The desktop role installs the nixpkgs package as well, so fontconfig sees both.
Until 2026-10-05 the file was a copy made by hand on the laptop.

Windows gets the same bytes.
`install/windows/fonts.pin` pins this file from Google Fonts by its sha256, and the `fonts-machine` unit installs it for each account ([Fonts on Windows](../../../../docs/design/typography/README.md#fonts-on-windows)).
`bin/gen-avatar.sh` sets [the "pj" seal](../dram/README.md) in the EB Garamond Italic that fontconfig matches.

## The file

- EB Garamond Italic, version 1.003: a variable TrueType font with one axis, weight, from 400 to 800.
- Five named styles: Italic, Medium Italic, SemiBold Italic, Bold Italic and ExtraBold Italic.
- Latin, Greek, Cyrillic and Vietnamese, the subsets Google Fonts lists for it.
- Byte for byte `ofl/ebgaramond/EBGaramond-Italic[wght].ttf` at google/fonts commit `f8c1d3d` of 2026-06-17, sha256 `bba2c4499c93c9612b90b9825d32b07da52fce2fe57562a1eb6b833553f93c4e`.

## Files

| File | What it does |
|---|---|
| `EBGaramond-Italic.ttf` | the font |
| `OFL.txt` | the font's copyright line and the license text |
| `modules/desktop.nix` | links the font into `~/.local/share/fonts/` |
| `install/windows/fonts.pin` | pins the same file for Windows |

## License

SIL Open Font License 1.1 (OFL-1.1), Copyright 2017 The EB Garamond Project Authors: Georg Duffner and Octavio Pardo.
`OFL.txt` holds the copyright line and the license text as octaviopardo/EBGaramond12, the repository the font's copyright line names, publishes them.
That file has a second copyright line, for citation glyphs added in 2025, which `OFL.txt` leaves out: the font's own copyright string and Google Fonts' notice for this build name only the 2017 line.
The license asks each copy of the font to carry its copyright notice and the license, so keep `OFL.txt` with the font.

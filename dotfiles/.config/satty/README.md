# satty

[Design](../../../docs/design/README.md) › [Shell & bars](../../../docs/design/shell-and-bars/README.md) › Screenshots

The configuration for satty, which annotates screenshots in the theme's inks and writes text in Fraunces.
A region or window shot from `screenshot.sh` opens in satty, where Ctrl+C copies the result and Ctrl+S saves it.
`dram theme` splices the active theme's palette line into satty's live config.

| | |
|---|---|
| Needs | satty 0.22.0, tested 2026-10; wl-clipboard; Fraunces; for the binds, grim, slurp and jq |
| Copy alone | yes, after copying the template to `config.toml` |
| License | MIT |

## What it needs

- satty 0.22.0 from Arch's `extra` repo, tested 2026-10.
  It is a GTK 4 program with libadwaita.
- `wl-copy` from wl-clipboard 2.3.0, which the template names as the copy command.
- The Fraunces font for the text tool ([Typography](../../../docs/design/typography/README.md)).
- For the binds, `screenshot.sh` from `dotfiles/.local/bin/` with grim 1.5.0, slurp 1.5.0, jq 1.8.2, `hyprctl` and `notify-send`.
- Not needed: Nix, Home Manager or `dram`.
  Without `dram theme` the palette stays the template's, which is washi's.

## Copy it alone

1. Copy `config.toml.default` to `~/.config/satty/config.toml`.
2. For another theme's inks, replace the `palette = [...]` line with the one in that theme's `satty.toml`.
3. Create `~/pictures/screenshots/`, where the template saves, or change `output-filename`.
4. Copy `dotfiles/.local/bin/screenshot.sh` to `~/.local/bin/` and bind it, or pipe a shot in by hand:

   ```sh
   grim -g "$(slurp)" - | satty --filename -
   ```

5. Select a region.
   satty opens with the arrow tool chosen and the palette's colors in its toolbar.
   Ctrl+C copies the annotated shot and closes satty, and Ctrl+S saves it and closes satty.

## How it is wired here

`modules/desktop.nix` links `dotfiles/.config/satty` whole to `~/.config/satty` on hosts with the desktop role, and `packages/roles/desktop.txt` installs satty.
The live `config.toml` is therefore written into the checkout beside the template, and `.gitignore` keeps it out of git.

satty reads no include and takes no palette flag, and its `--config` flag makes it skip the other config files.
So `dram theme` keeps the palette in the live file.
It copies `config.toml.default` to `config.toml` when the live file is missing, then replaces the `palette = [...]` line with the same line from the new theme's `satty.toml`, using sed.
Each theme's `satty.toml` keeps its palette on one line for that sed.
In each of the 17 themes the first color is the theme's accent, and the count runs from four to six; no check holds either.
To change any other setting, edit the template, delete `config.toml`, and run `dram theme` to seed it again ([Machine-state files](../../../docs/design/themes/switcher.md#machine-state-files)).

## The screenshot binds

`hyprland.lua` binds four keys to `screenshot.sh`, which names each shot `~/pictures/screenshots/screenshot-YYYYMMDD-HHMMSS.png` ([Keybinds](../../../docs/design/shell-and-bars/keybinds.md)):

| Key | Mode | What happens |
|---|---|---|
| Print | `region` | slurp selects a region, and the shot opens in satty |
| SUPER+SHIFT+Print | `window` | the active window's geometry comes from `hyprctl activewindow`, and the shot opens in satty |
| SUPER+CTRL+Print | `output` | the focused monitor is saved and copied, and a notification gives the path |
| SUPER+Print | `all` | the whole desktop, across the monitors, is saved as one file and copied, and a notification gives the path |

For satty the script pipes the PNG to `satty --filename - --output-filename <path>`.
The path has the same pattern as the template's `output-filename`, so annotated and plain shots sort together.
Without satty a region or window shot goes to the clipboard alone, and a notification says so.
Escape in slurp cancels a region shot with no message.
A missing grim or jq stops each mode with a critical notification.

`ocr-copy.sh` (SUPER+SHIFT+X) takes a region with the same grim and slurp and does not open satty.
tesseract 5.5.3 reads the region in English, `wl-copy` takes the text, and a notification shows its first 120 characters.

## The template

| Key | Value | What it does |
|---|---|---|
| `fullscreen` | `false` | opens satty as a window |
| `early-exit` | `true` | closes satty after a copy or a save |
| `initial-tool` | `"arrow"` | starts with the arrow |
| `copy-command` | `"wl-copy"` | hands the image to the Wayland clipboard |
| `output-filename` | `"~/pictures/screenshots/screenshot-%Y%m%d-%H%M%S.png"` | where Ctrl+S saves when no script names the file |
| `save-after-copy` | `false` | Ctrl+C copies without saving |
| `corner-roundness` | `3` | the house 3 px radius on rectangles |
| `annotation-size-factor` | `1.5` | strokes and text at 1.5 times satty's size |
| `[font]` `family`, `style` | `"Fraunces"`, `"Regular"` | the text tool's face |
| `[color-palette]` `palette` | four to six colors | the toolbar's inks, replaced by `dram theme` |

## Files

| File | What it does |
|---|---|
| `config.toml.default` | the tracked template, which `dram theme` copies to the live `config.toml` |
| `dotfiles/.config/themes/<theme>/satty.toml` | each theme's `palette = [...]` line |
| `dotfiles/.local/bin/dram-theme` | seeds `config.toml` and splices the palette line |
| `dotfiles/.local/bin/screenshot.sh` | takes the shot and opens it in satty, or saves and copies it |
| `dotfiles/.local/bin/ocr-copy.sh` | copies the text of a region to the clipboard |

## License

MIT, Patrick Jordan.

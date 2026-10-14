# Terminal

[Design](../README.md) › [Shell & bars](README.md) › Terminal

A terminal on an Arch host is three programs: kitty draws the window, bash runs the commands, and starship writes the prompt.
kitty holds the active theme's 16 colors, and the prompt and most tools print in them, so `dram theme` recolors the whole terminal.
On Windows, Windows Terminal takes kitty's settings and washi's colors.

| | |
|---|---|
| Code | [`dotfiles/.config/kitty/`](../../../dotfiles/.config/kitty/README.md), `modules/shell.nix`, `modules/cli.nix`, `dotfiles/.config/btop/`, `dotfiles/.config/cava/`, [`dotfiles/.config/yazi/`](../../../dotfiles/.config/yazi/README.md), `bin/gen-tui-themes.py`; on Windows `install/windows/letterpress/` (generated) and `install/windows/dram-windows/look.ps1` |
| Runs on | each Arch host and WSL clone; kitty and cava with the desktop role (cabin, lantern, campfire); Windows Terminal on cabin-win |
| Needs | kitty 0.49.2, cava 1.0.0 and yazi 26.9.1 from pacman, the other tools from nixpkgs at the versions below, Monaspace 1.400; tested 2026-10 |
| Decided in | Windows Terminal and the prompt as on Arch ([decided 2026-10-12](../../../decisions/log.md#d86)); fastfetch, ble.sh and duf removed under [the software rules](../../../decisions/0013-software-rules-and-waivers.md) |

## How it works

kitty draws Monaspace Xenon over a tiled paper grain, sets italics in Monaspace Radon, and keeps 20,000 lines of scrollback, which Ctrl+Shift+G opens in a pager.
Its colors come from `~/.config/themes/current/kitty.conf`: the active theme's 16 ANSI colors, its cursor and its tab bar.
[kitty's README](../../../dotfiles/.config/kitty/README.md) covers its configuration, its keys and the running head of tabs.

kitty starts bash, and bash reads `~/.bashrc`, which Home Manager writes from `modules/shell.nix`.
The file keeps duplicate lines and lines that start with a space out of the history, which holds 50,000 lines in memory and 100,000 in `~/.bash_history`.
It defines the aliases below and loads fzf's keys, zoxide's `z` and starship's hook.
Its last lines load bash-preexec and atuin, so atuin's Ctrl-R replaces fzf's.
kitty adds its own shell integration when it starts bash, with no line in `~/.bashrc`.
Through it, a command that runs 10 s or more in a window without focus ends with a notification.

Before each prompt, bash runs starship, which reads `~/.config/starship.toml` and prints two lines.
[Prompt](prompt.md) reads them segment by segment.

| Part | Colors from | How `dram theme` changes them |
|---|---|---|
| kitty, the prompt, eza, fd, ripgrep | the 16 colors in `themes/current/kitty.conf` | repoints `current`, then sends kitty `SIGUSR1` |
| bat | the theme's `BAT_THEME` in `meta.sh`: `ansi`, the 16 colors, for eleven themes, and one of bat's own themes for the other six | writes `~/.config/bat/config` |
| fzf | `themes/current/fzf.opts`, read through `FZF_DEFAULT_OPTS_FILE` | repoints `current` |
| btop, cava | generated theme files ([TUI monitors](#tui-monitors)) | links btop's, splices cava's, then sends both `SIGUSR2` |
| yazi | a generated flavor for each theme ([yazi](#yazi)) | rewrites two lines of `~/.config/yazi/theme.toml` |

bash, starship, the tools and btop come from Home Manager, and yazi from `packages/base.txt`, so each Arch host and each WSL clone has them.
kitty and cava come with the desktop role.
`EDITOR` and `VISUAL` are vim on each host (`modules/cli.nix`).
bash-completion, from `packages/base.txt`, completes `dram` on Tab.
pacman gets no completion: its completion reads the package database, whose null bytes make bash print a warning.

## The command-line tools

| Tool | In place of | Use | Version |
|---|---|---|---|
| eza | `ls` | the aliases `ls`, `ll`, `la` and `tree`; `ll` and `la` add a git column | 0.23.5 |
| bat | `cat` | `cat <file>` prints with syntax colors and no pager, and `bat <file>` pages | 0.26.1 |
| fd | `find` | `fd <name>`, `fd -e lua` for an extension, `-H` for hidden files | 10.5.0 |
| ripgrep | `grep -r` | `rg <pattern>`: smart case, hidden files searched, `.git/` skipped (`programs.ripgrep` in `modules/dev.nix`) | 15.2.0 |
| zoxide | `cd` | `z <part of a path>` and `zi`, the keys below | 0.10.0 |
| fzf | typing a path | Ctrl-T and Alt-C | 0.74.4 |
| atuin | bash's own Ctrl-R | Ctrl-R, with the history kept in `~/.local/share/atuin` | 18.21.0 |
| tealdeer | `man` | `tldr <command>` shows the common uses as examples | 1.9.0 |
| dust | `du -sh *` | `dust <dir>` draws the space each entry takes as a tree | 1.2.6 |
| yazi | `mv` and `cp` by hand | `yazi`: arrows or `h j k l` to move, Space to select, `y` to copy, `x` to cut, `p` to paste, `q` to quit | 26.9.1 |
| btop | `top` | `btop`: the CPU, memory, disks, network and processes, with `h j k l` as arrows | 1.4.7 |

The versions are those Home Manager built on cabin on 2026-10-11 from `flake.lock`, and pacman's for yazi.
duf left on 2026-10-11: it had no commit in 12 months, which fails the Community rule of [the software rules](../../../decisions/0013-software-rules-and-waivers.md), and `df -h` and `dust` cover it.
fastfetch left on 2026-10-10 under the Origin rule.

| Key | From | What it does |
|---|---|---|
| Ctrl-R | atuin | searches the history with fuzzy matching in a 15-line list; Enter puts the command on the line, and a second Enter runs it |
| Up | bash | steps back through bash's own history: atuin loads with `--disable-up-arrow` |
| Ctrl-T | fzf | lists the files below the current directory, hidden ones included and `.git` left out, with a bat preview, and types the chosen path |
| Alt-C | fzf | lists the directories the same way, with a two-level eza tree as the preview, and changes into the chosen one |
| `z <name>` | zoxide | changes to the visited directory that best matches, ranked by its visits, the recent ones weighing more |
| `zi` | zoxide | the same, picked from a list in fzf |

fzf opens in 40 % of the window's height, its prompt at the top, inside a border (`FZF_DEFAULT_OPTS` in `modules/shell.nix`).

`modules/shell.nix` defines these aliases:

| Alias | Runs |
|---|---|
| `ls` | `eza --group-directories-first` |
| `ll` | `eza -l --git --group-directories-first` |
| `la` | `eza -la --git --group-directories-first` |
| `tree` | `eza --tree` |
| `cat` | `bat --paging=never` |
| `grep` | `grep --color=auto` |
| `..` | `cd ..` |
| `upgrade` | `dram update --clean` |
| `vpn`, `vpn-down` | `sudo wg-quick up home`, `sudo wg-quick down home` |
| `backup` | `borgmatic --verbosity 1` |
| `backup-eva` | `bash <repo>/system/backup-eva.sh` |
| `k`, `kx`, `kn`, `t` | `kubectl`, `kubectx`, `kubens`, `talosctl`, which the sysadmin role installs |

Home Manager's own eza aliases are off, so there is no `lt` or `lla`.
`lg` is lazygit's wrapper function, from `modules/dev.nix`.

## TUI monitors

btop and cava are set as the page: no background of their own, so kitty's grain shows through, the body ink for text, one hairline gray for the boxes, and the theme's accent for the graphs.
Each graph runs through three stops, from a faint tint of the accent to the full accent.
Until 2026-10-06 the files had four box colors and a six-color rainbow.

`bin/gen-tui-themes.py` writes `btop.theme` and `cava.theme` into each theme's directory from its `waybar.css` (`base`, `text`, `subtext`, `overlay`, `surface0`, `surface1`, `red`) and the accent in its `palette.lua`.
It rewrites a file only when the content differs, prints each file it rewrote, and its output is committed.
Faint is a color mixed 55 % of the way to the paper (`base`), and mid is one mixed 25 %.

| Palette | btop keys | cava keys |
|---|---|---|
| none | `main_bg` is empty, and `btop.conf` sets `theme_background = false` | `background = default` |
| `text` | `main_fg`, `title` | `foreground` |
| `accent` | `hi_fg`, `selected_fg`: the hotkey letters and the selected row's text | `gradient_color_3` |
| `surface0` | `selected_bg`, the selected row | |
| `overlay` | `inactive_fg` | |
| `subtext` | `graph_text`, `proc_misc` | |
| `surface1` | `meter_bg` | |
| `subtext` 40 % of the way from the paper | `cpu_box`, `mem_box`, `net_box`, `proc_box`, `div_line`: one hairline | |
| faint, mid, `accent` | `cpu_*`, `free_*`, `used_*`, `available_*`, `download_*`, `process_*` | `gradient_color_1` to `_3`, with `gradient_count = 3` |
| faint, mid, `subtext` | `cached_*`, `upload_*`: the muted second tone | |
| faint, `accent`, `red` | `temp_*`: red only at the hot end | |

### btop

btop 1.4 looks up `color_theme` by name in its theme directories (`~/.config/btop/themes/`, a `--themes-dir`, the shared one), and for an absolute path outside them it falls back to its Default theme with no message.
So `dram theme` links `themes/current/btop.theme` as `~/.config/btop/themes/dram.theme`, and `btop.conf` names `color_theme = "dram"`.
btop writes each of its keys back to `~/.config/btop/btop.conf` when it exits (`save_config_on_exit`), so the live file is btop's.
`modules/cli.nix` links only the template, `dotfiles/.config/btop/btop.conf.default`.
The template sets `color_theme = "dram"`, `theme_background = false`, `truecolor = true`, `rounded_corners = false`, `graph_symbol = "braille"`, `vim_keys = true` and `update_ms = 1000`.
`dram theme` copies it into place when the live file is missing, sets `color_theme`, `rounded_corners` and `theme_background` back to these values on each switch, and sends btop `SIGUSR2` to read the theme again.

### cava

`modules/desktop.nix` links the whole `dotfiles/.config/cava/` directory, and the live `config` beside the template is gitignored.
The template, `config.default`, draws thin bars (`bar_width = 1`, `bar_spacing = 1`, as many as fit) at 60 frames a second from PulseAudio, in ncurses and in stereo.
`dram theme` copies it to `config` when that is missing, replaces the `[color]` block with the theme's `cava.theme`, sets `bar_width = 1` again, and sends cava `SIGUSR2`, which reloads the colors.

A live file seeded from an older template keeps its other keys, so a change to `graph_symbol` or `bar_spacing` reaches a host only after its live file is removed ([Use it](#use-it)).

`btop` shows square hairline boxes, the grain through the page, one ink in each graph, and the accent only on hotkey letters and the selected row.
`cava` with nothing playing shows its baseline row in the faint stop, and with music the bars climb into the accent.
After `dram theme washi-day`, both show ink on cream.

## yazi

yazi comes from pacman on each host (`packages/base.txt`), and `modules/cli.nix` links its files one by one, because the live `theme.toml` is machine state.
`yazi.toml` hides dotfiles, sorts names naturally with directories first, and shows each file's size.
It caps image previews at 1200 × 1600 px and shows a tab as four spaces in text previews.
`init.lua` makes the status bar show the whole mode word (`NORMAL`, `SELECT`, `UNSET`), where yazi cuts it to three letters.
`package.toml` declares no dependencies, so `ya pkg` installs none.
The colors are one flavor per theme, `flavors/letterpress-<id>.yazi`, written by `bin/gen-yazi-flavors.py`.
`dram theme` sets both the `dark` and the `light` line of `theme.toml` to the theme's flavor: yazi picks between them by the terminal's background, and the theme decides that background.
[yazi's README](../../../dotfiles/.config/yazi/README.md) has the flavors and how they map the palette.

## Windows

On cabin-win, Windows Terminal hosts each console program, and it is set up item by item as kitty is ([decided 2026-10-12](../../../decisions/log.md#d86)).
`bin/gen-windows-look.py` writes its keys from washi's palette files into `install/windows/letterpress/wt-settings.json`, and `look.ps1` merges them into Windows Terminal's `settings.json` at each converge.

| kitty | Windows Terminal |
|---|---|
| Monaspace Xenon 12 with `calt`, `liga` and `ss01` to `ss03` | the same face, size and features |
| Symbols Nerd Font Mono for private-use codepoints, through `symbol_map` | `Monaspace Xenon, Symbols Nerd Font Mono` as the face, a fallback list |
| Monaspace Radon for italics | Xenon's own italic: Windows Terminal takes one family |
| the beam cursor | `cursorShape` `bar` |
| padding 10 | `padding` `10` |
| 20,000 lines of scrollback | `historySize` 20000 |
| the bell as a window alert | `bellStyle` `window` and `taskbar` |
| the theme's 16 colors | the `Washi` scheme, with `adjustIndistinguishableColors` `never` so the colors stay as given |
| opacity 0.92 over the paper grain | opacity 100, no acrylic and no grain |

The same file sets Windows Terminal's own theme, `letterpress`: dark, no Mica, the tab row in washi's paper, the active tab in the terminal's background, and a tab's close button only on hover.
The default profile is PowerShell 7 when it is installed.
`wt-schemes.json` holds the 17 themes as color schemes named after their ids (`Washi`, `Washi Day`, `CRT` and the rest).
`look.ps1` puts it at `%ProgramData%\Microsoft\Windows Terminal\Fragments\dram\letterpress.json`, a fragment each account on the PC reads.
The fonts come from `install/windows/fonts.pin` ([Typography](../typography/README.md)).

The units `terminal-default-console` and `terminal-default-terminal` in `windows/roles/base.nix` make Windows Terminal the host of each console program.
conhost, the classic console, draws anything Windows Terminal does not host, and the unit `conhost-letterpress` gives it washi's 16 colors: `ColorTable00` to `ColorTable15` under `HKCU\Console`, from `letterpress/conhost.json`.

Windows Terminal makes a profile of its own for each WSL distribution, and the clone's profile takes the defaults above, so it opens in Washi and Monaspace.
Inside, bash and starship run from Home Manager as on Arch, because `modules/shell.nix` and `modules/cli.nix` apply to the clones.
`letterpress/wsl/terminal-profile.json` holds the same profile and the Washi scheme as a template.
The render stages it with the rest of `letterpress\`, and as of 2026-10-13 no script uses it.

PowerShell 7 and Windows PowerShell 5.1 draw the same starship prompt ([Prompt](prompt.md#on-windows)).
cmd keeps its own prompt, in the scheme's colors.
Git Bash would take a generated mintty theme, and `look.ps1` skips it because Git for Windows is not installed ([decided 2026-10-12](../../../decisions/log.md#d108)).

## Use it

```sh
dram theme <id>                       # kitty, bat, fzf, btop, cava and yazi take the theme
python3 bin/gen-tui-themes.py         # after a palette change: btop.theme and cava.theme for each theme
python3 bin/gen-tui-themes.py washi   # only the themes named
rm ~/.config/btop/btop.conf ~/.config/cava/config && dram theme <id>   # seed both from their templates again
```

`gen-tui-themes.py` prints one `wrote dotfiles/.config/themes/<id>/btop.theme` line for each file it changed, and stays silent when the files are current.
On Windows, `python3 bin/gen-windows-look.py` writes `install/windows/letterpress/` again after a palette change, and `bin/check.sh` §19 fails while that directory is stale.
[Windows look](../themes/windows.md) has the push that takes it to the PC.

## When it breaks

| Symptom | Check | Fix |
|---|---|---|
| fzf, Ctrl-T and Alt-C quit at once | `dram doctor` warns that `themes/current` does not resolve to a theme | `dram switch`, which seeds it with washi |
| btop shows its own Default theme in green, olive and purple | `grep '^color_theme' ~/.config/btop/btop.conf` prints a path, or `~/.config/btop/themes/dram.theme` is missing | `dram theme <id>` |
| `dram switch` stops at `~/.config/yazi/flavors` | the directory is a real one, left by an old `ya pkg install` | `rm -rf ~/.config/yazi/flavors && dram switch` |

## Limits

- bash draws no right-hand prompt since ble.sh left on 2026-10-10, so the duration, the battery and the clock do not show ([Prompt](prompt.md#reading-the-prompt)).
  kitty's notification still marks a long command in a window without focus.
- Nothing checks `btop.theme` and `cava.theme` against their palettes.
- No step in a WSL clone runs `dram theme`, so btop, yazi and bat keep their stock colors there, while the prompt and fzf follow washi.
- Windows Terminal stays at opacity 100 without grain: kitty's 92 % has not been tried there with Windows' transparency effects off.
- Windows Terminal draws washi: the other 16 schemes are in its list, and `look.ps1` sets Washi as the default again at each converge.

# check.sh

[Operations](../README.md) › [Quality](README.md) › check.sh

`bin/check.sh` checks the repo's invariants without Nix, so it runs on the Mac as well as on a host.
It exits 1 on any failure, and warnings do not fail it.

| | |
|---|---|
| Code | `bin/check.sh`, and the helpers each section names |
| Runs on | the Mac (bash 3.2), each host through `dram check`, CI; `bin/release.sh` runs it before it tags |
| Needs | bash, git, grep, awk, python3; shellcheck and shfmt 3.11, each skipped with a warning when missing; luac for §16 and OpenSSL 3 for §22, the same way; bsdtar and curl for §19's test |
| Decided in | the sections cite their decision records |

## How it works

Each section prints `[ok]`, `[warn]` or `[FAIL]` lines under its number, and the run ends with the count of failures and warnings.
The script's header lists the sections, and this table follows it as of 2026-10-14:

| § | Checks | Fails when |
|---|---|---|
| 1 | dotfile link targets | a `link "…"` in `modules/*.nix` has no file under `dotfiles/`, gitignored runtime seeds excepted |
| 2 | hosts | `modules/hosts/<h>.nix` and `hosts/<h>/` do not pair up |
| 3 | package lists | a list has an inline comment, two names on a line, a duplicate, or an AUR name; it warns on a declared name no host installed and an explicit package no list declares |
| 4 | bash scripts | shellcheck finds a warning, or `shfmt -i 2 -ci -bn` would change a script |
| 5 | interpreters | a Python program has a `.sh` name: a warning, a failure with `CHECK_STRICT=1` |
| 6 | documentation paths | a backticked repo path in the checked pages does not exist |
| 7 | secrets | a tracked file's name looks like a secret, or a file holds a private key or a token |
| 8 | `flake.lock` | a warning when it is older than 60 days |
| 9 | `/usr/bin` in Nix | a `/usr/bin/<bin>` in `modules/*.nix` has no package in a list |
| 10 | Waybar | the `jsonc` files do not parse, or the captions and spacing break the house rules (`bin/check-waybar.py`) |
| 11 | host flags | a host file lacks `hostName`, a one-line `roles` with a list per role, `isLaptop` or `gpu` |
| 12 | `pkgs/` | `bin/pkgs.sh check` fails: manifest and directories, pins, shadowing |
| 13 | `--help` | a script's `--help` fails or does not start with `usage:`, a bad flag does not exit 2, a script with a `usage:` header is not mode 100755, or `docs/commands.md` is stale |
| 14 | themes | `/home/pj` appears under `dotfiles/.config`, or the theme directories differ in schema (`bin/check-themes.py`) |
| 15 | the register | `bin/check-register.py` fails ([Quality](README.md#the-register-checker)) |
| 16 | Gaming Mode | `tests/gaming-switch.sh` fails, or a `hypr/*.lua` file does not parse |
| 17 | recording | `tests/rec-websocket.py` fails, or `dotfiles/obs/` holds a stream key, a password or a home path |
| 18 | YubiKeys | `keys/ssh.pub` or `keys/pam-u2f.txt` breaks its format, a label repeats, or `tests/yubikey-t0.sh` fails |
| 19 | Windows | `install/windows/letterpress/` or `windows/build/` is stale, a Windows source has a non-ASCII byte, or `tests/push-windows.sh` fails |
| 20 | the case display | `tests/case-display.py` fails |
| 21 | WSL clones | a `packages/wsl-skip.tsv` row has no reason or names nothing, or a clone's plan holds a metal, hardware or `[dram]` name or a session role |
| 22 | the org chart | `docs/map.tsv` leaves a tracked path to the catch-all row, or a directorate or division of the chart has no page (`bin/check-docs.py map`) |
| 23 | generated records pages | `docs/catalogue.md`, `decisions/README.md` or the chart in `README.md` and `docs/README.md` differs from what its generator writes |
| 24 | private words | tracked text holds a word from the clone's own list in `.git/info/private.tsv` (`bin/check-docs.py private`) |

### Sections 6 and 13 in detail

§6 reads `README.md`, `CHANGELOG.md`, `docs/*.md`, `docs/records/handbook/*.md`, `decisions/*.md` and a few named READMEs.
It checks each backticked path under `system/`, `bin/`, `install/`, `modules/`, `packages/`, `docs/`, `dotfiles/`, `hosts/`, `decisions/`, `pkgs/` and `secrets/`, and accepts a prefix such as `decisions/0003`.
It skips placeholders: a path with `...`, and a segment in capitals such as `hosts/OLD/`.
`docs/history/` and `decisions/0007-rename-rice-to-dram.md` are left out: both record paths that no longer exist.

§13 puts stand-ins for `ssh`, `hyprctl`, `rofi`, `home-manager`, `borgmatic`, `pacman` and `notify-send` first on `PATH`, so a script with broken help cannot act.
It runs each `dram` subcommand with `--help` and with a bad flag against a throwaway clone and a throwaway `HOME`, and fails if the clone changed.
Then `bin/gen-commands-doc.py --check` compares `docs/commands.md` with what the headers produce.

### Settings

| Variable | Effect |
|---|---|
| `CHECK_STRICT=1` | style warnings (§5) fail |
| `CHECK_PKGDB=1` | §3 also resolves each package name against the Arch mirrors (`bin/check-pkgnames.py`, downloads the databases) |
| `CHECK_ROLLOUT=1` | §15 fails on `swap` and `pending` verdicts; set it before rebuilding a machine |

## Use it

```sh
bash bin/check.sh                    # on the Mac
dram check                           # on a host: this, then nix flake check
CHECK_PKGDB=1 bash bin/check.sh      # plus the package names against the mirrors
```

A run takes about 40 seconds on the Mac.

## When it breaks

| Symptom | Fix |
|---|---|
| `docs/commands.md is stale` | `python3 bin/gen-commands-doc.py`, and commit the result with the header change |
| `windows/build is stale` | `bin/render-windows.sh`, and commit `windows/build/` |
| `install/windows/letterpress is stale` | `python3 bin/gen-windows-look.py`, and commit the result |
| `shfmt: <file>` | `shfmt -i 2 -ci -bn -w <file>` |
| `docs reference a path that does not exist` | fix the path in the page the message names |

## Limits

- §6 reads one level of `docs/`, so pages under `docs/<directorate>/` and module READMEs are not checked yet, and neither are Markdown links or paths under `windows/`, `tests/`, `keys/` and `templates/`.
- No section checks that a `see:` line in a script header names a file that exists.
- §13 does not run `dram boot-to`, which exits 1 for a bad flag on a machine without `efibootmgr`.

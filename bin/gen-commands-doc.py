#!/usr/bin/env python3
"""usage: gen-commands-doc.py [--check]

Writes docs/commands.md from the scripts' own `usage:` headers: the "which
command when" tables (data in this file), then every script under
dotfiles/.local/bin, bin/, system/ and install/ with its usage block verbatim
and what invokes it (keybinds parsed from hyprland.lua, bar modules from
waybar/modules.jsonc, timers and callers from a table here), then the shell
aliases from modules/shell.nix. Deterministic and idempotent: running it twice
produces no diff. Needs only python3 and the repo; runs on the Mac. bin/check.sh
§13 runs it with --check.

  --check       write nothing; exit 1 (with a diff) when docs/commands.md is stale
  -h, --help    this text

needs:  python3; scripts whose leading comment block, or docstring, is their --help
alone:  yes, after replacing the WHEN and INVOKED tables and the paths it reads
here:   bin/check.sh §13 runs --check; run it by hand after editing a script's header
exit:   0 ok · 1 --check found a difference, or a script has no header · 2 bad usage
see:    docs/commands.md, docs/operations/dram/README.md
"""
# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT
import ast
import difflib
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "commands.md")
HYPR = os.path.join(ROOT, "dotfiles", ".config", "hypr", "hyprland.lua")
WAYBAR = os.path.join(ROOT, "dotfiles", ".config", "waybar", "modules.jsonc")
SHELL_NIX = os.path.join(ROOT, "modules", "shell.nix")

DIRS = [
    ("dotfiles/.local/bin", "`~/.local/bin` — on every host",
     "Linked into `~/.local/bin`: `dram` and its two shims by `modules/cli.nix` on every host, "
     "the rest by `modules/desktop.nix` (the desktop's own commands)."),
    ("bin", "`bin/` — the Mac (and `dram check` / `dram pkgs` on a host)",
     "Repo tooling: checks, generators, the Mac-side host tools."),
    ("system", "`system/` — root on a host",
     "The system layer (`/etc`, the ESP, the initramfs): `sudo bash system/<script>`; "
     "every writer has `--dry-run`."),
    ("install", "`install/`",
     "The installer and the Mac's launchd job."),
]
SKIP = {"house-palette.sh", "__pycache__", "check.sh"}

# --------------------------------------------------------------- which command when
# Hand-written data: the inventory of 2026-10-06. Keep each row one line.
WHEN = [
    ("Update", "you want", "run", "and know", [
        ("update everything", "`dram update`",
         "**canonical.** keyring → `paccache` → `pacman -Syu` (official repos + `[dram]`) → `flatpak update` → pacnew / orphans / reboot report → `dram switch` → `dram doctor --brief`"),
        ("the same, old spelling", "`sysupdate`", "a shim: `exec dram update \"$@\"`, flags pass through"),
        ("the monthly one with cleanup", "`upgrade`",
         "a bash alias for `dram update --clean` (`modules/shell.nix`): **interactive shells only** — scripts and `ssh host upgrade` call `dram` directly"),
        ("see what is pending, change nothing", "`dram update --check`", "read-only: `checkupdates` (official + `[dram]`), `arch-audit -u`, then a build (not a switch) of the dram"),
        ("also bump the pinned nix inputs", "`dram update --full`", "`nix flake update`; `flake.lock` is restored if the rebuilt dram fails to switch"),
        ("also expire old generations and collect garbage", "`dram update --clean`", "Home Manager generations older than 7 days + `nix-collect-garbage`"),
        ("update but leave the flake alone", "`dram update --no-switch`", "everything except the final `dram switch`"),
        ("only packages, by hand", "`sudo pacman -Syu`",
         "lower level: no keyring check, no pacnew report, no switch, no doctor — `dram update` wraps these"),
        ("only Flatpaks", "`flatpak update`", "lower level; `dram update` runs it"),
        ("apply the flake after editing `modules/`", "`dram switch` (= `dram-switch`)",
         "the flake for `pj@<host>` with a dated `-b bak-<stamp>`. Bare `home-manager switch` is **forbidden**: it ignores the flake and once tore down every dotfile symlink"),
        ("go back one Home Manager generation", "`dram rollback [N]`", "asks first; `dram switch` goes forward again"),
        ("take a vendored package to its new AUR version", "`dram pkgs update <name>`",
         "**packaging, not updating**: edits `pkgs/<name>` on cabin; then `dram pkgs build`, `dram pkgs publish`, `bin/sync-dram-repo.sh`, and `dram update` installs it"),
        ("converge `/etc`, hooks, timers, services", "`sudo bash system/maintenance.sh`", "**convergence, not updating**: idempotent, `--dry-run` first"),
        ("get this repo's commits onto a host", "`bin/push-host.sh pj@<host>` (Mac)",
         "deploys the repo (tracked files only) plus every tag; `~/.local/bin` is symlinked into it, so scripts are live at once; `dram switch` on the host only when `modules/` changed. A host detached at a release (channel stable) keeps its checkout until `dram update`"),
        ("get a release onto a Windows PC", "`bin/push-windows.sh <host> [--apply]` (Mac)",
         "the flake's render and every file its manifest lists, only what changed since the PC's live release; `dram receive` there checks each sha256 and switches `C:\\ProgramData\\dram`, `--apply` converges, `--dry-run` changes nothing on Windows (`docs/operations/releases/pushes.md`)"),
    ]),
    ("Release", "you want", "run", "and know", [
        ("see what version a host runs", "`dram version`", "from `~/.config/dram/release`, written by `dram switch`: release tag (or `0.0.0-dev`), build id `<date>.<sha>`, channel, Home Manager generation; `--json` for scripts"),
        ("know if a newer build is out", "`dram update --check`", "`dram: <current> -> <target> (N commits)` or `dram: up to date`; **exit 7 when nothing at all is pending** (packages, Flatpaks, dram) — the SteamOS convention. The welcome toast and the bar badge say the same"),
        ("follow releases or the newest push", "`dram channel stable` / `dram channel main`", "**stable** = the latest `v*` tag, **main** = `master` as pushed from the Mac; `dram update` checks the target out before it touches packages. Default: stable once a tag exists"),
        ("read the release notes", "`dram changelog [vX | --since vX]`", "the matching sections of `CHANGELOG.md`"),
        ("cut a release", "`bin/release.sh -m \"<summary>\"` (Mac)", "clean tree + `check.sh` green → next `vYYYY.MM.N` → `CHANGELOG.md` section → annotated tag → `push-host.sh` to every host with `dram.address`; `--dry-run` shows it all, `--checkpoint` marks a build every host must pass through"),
        ("go back to the previous build", "`dram rollback`", "checks out the previous build's commit, activates its Home Manager generation, **prints** (never runs) the `sudo pacman -U /var/cache/pacman/pkg/…` lines for packages that differ; `dram rollback --list` = `dram builds` shows the last 5 recorded builds"),
    ]),
    ("Theme", "you want", "run", "and know", [
        ("switch the theme", "`dram theme [name]` (= `dram-theme`)",
         "without a name: the rofi picker (**SUPER+T**); a name is the bar name or the dir id; `dram theme --list` shows both"),
        ("follow the sun", "`dram-theme-auto`",
         "the systemd user timer runs it **every 10 min** and at login; it only flips `washi` ↔ `washi-day` and the night light, and never overrides a theme picked by hand; `--print` shows the times"),
        ("night light now", "`nightlight.sh`", "**SUPER+ALT+N**; hands control back to the sun on the second press"),
        ("another wallpaper on this monitor", "`wallpaper-menu.sh`", "**SUPER+SHIFT+W**; `quote-wallpaper.sh` repaints the quote wall on the next theme switch or hotplug"),
        ("re-render the quote wallpaper", "`quote-wallpaper.sh [--en|--ru|--show]`", "run at login, by `dram-theme` and by `wallpaper-hotplug.sh`; a theme's `wall.sh` overrides it"),
        ("regenerate a theme's adapter files after editing its palette", "`bin/gen-*.py [theme]`",
         "**dev-time, on the Mac**: rofi, GTK, browser, kitty tabs, TUI, VS Code, yazi; commit the output — `dram-theme` only links files"),
    ]),
    ("Lock", "you want", "run", "and know", [
        ("lock now", "**SUPER+L**", "`pidof hyprlock || hyprlock` (hyprland.lua); no script"),
        ("the power menu", "**SUPER+X** / **SUPER+M**", "`power-menu.sh` (a rofi list): lock, logout, suspend, reboot, shutdown"),
        ("automatic", "`hypridle`", "**30 min** → lock (`loginctl lock-session`; + suspend on battery) · **45 min** → screens off (`dotfiles/.config/hypr/hypridle.conf`)"),
        ("the lid", "`lid.sh open|close`", "disables / re-enables the internal panel while docked; it **does not lock** (hypridle's `before_sleep_cmd` does, on suspend)"),
    ]),
    ("Back up", "you want", "run", "and know", [
        ("automatic", "borgmatic user timer", "**03:00** daily (+ up to 1 h jitter) to the peer host (`modules/backup.nix`, `docs/operations/backups/README.md`)"),
        ("a backup now", "`dram backup` (= `backup` alias)", "`borgmatic --verbosity 1`"),
        ("see or verify what is there", "`dram backup list`, `dram backup check`", "borgmatic list / check"),
        ("a file back", "`dram backup restore ~/path`", "from the latest archive into `/tmp/dram-restore/`; copy it back yourself"),
        ("the third copy on the Mac", "`bin/pull-backups.sh`", "launchd daily **06:00** + at login (`install/mac-launchd.sh`); stages each host's repo under the Borg lock, rsyncs it into `~/backups/borg/on-<host>/`; `--check` prints the copies' age"),
        ("an offline copy on the eva drive", "`backup-eva` alias", "`system/backup-eva.sh`, by hand when the drive is plugged in"),
    ]),
    ("Health", "you want", "run", "and know", [
        ("the host", "`dram doctor`", "read-only; every warning names its fix; `--brief` warnings only, `--boot` adds the boot chain, `--supply` provenance only"),
        ("the repo", "`dram check`", "`bin/check.sh` (nix-free invariants, runs on the Mac too) then `nix flake check` where nix exists"),
        ("pending updates", "`dram update --check`", "see Update"),
        ("the `[dram]` package repo", "`dram pkgs check`", "manifest, pins, no shadowing; `bin/check.sh` §12 runs it"),
        ("reproducibility", "`bin/repro.sh`", "archlinux-repro for the official set, double build + diffoscope for ours (`docs/security/software-supply/integrity.md`)"),
        ("what a system script would do", "`--dry-run`", "every writer in `system/` and `install/bootstrap.sh` take it and need no root for it"),
    ]),
]

# --------------------------------------------------------------- invoked-by (static part)
INVOKED = {
    "dram": "by hand; the bar's updates badge click (`kitty -e dram update`); `dram-switch`, `sysupdate`, the `upgrade` alias",
    "dram-switch": "by hand (shim onto `dram switch`)",
    "sysupdate": "by hand (shim onto `dram update`)",
    "dram-theme": "`dram theme`; `dram-theme-auto`",
    "dram-theme-auto": "systemd user timer every 10 min + at login (`modules/desktop.nix`); `nightlight.sh` (with `--nightlight`)",
    "codium-themes-install": "`dram-theme`, on every switch",
    "quote-wallpaper.sh": "`dram-theme`; `wallpaper-hotplug.sh --show`",
    "check-waybar.py": "`bin/check.sh` §10",
    "check-docs.py": "`bin/check.sh` §6 (`links see`), §22 (`map`) and §24 (`private`)",
    "gen-catalogue.py": "`bin/check.sh` §23 (`--check`); by hand after a module README's fact box changes",
    "gen-org-doc.py": "`bin/check.sh` §23 (`--check`); by hand after `docs/map.tsv`, a decision record or `decisions/log.md` changes",
    "gen-commands-doc.py": "`bin/check.sh` §13 (`--check`); by hand after editing a script's header",
    "gen-windows-look.py": "by hand on the Mac after a palette change (commit the output); `bin/check.sh` §19 (`--check`)",
    "render-windows.sh": "by hand on the Mac (or Arch) after a change under `windows/`, `packages/winget/` or the rice (commit `windows/build/`); `bin/check.sh` §19 (`--check`); `install/windows/apply-windows.sh` (`--check`)",
    "pkgs.sh": "`dram pkgs <cmd>`; `bin/check.sh` §12 (`check`)",
    "pull-backups.sh": "launchd daily 06:00 (`install/mac-launchd.sh`); by hand",
    "release.sh": "by hand on the Mac, when a batch is ready for the hosts (`docs/operations/releases/README.md`)",
    "push-host.sh": "by hand on the Mac; `bin/release.sh` for every host with `dram.address`",
    "push-windows.sh": "by hand on the Mac, for a Windows PC (`docs/operations/releases/pushes.md`); `tests/push-windows.sh` (`bin/check.sh` §19)",
    "apply-ly.sh": "`system-dram.sh`, `harden.sh` step 6, `install/bootstrap.sh`; by hand",
    "apply-refind.sh": "`system-dram.sh` (a `dram apply` hook); by hand",
    "plymouth-setup.sh": "`system-dram.sh` (a `dram apply` hook); by hand",
    "backup-eva.sh": "the `backup-eva` alias; by hand",
    "bootstrap.sh": "by hand on a fresh box (`docs/platforms/arch/install.md`)",
    "mac-launchd.sh": "by hand on the Mac, once",
}
GEN_PY = "by hand on the Mac (dev-time); commit the output"


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def header_of(path):
    """The usage block: the leading # block of a bash script, or the module docstring."""
    src = read(path)
    first = src.split("\n", 1)[0]
    if "python" in first:
        doc = ast.get_docstring(ast.parse(src), clean=False)
        return (doc or "").strip("\n"), "python"
    lines = src.split("\n")[1:]
    block = []
    for l in lines:
        if not l.startswith("#"):
            break
        block.append(re.sub(r"^# ?", "", l))
    return "\n".join(block).strip("\n"), "bash"


def scripts(rel_dir):
    d = os.path.join(ROOT, rel_dir)
    out = []
    for name in sorted(os.listdir(d)):
        p = os.path.join(d, name)
        if name in SKIP or not os.path.isfile(p):
            continue
        with open(p, "rb") as f:
            first = f.readline()
        if not first.startswith(b"#!"):
            continue
        if b"bash" not in first and b"python" not in first:
            continue
        out.append((name, p))
    return out


# --------------------------------------------------------------- hyprland.lua
def key_name(expr):
    expr = expr.strip()
    expr = expr.replace('mainMod .. "', "SUPER").replace('"', "")
    return expr.strip()


def binds():
    """script name -> ["SUPER + X — description", ...] from hl.bind(..., exec_cmd("..."))."""
    out = {}
    pat = re.compile(r'hl\.bind\((.+?),\s*hl\.dsp\.exec_cmd\("((?:[^"\\]|\\.)*)"\)\s*,\s*\{(.*?)\}\s*\)')
    auto = re.compile(r'^\s*hl\.exec_cmd\("([^"]*)"\)')
    for line in read(HYPR).split("\n"):
        if line.lstrip().startswith("--"):
            continue
        m = pat.search(line)
        if m:
            key, cmd, opts = m.groups()
            d = re.search(r'description\s*=\s*"([^"]*)"', opts)
            for s in re.findall(r"\.local/bin/([A-Za-z0-9_.-]+)", cmd):
                desc = d.group(1) if d else cmd.replace("$HOME/.local/bin/", "")
                out.setdefault(s, []).append("**%s** — %s" % (key_name(key), desc))
            continue
        m = auto.search(line)
        if m:
            for s in re.findall(r"\.local/bin/([A-Za-z0-9_.-]+)", m.group(1)):
                out.setdefault(s, []).append("autostart (`hyprland.lua`)")
    return out


# --------------------------------------------------------------- waybar/modules.jsonc
def bar_modules():
    """script name -> ["bar: custom/date (exec)", ...]."""
    out = {}
    module = None
    for line in read(WAYBAR).split("\n"):
        m = re.match(r'^ {2}"([^"]+)":\s*\{', line)  # module keys sit at 2 spaces; nested tables deeper
        if m:
            module = m.group(1)
            continue
        m = re.match(r'^\s*"(exec|on-click|on-click-right|on-click-middle|on-scroll-up|on-scroll-down)":\s*"(.*)"', line)
        if m and module:
            for s in re.findall(r"\.local/bin/([A-Za-z0-9_.-]+)", m.group(2)):
                out.setdefault(s, []).append("bar: `%s` (%s)" % (module, m.group(1)))
    return out


# --------------------------------------------------------------- modules/shell.nix
def aliases():
    src = read(SHELL_NIX)
    m = re.search(r"shellAliases\s*=\s*\{(.*?)\n\s*\};", src, re.S)
    rows = []
    if not m:
        return rows
    for line in m.group(1).split("\n"):
        mm = re.match(r'\s*"?([^"=\s]+)"?\s*=\s*"((?:[^"\\]|\\.)*)";\s*(?:#\s*(.*))?$', line)
        if mm:
            name, val, note = mm.groups()
            val = val.replace("${dram.repo}", "~/git/dotfiles")
            rows.append((name, val, (note or "").strip()))
    return rows


# --------------------------------------------------------------- render
def render():
    kb = binds()
    bar = bar_modules()
    o = []
    o.append("# Commands — which one, when, and every script's `--help`\n")
    o.append("<!-- GENERATED by bin/gen-commands-doc.py from the scripts' own `usage:` headers; "
             "do not edit. Regenerate: python3 bin/gen-commands-doc.py (bin/check.sh §13 fails when stale). -->\n")
    o.append("Every script in `~/.local/bin`, `bin/`, `system/` and `install/` answers `-h` / "
             "`--help` with the block shown below (exit 0) and prints a one-line usage with exit 2 "
             "on a bad argument. `dram <command> --help` works for every subcommand. The first "
             "section says which command to reach for; the rest is the scripts' own text.\n")
    o.append("## Which command when\n")
    for title, c1, c2, c3, rows in WHEN:
        o.append("### %s\n" % title)
        o.append("| %s | %s | %s |" % (c1, c2, c3))
        o.append("|---|---|---|")
        for a, b, c in rows:
            o.append("| %s | %s | %s |" % (a, b, c))
        o.append("")
    for rel, title, blurb in DIRS:
        o.append("## %s\n" % title)
        o.append(blurb + "\n")
        for name, path in scripts(rel):
            block, kind = header_of(path)
            if not block.startswith("usage:"):
                print("%s: no `usage:` header" % os.path.relpath(path, ROOT), file=sys.stderr)
                return None
            o.append("### `%s`\n" % name)
            inv = []
            inv += kb.get(name, [])
            inv += bar.get(name, [])
            static = INVOKED.get(name)
            if static:
                inv.append(static)
            if not inv:
                inv.append(GEN_PY if name.startswith("gen-") else "by hand")
            o.append("invoked by: " + "; ".join(inv) + "\n")
            o.append("```")
            o.append(block)
            o.append("```\n")
    o.append("## Aliases and shims\n")
    o.append("Bash aliases from `modules/shell.nix` (`programs.bash.shellAliases`): interactive "
             "shells only — a script or `ssh host <alias>` must spell the command out.\n")
    o.append("| alias | runs | note |")
    o.append("|---|---|---|")
    for name, val, note in aliases():
        o.append("| `%s` | `%s` | %s |" % (name, val, note))
    o.append("")
    o.append("Shim scripts (real files in `~/.local/bin`, so they work from anywhere):\n")
    o.append("| shim | runs | note |")
    o.append("|---|---|---|")
    o.append("| `sysupdate` | `dram update \"$@\"` | kept for muscle memory and old docs |")
    o.append("| `dram-switch` | `dram switch \"$@\"` | same; never bare `home-manager switch` |")
    o.append("")
    return "\n".join(o)


def _parse_args():
    import argparse
    doc = (__doc__ or "").strip().splitlines()
    ap = argparse.ArgumentParser(
        prog=doc[0].split()[1], usage=doc[0][len("usage: "):],
        description="\n".join(doc[1:]).strip(), add_help=False,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-h", "--help", action="help", help=argparse.SUPPRESS)
    ap.add_argument("--check", action="store_true", help=argparse.SUPPRESS)
    return ap.parse_args()


def main():
    args = _parse_args()
    text = render()
    if text is None:
        return 1
    if args.check:
        old = read(OUT) if os.path.exists(OUT) else ""
        if old == text:
            return 0
        sys.stdout.writelines(difflib.unified_diff(
            old.splitlines(True), text.splitlines(True), "docs/commands.md", "generated"))
        print("docs/commands.md is stale: python3 bin/gen-commands-doc.py", file=sys.stderr)
        return 1
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(text)
    print("wrote docs/commands.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())

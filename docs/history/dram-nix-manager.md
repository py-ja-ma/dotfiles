> **Historical (audit of 2026-07-03).** The reasoning still holds; the names do not:
> `dram-switch` / `sysupdate` are now shims onto `dram switch` / `dram update`
> (`docs/dram-cli.md`), and the config is split over `modules/*.nix`
> (`decisions/0004-module-split.md`), not one `home.nix`.

# How Nix + Home Manager work on this machine (plain-language guide)

Audit date: 2026-07-03, against Home Manager 26.11-pre / Nix 2.34, checked
against the Home Manager manual and current community practice for running
**standalone** Home Manager flakes on Arch. Verdict up front: **this setup is
structurally sound and matches what the community does.** The details below
explain *why* each piece is the way it is, so future-you doesn't "fix" a
deliberate choice.

---

## The two worlds

- **Arch (pacman/paru)** owns the SYSTEM: kernel, Hyprland, waybar, ly, drivers,
  anything that touches /etc or boot. Lists: `packages/*.txt` (what
  `install/bootstrap.sh` installs, split by vendor) and `hosts/<h>/packages/`
  (what each host actually has, via `bin/harvest.sh`). `legacy/pkglist*.txt`
  is an older panasonic snapshot kept only for `legacy/pkgs-snapshot.sh`.
- **Nix Home Manager (HM)** owns the USER layer: CLI tools (bat, eza, fzf,
  starship, fonts…) and every dotfile symlink in `~/.config`. Config lives in
  this repo: `flake.nix` + `modules/*.nix` (imported by `modules/default.nix`) + `modules/hosts/<h>.nix`.

Never let one world own the other's stuff — that's the whole design.

## The flake, in one paragraph

`flake.nix` says "for every file in `modules/hosts/`, build
`homeConfigurations."pj@<host>"` from `modules/default.nix` (which imports the
per-concern modules next to it) plus that host's `modules/hosts/<host>.nix`, using
*exactly* the nixpkgs and home-manager versions written down in `flake.lock`".
That lock file is why a rebuild today and a rebuild in six months produce the
same result — nothing moves until you deliberately update the lock. The same
file gives `nix flake check` one check per host plus the lints (statix, deadnix,
shellcheck), `nix fmt` and `nix develop`, on a host or on the Mac
(`decisions/0006-flake-layout.md`).

- **Apply changes:** `dram-switch` (wrapper for
  `home-manager switch --flake ~/git/dotfiles#pj@$(cat /etc/hostname)`; the hosts
  have no `hostname` binary).
  **Never bare `home-manager switch`** — it ignores the flake, reads the stale
  `~/.config/home-manager/home.nix`, and once tore the dram down.
- **Preview first, change nothing:** `sysupdate --check` — lists pending repo
  (`checkupdates`) and AUR (`paru -Qua`) updates, then *builds* the dram for
  this host (`home-manager build --no-out-link`, or `nix build --no-link` of the
  activationPackage when `home-manager` is not on PATH yet) to prove the flake
  still evaluates. No install, no switch, no new generation. The other
  `sysupdate` options are `--clean` (trim caches/generations/orphans) and
  `--full` (also `nix flake update`); they combine.
- **Update pinned packages** (deliberate, occasional — monthly is a fine cadence):
  ```bash
  cd ~/git/dotfiles
  nix flake update && dram-switch     # then commit flake.lock
  ```
  Commit `flake.lock` every time it changes — the lock file IS the
  reproducibility. Routine `sysupdate` intentionally does *not* touch it.

## Why the dotfiles are "impure" symlinks (mkOutOfStoreSymlink)

The pure-Nix way copies each dotfile into the read-only /nix/store and symlinks
to that copy. You get rollbacks of file *content*, but every one-line tweak to
waybar needs a full `dram-switch` before it takes effect. For a dram you tweak
daily, that's miserable.

So `modules/options.nix`'s `link` helper uses `mkOutOfStoreSymlink`: `~/.config/hypr` → straight into this
git repo. Edits are live instantly AND git-tracked. Trade-offs, eyes open:

- HM rollbacks restore *which files are linked*, not their contents — **git is
  the content rollback** (`git log`, `git revert`). Commit often.
- The repo **must** live at exactly `~/git/dotfiles` (the path is
  baked into the symlinks). Don't move it.
- One subtlety done correctly here: with flakes, `mkOutOfStoreSymlink ./file`
  (a path *literal*) silently points into a store copy that goes stale. This
  config builds the target from a **string** (`"${config.home.homeDirectory}/git/…"`),
  which is the correct pattern — keep it that way if you add entries.

Community verdict: this is a well-known, widely-used pattern for exactly this
use case (fast-iterating desktop configs). Purists prefer store symlinks;
neither is "wrong". **Keep this one.**

## stateVersion (don't touch it)

`home.stateVersion = "26.05"` in `modules/core.nix` records which HM release this
config was born under. It only gates backwards-compatibility shims, and it must
**never** be bumped when you update HM — updating the flake inputs is how you
get new features. (Audit note: it originally said "24.11", a copy-paste from an
older template; corrected to 26.05, the release current at install time. None
of the 24.11→26.05 gated changes affected this config.)

## Generations & disk space (garbage collection)

Every `dram-switch` snapshots a new "generation" (rollback:
`home-manager generations`, then run an old generation's `activate`). They pile
up — ~20 in the first three days here — and each pins old packages in
`/nix/store`, which only shrinks when you garbage-collect.

**The story on this box:** `sysupdate --clean` already does the right thing —
```bash
home-manager expire-generations "-7 days"   # drop old dram snapshots
nix-collect-garbage --delete-older-than 7d  # then actually free the store
```
Run it every few weeks. Two rules the community warns about:
1. Run it **as pj, not sudo** — root's GC misses your user profiles under
   `~/.local/state/nix/profiles`. (sysupdate already gets this right.)
2. Expire generations *first*, GC *second* — GC can only free what no
   generation references.

Standalone HM has no `nix.gc.automatic` timer like NixOS; running
`sysupdate --clean` periodically is the accepted equivalent. Store size at
audit time: 4.0 GB — healthy.

## Session variables on Arch (why this works, and its one gotcha)

`home.sessionVariables` land in a generated `hm-session-vars.sh`, sourced from
HM's `~/.profile` via `~/.bash_profile`. That only runs in **login shells** —
on NixOS the display manager guarantees it, on Arch it depends on the greeter.
**Verified working here:** ly starts the Hyprland session through a login
shell, so the vars (checked: `FZF_DEFAULT_OPTS_FILE`, `PATH` with
`~/.nix-profile/bin`) are present inside Hyprland. `targets.genericLinux.enable
= true` provides the rest of the non-NixOS glue (XDG paths, desktop entries)
and `fonts.fontconfig.enable = true` makes nix-installed fonts visible to Arch
apps — both required on Arch, both present.

Gotcha: a var added to `home.sessionVariables` appears in new terminals after
`dram-switch`, but Hyprland itself (and anything it spawned) only sees it after
**log out / log in**. If a var "isn't working", that's why.

## One local quirk

Hyprland's `exec-once` starts swaync, but the Arch package also ships a systemd
user unit that raced it at login, failed ("already running"), and made every
`dram-switch` print "The user systemd session is degraded". Fixed by masking
the redundant unit: `systemctl --user mask swaync.service` (2026-07-03; must be
re-done on a fresh install — it's in the reinstall checklist).

## If things break

- `dram-switch` fails → the error names the `modules/*.nix` line; nothing was
  applied (switches are atomic — half-broken states don't happen).
- A dotfile symlink is missing → run `dram-switch`; if it reports a clobbered
  file it saved it as `*.bak`.
- Worst case → `docs/new-machine.md` (installer) and `docs/history/rice-reinstall.md`
  (panasonic specifics) rebuild the whole machine from zero.

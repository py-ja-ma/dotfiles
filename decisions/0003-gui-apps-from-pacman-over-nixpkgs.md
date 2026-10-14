# 0003: GUI and GL programs come from pacman, not nixpkgs

[Toolchain › Packaging](../docs/toolchain/packaging/README.md) · accepted 2026-10-05

Anything that opens a window or touches the GPU is a pacman package, and Nix keeps to command-line tools, fonts and the dotfile wiring; the cost is two package managers with a line between them.

## Context

On NixOS, nixpkgs GUI programs find the system's GL drivers. On Arch they do not:
a nixpkgs-built Hyprland, Waybar, or browser links against nixpkgs' own Mesa and
cannot see the NVIDIA driver pacman installed. The usual workaround (nixGL
wrapping via `targets.genericLinux.nixGL`) has mixed results and is one more
thing to break on the NVIDIA desktop.

My maintenance notes of 2026-07, since retired, already put it plainly.
Arch is pacman: the whole system, the kernel and the drivers are pacman packages.
Moving the apps into Nix on top of Arch means two overlapping systems.

## Decision

- **pacman owns** (paru left the hosts 2026-10-10, decisions/0013): anything that opens a window or touches GL/Vulkan/VA-API —
  Hyprland and its ecosystem, Waybar, kitty, browsers, Steam, Electron apps, GTK/Qt
  themes. (Since 2026-10-06 "AUR" means the signed `[dram]` repo I build,
  `decisions/0005-own-package-repo.md`; the Flatpak vendor binaries and emulators are the
  carve-out, `docs/toolchain/packaging/flatpak.md`.)
- **nixpkgs (via the flake) owns:** CLI/TUI tools (`bat eza fd rg btop atuin
  starship`; fastfetch left 2026-10-10, decisions/0013), fonts, and the dotfile wiring. `targets.genericLinux.enable`
  stays on for session-var and XDG integration.
- If a nixpkgs GUI program is ever needed, it must be wrapped with
  `config.lib.nixGL.wrap` and the wrapper chosen per host — never added bare to
  `home.packages`.

## Consequences

- `home.packages` (split over `modules/shell.nix`, `modules/dev.nix`, `modules/desktop.nix`) must stay GUI-free. Review it in that light.
- The one gotcha this creates: a nixpkgs CLI binary shadowing a pacman one on
  `$PATH` (`~/.nix-profile/bin` is prepended). That is intended for the tools
  above; check `type -a <cmd>` before assuming which one you are running.

## How it is checked

`bin/check.sh` §9 fails when a `/usr/bin/<name>` that a module calls is in no package list, so a GUI program the modules start comes from pacman.
`bin/check-register.py` (§15) reads the Nix user layer too, so every `home.packages` name carries a verdict.
Nothing fails a GUI program added to `home.packages`: review catches that.

## History

- 2026-10-05: accepted, making explicit a rule the repo already followed.
- 2026-10-06: the AUR packages moved into the signed `[dram]` repo ([0005](0005-own-package-repo.md)).
- 2026-10-10: paru left the hosts ([0013](0013-software-rules-and-waivers.md)).
- 2026-10-11: the Flatpak carve-out widened to the emulators ([0016](0016-emulation-set-and-flatpak.md)).

# System hooks

[Platforms](../../README.md) › [Arch Linux](../README.md) › System hooks

`dram apply` installs a host's packages, then converges the rest of the system layer from three tables in `system/`.
`apply-hooks.tsv` lists the idempotent scripts each role runs, `files.tsv` the repo files copied verbatim into `/etc`, and `units.tsv` the system units each role needs enabled.
`system/maintenance.sh` is the hook every host runs: pacman's upkeep, its timers and its own pacman hooks.
Nothing on a host updates unattended; the timers only trim the cache, rank mirrors and scan for CVEs.

| | |
|---|---|
| Code | `system/apply-hooks.tsv`, `system/files.tsv`, `system/units.tsv`, `system/maintenance.sh`, `system/hooks/50-pkglist.hook`, `system/hooks/70-proton-pass-sandbox.hook`, `system/pacman-contrib.conf`, `system/reflector.conf`, `system/reflector-tolerant.conf` |
| Runs on | every Arch host; a WSL clone takes the `base` and `wsl` rows and skips what Windows owns |
| Needs | pacman-contrib, reflector, arch-audit, rebuild-detector, all in `packages/base.txt` |
| Decided in | [decision 0008](../../../decisions/0008-system-layer-converge.md) |

## How it works

### Role hooks

Each row of `system/apply-hooks.tsv` names a role, a script, a mode, when it runs, and a note `dram apply` prints.
Rows run from top to bottom, and `dram apply --dry-run` passes `--dry-run` to every script.

| Column | Values |
|---|---|
| role | a role, `base` (every host), `metal` (every host on its own hardware), `wsl` (every clone), or `a,b` for a row that needs both |
| mode | `auto` runs on every apply, unasked with `--yes`; `ask` runs only after a yes at the terminal, never with `--yes` alone |
| when | `pre` runs before the package install, `post` after it |

The `ask` rows are the ones where a mistake costs remote access or a boot: the firewall, the Secure Boot keys, the disk unlock, the boot chain, the builder.
The hooks this division owns:

| Hook | Role | Mode | What it does |
|---|---|---|---|
| `system/maintenance.sh` | base | auto | the pacman upkeep below |
| `system/snapshots-setup.sh` | metal | auto | snapper, the snapshot pacman hooks, a boot entry per snapshot ([Boot chain](boot-chain.md#snapshots)) |
| `system/uki-presets.sh` | metal | auto | a UKI for every installed kernel |
| `system/system-dram.sh` | desktop | ask | rEFInd, the splash, the greeter, one Hyprland session ([Boot chain](boot-chain.md)) |
| `system/windows-esp-retire.sh` | desktop | ask | Windows' boot files off Arch's ESP once Windows has its own ([boot guard](../windows/boot-guard.md)) |
| `system/wsl-setup.sh` | wsl | auto | the clone's own system half ([WSL](../wsl/README.md)) |

The firewall, Secure Boot, TPM2 and YubiKey rows are [Security](../../security/README.md)'s; the `[dram]` repo, Flatpak, builder and role setup rows are [Toolchain](../../toolchain/README.md)'s.

### Files in `/etc`

`system/files.tsv` maps each repo file to its target, the role that takes it, and the hook that writes it.
The hook writes a file only when its content differs and keeps the previous one once as `<file>.bak-<stamp>`.
`dram doctor` compares every target with its source and names the hook to run again.
Files a hook builds from a template (`reflector.conf`, the `pacman.conf` options, the ly and rEFInd configs) are not on the table: their hooks own the comparison.

### Units

`system/units.tsv` lists the system units a host must have enabled, by role.
`dram apply` enables the missing ones, timers with `--now`, and `dram doctor` reports drift.
Its role column also takes `!role` (every host without it) and several conditions joined by `,` that must all hold: `metal,!desktop` is a headless host on its own hardware.
Units whose state depends on something else stay with their script.
NetworkManager must stop networkd and iwd in the same step, iwd runs only with a Wi-Fi device, and Docker is a role a host opts into.
User units belong to Home Manager.

### `maintenance.sh`

| Piece | Where it goes | Effect |
|---|---|---|
| pacman-contrib, reflector, arch-audit, rebuild-detector | installed with `pacman -S --needed` when missing | the tools below |
| `system/hooks/50-pkglist.hook` | `/etc/pacman.d/hooks/` | after every transaction, `pacman -Qqe` and `-Qqm` into `/var/lib/pacman/pkglist.txt` and `aurlist.txt` |
| `system/hooks/70-proton-pass-sandbox.hook` | `/etc/pacman.d/hooks/` | after each `proton-pass-bin` install, removes the setuid bit from its `chrome-sandbox`: unprivileged user namespaces sandbox Electron on Arch |
| rebuild-detector's own hook | shipped by the package | `checkrebuild` after every transaction; checked, not copied |
| `system/pacman-contrib.conf` | `/etc/conf.d/pacman-contrib` | the weekly `paccache.timer` keeps two versions of each package, for an offline downgrade |
| `system/reflector.conf` | `/etc/xdg/reflector/reflector.conf` | the weekly `reflector.timer` writes the ten newest https mirrors in `MAINT_COUNTRY`, sorted by rate |
| `system/reflector-tolerant.conf` | a drop-in for `reflector.service` | a failed refresh keeps the current mirror list: archlinux.org, the mirror-status source, is unreachable from my LAN |
| `/etc/pacman.conf` | single options, by `sed` | `Color`, `VerbosePkgLists`, `ParallelDownloads = 10`, and the `NoExtract` line that keeps a second Hyprland session out of the greeter; a `.bak-<stamp>` before the first edit |
| timers | enabled `--now` | `paccache.timer`, `reflector.timer`, `arch-audit.timer`, and `smartd.service` on the stock `DEVICESCAN` config; `archlinux-keyring-wkd-sync.timer` is only checked |
| arch-audit's drop-in | `/etc/systemd/system/arch-audit.service.d/10-dram.conf` | `SuccessExitStatus=1`: arch-audit exits 1 whenever any installed package has an open CVE, which is a report, not a failure |
| `system/v4l2loopback.conf`, `v4l2loopback-load.conf` | `/etc/modprobe.d/`, `/etc/modules-load.d/` | only where `v4l2loopback-dkms` is installed: the OBS virtual camera's module options, loaded at boot |
| services | enabled | `iwd` only with a Wi-Fi device (`MAINT_IWD=1` forces it), `bluetooth` when bluez is installed; the WireGuard client config is reported, never created |
| `system/limits-hyprland.conf` | `/etc/security/limits.d/20-hyprland.conf` | `rtprio 99` and `nice -10` for the login user, so Hyprland gets the real-time scheduling it asks for at every start; it applies at the next login |

The script exits 1 when a step it attempted failed, and the other steps still run.
Reports about the host's state, such as no Wi-Fi device, no WireGuard config or a swapped-out package still installed, stay `[!]` lines and leave the exit status at 0.
In a WSL clone it skips smartd, Bluetooth and the WireGuard report.

### How an update flows

`dram update` is the only command that upgrades:

```
sudo once ─ keyring (only if behind) ─ paccache -rk2
  ─ pacman -Syu ─ flatpak update ─ pacdiff -o ─ orphans? ─ reboot?
  ─ dram switch ─ dram doctor --brief
```

Between updates the timers trim the cache, rank mirrors and write the CVE report to the journal, and the pacman hooks keep the package lists and the rebuild list current.
The Waybar badge shows the pending count from `checkupdates`, which covers `[dram]`, cached for 30 minutes.
What `dram update` and `dram doctor` do line by line is on [the dram page](../../operations/dram/README.md).

## Use it

```sh
dram apply --dry-run                                          # the plan: packages, files, units, hooks
dram apply                                                    # converge; ask hooks wait for a yes
sudo bash ~/git/dotfiles/system/maintenance.sh --dry-run      # one hook on its own: every change it would make
MAINT_COUNTRY="Germany" sudo -E bash system/maintenance.sh    # another mirror country (default United States)
dram doctor                                                   # drift: files, units, timers, hooks
```

## When it breaks

| Symptom | Check | Fix |
|---|---|---|
| `dram doctor` names a file under `/etc` that differs | the file's row in `system/files.tsv` names its hook | run that hook again, or `dram apply` |
| a unit is not enabled | its row in `system/units.tsv` | `dram apply` |
| `arch-audit.service` shows failed | `systemctl cat arch-audit.service` has no `10-dram.conf` drop-in | `sudo bash system/maintenance.sh` |
| bootstrap warns that `maintenance.sh` reported problems | the `[x]` lines in its output | run it again after the first `dram update` |
| two Hyprland sessions in the greeter | `grep NoExtract /etc/pacman.conf` | `sudo bash system/maintenance.sh`, or `system/system-dram.sh` |

## Limits

- `maintenance.sh` still writes its own files instead of reading them from `files.tsv`: it already converges, and rewriting it untested on a host was the larger risk.
- `dram apply` never upgrades and refuses to run on a half-synced system; `dram update` runs `pacman -Syu` first.
- Undeclared packages are reported, not removed, until `dram apply --prune` and a typed hostname.

# Handbook

[Office of Records](../README.md) › Handbook

Eleven chapters that take a machine from a blank disk to a `dram` host and back out again, in the order the work happens: the ISO, `install/arch-install.sh`, the roles, `dram apply`, Secure Boot, the first login.
They are written for someone with a machine, the Arch ISO and this repo.
Each command in them exists in this repo and answers `--help`.
The install and first-boot path ran end to end in the VM tests (`tests/t2-vm.sh`, `tests/t2-bootstrap.sh`) before the chapters were written; the rest ran on a host or as a dry run.
The machines and their names are on the [Platforms](../../platforms/README.md) page.

The command was called `rice` until 2026-10-06; `dram` is the same tool under its new name, and it moves the old state directories itself ([decision 0007](../../../decisions/0007-rename-rice-to-dram.md)).

## Three commands to know first

```sh
dram --help            # every subcommand on one screen; `dram <cmd> --help` for each
dram doctor            # read-only health report; every warning names its fix
dram update --check    # what is pending, nothing changed; exit 7 = nothing at all
```

## The chapters

| # | Chapter | One line |
|---|---|---|
| 1 | [Install](01-install.md) | the pinned ISO, firmware, `install/arch-install.sh` with a preset and the roles, then `install/bootstrap.sh` phase by phase → systemd-boot with signed UKIs, Secure Boot, the laptop's TPM2; any machine, a new one included |
| 2 | [First login](02-first-login.md) | the greeter and the desktop, then the once-per-machine steps no installer can do: the host's key, its state back to the Mac, the YubiKeys, groups, Bridge, browsers, Proton Pass, the roles' first runs, VPN |
| 3 | [Cadence](03-cadence.md) | what runs on its own (timers, snapshots), what you run daily / weekly / monthly / quarterly, `dram update` and its flags, when to reboot |
| 4 | [Update, version, rollback](04-update-version-rollback.md) | builds, releases, channels; `dram version`, `dram channel`, `dram update --check` (exit 7), the update flow line by line, `dram rollback` to the previous build, the system's snapshots and `dram rollback --system`, cutting a release on the Mac |
| 5 | [Backup and restore](05-backup-restore.md) | backups are paused until the NAS: what protects what today, a file back from a `/home` snapshot, the irreplaceable set to the Mac by hand, turning Borg on again |
| 6 | [Theme and look](06-theme-and-look.md) | the seventeen drinks, `dram theme`, day/night and the night light, wallpaper, fonts, adding a theme |
| 7 | [Packages](07-packages.md) | pacman manifests by role, the `[dram]` repo built on cabin (and from scratch on a fresh builder), the residual AUR set (empty today), adding and vendoring a package |
| 8 | [Secrets](08-secrets.md) | sops-nix with one age key per host plus the two YubiKeys; adding a secret, adding a host, losing a key, the state after the 2026-10 reinstall |
| 9 | [Move or rename](09-move-or-rename.md) | a new LAN or time zone, a host under a new name, without losing its secrets |
| 10 | [Teardown](10-teardown.md) | reinstall a host under its own name; retire a host (`system/decommission.sh --plan`, `bin/forget-host.sh`), a YubiKey, the whole dram, the Mac; what can never be undone |
| 11 | [Troubleshooting](11-troubleshooting.md) | symptom → the check that proves it → the fix, by boot / session / updates / YubiKeys and secrets / network / packages |

## How every chapter is written

| Rule | What it means |
|---|---|
| Declarative voice | The text says what is true and what a command prints when it worked, not what you might try. A sentence with "should" in it is a defect. |
| Before you start | Each chapter lists what it assumes: usually the previous chapter, a password from Proton Pass, a terminal on the host. |
| Every command has its output | `# prints:` comments and quoted blocks are real output from a host on the date the chapter was written; a placeholder is in angle brackets (`<host>`, `<sha>`). |
| Done when | Each chapter closes with a checklist of commands whose output proves the chapter took. Verify on your host: the checklist is the test. |
| Reference lines | The top of a chapter names the pages behind it, so nothing is explained twice. |
| Dry run first | Every writer in `system/` and `install/bootstrap.sh` takes `--dry-run` without root, except the opt-in `backup-eva.sh` (a Borg archive on a plugged-in drive); the teardown scripts default to `--plan`. Chapters show the dry run before the real run. |

## The reference pages

The depth behind each chapter lives in the directorates of [the org chart](../../README.md):

| Directorate | For |
|---|---|
| [Platforms](../../platforms/README.md) | the machines, and how Arch, Windows, the WSL clones and the bench are installed and kept |
| [Design](../../design/README.md) | Letterpress: the themes, the fonts, the bars, the boot screens, the keybinds |
| [Toolchain](../../toolchain/README.md) | the app set, development, packaging and the `[dram]` repo, the profiles |
| [Security](../../security/README.md) | the YubiKeys and secrets, boot trust, the network and the software register |
| [Operations](../../operations/README.md) | `dram`, releases and pushes, backups, the checks and tests |

Every script's `--help` is on one page, [commands](../../commands.md), with "which command when".
The decisions behind the chapters are indexed in [decisions](../../../decisions/README.md).
[History](../../history/README.md) holds dated pages about how the hosts got here; they are not maintained.

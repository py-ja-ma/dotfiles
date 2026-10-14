# Profiles

[Toolchain](../README.md) › Profiles

A profile is what a machine is for beyond the desktop: work, study, making videos, play.
Each one is one or more roles, so a host file's `roles` line says which profiles a machine has, and `dram apply` installs them ([decision 0009](../../../decisions/0009-roles-and-host-shape.md)).
A Windows PC takes the same role names, and a WSL clone takes the terminal half.

| Profile | For | Roles | Arch hosts | Windows | Page |
|---|---|---|---|---|---|
| Office | work | `office` | cabin, lantern, cabin-wsl, thermos-wsl | cabin-win | [Office](office.md) |
| College | study | `college` | cabin, lantern, cabin-wsl, thermos-wsl | cabin-win | [College](college.md) |
| Reverse-engineering lab | work | `re-lab`, with `dump-kit` for discs | cabin, lantern, thermos-wsl | thermos, not rendered yet | [Re-lab](re-lab.md) |
| Creator | making videos | `creator`, with `recording` on the recorder | cabin, campfire | cabin-win | [Creator](creator.md) |
| Gaming | play | `gaming` | cabin, lantern | cabin-win | [Gaming](gaming.md) |
| Emulation | play | `emulation`, `dump-kit` | cabin; `dump-kit` on lantern too | none | [Emulation](emulation.md) |
| Chat | play | `chat` | none yet | cabin-win | below |

The [Development](../development/README.md) roles (`dev`, `sysadmin`, `docker`, `ml`) and the `desktop` role sit under every profile; the [Toolchain](../README.md) page has the desktop's app set.
`packages/roles/README.md` lists every role with its lists in each source.

## How the profiles fit

A role is a set of package lists with the same name, one per source: `packages/roles/<role>.txt` for pacman, `packages/flatpak/<role>.txt`, `packages/winget/<role>.txt`, and `packages/uv/` for the re-lab tools.
Some roles also have a setup script under `system/` that `dram apply` runs as a hook (`system/apply-hooks.tsv` names the role of each), and a Home Manager module under `modules/`.
A role exists for Nix when its pacman list exists: `modules/options.nix` builds the list of valid roles from `packages/roles/*.txt`, and `bin/check.sh` §11 fails on a host that names a role without a list.

These roles never go to Windows: docker, builder, dump-kit, telephony and ml-cuda.
Emulation stays on Arch too ([D62](../../../decisions/log.md#d62)).
The ML role stays on cabin's Arch.

## Chat

Voice and IRC on each declarative build, the apps only, with no servers yet ([D45](../../../decisions/log.md#d45)).

| App | What | Where |
|---|---|---|
| Mumble 1.5 | voice, BSD-3-Clause | Windows (`packages/winget/chat.txt`) |
| Halloy | IRC with a window | Windows |
| WeeChat | IRC in a terminal | planned with Arch's chat role, so the WSL clones get it too |
| TeamSpeak 3 | voice, under a waiver until 2027-10-12 ([D46](../../../decisions/log.md#d46)) | Windows |
| Vesktop | Discord | Windows from winget; Arch from Flathub ([Flatpak](../packaging/flatpak.md)) |

HexChat, irssi and Quassel fail the Community rule, and Srain fails Origin.
Mumble's settings hold the client certificate, so they stay out of the repo.
Arch has no chat role yet: the plan is *packages/roles/chat.txt* with mumble, halloy, teamspeak3 and weechat, on cabin and lantern.

## Operating it

Giving a host a profile: add its roles to the host file's `roles` line, push, and `dram apply` on the host ([handbook chapter 7](../../records/handbook/07-packages.md)).
The first run of each role: [handbook chapter 2](../../records/handbook/02-first-login.md).

## Status

As of 2026-10-13 each profile in the table runs on the hosts it lists, except chat on Arch and the recorder, which is not built.

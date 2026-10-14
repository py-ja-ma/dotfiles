# Module README

[Office of Records](../README.md) › [Templates](README.md) › Module README

A module is anything someone could copy on its own: a directory, or a single file.
A directory module gets this README; a single-file module carries the same facts in its header comment.

The fact box under the lead is fixed: three rows with the labels Needs, Copy alone and License, in that order.
`bin/gen-catalogue.py` reads it from every module README into [the catalogue](../../catalogue.md), and `bin/check.sh` §23 fails when the catalogue is stale or a box breaks the shape.
Before adding a README inside a directory that an app reads whole (some of `dotfiles/.config/`), check that the app ignores a stray `README.md`.

````markdown
# <name>

[<Directorate>](…) › [<Division>](…) › <Branch>

<What it is, in one sentence under 120 characters.
What it looks like or does, in one or two more.>

| | |
|---|---|
| Needs | <software and the version tested, with the month; fonts; files from elsewhere in this repo> |
| Copy alone | <yes / yes, after one change / no, and why> |
| License | <MIT, or the licenses of the files that differ> |

## What it needs

<Each dependency with the version tested and the month.
Files from elsewhere in this repo, by path, and what each provides.
What it does not need (Nix, Home Manager, dram), when a reader might assume it does.>

## Copy it alone

<Numbered steps that work on a machine without this repo: where the files go, what to replace,
what to delete, and how to tell it worked.>

## How it is wired here

<Which module links it, which script generates or checks it, which hosts and roles get it.
A copier can skip this section.>

## Files

| File | What it does |
|---|---|

## License

<SPDX identifiers and holders; third-party files by name.>
````

A single-file module keeps the shell header that `--help` prints and adds three lines after its options, then the SPDX lines after the first blank line:

```bash
# needs:  nftables, openssh, systemd-resolved, sudo; root unless --dry-run
# alone:  set `define LAN` in nftables.conf to your subnet first, or lose SSH
# here:   an `ask` hook of `dram apply` on metal hosts (system/apply-hooks.tsv)
# see:    docs/security/network/README.md

# SPDX-FileCopyrightText: 2026 Patrick Jordan
# SPDX-License-Identifier: MIT
```

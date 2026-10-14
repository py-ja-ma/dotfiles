# Changelog

[Office of Records](README.md) › Changelog

[`CHANGELOG.md`](../../CHANGELOG.md) at the root holds the release notes, one section per release tag, newest first.
`bin/release.sh` writes a section when it cuts a release, and `dram changelog` prints sections on a host.
The format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/).

## A section

```markdown
## v2026.10.29 (2026-10-13)

The summary given to `bin/release.sh -m`: what changed for someone running the hosts.

### Removed
- windows: the hand-written common.winget and cabin.winget.

### Added
- bin: push-windows.sh sends a Windows host's build to the PC, only the files that changed.
```

| Part | Rule |
|---|---|
| Heading | `## <tag> (<date>)`: the release tag and its ISO date, no dash |
| First line | the summary, one or two sentences on what changed for someone running the hosts |
| Groups | Removed, Added, Changed, Fixed, Security, in that order; an empty group is left out |
| Entry | one change a reader would notice, at most 120 characters, starting with its area (a division slug or a top-level directory) and saying what is different |
| Not in an entry | tracking numbers from notes, commit hashes (the tag pins the commit) |
| A pulled release | `[YANKED]` after its date and one line saying why |

There is no Unreleased section: `dram update --check` shows what is pending on a host, and a section is written when its tag is cut.

## Where the entries come from

Each entry is a commit's subject, written `area: what changed`.
The commit's `Changelog:` trailer picks the group: `added`, `changed`, `fixed`, `removed` or `security`.
`Changelog: skip` keeps a commit out (a typo, a page reworded), and a commit without the trailer lands under Changed.
`bin/release.sh` reads the trailers with `git log --format='%(trailers:key=Changelog)'` and writes the groups in the order above.

The intro of `CHANGELOG.md`, above its first `## v` heading, is written once and kept as it is, so an edit to it survives a release.

## Numbering

A release is an annotated tag `vYYYY.MM.N` on a commit, with N counting up within the month (`bin/release.sh` picks it).
The first public release, v2026.10.29 on 2026-10-13, starts the public history; the 28 releases before it were made while the repo was private, and their notes stay with that history.

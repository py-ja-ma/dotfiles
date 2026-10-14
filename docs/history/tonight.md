> **Historical (deploy runbook of 2026-10-06) — superseded.** The release flow it
> sketches lives in `docs/records/handbook/04-update-version-rollback.md` §8 ("Cutting a
> release") and `docs/release-model.md`; the `rice …` names below are the names of
> the time (`dram …` since `decisions/0007-rename-rice-to-dram.md`), and "the next
> batch" became v2026.10.1. Kept for the batch table.

# Tonight — deploying a batch to both hosts

The way a batch of unreleased changes reaches the hosts is the release flow
(`docs/release-model.md`), not a hand-run sequence any more:

```sh
mac$  git status --short && bash bin/check.sh      # clean, green
mac$  bin/release.sh --dry-run                      # the next vYYYY.MM.N, the CHANGELOG section, the push targets
mac$  bin/release.sh -m "one line: what this batch is"   # commit CHANGELOG.md, tag, push to every host with rice.address
host$ rice update --check                           # "rice: <current> -> vX (N commits)"; exit 7 = nothing pending
host$ rice changelog                                # the notes for that tag
host$ rice update                                   # checkout -> packages -> rice switch -> doctor; writes ~/.config/rice/release
host$ rice version && rice doctor                   # the build that runs, and that nothing is left behind
host$ rice rollback                                 # the way back: previous commit + generation, pacman -U lines printed
```

Both hosts run `rice channel stable` today, so they move only on `rice update`
after a release. To make panasonic the canary again, `rice channel main` there:
it then follows every push from the Mac. A push without a release (`bin/push-host.sh pj@<ip>`) still works and
leaves a stable host's checkout where it is.

What the old step-by-step runbook covered beyond that — clearing generated
state before a switch (`rm -rf ~/.config/yazi/flavors`), the system layer
(`sudo bash system/maintenance.sh`), the theme pass (`rice theme <t>`
restarts the bar and writes every generated theme file), screenshots to
compare, `hyprctl configerrors` when the bar is gone, a relogin for
`limits.d` — belongs to the handbook chapters
and to `docs/maintenance.md`; the checks and ways back per step were, in
short: `rice check` before `rice switch`, `rice rollback` after it,
`git checkout <last-synced> -- <path>` + `hyprctl reload` for a bad
`hyprland.lua`.

## History

Batches pushed before the release flow existed. The next batch is the first
tagged release.

### The batch of 2026-10-06 (pushed by hand, `git log --oneline --no-merges 48252b0..HEAD` at the time, 12 commits; the next batch was `a3a113f..HEAD`)

| commit | subject |
|---|---|
| `97af6d4` | docs: Browser and mail chrome — userChrome on paper, the 17th theme file |
| `085d95c` | librewolf + thunderbird: Letterpress userChrome, rice-theme links it per profile |
| `66fd0eb` | gen-browser-css: the browser + mail chrome palette, one browser.css per theme |
| `d56b268` | docs: Editor section (design.md), apps/supply-chain/new-machine for the Letterpress VS Code themes |
| `d1dca1a` | rice theme: VS Code follows the rice via the local Letterpress extension |
| `0f25abd` | gen-vscode-themes.py: one Letterpress VS Code colour theme per rice theme |
| `3043ee2` | docs/tonight.md: the deploy runbook for a batch of unreleased changes (panasonic first, cabin second) |
| `4474d10` | docs: yazi flavors are generated, not fetched |
| `46f3856` | yazi: wire the letterpress flavors in, drop the 8 ya pkg deps |
| `2dd18c2` | yazi: one generated Letterpress flavor per rice theme (bin/gen-yazi-flavors.py) |
| `fe1099d` | review leftovers: check.sh §10 "Captions and spacing", stale bar-script mentions, limits.d for Hyprland's SCHED_RR |
| `cb69518` | gsimplecal: the calendar popup in Letterpress via a private XDG_CONFIG_HOME (gsimplecal-rice.sh) |

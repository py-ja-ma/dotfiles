# office

[Toolchain](../../docs/toolchain/README.md) › [Profiles](../../docs/toolchain/profiles/README.md) › [Office](../../docs/toolchain/profiles/office.md)

The starting points for the office role's two git repos: a Markdown notes vault and a plain-text hledger journal.
`office-init` copies each one into `~/documents` the first time, and from then on it is your repo, outside this one.

| | |
|---|---|
| Needs | git; hledger for the journal; any Markdown editor, Zettlr here; tested 2026-10 |
| Copy alone | yes: copy a folder and `git init` it |
| License | MIT |

## What it needs

- git, because each folder becomes its own repository.
- hledger for `finance/`: `hledger`, with `hledger-ui` and `hledger-web` if you want them.
- A Markdown editor for `vault/`; Zettlr opens the folder as it is, and `zk` works in a terminal.
- Not needed: Nix, Home Manager or the `dram` command. `office-init` only saves the copying.

## Copy it alone

1. `cp -R templates/office/vault ~/documents/vault` and `cp -R templates/office/finance ~/documents/finance`.
2. In each: `git init && git add -A && git commit -m "start"`.
3. Change the accounts in `finance/accounts.journal` and the CSV rules in `finance/rules/checking.csv.rules` to your bank's export.
4. `hledger -f ~/documents/finance/main.journal accounts` lists the accounts, and `hledger import` fills `2026.journal` from a CSV export.

## How it is wired here

`modules/office.nix` links `dotfiles/.local/bin/office-init` on hosts with the office role.
`office-init` copies `vault/` and `finance/` into `~/documents` only when each is missing, makes each a git repository with one commit, and prints the Taskwarrior sync step.
`vault/README.md` is part of the copy: each new vault starts with it.
Until the NAS, each repo's remote is a bare repo on lodge ([Office](../../docs/toolchain/profiles/office.md)).
A change here reaches only vaults and journals made after it.

## Files

| File | What it does |
|---|---|
| `vault/README.md` | the vault's own short guide, copied with it |
| `vault/{inbox,notes,projects,school,journal,attachments}/.keep` | the folders: quick capture, permanent notes, one folder per project, one per course, daily pages, attachments |
| `finance/main.journal` | the entry point: includes the accounts and one journal per year |
| `finance/accounts.journal` | the account names |
| `finance/2026.journal` | this year's transactions, empty until the first import |
| `finance/rules/checking.csv.rules` | hledger's CSV import rules for a checking export |

## License

MIT, Patrick Jordan.

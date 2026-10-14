# Office

[Toolchain](../README.md) › [Profiles](README.md) › Office

Tasks, notes, money and documents, kept as plain text in git wherever that costs no usability.

| | |
|---|---|
| Code | `packages/roles/office.txt`, `packages/winget/office.txt`, `modules/office.nix`, `dotfiles/.local/bin/office-init`, [`templates/office/`](../../../templates/office/README.md) |
| Runs on | cabin and lantern; the terminal tools in cabin-wsl and thermos-wsl; the GUI half natively on cabin-win |
| Needs | Taskwarrior 3, hledger, Zettlr, LibreOffice, git |
| Decided in | [D5](../../../decisions/log.md#d5), [D24](../../../decisions/log.md#d24) |

| Job | Tools | Where the data lives |
|---|---|---|
| Tasks and time | Taskwarrior 3 (`task`, `taskwarrior-tui`, `vit`), Timewarrior (`timew`) | Taskwarrior's own store, synced through an encrypted git remote |
| Notes | the Markdown vault, opened in Zettlr; `zk` and marksman in the terminal | `~/documents/vault`, a git repo |
| Money | hledger with `hledger-ui` and `hledger-web`, CSV import rules | `~/documents/finance`, a git repo |
| Documents | LibreOffice (the still line), US English spelling | anywhere |
| PDFs and scans | pdfarranger, qpdf, img2pdf, Tesseract, SANE with Simple Scan; Xournal++ comes with the college role | anywhere |

Obsidian left on 2026-10-11: it is closed source, and the vault is Markdown ([D5](../../../decisions/log.md#d5)).
An old Obsidian vault opens in Zettlr once its folder is copied into `~/documents/vault/notes/`.

On cabin-win the GUI half is native: LibreOffice (winget's newer line), Zettlr, hledger with `hledger-ui` and `hledger-web`, PDF Arranger, QPDF and calibre.
Taskwarrior, Timewarrior, zk and img2pdf run in the WSL clones, which take the office role ([D141](../../../decisions/log.md#d141)).
The vault and the journal are committed from Arch or a clone, because git lives only in the clone on Windows ([D58](../../../decisions/log.md#d58)).

## Use it

```sh
office-init   # ~/documents/vault and ~/documents/finance from templates/office/, as git repos
```

`office-init` creates each folder only when it is missing, and prints the Taskwarrior sync step.
Until the NAS, the remotes are bare repos on lodge:

```sh
git init --bare ~/git/vault.git                                    # on lodge, once
git -C ~/documents/vault remote add origin pj@lodge:git/vault.git  # on the host
```

The finance repo works the same way.
Calendar and contacts stay in Proton's web apps; Thunderbird can subscribe to the calendar, read-only.

```sh
hledger import --rules-file ~/documents/finance/rules/checking.csv.rules ~/downloads/checking.csv -f ~/documents/finance/2026.journal
hledger -f ~/documents/finance/main.journal balance
hledger-ui -f ~/documents/finance/main.journal
```

Adjust the CSV rules to each bank's header, with one rules file per account.
The business, from 2027, gets its own journal beside it, with invoices from a Typst template.

## Limits

- ocrmypdf is accepted but only in the AUR, so it waits to be vendored into `[dram]`.
- I have not ruled on the Origin of sane-airscan (network scanners) or unpaper, so neither is installed (2026-10-13).
- Scanning on Windows is driverless, or NAPS2 once I rule on it ([D107](../../../decisions/log.md#d107)).

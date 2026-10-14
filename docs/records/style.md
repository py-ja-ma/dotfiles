# Style guide

[Office of Records](README.md) › Style guide

How the pages, records, script headers and code comments in this repo are written.
The rules are numbered so a review note can cite one: "V2", "P5".
The aim is a page a stranger can act on, written the way one engineer writes notes for himself and for whoever comes next.
`bin/check.sh` checks the links, the `see:` lines and the map (§6, §22); I check the rest when I review a page.

## Voice

- V1. Write in the first person. Use "I" for choices, preferences and history: "I tried Tailscale on 2026-10-05 and removed it the same day: it needs an account." Facts about the system take no person: "The bar has no icons."
- V2. "I", never "we": one person keeps this repo. "our own signed repo" becomes "a signed repo I build".
- V3. Steps are imperative and may address "you" (the handbook, a README's "Copy it alone"). The handbook's rule stands: a sentence with "should" in it is a defect.
- V4. A page says what the system does and why. How it got there belongs in the decision log and the changelog.
- V5. Contractions are fine in prose (don't, isn't, can't). Rules and warnings spell out "do not" and use "never".

## Words

- W1. Plain verbs: use, run, build, write, check, keep, add, remove, start, stop, need, show.

  | Not | Write |
  |---|---|
  | leverage, utilize | use |
  | ensure | make sure, or say how |
  | facilitate, enable, empower | say what it does |
  | robust, seamless, comprehensive, powerful, elegant | delete, or give the measure |
  | streamline | say what was removed |
  | key (as an adjective), crucial, essential, pivotal | delete, or "main" |
  | deliver, deploy (outside software) | make, ship, install |
  | best-in-class, cutting-edge, battle-tested, world-class, game-changer | delete |

- W2. No adverbs that grade the writing: simply, just, easily, really, very, actually. When a choice was intentional, give the reason instead: "`force_no_accel` is off: the flat profile already removes acceleration."
- W3. Write "is" and "has", not "serves as", "acts as", "features", "boasts", or "provides" where "has" works.
- W4. Name the file, the command, the host, the number, the date. "the scripts in system/" becomes their names, or a link to the list.
- W5. No tracking numbers from notes: no phase, milestone or question numbers. Write the thing: "the VM install test (`tests/t2-vm.sh`) passes". The one family that stays is the decision number: D1 to D148 and on, permanent, each a section of [the decision log](../../decisions/log.md). Cite one as `D65` in code and commit subjects and as a link in a page: [D65](../../decisions/log.md#d65). The test tiers T0 to T4 are vocabulary of the tests themselves and stay.
- W6. Dates, not "now": "since 2026-10-11", "as of 2026-10". Not today, now, currently, recently, soon or "for now".
- W7. An absolute needs a check. Keep "every", "never", "always", "nothing" or "all" only where a named check enforces it: "Every script answers `--help` (`bin/check.sh` §13)". Otherwise write "each", or the count.
- W8. "the one X" only when it means "the only X" and that matters: "`install/lib/roles.sh` is the only reader of a host's roles". Never as emphasis.
- W9. "for example", "that is", "and so on", or the full list. Not e.g., i.e., etc. or via.
- W10. One spelling: American, which the code already uses (`color`, `License`, `center`).
- W11. One name per thing. The command is `dram`, the design is Letterpress, the package repo is `[dram]`. Don't alternate "the CLI", "the tool" and "the dram".

## Sentences

- S1. Lead with the point. The first sentence of a page or section says what the thing is or what to do.
- S2. One idea per sentence. Keep the median under 20 words and split anything over 40.
- S3. No openers that announce the page: "This page describes", "This document provides", "Here is", "Below", "In this section".
- S4. No closers that restate: "In short", "In summary", "Overall", "That's it".
- S5. A list of qualities ("fast, simple and reliable") becomes the one quality you can measure. A list of facts is fine at any length.
- S6. No rhetorical questions in prose, and no question headings outside a FAQ.

## Punctuation and layout

- P1. A colon before a list or an explanation, a comma for an aside, a full stop elsewhere. No dash in a title or heading.
- P2. Semicolons: at most one per paragraph. Three clauses joined by semicolons are three sentences.
- P3. Parentheses: at most one per sentence. A parenthesis may hold a path, a command, a number or a decision link.
- P4. Arrows only in tables and diagrams, for a sequence such as the boot order. In prose write "then" or "to".
- P5. Bold only for "Never" or "Do not" at the start of a rule, and for a term where it is defined. Never a bold label at the start of a list item: use a table with a label column, or a sentence.
- P6. No all-caps words for emphasis. In a script header, one capitalized word may mark a step that destroys data.
- P7. No emoji, badges or callout boxes. A warning is a sentence that starts with "Never" or "Do not" and says what happened the last time.
- P8. Headings in sentence case, at most six words, with no dash and no question mark. A title is the subject as a noun phrase; what used to be a subtitle becomes the first sentence.
- P9. Numbered lists for steps, bullets for parallel facts, one level of nesting at most. A table for a lookup of three or more rows; two facts stay in a sentence.
- P10. One sentence per line in any page you write or rewrite. A diff then shows the sentence that changed.
- P11. A page the reader reads gets a relative Markdown link; a file the reader opens or runs gets backticks. Link text is the page's title, never "here".

## Pages

- G1. Under the title, one breadcrumb line names the page's place in the chart, with links: `[Security](../README.md) › [Boot trust](README.md) › Secure Boot`. No YAML front matter: GitHub renders it as a table.
- G2. Start a new page from its template in [`docs/records/templates/`](templates/): directorate, division, branch, or a module README.
- G3. A module README opens with the fact box, three rows with these labels: Needs, Copy alone, License. `bin/gen-catalogue.py` reads it into [the catalogue](../catalogue.md).
- G4. A decision record's title states the decision after its number, and the line under it holds the owner, the status and its date: `[Security › Software supply](…) · accepted 2026-10-10`. `bin/gen-org-doc.py` reads both into [the index](../../decisions/README.md).
- G5. One fact lives on one page, and the others link to it.
- G6. A page changes in the same commit as the code it describes.

## Commands and code comments

- C1. Fenced blocks name their language. Commands show real output in `# prints:` comments or a following block. Placeholders go in `<angle brackets>`. `--dry-run` comes first.
- C2. Comments explain why, in the same plain register as the pages.
- C3. A generated file says so on its first line and names its generator.
- C4. A script's header is its `--help`: `usage:` on line 2, the text to the first blank line, then `see:` naming the page that documents it. `bin/check.sh` §13 and §6 check both.

## Habits to keep

- The incident behind a rule, with its date: "crashed boot twice, forced ISO recovery".
- What was tried and dropped, and why.
- Limits stated plainly under "Limits".
- Sections as long as their content. One sentence is a fine section.
- An opinion with its reason, once: "Tearing wins over VRR here: Hyprland bounces between the two modes (discussion #13244)."
- My own jokes, used once: the drink-named themes, "dram: a measure of whiskey".

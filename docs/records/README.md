# Office of Records

[Organization](../README.md) › Office of Records

The records of the repo: why it is the way it is, what changed in each release, and how to run the machines from install to teardown.
It also keeps the pieces every other directorate relies on: the map that places each file in the chart, the catalogue of parts that can be copied, the license, the style guide, and the checks that keep them true.

| Division | Covers |
|---|---|
| [Decisions](../../decisions/README.md) | the decision records and the [log](../../decisions/log.md) of every numbered decision |
| [Changelog](changelog.md) | `CHANGELOG.md`, one section per release, and how a section is written |
| [Handbook](handbook/README.md) | running a host, chapter by chapter, with real output and a "Done when" list |

## Shared pieces

| Piece | What it holds | Kept true by |
|---|---|---|
| `docs/map.tsv` | the directorate, division and branch of every tracked path, and the chart itself | `bin/check.sh` §22 |
| [Organization](../README.md) | the chart, the kinds of page, how to add a branch | `bin/gen-org-doc.py`, §23 |
| [Catalogue](../catalogue.md) | each part that can be copied alone, from its README's fact box | `bin/gen-catalogue.py`, §23 |
| [Decision index](../../decisions/README.md) | the records, the open decisions, the decisions of each division | `bin/gen-org-doc.py`, §23 |
| [Style guide](style.md) | how pages, records, headers and comments are written | review |
| [Templates](templates/README.md) | the directorate, division, branch and module README pages | review |
| `LICENSE`, `LICENSES/`, `REUSE.toml` | MIT for my own work; each third-party file under its own license | review; `reuse lint` where it is installed |
| `docs/history/` | dated pages about how the hosts got here, frozen | left out of §6 |

## Rules

- Every tracked path has a place in `docs/map.tsv`; a path that only the catch-all row matches is reported (`bin/check.sh` §22).
- Every relative link and anchor in a page resolves, and so does each repo path a page puts in backticks or a script names on its `see:` line (§6).
- A generated page equals what its generator writes: `docs/commands.md` (§13), the catalogue, the decision index and the chart (§23).
- Tracked text carries no private word: no address, serial number or mail address, from a list each clone keeps outside the repo (§24).
- A decision number is permanent: never reused or renumbered, and a superseded one keeps its section in the log.

§6, §22 and §24 follow the `DOCS_GUARDS` switch at the top of `bin/check.sh`.
It is `fail`: a finding fails the check. `CHECK_DOCS=warn` turns the findings into warnings for one run, with the first 25 of each listed.
`CHECK_DOCS=fail bash bin/check.sh` shows what failing would report.

## License

Everything I wrote is MIT: code, configuration and pages alike, so a command block in a page carries the same terms as the script it came from.
`LICENSE` holds the text, and `REUSE.toml` records each third-party file with its holder and license; those files keep their own terms.
A copied file carries two SPDX lines where it can hold a comment; the rest take their license from `REUSE.toml`.

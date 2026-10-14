# Branch page

[Office of Records](../README.md) › [Templates](README.md) › Branch page

A branch page exists only for a branch that spans several modules or has no code module of its own.
It says what the branch does on a host, how to use it, and how it fails.

````markdown
# <Branch>

[<Directorate>](../../README.md) › [<Division>](../README.md) › <Branch>

<What it does on a host, in the present tense, and the one fact a reader needs first.>

| | |
|---|---|
| Code | <paths> |
| Runs on | <hosts or roles> |
| Needs | <packages, with the version tested and the month> |
| Decided in | <decision record or log entry> |

## How it works

## Use it

<commands with real output>

## When it breaks

<symptom, the check that proves it, the fix>

## Limits

<what it doesn't do>
````

---
title: dvm list
description: List installed SDKs, marking the global default and the one this directory resolves to. Alias — dvm ls.
---

```text
dvm list
dvm ls
```

Shows everything in `~/.dvm/versions`, newest first, annotated with everything that points at it.

```sh
dvm list
```

```text
Installed Dart SDKs in /Users/you/.dvm/versions:

* 3.13.2  this project, global default, channel: stable, alias: work
  3.9.0
  3.4.0   alias: legacy

* = what /Users/you/code/api resolves to right now: pinned by /Users/you/code/api/.dvmrc.
```

`ls` is an alias for the same command.

## Reading the output

The `*` marks the version this directory resolves to. The line under the list says **which rule** produced that answer, in the same words [`dvm which`](/commands/which) uses — one resolution, one vocabulary, whichever command you asked.

Each row carries every name that resolves to it:

| Tag | Meaning |
| --- | --- |
| `this project` | What the current directory resolves to. |
| `global default` | The `global` in `~/.dvm/config.json`. |
| `channel: stable` | The version recorded for that channel at install time. |
| `alias: work` | An [alias](/versions/aliases) that resolves here. |
| `BROKEN: no bin/dart` | The directory exists but has no `dart` executable in it. |

## Entries marked BROKEN

A directory in `versions/` with no `dart` executable in it is **listed and marked**, because several hundred megabytes of half-removed SDK is exactly what you came here to find out about. The fix is `dvm remove <version> --force` followed by a fresh `dvm install`.

Names that are not semver sort after the ones that are, by name — that covers the Dart 1 build numbers the archive still carries, and anything you dropped into `versions/` by hand.

## When the SDK is outside this list

When this directory falls through to a `dart` from your `PATH`, or no rule applies at all, the summary line says which and leaves every row unmarked:

```text
* none of these: /Users/you/scratch falls through to /opt/homebrew/bin/dart on PATH (rule 4 of 5).
```

## A global default that needs installing

dvm writes a warning to **stderr** when `global` names a version you do not have:

```text
The global default names 3.9.0, which is not installed. Run: dvm install 3.9.0
```

This is the state [`dvm remove --force`](/commands/remove) can leave behind, and it is worth fixing straight away: the global default applies to every command run outside a pinned project.

## Before you install anything

```text
No Dart SDKs are installed in /Users/you/.dvm/versions.
Install one with: dvm install stable
```

## See also

- [`dvm list-remote`](/commands/list-remote) — what is available to install.
- [`dvm which`](/commands/which) — the full explanation for this directory.

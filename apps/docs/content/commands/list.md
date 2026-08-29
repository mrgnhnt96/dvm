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

The `*` marks the version this directory resolves to. The line under the list says **which rule** produced that answer, in the same words [`dvm which`](/commands/which) uses — the two commands never describe one resolution in two different vocabularies.

Each row carries every name that resolves to it:

| Tag | Meaning |
| --- | --- |
| `this project` | What the current directory resolves to. |
| `global default` | The `global` in `~/.dvm/config.json`. |
| `channel: stable` | The version recorded for that channel at install time. |
| `alias: work` | An [alias](/versions/aliases) that resolves here. |
| `BROKEN: no bin/dart` | The directory exists but has no `dart` executable in it. |

## Directories that are not usable SDKs

They are **listed rather than hidden**. A half-removed version taking up several hundred megabytes of disk is something you came here to find out about. It is marked `BROKEN: no bin/dart`, and the fix is `dvm remove <version> --force` followed by a fresh `dvm install`.

Names that are not semver sort after the ones that are, by name — that covers the Dart 1 build numbers the archive still carries, and anything you dropped into `versions/` by hand.

## When nothing resolves

If the current directory resolves to nothing, or falls through to a `dart` that dvm does not manage, the summary line says so instead of marking a row:

```text
* none of these: /Users/you/scratch falls through to /opt/homebrew/bin/dart on PATH (rule 4 of 5).
```

## A global default that is not installed

dvm writes a warning to **stderr** if `global` names something missing:

```text
The global default names 3.9.0, which is not installed. Run: dvm install 3.9.0
```

This is not hypothetical — it is what [`dvm remove --force`](/commands/remove) leaves behind, and every command run outside a pinned project fails until it is fixed.

## Empty

```text
No Dart SDKs are installed in /Users/you/.dvm/versions.
Install one with: dvm install stable
```

## See also

- [`dvm list-remote`](/commands/list-remote) — what is available to install.
- [`dvm which`](/commands/which) — the full explanation for this directory.

---
title: dvm remove
description: Delete an installed SDK, after checking what still points at it.
---

```text
dvm remove <version> [--force]
```

Deletes `~/.dvm/versions/<version>` from disk.

```sh
dvm remove 3.9.0
```

```text
Removed Dart 3.9.0 (/Users/you/.dvm/versions/3.9.0).
```

## Flags

| Flag | Effect |
| --- | --- |
| `-f`, `--force` | Remove it even if something still points at it. |

## What still points at it

```sh
dvm remove 3.13.2
```

```text
Refusing to remove Dart 3.13.2: 2 things still point at it.
  - the global default
  - the alias "work"
Repoint them first, or remove it anyway with: dvm remove 3.13.2 --force
```

Repointing first is almost always what you want: a [global default](/commands/global) applies to *every* command run outside a pinned project, so it is worth landing on a version you have.

With `--force`, dvm removes it and then names on stderr exactly what it changed, so you leave the command knowing what to repoint.

## What it cleans up on the way

Removing a version drops any channel record pointing at it, so `channels.stable` keeps naming something you have. [An alias stays as you wrote it](/versions/aliases) and dvm reports it instead — the name was your choice, so repointing it is yours too.

If the current project's `.dvmrc` pins the version you just removed, dvm warns about that too.

## The version may be a name

The argument is a pin, so an alias or a channel name resolves first:

```sh
dvm remove work     # removes whatever "work" currently means
```

## Already removed

```text
Dart 3.9.0 is not installed, so there is nothing to remove. See what is: dvm list
```

Exit code 1, so a script can tell "there was nothing there" from "it was removed".

## See also

- [`dvm list`](/commands/list) — what is installed, and what points at it.
- [`dvm unalias`](/commands/unalias) — remove a name without removing an SDK.

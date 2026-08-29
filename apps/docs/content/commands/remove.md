---
title: dvm remove
description: Delete an installed SDK — refusing if something still points at it, unless you insist.
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

## It refuses when something depends on it

```sh
dvm remove 3.13.2
```

```text
Refusing to remove Dart 3.13.2: 2 things still point at it.
  - the global default
  - the alias "work"
Repoint them first, or remove it anyway with: dvm remove 3.13.2 --force
```

Repointing first is almost always what you want. A [global default](/commands/global) naming a version that is not installed makes *every* command outside a pinned project fail until it is fixed, and the error appears somewhere unrelated to where you caused it.

With `--force`, dvm removes it and then tells you — on stderr — exactly what it just broke, so the damage is visible rather than latent.

## What it cleans up on the way

Removing a version drops any channel record pointing at it, so `channels.stable` does not keep naming a version that no longer exists. [Aliases are not rewritten](/versions/aliases) — an alias is a name you chose, and dvm repointing it at something you did not pick would be worse than leaving it dangling and saying so.

If the current project's `.dvmrc` pins the version you just removed, dvm warns about that too.

## The version may be a name

The argument is a pin, so an alias or a channel name resolves first:

```sh
dvm remove work     # removes whatever "work" currently means
```

## Not installed

```text
Dart 3.9.0 is not installed, so there is nothing to remove. See what is: dvm list
```

Exit code 1 — so a script cannot mistake "there was nothing there" for "it was removed".

## See also

- [`dvm list`](/commands/list) — what is installed, and what points at it.
- [`dvm unalias`](/commands/unalias) — remove a name without removing an SDK.

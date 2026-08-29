---
title: dvm unalias
description: Remove a named version. The SDK itself is untouched.
---

```text
dvm unalias <name>
```

Deletes an [alias](/commands/alias) from `~/.dvm/config.json`.

```sh
dvm unalias work
```

```text
Removed the alias "work" (it meant 3.13.2). The SDK itself is untouched.
```

This removes the *name* only. Nothing is deleted from `~/.dvm/versions` — for that, use [`dvm remove`](/commands/remove).

## Dangling references

After removing a name, dvm checks whether anything is still spelled with it, and reports each one on stderr:

```text
The global default still says "work", which no longer means anything. Run: dvm global <version>
The alias "current" still points at "work". Run: dvm alias current <version>
/Users/you/code/api/.dvmrc still pins "work". Run: dvm use <version>
```

The global default is the important one. Once `work` is not an alias, resolution treats it as a *concrete version*, and every command outside a pinned project fails with "a version called work is not installed" — which reads like a bug rather than a consequence of the command you just ran.

## Not an alias

```text
There is no alias "work". Defined: legacy, next
```

Exit code 1.

## See also

- [`dvm alias`](/commands/alias) — create and list aliases.
- [`dvm remove`](/commands/remove) — delete the SDK, not the name.

---
title: dvm alias
description: Give a version a name you will remember, or list the names you have.
---

```text
dvm alias <name> <version>
dvm alias list
```

An alias is a name you define for a version, stored in `~/.dvm/config.json`. Anywhere dvm accepts a version, it accepts an alias.

```sh
dvm alias work 3.13.2
```

```text
"work" now means 3.13.2.
```

Then:

```sh
dvm use work
dvm global work
dvm install work
```

## Repointing

Changing an alias moves every project pinned to it, in one command:

```sh
dvm alias work 3.14.0
```

```text
"work" now means 3.14.0.
  was: 3.13.2
  Dart 3.14.0 is not installed. Run: dvm install 3.14.0
```

Pointing an alias at an SDK you have not installed is **allowed** — you may reasonably write the alias before the download — but dvm says so, rather than letting you find out the next time you `cd` into a project.

## Listing

```sh
dvm alias list
```

```text
Aliases in /Users/you/.dvm/config.json:

  legacy -> 3.4.0  (installed)
  work   -> stable -> 3.13.2  (installed)

Channels, as recorded by dvm install:
  stable -> 3.13.2
```

The chain is shown when there is one. Channels are listed alongside because they are the *other* way a name maps to a version, and the two are easy to confuse — see [Aliases and Channels](/versions/aliases).

Plain `dvm alias` with no arguments does the same thing as `dvm alias list`.

## Names dvm refuses

| Rejected | Why |
| --- | --- |
| `stable`, `beta`, `dev` | Channel names. Resolution checks channels before aliases, so such an alias would be silently unreachable. |
| Anything that looks like a version | dvm could not tell the alias from the version. |
| `list` | `dvm alias list` has to keep meaning "show me the aliases". |
| A leading `-` | It reads as an option. |
| Whitespace or `/` or `\` | A name is a single word. |

Each of these is refused up front with a message, because the alternative is a name sitting in your config that quietly does nothing.

## Chains and loops

An alias may point at another alias or at a channel, and dvm follows the chain up to eight hops. It refuses to create a loop — including pointing an alias at itself — because a loop resolves to nothing and the error would surface far away from the command that caused it.

## See also

- [`dvm unalias`](/commands/unalias) — remove a name.
- [Aliases and Channels](/versions/aliases) — how names resolve, and what `stable` means offline.

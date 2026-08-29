---
title: dvm use
description: Pin a version for this project and write .dvmrc — installing it first if it is not there.
---

```text
dvm use <version> [--global]
```

The command you will type most. It writes [`.dvmrc`](/versions/dvmrc) in the current directory, creates the `.dvm/dart_sdk` symlink for your IDE, and installs the SDK first if it is missing.

```sh
dvm use 3.13.2
```

```text
Pinned Dart 3.13.2 for /Users/you/code/api.
  /Users/you/code/api/.dvmrc -> commit this
  /Users/you/code/api/.dvm/dart_sdk -> /Users/you/.dvm/versions/3.13.2 (for your IDE; do not commit it)
`.dvm/` is not ignored yet. Add it with: dvm use 3.13.2 --gitignore
```

## Flags

| Flag | Effect |
| --- | --- |
| `-g`, `--global` | Set the machine-wide default instead of pinning this project. Same as [`dvm global`](/commands/global). |
| `--gitignore` | Also append `.dvm/` to this project's `.gitignore`. |

## The two files it writes

**`.dvmrc`** — the pin. Two lines of JSON. **Commit it.** This is what makes the pin apply to everyone who clones the repository.

**`.dvm/dart_sdk`** — a symlink to `~/.dvm/versions/<version>`, for IDEs and analyzer plugins that want an SDK directory. It contains an absolute path into your home directory. **Do not commit it.**

If `.dvm/dart_sdk` already exists as something other than a symlink, dvm refuses to replace it rather than deleting whatever you have there.

## `--gitignore`

dvm only ever edits `.gitignore` when you explicitly ask:

```sh
dvm use 3.13.2 --gitignore
```

```text
Added `.dvm/` to /Users/you/code/api/.gitignore.
```

It appends:

```text
# dvm's per-project SDK symlink; .dvmrc is the part you commit.
.dvm/
```

Without the flag it just tells you the rule is missing. Editing a file you did not name, in a repository dvm does not own, is not something it does on its own — and there is no interactive prompt, because every dvm command has to stay runnable from a script and from CI.

If `.dvm` is already ignored under any of the usual spellings, dvm says so and adds nothing.

## It installs first

Naming a version you do not have is fine — `dvm use` installs it and then pins it. So the two-command form

```sh
dvm install 3.13.2 && dvm use 3.13.2
```

is only worth typing when you want the download to happen at a different time from the pin.

## Pinning a name

The argument is a pin, so an [alias or a channel](/versions/aliases) works:

```sh
dvm use work        # an alias you defined
dvm use stable      # the version `stable` resolved to when you last installed it
```

dvm reports the hop it followed:

```text
Pinned Dart 3.13.2 for /Users/you/code/api (work -> 3.13.2).
```

<Callout type="warning">
`.dvmrc` records the version, not the name. Pinning `stable` in a repository other people build means their `stable` may be a different SDK from yours — see [Aliases and Channels](/versions/aliases).
</Callout>

## In a monorepo

`dvm use` writes to the **current directory**, never to the nearest existing `.dvmrc` above it. Running it inside one package pins that package rather than silently rewriting the pin at the repository root.

## See also

- [The .dvmrc File](/versions/dvmrc) — the format, and where dvm looks for it.
- [`dvm global`](/commands/global) — the fallback for directories that pin nothing.
- [`dvm which`](/commands/which) — confirm what applies here now.

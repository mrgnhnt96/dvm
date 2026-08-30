---
title: dvm use
description: Pin a version for this project and write .dvmrc — installing it first if it is not there.
---

```text
dvm use <version> [--global] [--here]
```

The command you will type most. It updates the [`.dvmrc`](/versions/dvmrc) that governs the directory you are standing in — the same file `dart` reads — puts the `.dvm/dart_sdk` link for your IDE beside it, and installs the SDK first if it is missing.

```sh
dvm use 3.13.2
```

```text
Pinned Dart 3.13.2 for /Users/you/code/api.
  /Users/you/code/api/.dvmrc -> commit this
  /Users/you/code/api/.dvm/dart_sdk -> /Users/you/.dvm/versions/3.13.2 (for your IDE; do not commit it)
`.dvm/` is not ignored yet by /Users/you/code/api/.gitignore. Add it with: dvm use 3.13.2 --gitignore
```

## Flags

| Flag | Effect |
| --- | --- |
| `-g`, `--global` | Set the machine-wide default instead of pinning this project. Same as [`dvm global`](/commands/global). |
| `--here` | Pin **this** directory, creating a `.dvmrc` here even when a parent directory already has one. |
| `--gitignore` | Also append `.dvm/` to this project's `.gitignore`. |

## The two files it writes

**`.dvmrc`** — the pin. Two lines of JSON. **Commit it.** This is what makes the pin apply to everyone who clones the repository.

**`.dvm/dart_sdk`** — a link to `~/.dvm/versions/<version>`, for IDEs and analyzer plugins that want an SDK directory. It contains an absolute path into your home directory, so it means something on this machine and nowhere else. **Keep it out of version control.**

Both land in the directory that holds the pin, so one `.dvmrc` always has exactly one link beside it — and a later `dvm use` from anywhere in the project brings that link along with the pin.

On Windows, dvm creates a symbolic link where the account can make one and a **directory junction** where it cannot. A junction needs no special privilege and the filesystem resolves it itself, so an IDE opening `.dvm/dart_sdk/bin/dart.exe` reaches the SDK either way.

If `.dvm/dart_sdk` already exists as something other than a link, dvm leaves it where it is and says so — whatever you put there stays yours.

## Where the pin goes

`dvm use` updates the `.dvmrc` that applies where you are standing. It finds it with the same walk up the tree that [resolution](/versions/resolution-order) uses, so the file you change is the file `dart` reads, and it names that file in its output:

```sh
cd ~/code/api/packages/app
dvm use 3.13.2
```

```text
Pinned Dart 3.13.2 for /Users/you/code/api.
  You are in /Users/you/code/api/packages/app, which that pin covers, so the .dvmrc above it is the one that changed.
  /Users/you/code/api/.dvmrc -> commit this
  /Users/you/code/api/.dvm/dart_sdk -> /Users/you/.dvm/versions/3.13.2 (for your IDE; do not commit it)
`.dvm/` is not ignored yet by /Users/you/code/api/.gitignore. Add it with: dvm use 3.13.2 --gitignore
```

When there is a `.dvmrc` anywhere above you, that is the one `dvm use` updates. When there is none, it creates one right where you are. Either way the second line tells you which file moved, so the pin you changed and the pin in effect are always the same pin.

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

Without the flag it names the rule it would add and leaves the file to you. The repository is yours, so the edit is yours to ask for — by flag rather than by prompt, which is what keeps every dvm command runnable from a script and from CI.

If `.dvm` is already ignored under any of the usual spellings, dvm says so and leaves the file as it is.

## It installs first

Name a version you do not have and `dvm use` installs it, then pins it. So the two-command form

```sh
dvm install 3.13.2 && dvm use 3.13.2
```

is worth typing when you want the download to happen at a different time from the pin.

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
`dvm use stable` records the version `stable` currently means on this machine, so the `.dvmrc` you commit names a concrete SDK. A **hand-written** `.dvmrc` saying `stable` resolves against each machine's own record instead, so pin a version there for a repository other people build — see [Aliases and Channels](/versions/aliases).
</Callout>

## In a monorepo

Because the write follows the read, running `dvm use` inside a package updates the pin that was already governing it — usually the one at the repository root. That is the pin `dart` obeys in that package, so changing it is what actually moves the package onto the new SDK.

When a package wants an SDK of its own, ask for it with `--here`:

```sh
cd ~/code/api/packages/app
dvm use 3.13.2 --here
```

```text
Pinned Dart 3.13.2 for /Users/you/code/api/packages/app.
  /Users/you/code/api/packages/app/.dvmrc -> commit this
  /Users/you/code/api/packages/app/.dvm/dart_sdk -> /Users/you/.dvm/versions/3.13.2 (for your IDE; do not commit it)
  This pin shadows /Users/you/code/api/.dvmrc, which no longer applies in /Users/you/code/api/packages/app or below it.
`.dvm/` is not ignored yet by /Users/you/code/api/packages/app/.gitignore. Add it with: dvm use 3.13.2 --here --gitignore
```

That third line is the point of the flag. A nested pin takes over from the one above it for that directory and everything under it — [nearest wins](/versions/resolution-order) — and dvm names the pin it displaced at the moment you create it, so the new shape of the repository is on screen while you are still looking at it.

## See also

- [The .dvmrc File](/versions/dvmrc) — the format, and where dvm looks for it.
- [`dvm global`](/commands/global) — the fallback for directories that pin nothing.
- [`dvm which`](/commands/which) — confirm what applies here now.

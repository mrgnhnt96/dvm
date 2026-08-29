---
title: dvm global
description: Set the version used when no .dvmrc applies — rule 3 of the five.
---

```text
dvm global <version>
dvm global
```

Sets `global` in `~/.dvm/config.json`. This is [rule 3](/versions/resolution-order): what applies in a directory that has no `.dvmrc` above it.

```sh
dvm global 3.13.2
```

With no argument it reports the current value:

```sh
dvm global
```

```text
The global default is 3.13.2.
  /Users/you/.dvm/config.json
```

## It is a fallback, not a mode

This is the difference between dvm and a version manager you have to remember to switch. The global default does not override anything — a project with a `.dvmrc` ignores it entirely. It exists so that scratch directories, one-off scripts and your home directory have a Dart at all.

If you set no global default, directories with no pin fall through to [rule 4](/versions/resolution-order): whatever `dart` was already on your `PATH`. That is a perfectly reasonable way to run dvm.

```text
No global default is set. Directories with no .dvmrc fall through to the first dart on PATH.
Set one with: dvm global <version>
```

## It installs first

Naming a version you do not have installs it, exactly as [`dvm use`](/commands/use) does.

## A global naming something missing

```text
The global default is 3.9.0.
It is not installed. Run: dvm install 3.9.0
```

Exit code 1. This is the state [`dvm remove --force`](/commands/remove) can leave behind, and while it lasts, every command run outside a pinned project fails.

## The same thing, two spellings

```sh
dvm global 3.13.2
dvm use 3.13.2 --global
```

are identical. `dvm use --global` exists so you do not have to remember which command owns the concept when you are already typing `use`.

## See also

- [Resolution Order](/versions/resolution-order) — where rule 3 sits.
- [`dvm which`](/commands/which) — confirm whether the global is what is actually applying.

---
title: Resolution Order
description: The five rules dvm applies to decide which SDK you get, in order, first match wins — and how to see which one answered.
---

Every time you run `dart` through the shim, or run [`dvm dart`](/commands/dart) or [`dvm exec`](/commands/exec), dvm answers one question: *which SDK applies in this directory, right now?*

It answers it with five rules, in this order. **The first one that matches wins.**

## The five rules

### 1. The `DVM_DART_VERSION` environment variable

```sh
DVM_DART_VERSION=3.9.0 dart --version
```

If this variable is set and non-empty, it wins over everything on disk. It is the escape hatch for CI and for one-off commands — see [Using dvm in CI](/guides/ci).

Its value is a pin like any other: a version, an [alias, or a channel name](/versions/aliases).

### 2. The nearest `.dvmrc`

dvm walks **up** from the current directory to the filesystem root and uses the first [`.dvmrc`](/versions/dvmrc) it finds. This is the normal case and the one you want most of the time.

Nearest wins, which is what makes a monorepo with a per-package override work.

### 3. The global default

`global` in `~/.dvm/config.json`, set with [`dvm global`](/commands/global). This is what applies in directories that pin nothing.

### 4. The next real `dart` on `PATH`

When no rule above matched, dvm scans `PATH` for a `dart` that is **not one of its own shims** and hands off to that.

This rule is what keeps the rest of your machine working as it did. A directory that pins nothing and has no global default runs whatever `dart` you already had.

<Callout type="info">
Under rule 4 the SDK is your own, so dvm reports the path and leaves the version to it, and leaves `DVM_DART_VERSION` unset for the child process — a nested dvm then runs the same five rules and reaches the same SDK.
</Callout>

### 5. A clear error

When no rule matched, dvm says so and lists everything it checked:

```text
No Dart SDK applies in /Users/you/scratch.
  - DVM_DART_VERSION is not set
  - no .dvmrc here or in any parent directory
  - no "global" in /Users/you/.dvm/config.json
  - no dart on PATH that is not a dvm shim
Pin one for this project:  dvm use <version>
Or set a machine default:  dvm global <version>
```

## Seeing which rule answered

This is the point of the design, and it is why [`dvm which`](/commands/which) reports the *rule* and not just the path:

```sh
dvm which
```

```text
/Users/you/.dvm/versions/3.13.2/bin/dart
Dart 3.13.2
Chosen by rule 2 of 5: pinned by /Users/you/code/api/.dvmrc.
SDK: /Users/you/.dvm/versions/3.13.2
```

Every rule has its own sentence:

| Rule | What `dvm which` says |
| --- | --- |
| 1 | `Chosen by rule 1 of 5: DVM_DART_VERSION is set in the environment, which overrides everything on disk.` |
| 2 | `Chosen by rule 2 of 5: pinned by <path>/.dvmrc.` |
| 3 | `Chosen by rule 3 of 5: no .dvmrc applies here, so the global default in <path>/config.json was used.` |
| 4 | `Chosen by rule 4 of 5: nothing pins a version here and no global default is set, so this is the next dart on PATH, found in <dir>.` |

When a pin was indirect, the hop is spelled out too:

```text
  It says "work", an alias for 3.13.2 in /Users/you/.dvm/config.json.
```

[`dvm list`](/commands/list) prints a one-line version of the same thing under the list of installed SDKs.

## Every resolution is two small file reads

Every `dart` invocation on the machine pays for this path once the shim is installed, so it stays as cheap as it can be: at most two small files (`.dvmrc` and `config.json`) and one `stat`. That is what keeps `dart` through the shim as fast as `dart` without it — on a plane and behind a firewall as much as anywhere else.

[A channel name is answered from `config.json` here](/versions/aliases): `stable` means the version recorded when you last ran `dvm install stable`. Asking the archive what `stable` means today is its own command, run when you want it.

## The shim-skipping in rule 4

Rule 4 skips dvm's own shims, and that is what makes rule 4 terminate.

The shim *is* `~/.dvm/shims/dart`, you are told to put that directory first on `PATH`, and its body is `exec dvm exec dart "$@"`. A scan that took the first `dart` it found would find the shim, run it, and re-enter resolution — forking until the machine gave up.

So rule 4 skips three things:

- the shims directory itself, however it is spelled in `PATH` (`~/.dvm/shims`, `$HOME/.dvm/./shims/` and the absolute path are all the same directory, and all three turn up in real `PATH`s),
- a symlink pointing into the shims directory — what `ln -s ~/.dvm/shims/dart ~/.local/bin/dart` leaves behind,
- a *copy* of a shim, recognised by its contents, which no path comparison could catch.

## When a pin names a version you do not have

Rules 1, 2 and 3 name a version, so they can match and still have work left. When your `.dvmrc` pins a version you have not installed, dvm names it and gives you the command that fills the gap:

```text
dvm: Dart 3.9.0 is pinned by /Users/you/code/api/.dvmrc, but it is not installed. Run: dvm install 3.9.0
```

You get the SDK the project asked for, or a message naming the one it asked for. That is the guarantee the whole tool is built to give.

## Debugging checklist

When you want to know how `dart --version` reached its answer:

1. `which dart` — is it `~/.dvm/shims/dart`? If not, [your `PATH` order is wrong](/getting-started/shell-setup).
2. `dvm which` — which rule answered, and from which file?
3. `dvm doctor` — [PATH order, shim health, a shadowing shell function, config validity](/commands/doctor).
4. `echo $DVM_DART_VERSION` — rule 1 beats everything, including the `.dvmrc` you are looking at.

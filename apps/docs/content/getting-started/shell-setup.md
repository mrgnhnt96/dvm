---
title: The Shim and Your PATH
description: What `dvm setup` writes, why it has to be first on PATH, and the shell function that silently defeats it.
---

The shim is what makes dvm invisible. Without it you would have to type `dvm dart` instead of `dart`, and — much worse — every tool that spawns `dart` behind your back would still get the wrong SDK.

## What the shim is

`dvm setup` writes exactly one file per platform. On macOS and Linux it is a two-line POSIX shell script:

```sh
#!/bin/sh
exec /Users/you/.dvm/bin/dvm exec dart "$@"
```

On Windows it is a `.bat` doing the same thing.

That is the whole mechanism. `exec` **replaces** the shell process rather than spawning a child, so the only cost of the indirection is starting `/bin/sh` plus dvm's own AOT startup — and then the real `dart` inherits the terminal, the exit code, and the signals directly. Nothing sits between you and the SDK copying bytes.

```sh
dvm setup
```

```text
Wrote /Users/you/.dvm/shims/dart
  -> /Users/you/.dvm/bin/dvm exec dart

Add this to ~/.zshrc:

  export PATH="/Users/you/.dvm/shims:$PATH"

Then check it with: dvm doctor
```

## Why dvm does not edit your shell profile

`dvm setup` prints the line and stops. It will not write it to `.zshrc` for you.

A version manager that rewrites your login shell's startup file behind your back is one people stop trusting — and the correct line differs enough between shells, login versus non-login setups, and hand-managed profiles that getting it wrong does not produce a warning, it produces a shell that will not start.

Add it yourself, to whichever file your shell actually reads:

| Shell | File |
| --- | --- |
| zsh (macOS default) | `~/.zshrc` |
| bash | `~/.bashrc`, or `~/.bash_profile` on macOS |
| fish | `~/.config/fish/config.fish`, with `fish_add_path` |

Then start a **new** shell. Editing the file does not change the environment of the one you are in.

## Why "first" is not the same as "on"

The shims directory has to come **before** anything else on `PATH` that supplies a `dart`.

`PATH` is searched left to right and the first match wins. If Homebrew's `dart`, or a Flutter SDK's bundled `dart`, or `/usr/local/bin/dart` appears earlier in the list, that binary is found first and the shim is never reached. Your pins do nothing, and there is no error message — the symptom is `dart --version` reporting a version you did not ask for, with everything else apparently correct.

[`dvm doctor`](/commands/doctor) checks exactly this, and reports the offending entry by path:

```sh
dvm doctor
```

## The shadowing shell function

This is the one that costs people an afternoon, and it is why `doctor` exists.

The older [`cbracken/dvm`](/guides/migrating) is installed as a **shell function** sourced from your `.zshrc` or `.bashrc`. A shell function is resolved *before* `PATH` is searched at all. So on a machine that has ever had that tool installed, typing `dvm` runs the old function, the new binary is never reached, and nothing on screen says why — the commands are similar enough that the errors look like your own mistakes.

`dvm doctor` reads your shell startup files and reports it by file and line. The fix is to delete the line that sources the old tool, then start a new shell.

## Verifying it worked

```sh
dvm doctor
```

```text
dvm doctor
  ok    PATH: /Users/you/.dvm/shims is first on PATH.
  ok    shims: /Users/you/.dvm/shims/dart points at /Users/you/.dvm/bin/dvm.
  ok    shell: nothing shadows `dvm`.
  ok    config: /Users/you/.dvm/config.json parses.
  ok    project: /Users/you/code/my-project/.dvmrc pins 3.13.2 (installed).

Everything checks out.
```

And directly:

```sh
which dart      # => /Users/you/.dvm/shims/dart
dvm which       # => the SDK that resolves here, and which rule chose it
```

If `which dart` reports anything other than the shim, `PATH` order is the problem.

## What the shim does not cover

The shim is `dart` only. To run some *other* command with the pinned SDK first on its `PATH` — `melos`, a build script, your own tooling — use [`dvm exec`](/commands/exec):

```sh
dvm exec melos bootstrap
```

Every `dart` that `melos` goes on to spawn then resolves to the pinned SDK too, because `dvm exec` puts that SDK's `bin` first on the child's `PATH`.

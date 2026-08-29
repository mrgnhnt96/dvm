---
title: The Shim and Your PATH
description: What `dvm setup` writes, why it has to be first on PATH, and the shell function that silently defeats it.
---

The shim is what makes dvm invisible. With it on your `PATH`, plain `dart` follows your pins — and so does every tool that spawns `dart` behind your back.

## What the shim is

`dvm setup` writes exactly one file per platform. On macOS and Linux it is a two-line POSIX shell script:

```sh
#!/bin/sh
exec /Users/you/.dvm/bin/dvm exec dart "$@"
```

On Windows it is a `.bat` doing the same thing.

That is the whole mechanism. `exec` **replaces** the shell process rather than spawning a child, so the only cost of the indirection is starting `/bin/sh` plus dvm's own AOT startup — and then the real `dart` inherits the terminal, the exit code, and the signals directly. From there on you are talking to the SDK.

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

## Adding the PATH line

`dvm setup` prints the exact line and names the file it belongs in, so the change to your login shell stays yours to make. The right file differs between shells, between login and non-login setups, and between hand-managed profiles, and you are the one who knows which of those you have.

Add it to whichever file your shell actually reads:

| Shell | File |
| --- | --- |
| zsh (macOS default) | `~/.zshrc` |
| bash | `~/.bashrc`, or `~/.bash_profile` on macOS |
| fish | `~/.config/fish/config.fish`, with `fish_add_path` |

Then start a **new** shell. Editing the file does not change the environment of the one you are in.

## Why the shims directory goes first

`PATH` is searched left to right and the first match wins, so `~/.dvm/shims` belongs **ahead of** every other directory that supplies a `dart`.

That position is the whole of it. If Homebrew's `dart`, or a Flutter SDK's bundled `dart`, or `/usr/local/bin/dart` appears earlier in the list, that binary is found first and the shim is never reached. Your pins do nothing, and there is no error message — the symptom is `dart --version` reporting a version you did not ask for, with everything else apparently correct.

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

## Other commands, with the pinned SDK

The shim covers `dart`. For any other command that should run with the pinned SDK first on its `PATH` — `melos`, a build script, your own tooling — use [`dvm exec`](/commands/exec):

```sh
dvm exec melos bootstrap
```

Every `dart` that `melos` goes on to spawn then resolves to the pinned SDK too, because `dvm exec` puts that SDK's `bin` first on the child's `PATH`.

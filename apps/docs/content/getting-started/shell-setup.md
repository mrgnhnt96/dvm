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

`exec` **replaces** the shell process rather than spawning a child, so the only cost of the indirection is starting `/bin/sh` plus dvm's own AOT startup — and then the real `dart` inherits the terminal, the exit code, and the signals directly. From there on you are talking to the SDK.

On Windows it is `~/.dvm/shims/dart.bat`, doing the same thing:

```text
@echo off
"C:\Users\you\.dvm\bin\dvm.exe" exec dart %*
```

Windows resolves a bare `dart` to it through `PATHEXT`, so `cmd.exe` and PowerShell both find it, and the batch file's exit code is the SDK's.

That is the whole mechanism.

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

`dvm setup` reads `$SHELL` to work out which line to hand you and where it goes:

| Shell | Where the line goes |
| --- | --- |
| zsh (macOS default) | `~/.zshrc` |
| bash | `~/.bashrc`, or `~/.bash_profile` on macOS |
| fish | `~/.config/fish/config.fish`, with `fish_add_path` |
| PowerShell | your user environment — see [On Windows](#on-windows) below |

Then start a **new** shell. The file is read when a shell starts, so the one you are in keeps the environment it was given.

## Letting dvm add the line

When you would rather dvm made the edit, ask for it:

```sh
dvm setup --write-path-line
```

```text
Wrote /Users/you/.dvm/shims/dart
  -> /Users/you/.dvm/bin/dvm exec dart

Backed up /Users/you/.zshrc -> /Users/you/.zshrc.dvm-backup-20260829-154646
Added this line to /Users/you/.zshrc:

  export PATH="/Users/you/.dvm/shims:$PATH"

It takes effect in shells started after this. For the one you are in: source /Users/you/.zshrc
Undo it with: dvm setup --remove-path-line

Then check it with: dvm doctor
```

It copies the file to a timestamped backup first, and writes the line inside markers so it stays identifiable:

```sh
# >>> dvm >>>
export PATH="/Users/you/.dvm/shims:$PATH"
# <<< dvm <<<
```

Run it twice and the second run finds the line and adds nothing — including a line you typed yourself in different quoting, or with `$HOME` in place of your home directory. `dvm setup --remove-path-line` takes dvm's own block back out and leaves the shims in place; a line dvm did not write is reported and left exactly as you have it.

It stays opt-in because the reasoning above is still yours: dvm writes to one file, and you are the one who knows which file your login shell actually reads.

## On Windows

PowerShell takes `PATH` from your user environment rather than from a startup file, so `dvm setup` hands you the command that sets it:

```text
Run this once in PowerShell:

  [Environment]::SetEnvironmentVariable('Path', 'C:\Users\you\.dvm\shims;' + [Environment]::GetEnvironmentVariable('Path', 'User'), 'User')

That edits your user PATH, so it survives a reboot. It has to go ahead of anything else that puts a dart on PATH, and it only takes effect in terminals opened after you run it.

For the terminal you are in right now:

  $env:Path = 'C:\Users\you\.dvm\shims;' + $env:Path
```

It writes to the `User` scope, so it needs no elevation and applies to every terminal you open afterwards. [`dvm doctor`](/commands/doctor) hands you the same line when it finds the shims missing from `PATH`.

Git Bash and MSYS set `$SHELL`, so dvm gives them the POSIX `export` line and the startup file that shell reads — the shell you are actually in is the one dvm answers for.

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
  ok    PATH: /Users/you/.dvm/shims is on PATH ahead of every other dart.
  ok    shims: /Users/you/.dvm/shims/dart runs /Users/you/.dvm/bin/dvm.
  ok    shell: no shell function or alias named `dvm` in your startup files.
  ok    config: /Users/you/.dvm/config.json is valid; the global default Dart 3.9.0 is installed.
  ok    project: /Users/you/code/my-project/.dvmrc pins Dart 3.13.2, which is installed.
  ok    project: /Users/you/code/my-project/.dvm/dart_sdk points at /Users/you/.dvm/versions/3.13.2.

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

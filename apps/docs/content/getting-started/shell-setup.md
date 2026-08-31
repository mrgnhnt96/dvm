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

Add this line to /Users/you/.zshrc (/bin/zsh):

  export PATH="/Users/you/.dvm/shims:$PATH"

It has to go ahead of anything else that puts a dart on PATH, and it only takes effect in shells started after you save the file.

Or let dvm add it for you: dvm setup --write-path-line
It backs /Users/you/.zshrc up before touching it, and dvm setup --remove-path-line takes the line back out.

Then check it with: dvm doctor
```

## Adding the PATH line

`dvm setup` prints the exact line and names the file it belongs in, so the change to your login shell stays yours to make. The right file differs between shells, between login and non-login setups, and between hand-managed profiles, and you are the one who knows which of those you have.

`dvm setup` reads `$SHELL` to work out which line to hand you and where it goes:

| Shell | The file dvm names |
| --- | --- |
| zsh (macOS default) | `~/.zshrc` |
| bash | `~/.bashrc` |
| fish | `~/.config/fish/config.fish`, with `fish_add_path` |
| PowerShell | your user environment — see [On Windows](#on-windows) below |

dvm names **one** file per shell, and for bash that is always `~/.bashrc`. If yours is a macOS bash login shell — which reads `~/.bash_profile` and not `~/.bashrc` — put the line where your shell actually reads it, and be aware that `--write-path-line` writes to `~/.bashrc` rather than working that out for you.

Then start a **new** shell. The file is read when a shell starts, so the one you are in keeps the environment it was given.

## `dvm setup` prints; `dvm setup --write-path-line` writes

The difference is the single most common reason a correct install still resolves the wrong `dart`, so it is worth stating flatly:

| Command | Writes the shim | Adds the line to your startup file |
| --- | --- | --- |
| `dvm setup` | yes | **no** — it prints the line for you to add |
| `dvm setup --write-path-line` | yes | yes |

Plain `dvm setup` **writes the shim and prints the line**. It does not edit anything. If you run it, read the output as confirmation, and open a new terminal, nothing about your `PATH` has changed and `dart` still resolves to whatever it resolved to before. The shim is there and correct; it is simply not on `PATH`.

That is not a failure state you have to guess at — `dvm doctor` says it outright, and the section below shows exactly what it prints.

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

That position is the whole of it. If another directory holding a `dart` appears earlier in the list, that binary is found first and the shim is never reached. Your pins do nothing, and there is no error message — the symptom is `dart --version` reporting a version you did not ask for, with everything else apparently correct.

### What else on your machine provides a `dart`

More than people expect. These are the common ones, and the first four are all things a Dart or Flutter developer plausibly installed on purpose:

| Directory | Where it comes from |
| --- | --- |
| `~/fvm/default/bin` | [fvm](https://fvm.app), the Flutter version manager — its default SDK ships a `dart` |
| `<flutter>/bin/cache/dart-sdk/bin` | any Flutter SDK checkout; Flutter bundles its own Dart |
| `~/.asdf/shims` | asdf, if you have ever added a Dart or Flutter plugin |
| `/opt/homebrew/bin`, `/usr/local/bin` | `brew install dart`, or a symlink somebody made years ago |
| `~/.local/bin` | a hand-unzipped SDK, or a `dart` copied there |

You do not have to guess which of these you have. `dvm doctor` enumerates them.

### What it looks like when it goes wrong

This is the case that prompted this section: dvm installed correctly, `dvm setup` run, the shim written and valid — and `dart` still answering from fvm, because plain `dvm setup` prints the `PATH` line rather than adding it.

```sh
which dart
```

```text
/Users/you/fvm/default/bin/dart
```

```sh
dvm doctor
```

```text
dvm doctor
  FAIL  PATH: /Users/you/.dvm/shims is not on PATH, so `dart` does not go through dvm.
          PATH order (entries that provide a dart):
            1. /Users/you/fvm/default/bin
          -> Add it to your shell startup file: export PATH="/Users/you/.dvm/shims:$PATH"
  ok    shims: /Users/you/.dvm/shims/dart runs /Users/you/.dvm/bin/dvm.
  ok    shell: no shell function or alias named `dvm` in your startup files.

1 problem, 0 warnings.
```

Read the `ok` lines as carefully as the `FAIL`. The shim exists and points at a real dvm; nothing is broken or half-installed. The one missing thing is the `PATH` entry, and `--write-path-line` is what adds it:

```sh
dvm setup --write-path-line
```

The near neighbour of this is the shims directory being on `PATH` but *behind* something:

```text
dvm doctor
  FAIL  PATH: /Users/you/.dvm/shims is on PATH but an entry ahead of it provides a dart, so the shim is never reached.
          PATH order (entries that provide a dart):
            2. /Users/you/.dvm/shims  <- dvm shims
            1. /Users/you/fvm/default/bin
          -> Put the shims first: export PATH="/Users/you/.dvm/shims:$PATH"
```

The numbers are positions in `PATH`, not the order of the lines: dvm lists its own entry first so you can see where it landed, then everything that beats it. Here the shims are second and fvm is first, so fvm wins.

## Where in the *file* the line goes

`PATH` order is decided by your startup file, and a startup file is read top to bottom. So the position of the line within the file matters just as much as the position of the directory within `PATH` — and there is one shape that quietly discards everything above it.

Compare these two lines:

```sh
export PATH="$HOME/.dvm/shims:$PATH"   # RELATIVE — prepends, keeps what PATH held
export PATH=/a:/b:/c                   # ABSOLUTE — replaces PATH entirely
```

The second has no `$PATH` on the right-hand side. It does not add to `PATH`, it **sets** it, throwing away everything `PATH` held at that point. Plenty of real `.zshrc` files end with one, often written years ago or generated by an installer.

If dvm's line is above it, the absolute assignment wipes it out:

```sh
# ~/.zshrc — BROKEN
export PATH="$HOME/.dvm/shims:$PATH"
export PATH=$HOME/fvm/default/bin:/usr/local/bin:/usr/bin:/bin
```

```text
which dart -> /Users/you/fvm/default/bin/dart
```

The symptom is maddening precisely because the file *visibly contains the correct line*. You added it, you started a new shell, and `dart` is still wrong.

Moving dvm's line below fixes it:

```sh
# ~/.zshrc — WORKS
export PATH=$HOME/fvm/default/bin:/usr/local/bin:/usr/bin:/bin
export PATH="$HOME/.dvm/shims:$PATH"
```

```text
which dart -> /Users/you/.dvm/shims/dart
```

`dvm setup --write-path-line` **appends its block to the end of the file**, so it lands after an absolute assignment that is currently last, and it works. Do not read that as a guarantee: it is a consequence of the block going last, not of dvm understanding your file. If some other tool later regenerates its absolute `PATH` line at the end of your startup file, that line moves below dvm's block and `dart` stops resolving through dvm with nothing in dvm having changed. If that happens, `dvm doctor` reports it the same way as any other ordering problem.

## Running dvm and fvm on the same machine

You do not have to choose. They manage different things — fvm manages **Flutter** SDKs, dvm manages **Dart** SDKs — and it is entirely reasonable to want both. The collision is only that a Flutter SDK bundles a Dart SDK, so fvm's `bin` directory also answers a bare `dart`.

Whichever of the two is earlier on `PATH` wins for `dart`. That is a decision to make deliberately rather than discover:

- **Shims first (`~/.dvm/shims` ahead of `~/fvm/default/bin`).** A bare `dart` follows your dvm pins everywhere. `flutter` is untouched — it is a different executable and fvm still answers it. This is the right default if you write Dart packages and use dvm's `.dvmrc` pins.
- **fvm first.** A bare `dart` is whatever Dart ships inside your current Flutter SDK, which is what you want if the Dart version must always match the Flutter version. dvm still works; you reach it explicitly through [`dvm dart`](/commands/dart) and [`dvm exec`](/commands/exec), which do not depend on `PATH` order at all.

There is no need to uninstall anything. Order the two entries the way you want, and `dvm doctor` will tell you which one is actually winning.

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

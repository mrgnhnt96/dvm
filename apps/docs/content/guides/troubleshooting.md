---
title: Troubleshooting
description: The failures that look like dvm doing nothing at all — and the command that names each one.
---

Start here:

```sh
dvm doctor
dvm which
```

[`doctor`](/commands/doctor) covers the machine — `PATH`, shims, shell startup files, config. [`which`](/commands/which) covers this directory — which SDK, and which of the [five rules](/versions/resolution-order) chose it. Between them they name almost everything on this page.

## `which dart` is not dvm's shim

The most common report there is, usually phrased as "I installed dvm and `dart` is still the wrong version". Two commands settle it.

```sh
which dart
```

```text
/Users/you/fvm/default/bin/dart
```

Anything other than `~/.dvm/shims/dart` means the shim is not being reached and your pin is irrelevant — nothing dvm knows about versions has any effect. Then:

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

`doctor` numbers every `PATH` entry that provides a `dart`, so it names the directory that is actually winning instead of leaving you to read `$PATH` by eye. Work down these four causes in order; the `doctor` output tells you which one you are in.

**You ran `dvm setup` but not `dvm setup --write-path-line`.** These do different things. Plain `dvm setup` writes the shim and *prints* the `PATH` line; it edits nothing. This is exactly the state above: the `shims` line is `ok`, the `PATH` line is `FAIL`, and everything looks installed because it *is* installed. Fix it with:

```sh
dvm setup --write-path-line
```

**Another version manager is earlier on `PATH`.** [fvm](https://fvm.app) is the usual one — it manages Flutter SDKs, and every Flutter SDK bundles a `dart`, so `~/fvm/default/bin` answers a bare `dart` too. asdf's shims, a Homebrew `dart`, a Flutter checkout's `bin/cache/dart-sdk/bin`, and a hand-unzipped SDK in `~/.local/bin` all do the same. `doctor` reports this as the shims being on `PATH` *behind* something:

```text
  FAIL  PATH: /Users/you/.dvm/shims is on PATH but an entry ahead of it provides a dart, so the shim is never reached.
          PATH order (entries that provide a dart):
            2. /Users/you/.dvm/shims  <- dvm shims
            1. /Users/you/fvm/default/bin
          -> Put the shims first: export PATH="/Users/you/.dvm/shims:$PATH"
```

The numbers are `PATH` positions; dvm lists its own entry first so you can see where it landed. You do not have to remove the other tool — see [Running dvm and fvm on the same machine](/getting-started/shell-setup) for choosing which one wins on purpose.

**The line is in your startup file but something below it overwrites `PATH`.** A line like `export PATH=/a:/b:/c`, with no `$PATH` on the right-hand side, *replaces* `PATH` rather than adding to it, discarding everything set above it. If dvm's line is above one of those, it is silently erased — and the file visibly contains the correct line, which is what makes this one so hard to see. Move dvm's line **below** the absolute assignment. [Where in the *file* the line goes](/getting-started/shell-setup) has the before and after.

**You never ran [`dvm setup`](/commands/setup) at all.** Then `doctor` fails on `shims` as well as `PATH`, and the shim simply does not exist yet.

In every case the fix takes effect in shells started afterwards, so open a new terminal before re-testing.

If `which dart` *is* the shim, the pin is being resolved and the answer is not what you expected. Run `dvm which` — it names the rule and the file.

## `dvm` runs, but it is not the dvm I installed

The one that costs an afternoon.

The older [`cbracken/dvm`](/guides/migrating) installs itself as a **shell function** sourced from `.zshrc` or `.bashrc`. A shell function is resolved *before `PATH` is searched at all*, so the binary you installed is never reached — and the two tools have enough overlapping command names that the errors read like your own mistakes.

```sh
type dvm      # "dvm is a shell function" => this is you
```

`dvm doctor` reports it by file and line. Delete the line that sources the old script and start a new shell.

## `DVM_DART_VERSION` is set and I forgot

Rule 1 beats everything on disk, including the `.dvmrc` you are looking at.

```sh
echo "$DVM_DART_VERSION"
```

`dvm which` says so outright when this is what happened:

```text
Chosen by rule 1 of 5: DVM_DART_VERSION is set in the environment, which overrides everything on disk.
```

Common source: a shell exported it in an earlier command, or a CI job set it at the workflow level and you are debugging a step that inherits it.

## "is pinned by … but it is not installed"

```text
dvm: Dart 3.9.0 is pinned by /Users/you/code/api/.dvmrc, but it is not installed. Run: dvm install 3.9.0
```

Exactly what it says. dvm refuses to fall through to another SDK, because silently running a different version than the project asked for is the failure the tool exists to prevent.

```sh
dvm install 3.9.0
```

Or, if the pin is wrong, `dvm use <right version>`.

## "no stable SDK has been installed, so dvm does not know which version that is"

Your pin says `stable`, but nothing has recorded what `stable` means on this machine.

[Resolution answers a channel name from `config.json`](/versions/aliases), so `stable` means whatever was written down when you last ran `dvm install stable`. Run it:

```sh
dvm install stable
```

## "No Dart SDK applies in …"

[Rule 5](/versions/resolution-order): nothing matched. The message lists all four things it checked. Pick one:

```sh
dvm use <version>      # pin this project
dvm global <version>   # set a machine-wide fallback
```

## An SDK is installed but marked `BROKEN: no bin/dart`

An interrupted install, or something in `~/.dvm/versions` that is not an SDK. `dvm list` shows it and marks it, because a few hundred megabytes of unusable disk is worth knowing about.

```sh
dvm remove <version> --force
dvm install <version>
```

## The global default names something that is not installed

```text
The global default names 3.9.0, which is not installed. Run: dvm install 3.9.0
```

This is what [`dvm remove --force`](/commands/remove) leaves behind, and while it lasts, every command run outside a pinned project fails. Either install it or repoint it with [`dvm global`](/commands/global).

## My IDE has not noticed the pin

The `dart` on `PATH` is only half the story for editors — many want an SDK *directory*. [`dvm use`](/commands/use) writes one for exactly this:

```text
.dvm/dart_sdk -> ~/.dvm/versions/3.13.2
```

It sits in the directory that holds the `.dvmrc`, so in a monorepo look next to the pin that governs your package rather than in the package you are standing in. Point the analyzer or Dart plugin at it and it follows the pin along with everything else. Keep it out of version control — it is an absolute path into your home directory.

## The `.dvm/` symlink got committed

```sh
git rm --cached -r .dvm
dvm use <version> --gitignore
```

The second command appends `.dvm/` to `.gitignore` for you; dvm makes that edit when you pass the flag.

## `dvm exec: command not found: X`

Exit code 127, the same as a shell. The command was not on the child's `PATH` — which is the pinned SDK's `bin`, then everything you already had. If `X` is a globally activated Dart executable, it lives in `~/.pub-cache/bin`, which has to be on your `PATH` for `dvm exec` to find it too.

## An interrupted install

`~/.dvm/cache` holds in-flight downloads and is safe to delete at any time:

```sh
rm -rf ~/.dvm/cache
```

Extraction happens in `cache/` and is renamed into place atomically, so `versions/` only ever holds complete SDKs and `cache/` is the whole of the cleanup.

## Still stuck

`dvm doctor` output and `dvm which` output, together, describe the whole state that decides which SDK you get. They are the right thing to paste into [an issue](https://github.com/mrgnhnt96/dvm/issues).

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

## `dart --version` is not the version I pinned

Check what `dart` even is:

```sh
which dart
```

If it is **not** `~/.dvm/shims/dart`, the shim is not being reached and your pin is irrelevant. Two causes:

**Something earlier on `PATH` supplies a `dart`.** `PATH` is searched left to right, so Homebrew's `dart`, a Flutter SDK's bundled `dart`, or `/usr/local/bin/dart` appearing before `~/.dvm/shims` wins. There is no error — that is the whole problem. `dvm doctor` prints the offending entry. Move `~/.dvm/shims` to the front and start a new shell.

**You never ran [`dvm setup`](/commands/setup).** The shim does not exist yet.

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

Point the analyzer or Dart plugin at `.dvm/dart_sdk`, and it follows the pin along with everything else. Do not commit that symlink — it is an absolute path into your home directory.

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

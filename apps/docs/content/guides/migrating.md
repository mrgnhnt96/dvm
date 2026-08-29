---
title: Migrating from cbracken/dvm
description: Move an existing ~/.dvm across without re-downloading a single SDK — and remove the shell function that would otherwise hide the new tool.
---

[`cbracken/dvm`](https://github.com/cbracken/dvm) is the older Dart version manager, and it also lives in `~/.dvm`. This dvm deliberately takes that directory over, and [`dvm migrate`](/commands/migrate) is how the handover happens.

## What is already there

An older install looks like this:

```text
~/.dvm/
  darts/<version>/     the SDKs, extracted
  scripts/dvm          the shell function that gets sourced
  environments/        the older tool's per-environment symlinks
  .git/                its own checkout
```

The important part: `darts/<version>` holds extracted SDKs **in exactly the layout this dvm expects in `versions/<version>`**. So migration is a move, not a download.

## Step 1 — install this dvm

```sh
curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh
```

The install script writes `~/.dvm/bin/dvm`, a path the older tool leaves alone, so at this point both installs sit side by side.

## Step 2 — remove the shell function

**Do this first — it is what lets the rest of this page work.**

The older dvm is installed as a shell *function*, sourced from your `.zshrc` or `.bashrc`:

```sh
[[ -s "$HOME/.dvm/scripts/dvm" ]] && . "$HOME/.dvm/scripts/dvm"
```

A shell function is resolved **before `PATH` is searched at all**. So with that line in place, typing `dvm` runs the old tool no matter what you have installed — and because the two tools have overlapping command names, the errors look like your own mistakes rather than like the wrong program answering.

Delete the line, then start a new shell. [`dvm doctor`](/commands/doctor) reports this by file and line if you are not sure whether you got it:

```sh
dvm doctor
```

## Step 3 — see the plan

```sh
dvm migrate --dry-run
```

```text
Found an older dvm (cbracken/dvm) in /Users/you/.dvm:
  darts/  scripts/  environments/

Would move 3 SDKs from darts/ to versions/:
  3.4.0
  2.19.6
  3.0.5   (skipped: versions/3.0.5 already exists)

A later `dvm migrate --clean` would delete:
  /Users/you/.dvm/scripts
  /Users/you/.dvm/environments
  /Users/you/.dvm/.git
```

`--dry-run` reports and stops there, so the disk is exactly as you left it.

## Step 4 — migrate

```sh
dvm migrate
```

This moves the SDKs and stops there. Deleting is a separate `--clean` run.

Those directories may be your only copy of those SDKs, so the command is written around that: the move happens before any deletion, a version already present in `versions/` is skipped rather than overwritten, and a move is only reported as done once the destination is verified.

## Step 5 — set up the shim

The older tool worked by switching a global environment. This one resolves per directory, through a shim:

```sh
dvm setup
```

Add the `PATH` line it prints, start a new shell, and check:

```sh
dvm doctor
```

See [The Shim and Your PATH](/getting-started/shell-setup).

## Step 6 — clean up, when you are ready

```sh
dvm migrate --clean
```

Removes the older tool's `scripts/`, `environments/` and `.git/`. It asks first, and you can take your time: they cost a few megabytes, and `doctor` reports them as a warning.

## What changes about your workflow

| Old way | New way |
| --- | --- |
| `dvm install 2.19.6` | [`dvm install 2.19.6`](/commands/install) — same idea, [central cache](/commands/list). |
| `dvm use 2.19.6` — switched a global environment | [`dvm use 2.19.6`](/commands/use) — writes a committed [`.dvmrc`](/versions/dvmrc) for *this project*. |
| `dvm list` | [`dvm list`](/commands/list). |
| Remembering which environment is active | `cd` into a project and `dart` is that project's SDK. |
| — | [`dvm which`](/commands/which) tells you which of [five rules](/versions/resolution-order) chose the SDK you got. |

The headline difference is the per-project pin. The older tool has one global environment at a time; this one answers the question per directory, which is what lets two repositories on one machine disagree about their SDK and both be right.

---
title: dvm migrate
description: Import SDKs from the older cbracken/dvm layout, without re-downloading anything.
---

```text
dvm migrate [--dry-run] [--clean]
```

Moves the SDKs an older `cbracken/dvm` install already downloaded into the layout this dvm uses. See [Migrating from cbracken/dvm](/guides/migrating) for the full walkthrough; this page is the command's reference.

## Flags

| Flag | Effect |
| --- | --- |
| `--dry-run` | Print everything that would move and everything a later `--clean` would delete. Reports only. |
| `--clean` | Remove the older tool's own files, once its SDKs have been migrated. Always a step of its own. |
| `-y`, `--yes` | Answer yes to the questions this command would ask. |

## What it does

Both tools live in `~/.dvm`. The older one keeps its SDKs in `~/.dvm/darts/<version>`, extracted, in exactly the shape this dvm keeps them in `~/.dvm/versions/<version>`.

So migration is a **move**: several hundred megabytes of SDK you already have get relocated on disk rather than downloaded again.

```sh
dvm migrate
```

```text
Found an older dvm (cbracken/dvm) in /Users/you/.dvm:
  darts/  scripts/  environments/

Moving 3 SDKs from darts/ to versions/...
  3.4.0  moved
  2.19.6 moved
  3.0.5  skipped: versions/3.0.5 already exists

2 SDKs moved. The older tool's own files are still here.
Remove them with: dvm migrate --clean
```

## How your SDKs stay safe

Those directories may be your only copy of those SDKs, so the command is built around keeping them:

- the move happens **before** anything is deleted,
- a version already present in `versions/` is **skipped**, so what you have stays what you have,
- a move is reported as done once the destination is verified,
- deleting the older tool's own files is a **separate `--clean` run** that has to be asked for and then confirmed.

Run `--dry-run` first if you want to see the whole plan before anything moves.

## `--clean`

```sh
dvm migrate --clean
```

Removes the older tool's `scripts/`, `environments/` and its git checkout. It asks for confirmation; `--yes` answers for you, for scripted use.

It is a separate step on purpose, so a migration that succeeded stays succeeded while the deletion waits for you.

## On a machine with only this dvm

```text
Nothing to migrate: no older dvm (cbracken/dvm) install in /Users/you/.dvm.
That directory would have a scripts/dvm and a darts/ in it.
```

Exit code 0: there was nothing to do, and that is a success.

## See also

- [Migrating from cbracken/dvm](/guides/migrating) — including the shell function you have to remove by hand.

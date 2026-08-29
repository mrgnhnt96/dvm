---
title: dvm exec
description: Run any command with the resolved SDK first on PATH.
---

```text
dvm exec <command> [args...]
```

Resolves the SDK for the current directory, puts its `bin` first on the child's `PATH`, and runs the command you named.

```sh
dvm exec melos bootstrap
dvm exec ./tool/build.sh
dvm exec dart_frog dev
```

This is the general form of [`dvm dart`](/commands/dart). The payoff is every `dart` that the command you name goes on to spawn.

## Why this matters

`melos bootstrap` runs `dart pub get` in every package. A build script shells out to `dart compile`. A code generator spawns `dart run build_runner`. Each of those inherits the environment of its parent, so putting the pinned SDK first on that environment's `PATH` is what makes the pin apply all the way down.

## The lookup is done on the child's PATH

dvm resolves the command name itself rather than handing a bare name to the operating system, because the whole point is to search the `PATH` the *child* is about to get, not the one dvm has.

The shell's rule applies: a name containing a separator (`./tool/build.sh`, `/usr/bin/env`) is treated as a path and used as given. On Windows a bare name is resolved through the usual `.exe`/`.bat`/`.cmd` extensions.

## Exit code 127

```text
dvm exec: command not found: melos
```

**127** is what a shell returns for the same condition. `dvm exec` is a launcher, so it answers the way the thing it stands in for answers, and a script testing for 127 gets 127.

## Environment

Identical to [`dvm dart`](/commands/dart), because both build it the same way:

- stdio inherited, exit code forwarded, `SIGINT`/`SIGTERM` forwarded,
- the resolved SDK's `bin` prepended to `PATH`,
- `DVM_DART_VERSION` set to the resolved version, except under [rule 4](/versions/resolution-order).

Nested `dvm exec` calls keep `PATH` the same size: when the first entry is already the SDK's `bin`, it stays as it is.

## Arguments

Everything after `exec` belongs to the child, including flags. A leading `--` is dropped, so `dvm exec -- melos --version` works.

## See also

- [`dvm dart`](/commands/dart) — the `dart`-specific shorthand.
- [Using dvm in CI](/guides/ci) — where `dvm exec` replaces a shim entirely.

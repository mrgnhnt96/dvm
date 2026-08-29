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

This is the general form of [`dvm dart`](/commands/dart). The point is not the command you name — it is every `dart` that command goes on to spawn.

## Why this matters

`melos bootstrap` runs `dart pub get` in every package. A build script shells out to `dart compile`. A code generator spawns `dart run build_runner`. None of those go through your shell's `PATH` lookup the way you do — but they do inherit the environment of their parent, so putting the pinned SDK first on that environment's `PATH` is what makes the pin apply all the way down.

## The lookup is done on the child's PATH

dvm resolves the command name itself rather than handing a bare name to the operating system, because the whole point is to search the `PATH` the *child* is about to get, not the one dvm has.

The shell's rule applies: a name containing a separator (`./tool/build.sh`, `/usr/bin/env`) is treated as a path and used as given, not searched for. On Windows a bare name is resolved through the usual `.exe`/`.bat`/`.cmd` extensions.

## Not found

```text
dvm exec: command not found: melos
```

Exit code **127** — what a shell returns for the same condition. `dvm exec` is a launcher, so it answers the way the thing it stands in for answers; a script testing for 127 must not be handed 1 instead.

## Environment

Identical to [`dvm dart`](/commands/dart), because both build it the same way — a difference between them would be a bug that only showed up in whichever one you used second:

- stdio inherited, exit code forwarded, `SIGINT`/`SIGTERM` forwarded,
- the resolved SDK's `bin` prepended to `PATH`,
- `DVM_DART_VERSION` set to the resolved version, except under [rule 4](/versions/resolution-order).

Nested `dvm exec` calls do not keep growing `PATH`: if the first entry is already the SDK's `bin`, it is left alone rather than added again.

## Arguments

Everything after `exec` belongs to the child, including flags. A leading `--` is dropped, so `dvm exec -- melos --version` works.

## See also

- [`dvm dart`](/commands/dart) — the `dart`-specific shorthand.
- [Using dvm in CI](/guides/ci) — where `dvm exec` replaces a shim entirely.

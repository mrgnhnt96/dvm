---
title: dvm dart
description: Run `dart` from the resolved SDK, forwarding every argument untouched.
---

```text
dvm dart <args...>
```

Runs the resolved SDK's `dart` with the arguments you gave, forwards its exit code, and forwards `SIGINT`/`SIGTERM` to it.

```sh
dvm dart --version
dvm dart run bin/main.dart
dvm dart test
```

This is what [the shim](/getting-started/shell-setup) calls. Once `~/.dvm/shims` is on your `PATH`, plain `dart` does the same thing, so this form is mostly for being explicit — or for a machine where the shim has yet to be installed.

## Arguments are passed through verbatim

Everything after `dvm dart` belongs to the child process, including flags that would otherwise look like dvm's own. That is why

```sh
dvm dart --version
```

reports the *SDK's* version rather than dvm's.

The one exception is a leading `--`. Writing `dvm dart -- --version` uses the terminator to say "stop reading these", so dvm drops the terminator and passes the rest along.

## What the child process sees

- **stdio is inherited.** The child talks to the real terminal, so anything that asks "am I a tty?" — a prompt from `dart run`, progress output, colour — gets the right answer, and dvm stays out of the byte path.
- **`PATH` has the resolved SDK's `bin` first**, so a `dart` that the child itself spawns is the same one.
- **`DVM_DART_VERSION` is set** to the resolved version, so nested dvm invocations agree with this one. Under [rule 4](/versions/resolution-order) it is left unset, so a nested dvm runs the five rules for itself and reaches the same SDK.
- **The exit code becomes dvm's.** A failing `dart test` fails through dvm exactly as it would without it, which is what CI depends on.

## Signals

`SIGINT` and `SIGTERM` are forwarded to the child. Ctrl-C at a terminal already reaches the whole foreground process group; forwarding extends the same behaviour to a `kill` aimed at dvm by a supervisor or a script, so the real work stops along with the wrapper.

## See also

- [`dvm exec`](/commands/exec) — the same thing for any command, not just `dart`.
- [The Shim and Your PATH](/getting-started/shell-setup) — how plain `dart` gets here.

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

This is what [the shim](/getting-started/shell-setup) calls. Once `~/.dvm/shims` is on your `PATH`, plain `dart` does the same thing and you rarely type this form — it is useful when the shim is not installed, or when you want to be explicit.

## Arguments are passed through verbatim

Everything after `dvm dart` belongs to the child process, including flags that would otherwise look like dvm's own. That is why

```sh
dvm dart --version
```

reports the *SDK's* version rather than dvm's.

The one exception is a leading `--`. Writing `dvm dart -- --version` uses the terminator to say "stop reading these", so dvm drops the terminator and passes the rest along. Without that, `dart` would receive an argument you meant for dvm.

## What the child process sees

- **stdio is inherited**, not piped. The child is talking to the real terminal, so anything that asks "am I a tty?" — a prompt from `dart run`, progress output, colour — gets the right answer, and dvm never sits in the middle copying bytes.
- **`PATH` has the resolved SDK's `bin` first**, so a `dart` that the child itself spawns is the same one.
- **`DVM_DART_VERSION` is set** to the resolved version, so nested dvm invocations agree with this one. It is deliberately *not* set under [rule 4](/versions/resolution-order), where the SDK is not dvm-managed.
- **The exit code becomes dvm's.** A version manager that turned a failing `dart test` into a success would break CI for everyone downstream.

## Signals

`SIGINT` and `SIGTERM` are forwarded to the child. Ctrl-C at a terminal already reaches the whole foreground process group, but a `kill` aimed at dvm by a supervisor or a script does not — without forwarding, that would kill the wrapper and leave the real work orphaned.

## See also

- [`dvm exec`](/commands/exec) — the same thing for any command, not just `dart`.
- [The Shim and Your PATH](/getting-started/shell-setup) — how plain `dart` gets here.

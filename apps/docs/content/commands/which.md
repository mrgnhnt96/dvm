---
title: dvm which
description: Print the resolved SDK and which of the five rules chose it. Alias — dvm current.
---

```text
dvm which [--path]
dvm current
```

The debugging command. It prints the `dart` that applies in this directory **and the rule that produced it**.

```sh
dvm which
```

```text
/Users/you/.dvm/versions/3.13.2/bin/dart
Dart 3.13.2
Chosen by rule 2 of 5: pinned by /Users/you/code/api/.dvmrc.
SDK: /Users/you/.dvm/versions/3.13.2
```

`current` is an alias for the same command.

## Flags

| Flag | Effect |
| --- | --- |
| `--path` | Print only the path to the `dart` executable, for scripting. |

```sh
"$(dvm which --path)" --version
```

## Why it names the rule

Debuggability is the point of the whole design. "Which Dart am I running?" is easy; "why *that* one?" is the question that costs an afternoon. Every one of the [five rules](/versions/resolution-order) gets its own sentence:

```text
Chosen by rule 1 of 5: DVM_DART_VERSION is set in the environment, which overrides everything on disk.
Chosen by rule 2 of 5: pinned by /Users/you/code/api/.dvmrc.
Chosen by rule 3 of 5: no .dvmrc applies here, so the global default in /Users/you/.dvm/config.json was used.
Chosen by rule 4 of 5: nothing pins a version here and no global default is set, so this is the next dart on PATH, found in /opt/homebrew/bin.
```

## Indirect pins

When the pin was a name rather than a version, the hop is spelled out:

```text
  It says "work", an alias for 3.13.2 in /Users/you/.dvm/config.json.
  It says "stable", the channel that was recorded as 3.13.2 when it was last installed.
```

## An SDK from your PATH

Under rule 4 the SDK is whatever was already on your `PATH`:

```text
/opt/homebrew/bin/dart
Chosen by rule 4 of 5: nothing pins a version here and no global default is set, so this is the next dart on PATH, found in /opt/homebrew/bin.
SDK: /opt/homebrew/opt/dart
This SDK is not managed by dvm. Pin one for this directory with: dvm use <version>
```

dvm reports the path and leaves the version to the SDK itself, since this is one it did not install.

## Reaching rule 5

When no rule matches, `dvm which` gives the same [rule 5](/versions/resolution-order) message every other command gives — a list of what was checked and what to run.

## See also

- [Resolution Order](/versions/resolution-order) — the rules this command reports on.
- [`dvm doctor`](/commands/doctor) — for when the problem is `PATH` rather than the pin.

---
title: dvm doctor
description: Check PATH order, shim health, stale symlinks, a shadowing shell function, and config validity.
---

```text
dvm doctor
```

Runs every check dvm knows how to run, and names the file each finding is about along with what to do next.

```sh
dvm doctor
```

```text
dvm doctor
  ok    PATH: /Users/you/.dvm/shims is on PATH ahead of every other dart.
  ok    shims: /Users/you/.dvm/shims/dart runs /Users/you/.dvm/bin/dvm.
  ok    shell: no shell function or alias named `dvm` in your startup files.
  ok    config: /Users/you/.dvm/config.json is valid; the global default Dart 3.9.0 is installed.
  ok    project: /Users/you/code/api/.dvmrc pins Dart 3.13.2, which is installed.
  ok    project: /Users/you/code/api/.dvm/dart_sdk points at /Users/you/.dvm/versions/3.13.2.

Everything checks out.
```

## Severities and the exit code

| Marker | Meaning | Affects exit code |
| --- | --- | --- |
| `ok` | Checked, nothing wrong. | no |
| `warn` | Worth knowing, not broken. | no |
| `FAIL` | Something is actually wrong. | **yes** |

Only `FAIL` changes the exit code, which is what makes

```sh
dvm doctor || exit 1
```

usable as a CI gate: it fails the build on what is actually broken, and passes a machine that merely still has the old tool's directories lying around.

## What it checks

**PATH** — whether `~/.dvm/shims` sits ahead of every other `dart` on `PATH`. Position is the question, because a `dart` in an earlier entry is found first and the shim never runs, which looks exactly like dvm doing nothing at all.

**shims** — that the shim exists, is executable, and points at a dvm binary that is still there. This is the check that catches a shim left behind by moving or reinstalling dvm; running [`dvm setup`](/commands/setup) again puts it right.

**shell** — whether a shell function or alias named `dvm` is being sourced from your startup files. **This is the most valuable check in the command.** On a machine that has ever carried [`cbracken/dvm`](/guides/migrating), `dvm` is a shell *function*, and a shell function is resolved before `PATH` is searched at all — so the binary you installed is never reached, and nothing on screen says why. `doctor` reports the file and the line.

**config** — that `~/.dvm/config.json` parses, and that the global default and aliases in it name versions that exist.

**project** — the `.dvmrc` that applies here, found by the same walk up the tree that [`dvm use`](/commands/use) writes by, whether the version it pins is installed, and whether the `.dvm/dart_sdk` link beside that pin still reaches that SDK.

## Reading a finding

Every non-`ok` finding carries supporting detail and a remedy:

```text
  FAIL  PATH: /Users/you/.dvm/shims is on PATH but an entry ahead of it provides a dart, so the shim is never reached.
          PATH order (entries that provide a dart):
            5. /Users/you/.dvm/shims  <- dvm shims
            2. /opt/homebrew/bin
          -> Put the shims first: export PATH="/Users/you/.dvm/shims:$PATH"
```

The remedy is written for the shell you are in. On Windows, where PATH is an environment setting rather than a line in a startup file, `doctor` hands you the PowerShell call that sets it:

```text
  FAIL  PATH: C:\Users\you\.dvm\shims is not on PATH, so `dart` does not go through dvm.
          PATH order (entries that provide a dart):
            3. C:\hostedtoolcache\windows\dart\3.13.2\x64\bin
          -> Run this once in PowerShell: [Environment]::SetEnvironmentVariable('Path', 'C:\Users\you\.dvm\shims;' + [Environment]::GetEnvironmentVariable('Path', 'User'), 'User')
```

## See also

- [Troubleshooting](/guides/troubleshooting) — the failures this command exists to catch.
- [`dvm which`](/commands/which) — for when `PATH` is fine and the *pin* is the surprise.

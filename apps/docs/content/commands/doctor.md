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
  ok    PATH: /Users/you/.dvm/shims is first on PATH.
  ok    shims: /Users/you/.dvm/shims/dart points at /Users/you/.dvm/bin/dvm.
  ok    shell: nothing shadows `dvm`.
  ok    config: /Users/you/.dvm/config.json parses.
  ok    project: /Users/you/code/api/.dvmrc pins 3.13.2 (installed).

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

**project** — the `.dvmrc` that applies here, and whether the version it pins is installed.

## Reading a finding

Every non-`ok` finding carries supporting detail and a remedy:

```text
  FAIL  PATH: /opt/homebrew/bin comes before /Users/you/.dvm/shims and supplies a dart.
          PATH: /opt/homebrew/bin:/usr/bin:/Users/you/.dvm/shims
          -> export PATH="/Users/you/.dvm/shims:$PATH"
```

## See also

- [Troubleshooting](/guides/troubleshooting) — the failures this command exists to catch.
- [`dvm which`](/commands/which) — for when `PATH` is fine and the *pin* is the surprise.

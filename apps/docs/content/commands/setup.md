---
title: dvm setup
description: Install the shims and print the PATH line to add — once per machine.
---

```text
dvm setup [--dvm-path <path>]
```

Writes `~/.dvm/shims/dart` (plus `dart.bat` on Windows) and tells you the one line to add to your shell's startup file.

```sh
dvm setup
```

```text
Wrote /Users/you/.dvm/shims/dart
  -> /Users/you/.dvm/bin/dvm exec dart

Add this to ~/.zshrc:

  export PATH="/Users/you/.dvm/shims:$PATH"

Then check it with: dvm doctor
```

## Flags

| Flag | Effect |
| --- | --- |
| `--dvm-path <path>` | The dvm binary to bake into the shim. Defaults to the running one; needed when running from source. |

## It prints the PATH line for you

It prints the exact line and names the file it belongs in, so the change to your login shell stays yours to make. See [The Shim and Your PATH](/getting-started/shell-setup) for which file each shell reads.

## It needs a dvm binary to point at

The shim contains an absolute path to a dvm binary, so `dvm setup` has to know where one is. Under `dart run bin/dvm.dart` the running executable is the *Dart VM*, and a shim baked with that path would read

```sh
exec /path/to/dart exec dart "$@"
```

and hand `exec dart` to the SDK as arguments on every `dart` invocation on the machine. So dvm names the binary it wants instead of guessing:

```text
dvm: dvm is running from source (via /Users/you/.dvm/versions/3.13.2/bin/dart), so it cannot tell where a dvm binary lives, and a shim pointing at the Dart VM would break every `dart` on this machine.
Compile it first:  dart compile exe bin/dvm.dart -o /usr/local/bin/dvm
Or name the binary: dvm setup --dvm-path <path to dvm>
```

`--dvm-path` names the binary directly, which is the answer whenever dvm is running from source.

## Exit code

`dvm setup` exits **1** when it finds something that would leave the shim inert — most importantly a [shell function shadowing `dvm`](/getting-started/shell-setup), which the older `cbracken/dvm` installs. The exit code tells you at the command that wrote the shim, rather than the next time you run `dart`.

## Re-running it

Safe, and the right thing to do after moving or reinstalling the dvm binary — the shim contains an absolute path to it.

## See also

- [The Shim and Your PATH](/getting-started/shell-setup) — what the shim is, and why `PATH` order matters.
- [`dvm doctor`](/commands/doctor) — check that it worked.

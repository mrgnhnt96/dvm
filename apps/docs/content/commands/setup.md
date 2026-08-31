---
title: dvm setup
description: Install the shims and get the PATH line — printed for you to add, or written for you with --write-path-line.
---

```text
dvm setup [--dvm-path <path>] [--write-path-line | --remove-path-line]
```

Writes `~/.dvm/shims/dart` (`dart.bat` on Windows) and tells you the one line that puts the shims on your `PATH` — or adds it for you, with `--write-path-line`.

```sh
dvm setup
```

```text
Wrote /Users/you/.dvm/shims/dart
  -> /Users/you/.dvm/bin/dvm exec dart

Add this line to /Users/you/.zshrc (/bin/zsh):

  export PATH="/Users/you/.dvm/shims:$PATH"

It has to go ahead of anything else that puts a dart on PATH, and it only takes effect in shells started after you save the file.

Or let dvm add it for you: dvm setup --write-path-line
It backs /Users/you/.zshrc up before touching it, and dvm setup --remove-path-line takes the line back out.

Then check it with: dvm doctor
```

## Flags

| Flag | Effect |
| --- | --- |
| `--dvm-path <path>` | The dvm binary to bake into the shim. Defaults to the running one; needed when running from source. |
| `--write-path-line` | Add the PATH line to your shell startup file instead of just printing it. Backs the file up first, and leaves it alone when the line is already there. |
| `--remove-path-line` | Take that line back out, leaving the shims in place. A line you added by hand stays yours. |

## It prints the PATH line for you

It prints the exact line and names the file it belongs in, so the change to your login shell stays yours to make. See [The Shim and Your PATH](/getting-started/shell-setup) for which file each shell reads.

And when you would rather dvm made the edit, `--write-path-line` does it:

```sh
dvm setup --write-path-line
```

```text
Wrote /Users/you/.dvm/shims/dart
  -> /Users/you/.dvm/bin/dvm exec dart

Backed up /Users/you/.zshrc -> /Users/you/.zshrc.dvm-backup-20260829-154646
Added this line to /Users/you/.zshrc:

  export PATH="/Users/you/.dvm/shims:$PATH"

It takes effect in shells started after this. For the one you are in: source /Users/you/.zshrc
Undo it with: dvm setup --remove-path-line

Then check it with: dvm doctor
```

It copies the file to a timestamped backup first and writes the line between `# >>> dvm >>>` and `# <<< dvm <<<`, so a second run finds it and adds nothing — and so `--remove-path-line` knows which line is dvm's:

```sh
dvm setup --remove-path-line
```

```text
Backed up /Users/you/.zshrc -> /Users/you/.zshrc.dvm-backup-20260829-154647
Removed dvm's PATH line from /Users/you/.zshrc.
Shells started after this will no longer find the shims. The shims themselves are still in /Users/you/.dvm/shims.
```

A line you typed yourself is recognised too — different quoting, or `$HOME` in place of your home directory, still counts as already on `PATH` — and removal reports it and leaves it exactly as you wrote it.

## Where in the file it writes

`--write-path-line` **appends** its block to the end of the startup file. It does not try to find a good spot in the middle, and it does not reorder anything you wrote.

The end is a deliberately safe place to land, because a startup file is read top to bottom and a line like `export PATH=/a:/b:/c` — with no `$PATH` on the right-hand side — replaces `PATH` outright and discards everything set above it. Appending puts dvm's line after such an assignment rather than in front of it, where it would be silently erased.

That is a consequence of going last, not an understanding of your file. If another tool later rewrites its own absolute `PATH` assignment at the end of the file, it ends up below dvm's block and the shims stop winning. [The Shim and Your PATH](/getting-started/shell-setup) works through that case with a before and after.

It also writes to exactly one file — the one named for your `$SHELL`, which for bash is always `~/.bashrc`. If your shell reads something else, add the line there yourself.

## When it refuses to write

A shell function or alias named `dvm` is resolved before `PATH` is ever searched, so it beats the binary outright. Writing the `PATH` line in that state would look like it worked and change nothing, so `--write-path-line` declines and says why, leaving the file untouched:

```text
Wrote /Users/you/.dvm/shims/dart
  -> /Users/you/.dvm/bin/dvm exec dart

Not writing the PATH line: something in your startup files would beat it, or dvm could not read a file that might. A shell function or alias is resolved before PATH is ever searched, so the line would change nothing while looking like it worked.
Sort out the warnings below, then run this again.

WARNING: your shell defines its own `dvm`, which will win over the binary you just set up — a shell function or alias is resolved before PATH is ever searched.
  /Users/you/.zshrc:1: alias dvm='fvm dart'
Remove or comment out the line(s) above, then start a new shell.

Then check it with: dvm doctor
```

A startup file that exists but cannot be read counts the same way, because the file dvm could not open may be the one holding the definition. Clear the warning, start a new shell, and run it again.

## On Windows

PowerShell takes `PATH` from your user environment rather than from a startup file, so `dvm setup` hands you the call that sets it:

```text
Wrote C:\Users\you\.dvm\shims\dart.bat
  -> C:\Users\you\.dvm\bin\dvm.exe exec dart

Run this once in PowerShell:

  [Environment]::SetEnvironmentVariable('Path', 'C:\Users\you\.dvm\shims;' + [Environment]::GetEnvironmentVariable('Path', 'User'), 'User')

That edits your user PATH, so it survives a reboot. It has to go ahead of anything else that puts a dart on PATH, and it only takes effect in terminals opened after you run it.

For the terminal you are in right now:

  $env:Path = 'C:\Users\you\.dvm\shims;' + $env:Path

Then check it with: dvm doctor
```

That writes to the `User` scope, so it needs no elevation. Git Bash and MSYS set `$SHELL`, so dvm gives them the POSIX `export` line and the startup file that shell reads.

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

`--write-path-line` exits 1 for the same reason when it holds off: a function or alias named `dvm` beats `PATH` outright, so the line would look like it worked and change nothing. It says so, leaves the file untouched, and asks you to clear the warning and run it again. `--remove-path-line` exits **0** whether it removed dvm's block, found a line you wrote yourself, or found nothing to remove.

## Re-running it

Safe, and the right thing to do after moving or reinstalling the dvm binary — the shim contains an absolute path to it. `--write-path-line` is safe to repeat too: the second run finds the line already there and says so.

## See also

- [The Shim and Your PATH](/getting-started/shell-setup) — what the shim is, and why `PATH` order matters.
- [`dvm doctor`](/commands/doctor) — check that it worked.

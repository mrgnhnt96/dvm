# dvm architecture

The contract every part of the CLI is written against. Read this before touching
`packages/dvm`.

## What dvm is

A per-project Dart SDK version manager. Every SDK lives in one central cache; each
project pins a version in a committed `.dvmrc`; `dart` resolves to the pinned SDK.
It is to Dart what `fvm` is to Flutter.

## The shape, and why it is this one

Two forks define dvm, and the surrounding ecosystem has taken both of them the
other way. They are written down here because each is cheap to undo by accident,
and neither belongs on the front page.

**The selection is per project, and it is committed.** A version manager can
instead keep one active SDK per machine and switch it with a command — that is the
shape `cbracken/dvm` chose, and it is why `~/.dvm` was already occupied when we got
there (see On-disk layout). dvm makes the choice a property of the directory,
written to a `.dvmrc` that goes into the repository. Cloning a project is then
enough to get its SDK, two projects on different versions need no switch between
them, and an SDK change shows up in a diff where somebody can review it. The price
is that resolution runs on every single `dart` invocation, which is why rule 2's
walk is held to zero network I/O — see the resolution contract below, and do not
relax it.

**`dart` itself resolves, through a shim on PATH.** The alternative is to require
every call site to say `dvm dart …` or `dvm exec …`. dvm ships `exec` because CI
genuinely wants an explicit form, but the shim is the default, because the callers
that matter most — build scripts, test runners, and editors — spawn `dart` without
asking anyone first. Anything that weakens the shim silently moves those callers
back onto whichever `dart` happens to be first on PATH, which is the failure this
whole design exists to prevent. It is also why `doctor` checks PATH *order* and
shell functions that shadow `dart`, not merely that the shim file exists.

## On-disk layout

```
~/.dvm/
  versions/<version>/   extracted SDK — contains bin/, lib/, version
  shims/dart            + dart.bat on Windows
  config.json           { "global": "3.13.2", "aliases": { "work": "3.9.0" } }
  cache/                in-flight downloads; safe to delete at any time
```

Per project:

```
.dvmrc                  committed:  { "dart": "3.9.0" }
.dvm/dart_sdk           gitignored symlink -> ~/.dvm/versions/3.9.0, for IDEs
```

`~/.dvm` is also the home of the older `cbracken/dvm`, which stores SDKs in
`~/.dvm/darts/<version>` and keeps a `scripts/`, `environments/`, and a git
checkout alongside. dvm deliberately takes that directory over; see `migrate`.

## `.dvmrc` format

Canonically JSON so it can grow later:

```json
{ "dart": "3.9.0" }
```

A bare version string on a single line is ALSO accepted, for hand-editing, the way
`.nvmrc` works. `dvm use` always writes the JSON form. The value may be a concrete
version, an alias, or a channel name.

## Version resolution — the single most important contract

Used by `dvm exec`, `dvm dart`, and the PATH shim. In order, first match wins:

1. `DVM_DART_VERSION` environment variable — the CI / one-off escape hatch.
2. The nearest `.dvmrc`, walking up from the current directory to the filesystem root.
3. `global` in `~/.dvm/config.json`.
4. The next real `dart` on `PATH` that is not a dvm shim — so directories with no
   `.dvmrc` and no global keep working instead of breaking.
5. A clear, actionable error naming what to run.

**This path must perform ZERO network I/O and minimal file I/O.** Every single
`dart` invocation on the machine pays for it once the shim is installed. Channel
names are never re-resolved over the network here — see below.

`which`/`current` must report not just the resolved path but WHICH of these five
rules produced it. Debuggability is the point.

### Writes follow the same walk as reads

`dvm use` updates the `.dvmrc` that rule 2 would find — the nearest one walking up —
wherever it happens to live, and it uses `DvmrcStore.findNearest` to find it rather
than repeating the walk. One walk, so write and read cannot disagree. Run in a
subdirectory under a repository-root pin, `use` edits the root's file and says so,
naming the absolute path it changed.

Only when no `.dvmrc` exists anywhere up to the filesystem root does `use` create one,
in the working directory. A monorepo package that genuinely needs its own SDK asks for
that with `--here`, which creates a nested pin and reports which ancestor it now
shadows. The nesting is available, but never arrives by accident from the directory
someone happened to be standing in.

`.dvm/dart_sdk` and the `--gitignore` rule go beside the `.dvmrc`, not beside the user:
one pin owns exactly one symlink, so a later repin from anywhere in the tree updates the
link that exists instead of stranding one in a subdirectory. `doctor` resolves the
project the same way, as the parent of the `.dvmrc` it found.

## Aliases and channels

Aliases are user-defined names in `config.json` mapping to a concrete version.
`stable`, `beta`, and `dev` are channel names that resolve to whichever concrete
version was installed for that channel, recorded at install time. They are only
re-resolved against the network by an explicit `dvm install`/`dvm upgrade`, never
during resolution.

## Upstream SDK source

Dart SDKs come from the `dart-archive` Google Cloud Storage bucket. All of the
following is verified against the live service:

- **List releases in a channel**
  `GET https://storage.googleapis.com/storage/v1/b/dart-archive/o?delimiter=/&prefix=channels/<channel>/release/&fields=prefixes`
  Returns ~205 prefixes for stable. **177 are semver; 28 are legacy Dart 1 build
  numbers** (`29803`, `41096`, …) plus a `latest` entry. Filter to semver.
- **Resolve a channel to a version**
  `GET .../channels/<channel>/release/latest/VERSION` →
  `{"date": "...", "version": "3.13.2", "revision": "..."}`
- **Download**
  `.../channels/<channel>/release/<version>/sdk/dartsdk-<os>-<arch>-release.zip`
  `os` ∈ `macos | linux | windows`; `arch` ∈ `x64 | arm64`, plus `arm` and
  `riscv64` on linux only.
- **Verify** the sibling `.sha256sum`, whose body is `<hex> *<filename>`.

Channels are `stable`, `beta`, `dev`. A given version can exist in more than one
channel, so resolve channel→version first; for a bare version string, probe the
channels in order stable, beta, dev.

## Installing an SDK

Download → verify sha256 → extract into `~/.dvm/cache/<tmp>` → `rename()` into
`~/.dvm/versions/<version>`. The rename is what makes it atomic: an interrupted
install must never leave a half-extracted directory that later looks installed.

Extraction uses `package:archive`. **Its zip decoder carries unix permissions in
`ArchiveFile.mode` but does not apply them**, so without an explicit `chmod` pass
everything under `bin/` lands non-executable and the SDK is inert. Windows needs
no chmod.

## Running the pinned SDK

Dart has no `exec()`. Use:

```dart
Process.start(exe, args, mode: ProcessStartMode.inheritStdio)
```

then forward the child's exit code, and forward `SIGINT`/`SIGTERM` to the child so
Ctrl-C and interactive `dart run` behave. Getting this wrong is the likeliest
source of "dvm feels broken" reports.

## Shims

`~/.dvm/shims/dart` is a two-line POSIX shell script:

```sh
#!/bin/sh
exec /path/to/dvm exec dart "$@"
```

`exec` replaces the process, so the only overhead is shell startup plus dvm's own
AOT start. Windows gets a `.bat` equivalent. `~/.dvm/shims` has to be on PATH ahead
of everything else, and `setup` prints the line that puts it there.

`setup --write-path-line` adds that line to the startup file instead of printing it.
Printing stays the default: a version manager that rewrites `.zshrc` unasked is one
people stop trusting, and a wrong line breaks the login shell they would need in
order to fix it. The flag is the opt-in for a user who would rather not paste.

Four properties make the edit safe to hand out, and `PathLineEditor`
(`lib/src/core/path_line.dart`) is where they live:

- **A timestamped backup** beside the file (`.zshrc.dvm-backup-20260829-141530`),
  named in the output. The timestamp rather than a fixed `.bak` means a second edit
  cannot overwrite the copy taken before the first one.
- **Idempotent.** A line already putting the shims directory on PATH — dvm's own, or
  a hand-typed one differing in quoting, spacing, or `$HOME` for the home directory
  — is recognised and left alone. A doubled PATH entry is the likeliest bug here and
  the hardest to notice.
- **It declines when the edit would not help.** A shadowing shell function or alias
  beats PATH outright, and an unreadable startup file may be the one holding it, so
  in either case the line is not written and `setup` exits 1 — the same code, and the
  same reason, as the existing conflict contract.
- **Reversible.** Everything written goes between `# >>> dvm >>>` and `# <<< dvm <<<`,
  which is what lets `setup --remove-path-line` find it again. Removal takes the block
  and nothing else: a PATH line with no markers around it is reported and left, since
  the one thing dvm knows about it is that it did not write it. Removal exits 0 whether
  it removed something or found nothing.

PowerShell takes PATH from the user's environment rather than a startup file, so both
flags decline there and print the `SetEnvironmentVariable` call instead. Windows users
in Git Bash or MSYS set `$SHELL`, so they get the POSIX path and the flags work. A
container with neither `$HOME` nor `$USERPROFILE` set has no file to name, so the flags
print the line and exit 1 rather than guess at a path.

## Code conventions

- Plain `package:args` `CommandRunner`. **No riverpod, no build_runner, no
  codegen.** The dormant competitor `dvmx` is built on those and it is why
  contributing to it is unpleasant.
- Constructor injection. Every command takes its collaborators as constructor
  parameters — no service locators, no globals.
- All filesystem access goes through `package:file`'s `FileSystem`, never
  `dart:io` directly, so commands are testable against `MemoryFileSystem`.
  **No test may touch the real `~/.dvm`.**
- `dart analyze` must be clean under `packages/dvm/analysis_options.yaml`, which
  turns on `strict-casts`, `strict-inference`, and `strict-raw-types`.
- Comments explain *why*, not *what*. Match the density of the file you are in.

## Saying what it did — `-v` / `DVM_VERBOSE`

dvm is silent by design, and that silence has a cost: when it misbehaves there is
nothing to read but the source. The verbose channel is the way out. It is off by
default and turned on by either `dvm -v <command>` — a flag on the `CommandRunner`,
so every subcommand inherits it — or `DVM_VERBOSE` in the environment, set to any
non-empty value other than `0`/`false`. They are an OR, not a precedence order.

The environment variable is not a convenience. Anything reaching dvm **through the
shim** never sees a dvm command line at all: `~/.dvm/shims/dart` is
`exec dvm exec dart "$@"`, so a CI job that wants its log to say which SDK actually
ran has no flag to pass. That case is why the variable exists.

`VerboseLog` (`lib/src/core/verbose.dart`) is an ordinary injected collaborator on
`DvmContext`, constructed in `lib/dvm.dart` beside `out` and `err` and handed to
everything below. Deliberately **not** a global logger or a service locator — this
file rules those out everywhere else and the exception would not stay one. A
collaborator built outside the composition root gets `VerboseLog.disabled`, so a
test that does not care never has to say so.

Three properties are load-bearing:

- **It writes to stderr, always.** `dvm which` and `dvm list` are read by scripts,
  and `dvm exec` hands the child dvm's own stdio — a tool parsing `dart --version`
  must not receive dvm's chatter on stdout. The non-verbose stdout of every command
  is byte-for-byte what it was, and a test asserts exactly that.
- **It costs nothing when off.** Messages are callbacks, not strings: resolution
  runs on every `dart` invocation on the machine once the shim is installed, and a
  silent run must not build text it discards. `VerboseLog.stopwatch()` returns null
  while the log is off, for the same reason.
- **It decides nothing.** Every line describes a choice already made. Resolution
  order, exit codes and output are unchanged by turning it on.

Lines are prefixed `[dvm <area>]` — `resolve`, `exec`, `net`, `fs`, `proc`,
`install`, `cli` — so a log can be grepped down to one concern.

## Printing a path

A path **under the working directory** prints RELATIVE to it, with no `./` in
front: `.dvmrc`, `.dvm/dart_sdk`, `packages/api/.dvmrc`. **Everything else
prints absolute.** A parent directory does not become `../..`, and a path under
`$HOME` does not become `~/…` — both were considered and declined. The working
directory itself is not under itself, so it keeps its absolute path: `Pinned
Dart 3.13.2 for .` names the project worse than its own path does.

The point is signal. In `dvm use` the thing worth reading is WHICH file — and in
a repository the user is standing in, everything before it is the directory they
already know they are in. Note what the rule gives for free: the SDK store
(`~/.dvm/versions/<v>`) is never inside a project, so it stays absolute with no
special case. Do not write one.

`DvmContext.display` is the only place this happens, and it is deliberately one
function rather than `p.relative` at each call site — that is how the carve-out
below gets forgotten at the thirty-fourth. It is purely lexical and touches no
filesystem. A working directory that is the filesystem ROOT formats nothing:
everything is under `/`, and stripping that one character removes the only thing
the path was stating for certain.

Three things must NOT go through it:

- **`dvm which`'s machine-readable paths.** The `--path` flag's entire output,
  and the first line of the default output, which is what `dvm which | head -1`
  takes. A relative path there resolves against the CALLER's working directory,
  which is not necessarily dvm's, so a consumer handed `.dvm/dart_sdk/bin/dart`
  silently points at nothing. `which`'s `SDK:` line and the rest of its prose
  follow the normal rule. Tests pin both.
- **Anything dvm WRITES to a file.** `.dvmrc` contents, the `.dvm/dart_sdk`
  symlink target, and the PATH line `setup --write-path-line` adds are all
  absolute and stay absolute. This is about what is PRINTED and nothing else.
  The PowerShell `$env:Path` snippet counts here too: it is a PATH value the
  user pastes, not prose about a file.
- **The verbose channel.** `-v` output is a diagnostic read when something is
  already wrong, and an unambiguous path is worth more there than a short one.

## Command surface

| Command | Behavior |
|---|---|
| `install <version\|channel\|alias>` | download, verify, extract, atomically install |
| `use <version>` | update the governing `.dvmrc` + its `.dvm/dart_sdk`; auto-install if absent; `--here` pins this directory instead; `--global` sets default |
| `list` / `ls` | installed versions, marking global and current-project |
| `list-remote` | available releases from the archive |
| `remove <version>` | delete from cache; refuse if global or an alias target unless `--force` |
| `alias <name> <version>` / `alias list` / `unalias <name>` | named versions |
| `global <version>` | the default when no `.dvmrc` applies |
| `which` / `current` | resolved SDK path AND which resolution rule chose it |
| `dart <args…>` | forward to the resolved SDK's `dart` |
| `exec <cmd> <args…>` | run any command with the resolved SDK first on PATH |
| `setup` | create shims, print the PATH line, detect a shadowing shell function; `--write-path-line` writes the line to the startup file, `--remove-path-line` takes it back out |
| `migrate` | import cbracken dvm's SDKs, then offer to remove its files |
| `doctor` | PATH order, shim health, stale symlinks, shadowing function, config validity |
| `update` | replace the running dvm binary with the newest release; `--check` only reports |

## Distribution

The shipped artifact is an **AOT-compiled binary** (`dart compile exe`) attached to a
GitHub Release. A version manager cannot require the language it manages in order to
install itself, so `dart pub global activate` cannot be the channel at all — it would
mean needing Dart to install the thing that installs Dart.

There is **no Homebrew tap**. An install script plus a self-updater costs no second
repository, no cross-repo credential (`GITHUB_TOKEN` only grants access to the repo a
workflow runs in), and no formula-bumping job, and it reaches Linux users that a tap
largely does not.

**Release assets** are named `dvm-<os>-<arch>.zip`, each containing a bare `dvm`
binary (`dvm.exe` on Windows), for: `linux-x64`, `linux-arm64`, `macos-x64`,
`macos-arm64`, `windows-x64`. This naming is a CONTRACT: `install.sh` and the
`dvm update` command both construct these filenames, so changing it breaks every
installed copy's ability to update itself.

**Installing** is `curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh`,
linked from the README. The script detects os/arch, downloads the matching asset from
the latest release, verifies its checksum, and installs the binary to `~/.dvm/bin/dvm`.

**Updating** is `dvm update`, which does the same thing from inside the CLI. The
version it compares against is `kVersion` in a generated `lib/src/gen/version.dart`,
stamped at build time. Ordinary commands also run a check that prints a one-line notice
when a newer release exists; it is skipped when running from source rather than a
compiled binary, and suppressed by `--no-version-check`.

Do **not** resolve the latest release through GitHub's `/releases/latest` endpoint.
Scan `/releases` for the newest non-draft, non-prerelease entry that actually carries
the expected asset — a repo that later publishes per-package releases will otherwise
resolve "latest" to a release with no CLI binary in it.

Replacing the running binary works on POSIX because `rename` over a running executable
keeps the inode alive, so temp-file-then-rename is safe. Windows cannot replace a
running `.exe`; there the current binary must be renamed aside first, then the new one
written in its place.

dvm is **not published on pub.dev**, and there is no second channel of any kind. GitHub
Releases plus `install.sh` plus `dvm update` is the whole distribution story. `dart pub
global activate` is not offered even as a convenience for people who already have Dart —
a version manager that can be installed two ways has two upgrade paths to keep honest and
two ways for `dvm update` to be wrong about what is installed.

The package therefore declares `publish_to: none`, so an accidental `dart pub publish` is
refused by the tooling rather than by somebody remembering. It also means the package
directory does not need the `README.md`, `CHANGELOG.md` and `LICENSE` that pub scores; the
repository root carries those for humans.

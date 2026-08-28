# dvm architecture

The contract every part of the CLI is written against. Read this before touching
`packages/dvm`.

## What dvm is

A per-project Dart SDK version manager. Every SDK lives in one central cache; each
project pins a version in a committed `.dvmrc`; `dart` resolves to the pinned SDK.
It is to Dart what `fvm` is to Flutter.

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
AOT start. Windows gets a `.bat` equivalent. The user puts `~/.dvm/shims` on PATH
ahead of everything else.

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

## Command surface

| Command | Behavior |
|---|---|
| `install <version\|channel\|alias>` | download, verify, extract, atomically install |
| `use <version>` | write `.dvmrc` + `.dvm/dart_sdk`; auto-install if absent; `--global` sets default |
| `list` / `ls` | installed versions, marking global and current-project |
| `list-remote` | available releases from the archive |
| `remove <version>` | delete from cache; refuse if global or an alias target unless `--force` |
| `alias <name> <version>` / `alias list` / `unalias <name>` | named versions |
| `global <version>` | the default when no `.dvmrc` applies |
| `which` / `current` | resolved SDK path AND which resolution rule chose it |
| `dart <args…>` | forward to the resolved SDK's `dart` |
| `exec <cmd> <args…>` | run any command with the resolved SDK first on PATH |
| `setup` | create shims, print the PATH line, detect a shadowing shell function |
| `migrate` | import cbracken dvm's SDKs, then offer to remove its files |
| `doctor` | PATH order, shim health, stale symlinks, shadowing function, config validity |
| `update` | replace the running dvm binary with the newest release; `--check` only reports |

## Distribution

The shipped artifact is an **AOT-compiled binary** (`dart compile exe`) attached to a
GitHub Release. A version manager cannot require the language it manages in order to
install itself, so `dart pub global activate` cannot be the primary channel — it would
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

pub.dev remains a SECONDARY convenience for people who already have Dart: package
`dvm_cli`, executable `dvm` (the short name is squatted by a nine-year-old Dart 1 alpha).

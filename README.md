# dvm

A per-project Dart SDK version manager.

`dvm` keeps every Dart SDK you use in one central cache, lets you pin a version
per project with a committed `.dvmrc`, and makes `dart` resolve to the right SDK
automatically — the same way `fvm` does for Flutter.

Full documentation: <https://dvm.mrgnhnt.com>

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh
```

dvm ships as a compiled binary, so it is ready on a machine that has never had
Dart on it — it is the thing that installs Dart. From there,
[`dvm setup`](https://dvm.mrgnhnt.com/getting-started/shell-setup) writes the
`dart` shim and hands you the one line that puts it on your `PATH`.

Note that plain `dvm setup` **prints** that line rather than adding it — it does
not edit your shell startup file. To have dvm add it for you:

```sh
dvm setup --write-path-line
```

Either way `~/.dvm/shims` has to come *before* anything else that provides a
`dart` — a Flutter SDK, `fvm`, asdf, a Homebrew `dart`. If `which dart` is not
the shim afterwards, `dvm doctor` names the entry that is winning. See
[The Shim and Your PATH](https://dvm.mrgnhnt.com/getting-started/shell-setup)
for the details, including the `export PATH=...` line that discards everything
above it.

### The alpha channel

To install the latest `main` instead of the newest release:

```sh
curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh -s -- --alpha
```

The `-s --` is what tells `sh` that `--alpha` belongs to the script and not to
`sh` itself; without it the option is silently claimed by the wrong program.

This installs the rolling `alpha` prerelease, which is rebuilt and republished
from `main` on every push. It is unreleased code that nobody chose to publish, so
it is the right thing to run when you need a fix that has landed but not shipped,
and the wrong thing to run otherwise. An alpha reports itself with a build-tag
suffix — `dvm --version` prints something like `dvm 0.2.0+alpha.g1a2b3c4` — so
you can tell later what you are running.

Once you are on an alpha you do not need the installer again. `dvm update --alpha`
moves you to the newest one, and `dvm update --stable` takes you back to the newest
release. Both flags are per-invocation and remember nothing: a bare `dvm update`
still means "the newest release", and it will not silently swap an alpha for a
release that is not actually ahead of it — it says so and names both flags instead.
A plain install can never resolve to an alpha, with or without `--alpha`.

## Pin a project

[`dvm install`](https://dvm.mrgnhnt.com/commands/install) puts an SDK in the
cache, and [`dvm use`](https://dvm.mrgnhnt.com/commands/use) pins this project to
it and writes the `.dvmrc` you commit.

In `~/code/api`:

```console
$ dvm install 3.13.2
Downloading Dart 3.13.2 (macos-arm64, stable)
  dartsdk-macos-arm64-release.zip  0%  (0.0 / 215.4 MB)
…
  dartsdk-macos-arm64-release.zip  100%  (215.4 / 215.4 MB)
Installed Dart 3.13.2 to /Users/you/.dvm/versions/3.13.2
$ dvm use 3.13.2
Pinned Dart 3.13.2 for /Users/you/code/api.
  /Users/you/code/api/.dvmrc -> commit this
  /Users/you/code/api/.dvm/dart_sdk -> /Users/you/.dvm/versions/3.13.2 (for your IDE; do not commit it)
`.dvm/` is not ignored yet by /Users/you/code/api/.gitignore. Add it with: dvm use 3.13.2 --gitignore
$ dart --version
Dart SDK version: 3.13.2 (stable) (Tue Aug 25 01:01:12 2026 -0700) on "macos_arm64"
```

## The same command, two answers

Same shell, same `dart`. The directory is the only thing that changed.

In `~/code/api`:

```console
$ dart --version
Dart SDK version: 3.13.2 (stable) (Tue Aug 25 01:01:12 2026 -0700) on "macos_arm64"
```

In `~/code/legacy`:

```console
$ dart --version
Dart SDK version: 3.5.4 (stable) (Wed Oct 16 16:18:51 2024 +0000) on "macos_arm64"
```

"Which Dart am I running?" is a property of the directory you are standing in,
and [`dvm which`](https://dvm.mrgnhnt.com/commands/which) shows the whole answer
— the SDK, the version, and which of the
[five rules](https://dvm.mrgnhnt.com/versions/resolution-order) chose it.

In `~/code/legacy`:

```console
$ dvm which
/Users/you/.dvm/versions/3.5.4/bin/dart
Dart 3.5.4
Chosen by rule 2 of 5: pinned by /Users/you/code/legacy/.dvmrc.
SDK: /Users/you/.dvm/versions/3.5.4
```

## How it works

- **One cache.** Every SDK lives in `~/.dvm/versions/<version>`, extracted once
  and shared by every project that pins it.
- **A committed pin.** [`.dvmrc`](https://dvm.mrgnhnt.com/versions/dvmrc) is a
  small JSON file at the root of a project, and it is the one dvm file you
  commit. Anyone who clones the repository and has dvm gets the same SDK. It can
  name a concrete version, a channel, or an
  [alias](https://dvm.mrgnhnt.com/versions/aliases) such as `work`.
- **A shim on `PATH`.**
  [`~/.dvm/shims/dart`](https://dvm.mrgnhnt.com/getting-started/shell-setup) is a
  two-line shell script that hands off to dvm, so plain `dart` respects the pin —
  including when a build script or test runner spawns it for you.
- **A resolution order you can inspect.**
  [Five rules](https://dvm.mrgnhnt.com/versions/resolution-order), first match
  wins, and `dvm which` tells you which one answered. Resolution reads two small
  files, so `dart` stays fast and works offline.
- **A fallback you set once.** A
  [global default](https://dvm.mrgnhnt.com/commands/global) covers directories
  that pin nothing, while a project with a `.dvmrc` uses its own SDK.

On CI, [`dvm exec`](https://dvm.mrgnhnt.com/guides/ci) runs the same resolution
and hands the command straight to the pinned SDK, so a build machine needs the dvm
binary and the repository and nothing else.

## Where to go next

- [Installation](https://dvm.mrgnhnt.com/getting-started/installation) — one
  `curl` command, on a machine that has never had Dart on it.
- [Quick Start](https://dvm.mrgnhnt.com/getting-started/quick-start) — install an
  SDK, pin a project, and watch `dart` follow the pin.
- [Resolution Order](https://dvm.mrgnhnt.com/versions/resolution-order) — the
  five rules that decide which SDK you get. Read this one first when something is
  surprising.

## License

MIT

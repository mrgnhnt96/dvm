---
title: dvm
description: A per-project Dart SDK version manager — keep every SDK in one cache, pin a version per project with a committed .dvmrc, and make `dart` resolve to the right one automatically.
---

Install it with one command, on a machine that has never had Dart on it:

```sh
curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh
```

## From nothing to a pinned SDK

dvm arrives as a compiled binary, so it is ready before any SDK exists. [`dvm setup`](/commands/setup) then writes the `dart` shim and hands you the one line that puts it on `PATH`.

<Terminal cwd="~" caption="Two commands, and dart on this machine belongs to dvm.">

```text
$ curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh
Looking up the newest dvm release...
Downloading dvm-macos-arm64.zip (v0.2.0)...

dvm v0.2.0 is installed at /Users/you/.dvm/bin/dvm
…
$ dvm setup
Wrote /Users/you/.dvm/shims/dart
  -> /Users/you/.dvm/bin/dvm exec dart

Add this line to /Users/you/.zshrc (/bin/zsh):

  export PATH="/Users/you/.dvm/shims:$PATH"

It has to go ahead of anything else that puts a dart on PATH, and it only takes effect in shells started after you save the file.

Then check it with: dvm doctor
```

</Terminal>

From there, [`dvm install`](/commands/install) puts an SDK in the cache and [`dvm use`](/commands/use) pins this project to it.

<Terminal cwd="~/work/api" caption="dvm use writes the .dvmrc you commit, and dart follows it from the next keystroke on.">

```text
$ dvm install 3.13.2
Downloading Dart 3.13.2 (macos-arm64, stable)
  dartsdk-macos-arm64-release.zip  0%  (0.0 / 215.4 MB)
…
  dartsdk-macos-arm64-release.zip  100%  (215.4 / 215.4 MB)
Installed Dart 3.13.2 to /Users/you/.dvm/versions/3.13.2
$ dvm use 3.13.2
Pinned Dart 3.13.2 for /Users/you/work/api.
  /Users/you/work/api/.dvmrc -> commit this
  /Users/you/work/api/.dvm/dart_sdk -> /Users/you/.dvm/versions/3.13.2 (for your IDE; do not commit it)
`.dvm/` is not ignored yet by /Users/you/work/api/.gitignore. Add it with: dvm use 3.13.2 --gitignore
$ dart --version
Dart SDK version: 3.13.2 (stable) (Tue Aug 25 01:01:12 2026 -0700) on "macos_arm64"
```

</Terminal>

## The same command, two answers

Here is the whole idea in one screen. Same shell, same `dart` — the directory is the only thing that changed.

<Terminal cwd="~/work/api">

```text
$ dart --version
Dart SDK version: 3.13.2 (stable) (Tue Aug 25 01:01:12 2026 -0700) on "macos_arm64"
```

</Terminal>

<Terminal cwd="~/work/legacy">

```text
$ dart --version
Dart SDK version: 3.5.4 (stable) (Wed Oct 16 16:18:51 2024 +0000) on "macos_arm64"
```

</Terminal>

"Which Dart am I running?" is now a property of the directory you are standing in, and [`dvm which`](/commands/which) shows the whole answer: the SDK, the version, and which of the [five rules](/versions/resolution-order) chose it.

<Terminal cwd="~/work/legacy" caption="Rule 2 is the committed pin. dvm names the rule and the file, so the answer is always checkable.">

```text
$ dvm which
/Users/you/.dvm/versions/3.5.4/bin/dart
Dart 3.5.4
Chosen by rule 2 of 5: pinned by /Users/you/work/legacy/.dvmrc.
SDK: /Users/you/.dvm/versions/3.5.4
```

</Terminal>

Every tool that spawns `dart` behind your back goes through the same [shim](/getting-started/shell-setup), so build scripts and test runners land on the SDK the project asked for. Editors that want an SDK directory instead get one: `dvm use` keeps [`.dvm/dart_sdk`](/versions/dvmrc#the-other-file-dvmdart_sdk) pointed at the same version.

## In the course of a week

**Cloning a project that already pins its SDK.** The [`.dvmrc`](/versions/dvmrc) is in the repository, so the right SDK is chosen the moment you `cd` in.

<Terminal cwd="~/work/cloned" caption="The pin arrived with the clone, and dart followed it.">

```text
$ cat .dvmrc
{
  "dart": "3.13.2"
}
$ dart --version
Dart SDK version: 3.13.2 (stable) (Tue Aug 25 01:01:12 2026 -0700) on "macos_arm64"
```

</Terminal>

**Seeing what is on the machine.** [`dvm list`](/commands/list) marks what this directory resolves to with a `*`, and tags each SDK with everything that points at it.

<Terminal cwd="~/work/legacy" caption="One cache, shared by every project. Two projects on the same version cost one download.">

```text
$ dvm list
Installed Dart SDKs in /Users/you/.dvm/versions:

  3.13.2  global default, channel: stable
* 3.5.4   this project, alias: work

* = what /Users/you/work/legacy resolves to right now: pinned by /Users/you/work/legacy/.dvmrc via "work".
```

</Terminal>

**Giving a version a name you will remember.** An [alias](/versions/aliases) lets a `.dvmrc` say `work` where a team has settled on one SDK, and dvm reports the hop it made.

<Terminal cwd="~/work/legacy" caption="dvm which follows the alias and says where the name is defined.">

```text
$ dvm alias work 3.5.4
"work" now means 3.5.4.
  work -> 3.5.4
$ dvm which
/Users/you/.dvm/versions/3.5.4/bin/dart
Dart 3.5.4
Chosen by rule 2 of 5: pinned by /Users/you/work/legacy/.dvmrc.
  It says "work", an alias for 3.5.4 in /Users/you/.dvm/config.json.
SDK: /Users/you/.dvm/versions/3.5.4
```

</Terminal>

**Building it on CI.** A build machine writes every command itself, so [`dvm exec`](/commands/exec) is all it needs: it runs the same resolution and hands the command straight to the pinned SDK. See [Using dvm in CI](/guides/ci).

<Terminal cwd="~/work/api" caption="The build tests against the SDK the repository pins.">

```text
$ dvm exec dart --version
Dart SDK version: 3.13.2 (stable) (Tue Aug 25 01:01:12 2026 -0700) on "macos_arm64"
```

</Terminal>

## Start here

<CardGrid columns="3">

<Card title="Installation" href="/getting-started/installation" icon="rocket">

One `curl` command, on a machine that has never had Dart on it.

</Card>

<Card title="Quick Start" href="/getting-started/quick-start" icon="pin">

Install an SDK, pin a project, and watch `dart` follow the pin.

</Card>

<Card title="Resolution Order" href="/versions/resolution-order" icon="terminal">

The five rules that decide which SDK you get. Read this one first when something is wrong.

</Card>

</CardGrid>

## How the pieces fit

- **One cache.** Every SDK lives in `~/.dvm/versions/<version>`, extracted once and shared by every project that pins it.
- **A committed pin.** [`.dvmrc`](/versions/dvmrc) is a small JSON file at the root of a project, and it is the one dvm file you commit. Anyone who clones the repository and has dvm gets the same SDK.
- **A shim on PATH.** [`~/.dvm/shims/dart`](/getting-started/shell-setup) is a two-line shell script that hands off to dvm. It is what makes plain `dart` respect the pin.
- **A resolution order you can inspect.** Five rules, first match wins, and [`dvm which`](/commands/which) tells you which one answered. See [Resolution Order](/versions/resolution-order).
- **A fallback you set once.** A [global default](/commands/global) covers directories that pin nothing, while a project with a `.dvmrc` uses its own SDK.
- **A file read per invocation.** Resolution reads two small files and stats a directory, so `dart` stays fast, works offline, and works behind a firewall.
- **One way forward.** [The install script](/getting-started/installation) puts dvm on your machine and [`dvm update`](/commands/update) keeps it current — see [Updating dvm](/guides/updating-dvm).

## Everything else

<SectionCards />

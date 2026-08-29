---
title: dvm
description: A per-project Dart SDK version manager — keep every SDK in one cache, pin a version per project with a committed .dvmrc, and make `dart` resolve to the right one automatically.
---

`dvm` keeps every Dart SDK you use in one central cache, lets a project pin the version it wants in a committed `.dvmrc`, and makes the plain `dart` command resolve to that version — the same way `fvm` does for Flutter, and `nvm` does for Node.

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

## The whole thing in five commands

```sh
curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh
dvm setup               # write the dart shim, print the PATH line to add

dvm install 3.13.2      # download into ~/.dvm/versions
dvm use 3.13.2          # pin this project; writes .dvmrc
dart --version          # 3.13.2, here and nowhere else
```

`dvm use` writes a `.dvmrc` you commit. Anyone who clones the repo and has dvm installed gets the same SDK, and `dart` in that directory means that SDK — without them typing a dvm command at all.

## What it is made of

- **One cache.** Every SDK lives in `~/.dvm/versions/<version>`, extracted once and shared by every project that pins it. Two projects on the same version cost one download.
- **A committed pin.** [`.dvmrc`](/versions/dvmrc) is a two-line JSON file at the root of a project. It is the only dvm file you commit.
- **A shim on PATH.** [`~/.dvm/shims/dart`](/getting-started/shell-setup) is a two-line shell script that hands off to dvm. It is what makes plain `dart` — and every tool that spawns `dart` behind your back — respect the pin.
- **A resolution order you can inspect.** Five rules, first match wins, and [`dvm which`](/commands/which) tells you which one answered. See [Resolution Order](/versions/resolution-order).

## One machine, several projects

dvm is for a machine with more than one project on it. One repository needs the SDK it was built against; another has already moved on; a third pins an old one because a dependency has not caught up.

dvm makes "which Dart am I running?" a property of the directory you are standing in. `cd` into a project and `dart` is that project's SDK; `cd` into the next one and `dart` is that project's SDK. Your shell profile stays out of it.

## How it stays out of your way

- **One way in, one way forward.** [An install script](/getting-started/installation) puts dvm on your machine and [`dvm update`](/commands/update) keeps it current — see [Updating dvm](/guides/updating-dvm).
- **A file read per invocation.** Resolution reads two small files and stats a directory, so `dart` stays fast, works offline, and works behind a firewall — see [Resolution Order](/versions/resolution-order).
- **A fallback you set once.** A [global default](/commands/global) covers directories that pin nothing, while a project with a `.dvmrc` uses its own SDK.

## Everything else

<SectionCards />

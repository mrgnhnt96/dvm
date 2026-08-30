---
title: Quick Start
description: Install a Dart SDK, pin a project to it, and see plain `dart` follow the pin.
---

This assumes dvm is [installed](/getting-started/installation) and on your `PATH`. It takes about two minutes, most of which is one SDK download.

## 1. Install a Dart SDK

```sh
dvm install 3.13.2
```

```text
Installed Dart 3.13.2 to /Users/you/.dvm/versions/3.13.2
```

You can name a channel instead of a version, and dvm asks the archive what it currently means:

```sh
dvm install stable
```

The version that resolved to is recorded in `~/.dvm/config.json`, which is what lets you later pin `stable` without dvm needing the network. See [Aliases and Channels](/versions/aliases).

## 2. Set up the shim

You only ever do this once per machine:

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

Add that line, open a new shell, and confirm:

```sh
dvm doctor
```

[The shim page](/getting-started/shell-setup) explains what that file is and why its position on `PATH` matters.

## 3. Pin a project

```sh
cd ~/code/my-project
dvm use 3.13.2
```

```text
Pinned Dart 3.13.2 for /Users/you/code/my-project.
  /Users/you/code/my-project/.dvmrc -> commit this
  /Users/you/code/my-project/.dvm/dart_sdk -> /Users/you/.dvm/versions/3.13.2 (for your IDE; do not commit it)
`.dvm/` is not ignored yet by /Users/you/code/my-project/.gitignore. Add it with: dvm use 3.13.2 --gitignore
```

Two files were written, and the difference between them matters:

- **`.dvmrc`** is the pin. It is two lines of JSON and you **commit it**. It is what makes the pin apply to everyone who clones the repository.
- **`.dvm/dart_sdk`** is a link into your own `~/.dvm`, for IDEs that want an SDK path. It is machine-local and you **do not commit it**. `dvm use --gitignore` adds the rule for you.

`dvm use` installs the version first if you do not have it yet, so one command covers both. It also writes both files into the directory that holds the pin: run it deeper in a project that already has a `.dvmrc` above you and it updates that one, naming the file it changed. [`dvm use`](/commands/use) has the detail.

## 4. Watch `dart` follow the pin

```sh
dart --version
# Dart SDK version: 3.13.2 (stable) ...

cd ..
dart --version
# whatever applies out here — a different pin, your global default, or the system Dart
```

The `dart` on your `PATH` is dvm's shim, and it resolves per directory on every invocation — so both answers are current, and you switched nothing.

## 5. Ask why, whenever you need to

```sh
dvm which
```

```text
/Users/you/.dvm/versions/3.13.2/bin/dart
Dart 3.13.2
Chosen by rule 2 of 5: pinned by /Users/you/code/my-project/.dvmrc.
SDK: /Users/you/.dvm/versions/3.13.2
```

That second-to-last line is the one to remember. dvm has [exactly five resolution rules](/versions/resolution-order), and `dvm which` always names the one that answered. Whenever you want to know why you got the SDK you got, this is the first command to run.

## Where to go next

<CardGrid columns="2">

<Card title="Resolution Order" href="/versions/resolution-order" icon="pin">

The five rules, in order. The page to read when you want to know why dvm picked the SDK it did.

</Card>

<Card title="The .dvmrc File" href="/versions/dvmrc" icon="pin">

What you just committed, its format, and what a pin is allowed to contain.

</Card>

<Card title="Aliases and Channels" href="/versions/aliases" icon="terminal">

Give a version a name, and understand what `stable` means when you are offline.

</Card>

<Card title="Using dvm in CI" href="/guides/ci" icon="book">

Get the same SDK on a build machine, without a shim or a shell profile.

</Card>

</CardGrid>

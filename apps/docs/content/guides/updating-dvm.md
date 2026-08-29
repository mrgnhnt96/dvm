---
title: Updating dvm
description: How a new dvm reaches your machine, why there is no Homebrew tap, and how to turn the update notice off.
---

dvm updates itself. There are two paths to a newer version and they do the same work.

## The two ways

```sh
dvm update
```

from inside the CLI, or

```sh
curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh
```

which is the same script that installed it in the first place. Both find the newest release, download the asset for your platform, verify its checksum, and put the binary in place atomically. Use whichever you have in front of you.

## What ships

The artifact is an **AOT-compiled binary** — `dart compile exe` — attached to a GitHub Release. That is not a packaging preference; it is the constraint the whole distribution story is built around. A Dart version manager cannot require the language it manages in order to install itself: any channel that shipped source and compiled it on your machine would mean needing Dart to install the thing that installs Dart.

Assets are named:

```text
dvm-linux-x64.zip
dvm-linux-arm64.zip
dvm-macos-x64.zip
dvm-macos-arm64.zip
dvm-windows-x64.zip
```

Each contains a bare `dvm` (`dvm.exe` on Windows), and each has a `.sha256` published beside it.

<Callout type="info">
Those five names are a **contract**. `install.sh` and `dvm update` both construct them, so changing the naming would break every installed copy's ability to update itself. It is spelled identically in the install script, the release packaging script, and the updater.
</Callout>

## Why there is no Homebrew tap

A tap costs a second repository, a cross-repo credential (the `GITHUB_TOKEN` a workflow gets only grants access to the repo it runs in), and a formula-bumping job on every release. In exchange it reaches macOS users who already had another way to install, and Linux users hardly at all.

An install script plus a self-updater costs none of that and covers everyone. So: no tap, and none planned.

## How "latest" is decided

dvm scans `/releases` for the newest non-draft, non-prerelease entry that **actually carries the asset it needs**. It deliberately does not use GitHub's `/releases/latest` endpoint: a repository that later publishes per-package releases would otherwise resolve "latest" to a release with no CLI binary in it, and the failure would look like a broken download rather than a wrong lookup.

## Replacing a running binary

On POSIX, `rename` over a running executable keeps the old inode alive — the process you are in keeps running from the file that is no longer at that path — so writing a temp file and renaming it into place is safe, and never leaves a truncated `dvm` at the real path if the copy is interrupted.

Windows cannot replace a running `.exe` at all, so there the current binary is renamed aside first and the new one written in its place.

## The update notice

Ordinary commands start a check for a newer release before doing their work and report it afterwards, as one line:

```text
A newer dvm is available: 0.1.0 -> 0.2.0. Run: dvm update
```

Three things about it:

- It goes to **stderr**, so it cannot contaminate `dvm which --path` or `dvm list` for a script reading them.
- It is skipped when dvm is running from source rather than as a compiled binary.
- It is skipped during `dvm update`, which says all of this itself at more length.

Suppress it for one invocation:

```sh
dvm --no-version-check list
```

Anything scripted against dvm wants its output to be exactly what it asked for, which is what that flag is for. In CI, where the machine cannot act on the notice anyway, it is worth setting — see [Using dvm in CI](/guides/ci).

## Pinning the installer

```sh
curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | DVM_VERSION=0.2.0 sh
```

Useful in a Dockerfile, where an unpinned install script means your image changes underneath you.

## See also

- [`dvm update`](/commands/update) — the command reference.
- [Installation](/getting-started/installation) — the install script and its environment variables.

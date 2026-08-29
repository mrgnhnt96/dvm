---
title: Updating dvm
description: How a new dvm reaches your machine, what ships in a release, and how to turn the update notice off.
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

The artifact is an **AOT-compiled binary** — `dart compile exe` — attached to a GitHub Release. A compiled binary runs on a machine with nothing installed, which is exactly the machine a Dart version manager arrives on: the language it manages is the thing that is missing. That property is what the whole distribution story is built on.

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
Those five names are a **contract**. `install.sh` and `dvm update` both construct them, which is what lets an installed copy find its own next version. The same spelling appears in the install script, the release packaging script, and the updater.
</Callout>

## How "latest" is decided

dvm scans `/releases` for the newest non-draft, non-prerelease entry that **carries the asset it needs**. Choosing on the asset rather than on a release's position means "latest" always names a release with a CLI binary in it, even in a repository that also publishes per-package releases.

## Replacing a running binary

On POSIX, `rename` over a running executable keeps the old inode alive — the process you are in keeps running from the file that is no longer at that path — so writing a temp file and renaming it into place is safe: that path holds the old binary or the new one, and an interrupted copy leaves the old one there.

On Windows the current binary is renamed aside first and the new one written in its place, which is how a running `.exe` gets replaced there.

## The update notice

Ordinary commands start a check for a newer release before doing their work and report it afterwards, as one line:

```text
A newer dvm is available: 0.1.0 -> 0.2.0. Run: dvm update
```

Three things about it:

- It goes to **stderr**, so `dvm which --path` and `dvm list` keep handing a script exactly what it asked for on stdout.
- A compiled binary checks; dvm running from source goes straight to the work.
- `dvm update` says all of this itself, at more length, so it skips the one-liner.

Suppress it for one invocation:

```sh
dvm --no-version-check list
```

Anything scripted against dvm wants its output to be exactly what it asked for, which is what that flag is for. In CI it is worth setting — see [Using dvm in CI](/guides/ci).

## Pinning the installer

```sh
curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | DVM_VERSION=0.2.0 sh
```

Useful in a Dockerfile, where pinning the installer is what keeps the image reproducible.

## See also

- [`dvm update`](/commands/update) — the command reference.
- [Installation](/getting-started/installation) — the install script and its environment variables.

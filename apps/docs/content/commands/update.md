---
title: dvm update
description: Replace the running dvm binary with the newest release.
---

```text
dvm update [version]
dvm update --check
```

Updates dvm itself, leaving your SDKs, your pins and your config exactly as they are.

```sh
dvm update
```

```text
Updated dvm 0.1.0 -> 0.2.0 (/Users/you/.dvm/bin/dvm).
```

## Flags

| Flag | Effect |
| --- | --- |
| `--check` | Report whether a newer dvm exists, without installing anything. |

```sh
dvm update --check
```

```text
A newer dvm is available: 0.1.0 -> 0.2.0
Run `dvm update` to install it.
```

Already current:

```text
dvm 0.2.0 is already up to date.
```

## Installing a specific version

```sh
dvm update 0.1.5
```

Downgrading works the same way. The argument is a dvm version — Dart versions belong to [`dvm install`](/commands/install).

## How it replaces itself

It downloads the release asset for your platform, verifies its checksum, writes it to a temporary file, and renames that over the running binary.

On POSIX this is safe: `rename` over a running executable keeps the old inode alive, so the process you are in keeps running from the file that is no longer at that path. On Windows the current binary is renamed aside first and the new one written in its place, which is how a running `.exe` gets replaced there.

## The notice on other commands

Ordinary dvm commands run a background check and print a one-line notice on **stderr** when a newer release exists. Stderr is the point: `dvm which --path` and `dvm list` get read by scripts, and keeping stdout to exactly what was asked for is what lets a script rely on it.

Turn it off per invocation:

```sh
dvm --no-version-check list
```

A compiled binary runs the check; dvm running from source goes straight to the work, and so does `dvm update` itself, which says all this at more length anyway.

## See also

- [Updating dvm](/guides/updating-dvm) — where the releases come from and how "latest" is decided.
- [Installation](/getting-started/installation) — the install script, which does the same job for a machine reaching dvm for the first time.

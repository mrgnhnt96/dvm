---
title: dvm update
description: Replace the running dvm binary with the newest release.
---

```text
dvm update [version]
dvm update --check
```

Updates dvm itself. It does not touch your SDKs, your pins, or your config.

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

Downgrading is allowed. The argument is a dvm version, not a Dart version.

## How it replaces itself

It downloads the release asset for your platform, verifies its checksum, writes it to a temporary file, and renames that over the running binary.

On POSIX this is safe: `rename` over a running executable keeps the old inode alive, so the process you are in keeps running from the file that is no longer at that path. On Windows a running `.exe` cannot be replaced, so the current binary is renamed aside first and the new one written in its place.

## The notice on other commands

Ordinary dvm commands run a background check and print a one-line notice on **stderr** when a newer release exists. It is on stderr on purpose: `dvm which --path` and `dvm list` get read by scripts, and a notice mixed into their stdout would be a breaking change arriving on its own schedule.

Turn it off per invocation:

```sh
dvm --no-version-check list
```

It is skipped automatically when dvm is running from source rather than a compiled binary, and during `dvm update` itself, which says all this at more length anyway.

## See also

- [Updating dvm](/guides/updating-dvm) — where the releases come from and how "latest" is decided.
- [Installation](/getting-started/installation) — the install script, which does the same job for a machine with no dvm on it.

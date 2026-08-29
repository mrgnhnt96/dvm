---
title: Installation
description: Install dvm with one curl command, on a machine that has never had Dart on it.
---

dvm ships as a single compiled binary. The install script downloads the one built for your machine, checks it against a published checksum, and puts it in `~/.dvm/bin/dvm`.

## The install script

```sh
curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh
```

That is the whole thing. It runs on a machine that has never had Dart on it, which is the machine a Dart version manager is most needed on: the script fetches a compiled binary, so dvm is ready before any SDK exists.

The script prints where it put the binary and what to do next:

```text
Looking up the newest dvm release...
Downloading dvm-macos-arm64.zip (v0.2.0)...

dvm v0.2.0 is installed at /Users/you/.dvm/bin/dvm

Add this to your shell startup file (~/.zshrc, ~/.bashrc, ...):

  export PATH="/Users/you/.dvm/bin:$PATH"

Then start a new shell and run  dvm setup  to install the dart shim.
```

Do both of those. `~/.dvm/bin` on `PATH` is what makes `dvm` runnable; [`dvm setup`](/getting-started/shell-setup) is the separate step that makes plain `dart` follow your project pins.

<Callout type="warning">
The script covers Linux and macOS. On Windows, download `dvm-windows-x64.zip` from [the releases page](https://github.com/mrgnhnt96/dvm/releases) and put `dvm.exe` on your `PATH` — the script points you here and stops, so you always end up with a dvm that works.
</Callout>

### What the script checks

Three things have to hold before anything lands on disk, and the script names whichever one stopped it — so a run that finishes leaves you a working dvm:

- a published binary exists for your operating system and CPU architecture,
- the release asset is reachable (the GitHub API allows 60 unauthenticated requests per hour per IP — set `GITHUB_TOKEN` and retry if you meet that limit),
- the downloaded archive's SHA-256 matches the `.sha256` published alongside it.

### Environment variables

| Variable | Effect |
| --- | --- |
| `DVM_VERSION` | Install this version instead of the newest release. `0.2.0` and `v0.2.0` both work. |
| `DVM_HOME` | Install under this directory instead of `~/.dvm`. |
| `GITHUB_TOKEN` | Used for the release lookup if set. Raises the API rate limit. |

```sh
# pin the installer itself, e.g. in a Dockerfile
curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | DVM_VERSION=0.2.0 sh
```

## How dvm reaches your machine

The install script above puts dvm on a new machine, and [`dvm update`](/commands/update) keeps it current from then on. Both fetch the same compiled binary from the same GitHub Release and check it against the same published checksum, so you get the same dvm either way.

That pairing works because a compiled binary needs nothing already installed — which is what a Dart version manager needs, since the language it manages is exactly what is missing when you arrive. See [Updating dvm](/guides/updating-dvm).

## Verify it

```sh
dvm --version
dvm doctor
```

[`dvm doctor`](/commands/doctor) is worth running now rather than later. On a fresh install it points you at the shims, which is the next page.

## What is on disk now

```text
~/.dvm/
  bin/dvm          the binary you just installed
```

`versions/`, `shims/` and `config.json` arrive as the commands that need them run.

## Next steps

Run [`dvm setup`](/getting-started/shell-setup) to install the `dart` shim, then follow the [Quick Start](/getting-started/quick-start).

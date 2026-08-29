---
title: Installation
description: Install dvm with one curl command. You do not need a Dart SDK first — that is the point.
---

dvm ships as a single compiled binary. The install script downloads the one built for your machine, checks it against a published checksum, and puts it in `~/.dvm/bin/dvm`.

## The install script

```sh
curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh
```

That is the whole thing. There is no Dart SDK prerequisite, which is not an accident: a Dart version manager that required Dart in order to install itself would be useless on the machine that needs it most — a fresh one.

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
The script installs on Linux and macOS only. On Windows, download `dvm-windows-x64.zip` from [the releases page](https://github.com/mrgnhnt96/dvm/releases) and put `dvm.exe` on your `PATH` yourself — the script tells you the same thing and exits rather than doing something half-right.
</Callout>

### What the script checks

It fails loudly rather than partially, because a half-installed version manager is worse than none: you end up with a `dvm` on `PATH` that cannot do the one thing it exists for, and nothing on screen says why. Specifically it will refuse to install if:

- your operating system or CPU architecture has no published binary,
- the release asset cannot be found (usually the GitHub API's unauthenticated rate limit of 60 requests per hour per IP — set `GITHUB_TOKEN` and retry),
- the downloaded archive's SHA-256 does not match the `.sha256` published alongside it.

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

## There is only one channel

The install script above, and [`dvm update`](/commands/update) once dvm is on your machine. That is the whole distribution story, and the constraint behind it is the tool's own subject matter: a Dart version manager cannot require the language it manages in order to install itself.

There is **no Homebrew tap**, and there is not going to be one. A tap costs a second repository, a cross-repo credential that GitHub Actions does not hand out by default, and a formula-bumping job on every release — and it reaches Linux users hardly at all. An install script plus [a built-in self-updater](/guides/updating-dvm) covers everyone. See [Updating dvm](/guides/updating-dvm).

## Verify it

```sh
dvm --version
dvm doctor
```

[`dvm doctor`](/commands/doctor) is worth running now rather than later. On a fresh install it will tell you the shims are not set up yet, which is true and is the next page.

## What is on disk now

```text
~/.dvm/
  bin/dvm          the binary you just installed
```

Nothing else exists yet. `versions/`, `shims/` and `config.json` are created by the commands that need them.

## Next steps

Run [`dvm setup`](/getting-started/shell-setup) to install the `dart` shim, then follow the [Quick Start](/getting-started/quick-start).

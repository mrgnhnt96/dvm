---
title: Using dvm in CI
description: Get a build machine onto the SDK a project pins, without a shim, a shell profile, or a login shell.
---

CI is where dvm's design pays off most reliably: the version a build uses is the version in the repository, the same one developers have.

The main thing to know is that **[`dvm exec`](/commands/exec) is all a build machine needs.** The shim exists to make an interactive shell's `dart` follow the pin; in CI you write every command yourself, so naming `dvm exec` in front of them is simpler and takes no configuration.

## The short version

```yaml
- name: Install dvm
  run: curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh

- name: Install the pinned SDK
  run: ~/.dvm/bin/dvm install "$(cat .dvmrc | tr -d '{}" ' | cut -d: -f2)"

- name: Test
  run: ~/.dvm/bin/dvm exec dart test
```

That parsing is ugly. Two better options follow.

## Option 1 — `dvm use` reads the pin for you

Name the version in the workflow as well as in the repository, and let the two check each other:

```yaml
- name: Install dvm
  run: |
    curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh
    echo "$HOME/.dvm/bin" >> "$GITHUB_PATH"

- name: Install the pinned SDK
  run: dvm install 3.13.2      # must match .dvmrc

- name: Test
  run: dvm exec dart test
```

`dvm exec` resolves through [rule 2](/versions/resolution-order) — the repository's own `.dvmrc` — so the build tests against the SDK `.dvmrc` names. If the workflow ever names a different one, the `exec` step says so at once.

## Option 2 — `DVM_DART_VERSION`

[Rule 1](/versions/resolution-order) exists for exactly this. It overrides everything on disk, including the `.dvmrc`:

```yaml
env:
  DVM_DART_VERSION: 3.13.2

steps:
  - run: curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh
  - run: ~/.dvm/bin/dvm install "$DVM_DART_VERSION"
  - run: ~/.dvm/bin/dvm exec dart test
```

Use this when the build needs a *different* SDK from the one the repository pins — a matrix that tests against several versions is the obvious case:

```yaml
strategy:
  matrix:
    dart: ['3.9.0', '3.13.2']
env:
  DVM_DART_VERSION: ${{ matrix.dart }}
```

Rule 1 is also the right lever for a one-off locally:

```sh
DVM_DART_VERSION=3.9.0 dart test
```

## Turn the update notice off

```yaml
env:
  DVM_DART_VERSION: 3.13.2
run: dvm --no-version-check exec dart test
```

The notice is for a human at a terminal, and the check costs a network request per command, so a build runs faster and quieter without it.

## Cache `~/.dvm/versions`

An SDK download is the slowest part of the job and the most cacheable:

```yaml
- uses: actions/cache@v4
  with:
    path: ~/.dvm/versions
    key: dvm-${{ runner.os }}-${{ hashFiles('.dvmrc') }}
```

Key it on `.dvmrc` so bumping the pin invalidates the cache. Cache `versions/` and leave `~/.dvm/cache` to itself — that one holds in-flight download scratch, disposable by design, and a job starts cleaner without it.

## In a Dockerfile

Pin the installer as well as the SDK, so the image builds the same way every time:

```dockerfile
ENV DVM_VERSION=0.2.0
RUN curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh
ENV PATH="/root/.dvm/bin:${PATH}"

COPY .dvmrc .
RUN dvm install 3.13.2
```

`DVM_HOME` moves the whole installation somewhere else if `/root` is wrong for your image.

## Using the shim in CI

It works, and it is the right choice when the build runs scripts you did not write that call `dart` directly:

```yaml
- run: |
    curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh
    "$HOME/.dvm/bin/dvm" setup
    echo "$HOME/.dvm/shims" >> "$GITHUB_PATH"
    echo "$HOME/.dvm/bin" >> "$GITHUB_PATH"
```

Note the order: shims go [ahead of everything else on `PATH` that supplies a `dart`](/getting-started/shell-setup). GitHub's `$GITHUB_PATH` prepends, so the *last* line written ends up first — writing `shims` then `bin` gives you `bin` first, which works fine. Confirm it with `dvm doctor`.

## On a Windows runner

The same three steps, with the release zip in place of the install script — see [Installation](/getting-started/installation#on-windows) for where the binary comes from:

```yaml
- name: Install dvm
  shell: pwsh
  run: |
    $zip = "$env:RUNNER_TEMP\dvm.zip"
    Invoke-WebRequest -Uri "https://github.com/mrgnhnt96/dvm/releases/latest/download/dvm-windows-x64.zip" -OutFile $zip
    Expand-Archive $zip -DestinationPath "$env:USERPROFILE\.dvm\bin"
    "$env:USERPROFILE\.dvm\bin" | Out-File -FilePath $env:GITHUB_PATH -Append -Encoding utf8

- name: Install the pinned SDK
  run: dvm install 3.13.2

- name: Test
  run: dvm exec dart test
```

`dvm install`, `dvm exec` and `dvm which` behave the same there as anywhere else, and the cache step above already keys on `runner.os`, so adding `windows-latest` to a matrix caches its SDKs separately without another change.

## Verify before you rely on it

```yaml
- run: dvm which
```

One line in the log that names the SDK **and the rule that chose it** turns "which Dart did that build actually use?" from an investigation into a scroll.

---
title: Using dvm in CI
description: Get a build machine onto the SDK a project pins, without a shim, a shell profile, or a login shell.
---

CI is where dvm's design pays off least dramatically and most reliably: the version a build uses is the version in the repository, so it cannot drift from what developers have.

The main thing to know is that **you do not need the shim on a build machine.** The shim exists to make an interactive shell's `dart` follow the pin. In CI you control every command, so [`dvm exec`](/commands/exec) is simpler and has nothing to configure.

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

`dvm use` with no version is not a thing, but `dvm install` accepts what `.dvmrc` says if you hand it over. The cleanest form is to let dvm resolve and install in one step by pinning explicitly in the workflow *and* in the repository, and letting [`dvm doctor`](/commands/doctor) fail the build if they disagree:

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

`dvm exec` resolves through [rule 2](/versions/resolution-order) — the repository's own `.dvmrc` — so if the two ever drift, the SDK is not installed and the build fails loudly at the `exec` step rather than silently testing against the wrong version.

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

A build machine cannot act on "a newer dvm is available", and the check costs a network request per command. The notice goes to stderr, so it will not corrupt captured output — but there is no reason to pay for it.

## Cache `~/.dvm/versions`

An SDK download is the slowest part of the job and the most cacheable:

```yaml
- uses: actions/cache@v4
  with:
    path: ~/.dvm/versions
    key: dvm-${{ runner.os }}-${{ hashFiles('.dvmrc') }}
```

Key it on `.dvmrc` so bumping the pin invalidates the cache. Do **not** cache `~/.dvm/cache` — that is in-flight download scratch and is safe to delete at any time, which is exactly what you do not want a restored cache to bring back.

## In a Dockerfile

Pin the installer as well as the SDK, or the image changes underneath you:

```dockerfile
ENV DVM_VERSION=0.2.0
RUN curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh
ENV PATH="/root/.dvm/bin:${PATH}"

COPY .dvmrc .
RUN dvm install 3.13.2
```

`DVM_HOME` moves the whole installation somewhere else if `/root` is wrong for your image.

## If you do want the shim

It works, and it is the right choice when the build runs scripts you do not control that call `dart` directly:

```yaml
- run: |
    curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh
    "$HOME/.dvm/bin/dvm" setup
    echo "$HOME/.dvm/shims" >> "$GITHUB_PATH"
    echo "$HOME/.dvm/bin" >> "$GITHUB_PATH"
```

Note the order: shims first, so [nothing else on `PATH` supplies a `dart` before it](/getting-started/shell-setup). GitHub's `$GITHUB_PATH` prepends, so the *last* line written ends up first — put `shims` before `bin` and you get `bin` first, which is fine, but check with `dvm doctor` rather than assuming.

## Verify before you rely on it

```yaml
- run: dvm which
```

One line in the log that names the SDK **and the rule that chose it** turns "which Dart did that build actually use?" from an investigation into a scroll.

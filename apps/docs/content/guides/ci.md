---
title: CI
description: Install the required SDK and run your build with dvm exec.
---

Your CI job needs dvm, the SDK named in `.dvmrc`, and your project's dependencies. `dvm exec` selects the project version without shell startup configuration.

## A Linux CI job

After checking out the repository, run these commands from its root. This example assumes `.dvmrc` pins `3.9.0`; replace it with your project's version.

```sh
curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh
export PATH="$HOME/.dvm/bin:$PATH"
dvm --no-version-check install 3.9.0
dvm --no-version-check which
dvm --no-version-check exec dart pub get
dvm --no-version-check exec dart test
```

Keep the installation version in sync when changing `.dvmrc`. The job fails if the selected SDK is not installed.

## Test another Dart version

Set `DVM_DART_VERSION` in the job environment to override `.dvmrc`. Install that version before running the build:

```sh
export DVM_DART_VERSION=3.9.0
dvm --no-version-check install "$DVM_DART_VERSION"
dvm --no-version-check exec dart pub get
dvm --no-version-check exec dart test
```

For a version matrix, give each job a different `DVM_DART_VERSION` value.

## Cache SDK downloads

Cache `~/.dvm/versions`, or `$DVM_HOME/versions` if configured. Include the operating system, CPU architecture, and required Dart version in the cache key. If the version comes from `.dvmrc`, include that file's hash.

## Scripts that call dart directly

Run the script through dvm so Dart is available to commands inside it:

```sh
dvm --no-version-check exec ./tool/build.sh
```

The script must be executable. You can also run `dvm --no-version-check exec sh ./tool/build.sh` for a shell script.

## Windows runners

Install `dvm.exe` using the [Windows installation steps](/#installation-on-windows) and add its directory to the job's PATH. Then use the same `dvm install` and `dvm exec` commands as above.

## Pin the dvm release

Set `DVM_VERSION` when running the install script to choose a specific dvm release. See [Installation](/#installation-options).

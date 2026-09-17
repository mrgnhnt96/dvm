---
title: Managing versions
description: Choose Dart versions for projects, set a default, and configure your editor.
---

## Pin a project with .dvmrc

From your project directory:

```sh
dvm use 3.9.0 --gitignore
```

This installs the SDK if needed and saves its exact version in `.dvmrc`:

```json
{
  "dart": "3.9.0"
}
```

Commit `.dvmrc` and the `.gitignore` change. The local `.dvm/` directory stays out of version control. dvm also accepts a bare version on one line, but `dvm use` writes JSON.

A pin applies to its directory and subdirectories. `dvm use` updates the nearest existing `.dvmrc`, including one in a parent directory. Check the path printed by the command.

To give a package its own pin, run this inside that package:

```sh
dvm use 3.9.0 --here --gitignore
```

## Open an existing project

After cloning, read `.dvmrc` and run `dvm use` with the version it names. For example, for `{ "dart": "3.9.0" }`:

```sh
dvm use 3.9.0
dart pub get
```

This installs the SDK if needed and creates the editor link. A committed `.dvmrc` alone does not download Dart.

## Configure your editor

Set your editor's Dart SDK path to `.dvm/dart_sdk`, relative to the directory containing `.dvmrc`. Re-run `dvm use` when changing the project version to update the link. Restart the editor's Dart analyzer if needed.

## Set a default

```sh
dvm global 3.9.0
```

The SDK is installed if needed. This default applies outside pinned projects. Run `dvm global` without an argument to see the saved default.

## Channels and upgrades

Choose `stable`, `beta`, or `dev`:

```sh
dvm install stable
dvm use stable
```

`install` downloads the latest SDK from the channel and remembers its version on this machine. `use` saves that exact version in `.dvmrc`.

To upgrade a project later, run both commands again and commit the changed `.dvmrc`. `dvm use stable` alone does not check for a newer release.

Run `dvm global stable` after installation if you also want to update your default outside projects. Updating dvm itself uses [`dvm update`](/commands#dvm-update).

## Aliases

Save a memorable name:

```sh
dvm alias work 3.9.0
dvm use work
```

`dvm use work` installs the SDK if needed and saves its exact version. Changing `work` later does not change this project or a default created with `dvm global work`; run those commands again to select the new version.

List names with `dvm alias list` and remove a name with `dvm unalias work`.

A hand-written `.dvmrc` can contain an alias or channel name, but its meaning depends on each machine's settings. Use exact versions for shared projects.

## Resolution order

Run `dvm which` to see the selected SDK and why it applies. When using dvm, the priority is:

1. A non-empty `DVM_DART_VERSION` environment variable.
2. The nearest `.dvmrc`, starting in the current directory and checking parents.
3. The default set with `dvm global`.
4. Another Dart installation on PATH.
5. An error if none applies.

An invalid pin or missing selected SDK produces an error; dvm does not substitute another version. Install the version named in the error.

For a one-off override in bash/zsh, install the version first:

```sh
dvm install 3.9.0
DVM_DART_VERSION=3.9.0 dvm dart --version
```

This leaves `.dvmrc` unchanged. For CI, set `DVM_DART_VERSION` in the job environment. See [CI](/guides/ci).

---
title: Commands
description: Command syntax, options, and examples for using dvm.
---

Run `dvm --help` for the command list or `dvm <command> --help` for options. Version arguments may be exact versions, channels, or aliases unless noted below.

## dvm install

```sh
dvm install 3.9.0
dvm install stable
```

Download an SDK without changing a project pin or default. SDKs are shared across projects under `~/.dvm/versions`, or `$DVM_HOME/versions`.

Use `-f` / `--force` to reinstall. Channels (`stable`, `beta`, `dev`) select the latest release and remember its version locally.

## dvm use

```sh
dvm use 3.9.0 --gitignore
```

Install if needed, save the exact version in the nearest `.dvmrc`, and create `.dvm/dart_sdk` for your editor. If no pin exists, create one in the current directory.

| Option | Effect |
| --- | --- |
| `--here` | Pin the current directory even if a parent has a `.dvmrc`. |
| `--gitignore` | Add `.dvm/` to `.gitignore` beside the pin. |
| `-g`, `--global` | Set the default instead of a project pin. |

Install a channel before using its name: `dvm install stable`, then `dvm use stable`. See [Managing versions](/versions).

## dvm global

```sh
dvm global 3.9.0
dvm global
```

Set the default for directories without a project pin, or show the current default. Installs the SDK if needed and saves an exact version. Install a channel before using its name.

## dvm list

```sh
dvm list
```

List installed SDKs. `dvm ls` is equivalent. `*` marks the selected SDK; labels show project, default, alias, and channel references.

## dvm list-remote

```sh
dvm list-remote
dvm list-remote --channel beta --all
```

List available releases, newest first. Requires an internet connection.

- `-c` / `--channel`: `stable` (default), `beta`, or `dev`.
- `--all`: show all releases instead of the newest 25.

## dvm remove

```sh
dvm remove 3.9.0
```

Delete an SDK. Removal is blocked if the global default or an alias refers to it; change those references first or pass `-f` / `--force`.

Project pins do not block removal. Projects needing that version will fail until you reinstall it or select another version. dvm warns about the current project's pin; it does not search all repositories.

An alias argument deletes the SDK it names. To delete only the name, use `dvm unalias`.

## dvm alias

```sh
dvm alias work 3.9.0
dvm alias list
```

Create or change a local name, or list aliases and recorded channel versions. Plain `dvm alias` also lists them. Creating an alias does not install an SDK.

Names cannot be channel names, `list`, version-like names, start with `-`, or contain whitespace or path separators. Aliases may refer to other aliases or channels, but loops and chains longer than eight hops are rejected.

## dvm unalias

```sh
dvm unalias work
```

Remove a name and keep its SDK. Update any hand-written pin or alias that still uses the removed name. Exact version pins created by `dvm use work` remain usable.

## dvm which

```sh
dvm which
dvm which --path
```

Show the Dart executable, SDK directory, and reason for selection. `dvm current` is equivalent. Use `--path` to print only the absolute executable path for another tool.

## dvm dart

```sh
dvm dart --version
dvm dart pub get
dvm dart test
```

Run Dart using the selected SDK without needing the Dart shim on PATH. Install the required SDK first. Arguments after `dart` go to Dart, and its exit code is returned.

`dvm dart --version` reports Dart's version; `dvm --version` reports dvm's version.

## dvm exec

```sh
dvm exec dart test
dvm exec ./tool/build.sh
```

Run a program with the selected SDK first on PATH. Dart commands started by that program use the same SDK. Install the SDK and the program first.

Arguments after `exec` go to the program. A leading `--` separator is accepted by both `exec` and `dart`. The program's exit code is returned; 127 means the program could not be found.

## dvm setup

```sh
dvm setup --write-path-line
```

Create the Dart shim and configure PATH. Open a new terminal afterward.

| Option | Effect |
| --- | --- |
| No options | Create the shim and print manual PATH instructions. |
| `--write-path-line` | Back up and update the shell startup file. Not available for PowerShell. |
| `--remove-path-line` | Remove dvm's automatic PATH block, keeping shims and manually added lines. |
| `--dvm-path <path>` | Select the dvm executable the shim should launch. |

Re-run setup if you move the executable. See [Getting started](/#manual-shell-setup) for shell-specific instructions.

## dvm doctor

```sh
dvm doctor
```

Check PATH, shims, shell conflicts, settings, and the current project's SDK link. Follow the reported fixes, or see [Troubleshooting](/guides/troubleshooting).

## dvm migrate

```sh
dvm migrate --dry-run
dvm migrate
```

Import SDKs from cbracken/dvm without downloading them again. Versions already installed in the destination are skipped.

- `--dry-run`: preview SDK moves and files eligible for cleanup.
- `--clean`: remove the old tool's `scripts/`, `environments/`, and `.git/` after migration; asks for confirmation.
- `-y` / `--yes`: answer yes to confirmation prompts.

Follow [migration steps](/guides/troubleshooting#migrating-from-cbrackendvm) to remove the old shell setup first.

## dvm update

```sh
dvm update
dvm update --check
```

Update dvm itself to the newest available release, or check without installing. SDKs, project pins, and settings are kept.

Use `dvm update <version>` to choose a specific dvm release, including an older one. To change a project's Dart SDK, use `dvm use`.

If the updater cannot run, repeat the [installation steps](/). Re-run `dvm setup` if you move the executable.

## dvm config

```sh
dvm config color always
dvm config color
```

Save or show the color preference. Use `auto` (default) for terminal detection, `always` to force color, or `never` to disable it. In `auto` mode, `NO_COLOR` and `TERM=dumb` disable color.

Settings live in `~/.dvm/config.json`, or `$DVM_HOME/config.json`. These options control dvm output; programs it launches manage their own colors.

## Global options

Put global options before the subcommand:

```sh
dvm --no-version-check exec dart test
dvm --verbose doctor
dvm --color=never list
```

| Option | Effect |
| --- | --- |
| `--no-version-check` | Skip update checks and notices for this command. |
| `-v`, `--verbose` | Print diagnostic details to stderr. |
| `--color=<mode>` | Use `auto`, `always`, or `never` to override the saved color preference for this command. |
| `--version` | Show the dvm version. |
| `-h`, `--help` | Show help. |

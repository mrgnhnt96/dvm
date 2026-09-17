# dvm

Install Dart and choose a Dart SDK version for each project. No existing Dart SDK is required.

## Install

On macOS or Linux:

```sh
curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh
"$HOME/.dvm/bin/dvm" setup --write-path-line
```

Open a new terminal. For Windows, follow the [installation guide](https://dvm.mrgnhnt.com/#installation-on-windows).

## Use Dart in a project

From your project directory:

```sh
dvm install stable
dvm use stable --gitignore
dart --version
```

This installs the latest stable SDK and saves its exact version in `.dvmrc`. Commit `.dvmrc` and the `.gitignore` change; keep `.dvm/` local.

To choose a specific version, use `dvm use 3.9.0 --gitignore` instead. Replace `3.9.0` with your project's required version; dvm installs it if needed.

After cloning a project, read its `.dvmrc` and run `dvm use <version>` with that version before running Dart. Set your editor's Dart SDK path to `.dvm/dart_sdk` beside `.dvmrc`.

## Common tasks

| Task | Command |
| --- | --- |
| Set the default outside projects | `dvm global stable` (after `dvm install stable`) |
| Show the selected SDK | `dvm which` |
| List installed SDKs | `dvm list` |
| Find available versions | `dvm list-remote` |
| Run Dart without shell setup | `dvm dart pub get` |
| Run a command with the project SDK | `dvm exec dart test` |
| Check setup | `dvm doctor` |
| Update dvm | `dvm update` |
| Show command help | `dvm <command> --help` |

To upgrade a project's Dart SDK, run `dvm install stable` and `dvm use stable` again, then commit the changed `.dvmrc`.

## Documentation

- [Getting started](https://dvm.mrgnhnt.com/)
- [Managing versions](https://dvm.mrgnhnt.com/versions)
- [Commands](https://dvm.mrgnhnt.com/commands)
- [CI](https://dvm.mrgnhnt.com/guides/ci)
- [Troubleshooting](https://dvm.mrgnhnt.com/guides/troubleshooting)
- [llms.txt](llms.txt)

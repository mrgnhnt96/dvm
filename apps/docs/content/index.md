---
title: Getting started
description: Install dvm, set up your shell, and run Dart in your first project.
---

dvm lets each project use its own Dart SDK. You do not need Dart installed to use dvm.

## Installation on macOS and Linux

Supports x64 and ARM64. The install script needs `curl` or `wget`, `unzip` or Python 3, and one of `sha256sum`, `shasum`, or `openssl`.

```sh
curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh
"$HOME/.dvm/bin/dvm" setup --write-path-line
```

Setup backs up your shell startup file and adds dvm to PATH. **Open a new terminal** before continuing.

## Installation on Windows

1. Download `dvm-windows-x64.zip` from [GitHub Releases](https://github.com/mrgnhnt96/dvm/releases).
2. Extract `dvm.exe` into `%USERPROFILE%\.dvm\bin`.
3. In PowerShell, run:

```powershell
& "$env:USERPROFILE\.dvm\bin\dvm.exe" setup
```

Run the PATH commands printed by setup, then open a new terminal. PowerShell uses these commands instead of `--write-path-line`.

## Quick start

From your project directory, install the latest stable Dart SDK and pin it:

```sh
dvm install stable
dvm use stable --gitignore
dart --version
dart pub get
```

`dvm use` saves the exact SDK version in `.dvmrc`. Commit `.dvmrc` and the `.gitignore` change; keep `.dvm/` local.

If your project requires a specific version, use `dvm use 3.9.0 --gitignore` instead. It installs that version if needed. Version numbers in these docs are examples; choose the version your project requires.

To use the installed stable SDK outside pinned projects too:

```sh
dvm global stable
```

For an existing project or editor setup, see [Managing versions](/versions).

## Manual shell setup

If you prefer to edit PATH yourself, run `"$HOME/.dvm/bin/dvm" setup` and follow its instructions. Plain `dvm setup` creates the Dart shim and prints the PATH line; it does not edit your startup file.

For the default installation in bash or zsh:

```sh
export PATH="$HOME/.dvm/shims:$HOME/.dvm/bin:$PATH"
```

Add this to `~/.zshrc` for zsh or `~/.bashrc` for bash, after other PATH changes. If your bash login shell reads `~/.bash_profile`, make sure it sources `~/.bashrc` or add the line there. Other shells should use the instructions printed by setup.

Keep dvm's shims ahead of other directories supplying Dart, including Flutter, fvm, asdf, or Homebrew. Open a new terminal, then run:

```sh
dvm doctor
dvm which
```

Until shell setup is complete, use `dvm dart` in place of plain `dart`. See [Troubleshooting](/guides/troubleshooting) if a command is missing or selects the wrong SDK.

## Installation options

To install a particular dvm release, set `DVM_VERSION` on the install script. Replace `0.2.0` with the release you need:

```sh
curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | DVM_VERSION=0.2.0 sh
```

To use another directory instead of `~/.dvm`:

```sh
curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | DVM_HOME="$HOME/tools/dvm" sh
export DVM_HOME="$HOME/tools/dvm"
"$DVM_HOME/bin/dvm" setup --write-path-line
```

Save the `DVM_HOME` export in your shell startup file too, so later commands use the same SDKs and settings.

## Next steps

- [Managing versions](/versions): project pins, defaults, channels, aliases, and editors.
- [Commands](/commands): command options and updating dvm.
- [CI](/guides/ci): install the required SDK and run your build.
- [Troubleshooting](/guides/troubleshooting): setup fixes and migration.
- [llms.txt](/llms.txt): documentation index for AI tools.

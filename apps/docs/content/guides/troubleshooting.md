---
title: Troubleshooting
description: Fix missing commands, unexpected Dart versions, and editor setup.
---

## Start with these checks

```sh
dvm doctor
dvm which
```

`doctor` checks setup. `which` shows the SDK selected in the current directory and why it was selected.

## dvm is not found

For the default macOS or Linux installation:

```sh
"$HOME/.dvm/bin/dvm" setup --write-path-line
```

Open a new terminal. If that executable is missing, [install dvm](/) first. For a custom installation, use the path printed by the installer.

On Windows, run `& "$env:USERPROFILE\.dvm\bin\dvm.exe" setup` in PowerShell and follow its printed commands.

## dart is missing or uses the wrong version

```sh
dvm doctor
```

If PATH is the problem, run `dvm setup --write-path-line` on macOS or Linux and open a new terminal. Plain `dvm setup` only prints PATH instructions.

Ensure `~/.dvm/shims` appears before other directories supplying Dart. If the line is already in your startup file, move it after other PATH changes and make sure your shell reads that file. See [Shell Setup](/#manual-shell-setup).

If shell setup is correct, run `dvm which`. Check the `.dvmrc` it names and any `DVM_DART_VERSION` override. To clear an override in bash/zsh:

```sh
unset DVM_DART_VERSION
```

In PowerShell, use `Remove-Item Env:DVM_DART_VERSION`.

## dvm runs the old version manager

Run `type dvm` in bash/zsh. If it reports a shell function or alias, remove that definition from your startup file and open a new terminal.

For an older `cbracken/dvm` installation, follow [Migrating](#migrating-from-cbrackendvm).

## The pinned SDK is not installed

Run the install command shown in the error, for example:

```sh
dvm install 3.9.0
```

Cloning a repository with `.dvmrc` does not install its SDK automatically. To create the editor link too, run `dvm use 3.9.0` with the version from that file.

## dvm does not know which version stable is

Install the channel before selecting it:

```sh
dvm install stable
dvm use stable
```

The same applies to `beta` and `dev`.

## No Dart SDK applies

Select a project version with `dvm use <version>`, or set a default with `dvm global <version>`.

If a default names an SDK you removed, reinstall that version or choose a new default.

## An SDK is broken or installation was interrupted

Reinstall the affected version:

```sh
dvm install 3.9.0 --force
```

Replace `3.9.0` with the required version. If the download fails again, check your connection and retry the command shown in the error.

## My editor uses another SDK

From the project directory, run `dvm use <version>` with the version in `.dvmrc`. Set the editor's Dart SDK path to `.dvm/dart_sdk` beside that file. Restart the editor's Dart analyzer if needed.

Keep `.dvm/` out of version control. If it was committed, remove it from Git's index with `git rm --cached -r .dvm`, then run `dvm use <version> --gitignore`.

## dvm exec cannot find a command

Install the named program and put its executable directory on PATH. For a globally activated Dart tool, this is usually `~/.pub-cache/bin`. A local script can be run by path, for example `dvm exec ./tool/build.sh`.

## Migrating from cbracken/dvm

Install this dvm using [Getting started](/). Before running setup, remove the line that sources `~/.dvm/scripts/dvm` from your shell startup file, along with any old function or alias named `dvm`. Open a new terminal.

Use the installed executable directly to preview and import your SDKs, then configure your shell:

```sh
"$HOME/.dvm/bin/dvm" migrate --dry-run
"$HOME/.dvm/bin/dvm" migrate
"$HOME/.dvm/bin/dvm" setup --write-path-line
```

Open another terminal. Run `dvm list` to see your imported SDKs. Select your default with `dvm global <version>` and pin each project with `dvm use <version> --gitignore`.

Check `dvm doctor` and `dart --version`. Once the new setup works, run `dvm migrate --clean` and confirm to remove the old tool's files.

## Still stuck

Include the output of `dvm --version`, `dvm doctor`, and `dvm which` when [opening an issue](https://github.com/mrgnhnt96/dvm/issues). Use `dvm --verbose doctor` if you need more detail.

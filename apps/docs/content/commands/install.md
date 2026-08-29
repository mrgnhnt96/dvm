---
title: dvm install
description: Download, verify and install a Dart SDK into the central cache.
---

```text
dvm install <version|channel|alias>
```

Downloads a Dart SDK from Google's `dart-archive` bucket, verifies its checksum, and extracts it into `~/.dvm/versions/<version>`.

```sh
dvm install 3.13.2
```

```text
Installed Dart 3.13.2 to /Users/you/.dvm/versions/3.13.2
```

Already installed? It says so and exits 0, without touching the network:

```text
Dart 3.13.2 is already installed at /Users/you/.dvm/versions/3.13.2
```

## Flags

| Flag | Effect |
| --- | --- |
| `-f`, `--force` | Reinstall even if the version is already present. |

## What you can name

| Argument | Behavior |
| --- | --- |
| A version — `3.13.2` | Installed as written. No network access at all if it is already present. |
| A channel — `stable`, `beta`, `dev` | dvm asks the archive what that channel currently means, installs it, and **records the answer** in `~/.dvm/config.json`. |
| An [alias](/versions/aliases) — `work` | Followed locally to whatever it points at, then installed. |

Only naming a channel costs a network round trip for resolution, and that one is unavoidable — asking what `stable` means today is the whole reason to type it.

## Recording what a channel meant

```sh
dvm install stable
```

writes `channels.stable` into `~/.dvm/config.json`. This is what makes a later `dvm use stable` work: [version resolution never touches the network](/versions/resolution-order), so the concrete version has to have been written down at install time.

Note the asymmetry: `dvm install 3.13.2` does **not** update `channels.stable`, even if 3.13.2 happens to be the current stable. Only a request that named the channel moves what that channel points at — otherwise installing an old version would silently rewrite your `stable` to point backwards.

## How an install is made safe

1. **Download** `dartsdk-<os>-<arch>-release.zip` from the archive.
2. **Verify** it against the sibling `.sha256sum` published by Google. A mismatch aborts; nothing is installed.
3. **Extract** into a temporary directory under `~/.dvm/cache/`.
4. **Rename** that directory into place as `~/.dvm/versions/<version>`.

The rename is what makes step 4 atomic. An interrupted install leaves a partial directory in `cache/` — which is disposable and can be deleted at any time — and never a half-extracted directory in `versions/` that later looks installed.

Extraction also runs an explicit `chmod` pass on POSIX. The zip decoder carries unix permissions but does not apply them, so without it everything under `bin/` would land non-executable and the SDK would be inert.

## Platforms

Binaries exist for `macos`/`linux`/`windows` on `x64` and `arm64`, plus `arm` and `riscv64` on Linux. dvm picks the one matching the machine it is running on.

## See also

- [`dvm use`](/commands/use) — install *and* pin, in one command.
- [`dvm list-remote`](/commands/list-remote) — what is available to install.
- [`dvm list`](/commands/list) — what is installed already.

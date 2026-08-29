---
title: dvm list-remote
description: List the Dart releases available from the archive, newest first.
---

```text
dvm list-remote [--channel <stable|beta|dev>] [--all]
```

Asks Google's `dart-archive` bucket what has been published, and marks the ones you already have.

```sh
dvm list-remote
```

```text
  3.13.2  (installed)
  3.13.1
  3.13.0
  ...

Showing the newest 25 of 177 stable releases. Pass --all to see them all.
```

This is one of only two commands that touch the network at all. The other is [`dvm install`](/commands/install) when you name a channel. [Resolution never does](/versions/resolution-order).

## Flags

| Flag | Default | Effect |
| --- | --- | --- |
| `-c`, `--channel` | `stable` | Which release channel to list. One of `stable`, `beta`, `dev`. |
| `--all` | off | Show every release instead of the newest 25. |

```sh
dvm list-remote --channel beta
dvm list-remote --all
```

## Why it truncates by default

Stable alone carries around 177 semver releases. A full dump buries the handful anybody is actually about to install, so the newest 25 are shown and the rest are one flag away.

The archive also holds about 28 legacy Dart 1 build numbers (`29803`, `41096`, …) and a `latest` marker. dvm filters those out — they are not versions you can pin.

## A version can be in more than one channel

The same version is often published to `stable` and to `beta`. That is why [`dvm install`](/commands/install) probes the channels in order `stable`, `beta`, `dev` when you name a bare version, and why a channel is resolved to a version before anything is downloaded.

## See also

- [`dvm install`](/commands/install) — install one of these.
- [`dvm list`](/commands/list) — what is already on this machine.

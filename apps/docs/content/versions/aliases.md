---
title: Aliases and Channels
description: Give a version a name you will remember, and understand exactly what `stable` means when dvm resolves it.
---

There are two ways a name — rather than a version number — can appear in a `.dvmrc` or a global default. They look similar and behave differently.

## Aliases

An alias is a name **you** define, stored in `~/.dvm/config.json`:

```sh
dvm alias work 3.9.0
```

```text
"work" now means 3.9.0.
```

Then anywhere a version is accepted, `work` is too:

```sh
dvm use work
dvm global work
dvm install work
```

The point is repointing. When the team moves to a new SDK you change the alias once, and every project pinned to `work` follows:

```sh
dvm alias work 3.13.2
```

```text
"work" now means 3.13.2.
  was: 3.9.0
```

List what you have:

```sh
dvm alias list
```

```text
Aliases in /Users/you/.dvm/config.json:

  legacy -> 3.4.0  (installed)
  work   -> 3.13.2  (installed)

Channels, as recorded by dvm install:
  stable -> 3.13.2
```

### What an alias may not be called

dvm refuses some names up front, because the alternative is a name in your config that silently does nothing:

| Rejected | Why |
| --- | --- |
| `stable`, `beta`, `dev` | Channel names. Resolution checks channels *before* aliases, so an alias with one of these names would be unreachable. |
| Anything that looks like a version | dvm would have no way to tell `3.9` the alias from `3.9` the version. |
| `list` | `dvm alias list` has to keep meaning "show me the aliases". |
| Anything starting with `-` | It reads as an option. |
| Anything with whitespace or a path separator | A name is a single word. |

An alias may point at another alias, and dvm follows the chain (up to eight hops). It refuses to create a loop, and refuses to point an alias at itself.

An alias that names a version you have not installed yet is **allowed** — you may reasonably write the alias first — but dvm says so rather than letting you discover it later:

```text
"next" now means 3.14.0.
  Dart 3.14.0 is not installed. Run: dvm install 3.14.0
```

Remove one with [`dvm unalias`](/commands/unalias). That deletes the name only; the SDK is untouched.

## Channels

`stable`, `beta` and `dev` are Dart's release channels. They are not aliases and you do not define them.

When you run `dvm install stable`, dvm asks the Dart archive what `stable` currently is, installs it, and **writes down the answer** in `~/.dvm/config.json`:

```json
{
  "channels": { "stable": "3.13.2" }
}
```

From then on, a pin of `stable` means 3.13.2 on this machine — until you run `dvm install stable` again.

## Why a channel is never re-resolved during resolution

This is the design decision that shapes the whole tool.

Version resolution runs on **every single `dart` invocation on the machine** once the shim is installed. It is allowed to read a couple of small files and nothing else. If `stable` were re-resolved against the network each time, every `dart --version` would make an HTTPS request to a Google Cloud Storage bucket — so `dart` would be slow, would behave differently on a plane, and would break entirely behind a firewall.

So the network is touched at exactly two moments, both of which you asked for explicitly:

- `dvm install <channel>` — asks what the channel means now, and records it.
- [`dvm list-remote`](/commands/list-remote) — lists what is available.

Everything else reads `config.json`.

The practical consequence: **`stable` moving upstream does not move your SDK.** You get the new one when you run `dvm install stable`, and not before. If you want that, run it; if you want reproducibility, pin a concrete version instead.

<Callout type="info">
`dvm use stable` fails with "no stable SDK has been installed, so dvm does not know which version that is" if you have never run `dvm install stable`. That is the same rule seen from the other side — there is nothing recorded to resolve.
</Callout>

## Aliases, channels, and versions together

A pin is resolved in this order:

1. Is it a channel name (`stable`, `beta`, `dev`)? Use the version recorded for it.
2. Is it an alias? Follow it, and repeat — up to eight hops.
3. Otherwise it is a concrete version. Use it as written.

So an alias may point at a channel:

```sh
dvm alias current stable
```

and `dvm which` reports the whole chain rather than just the answer:

```text
Chosen by rule 2 of 5: pinned by /Users/you/code/api/.dvmrc.
  It says "current", an alias for 3.13.2 in /Users/you/.dvm/config.json.
```

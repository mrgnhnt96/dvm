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

### Names dvm reserves

Some names already mean something to dvm, so it says so as you define one — which is what keeps every name in your config a name that resolves:

| Reserved | What it already means |
| --- | --- |
| `stable`, `beta`, `dev` | Channel names. Resolution checks channels *before* aliases, so an alias with one of these names would be unreachable. |
| Anything that looks like a version | dvm would have no way to tell `3.9` the alias from `3.9` the version. |
| `list` | `dvm alias list` has to keep meaning "show me the aliases". |
| Anything starting with `-` | It reads as an option. |
| Anything with whitespace or a path separator | A name is a single word. |

An alias may point at another alias, and dvm follows the chain up to eight hops. A loop — including an alias pointing at itself — is reported at the command that would create it.

An alias may name a version you have not installed yet — writing the alias first is a reasonable thing to do — and dvm tells you right then, with the command that fills the gap:

```text
"next" now means 3.14.0.
  Dart 3.14.0 is not installed. Run: dvm install 3.14.0
```

Remove one with [`dvm unalias`](/commands/unalias). That deletes the name only; the SDK is untouched.

## Channels

`stable`, `beta` and `dev` are Dart's release channels. dvm knows all three already, so you name one and it does the rest.

When you run `dvm install stable`, dvm asks the Dart archive what `stable` currently is, installs it, and **writes down the answer** in `~/.dvm/config.json`:

```json
{
  "channels": { "stable": "3.13.2" }
}
```

From then on, a pin of `stable` means 3.13.2 on this machine — until you run `dvm install stable` again.

## What a channel name means on your machine

This is the design decision that shapes the whole tool.

Version resolution runs on **every single `dart` invocation on the machine** once the shim is installed, so it answers a channel name out of `config.json`. `stable` means the version recorded the last time you ran `dvm install stable` — the same answer at full speed, on a plane, and behind a firewall.

The network is reached at exactly two moments, both of which you ask for by name:

- `dvm install <channel>` — asks what the channel means now, and records it.
- [`dvm list-remote`](/commands/list-remote) — lists what is available.

Everything else reads `config.json`.

The practical consequence: **your `stable` moves when you move it.** Run `dvm install stable` to take the newest one. For a repository other people build, pin a concrete version, so everyone gets the same SDK.

<Callout type="info">
`dvm use stable` reads that same record. Before your first `dvm install stable` it says `dvm does not know which version "stable" is: no stable SDK has been installed on this machine, and resolving a channel name never goes to the network. Run: dvm install stable` — the same rule, from the side that reads it.
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

and `dvm which` reports the whole chain alongside the answer:

```text
Chosen by rule 2 of 5: pinned by /Users/you/code/api/.dvmrc.
  It says "current", an alias for 3.13.2 in /Users/you/.dvm/config.json.
```

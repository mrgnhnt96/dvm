---
title: The .dvmrc File
description: The one dvm file you commit — its format, where dvm looks for it, and what a pin is allowed to contain.
---

`.dvmrc` is how a project says which Dart SDK it wants. It is the only dvm file that belongs in version control.

## The format

Canonically it is JSON, which leaves room for the format to grow while everything already written keeps parsing:

```json
{ "dart": "3.9.0" }
```

[`dvm use`](/commands/use) always writes that form:

```sh
dvm use 3.9.0
```

```json
{
  "dart": "3.9.0"
}
```

A **bare version on a single line** is also accepted, the way `.nvmrc` works, for hand-editing:

```text
3.9.0
```

dvm reads both. It only ever writes the JSON one, so a hand-written bare pin becomes JSON the next time you run `dvm use` in that directory.

## What a pin may contain

The value is a *reference*. Three kinds are valid:

| Pin | Means |
| --- | --- |
| `3.9.0` | Exactly that version. |
| `work` | An [alias](/versions/aliases) you defined with `dvm alias work 3.9.0`. |
| `stable` | The version that channel resolved to when you last ran `dvm install stable`. |

Resolving an alias or a channel name reads `~/.dvm/config.json` and stops there: aliases live in that file, and a channel's concrete version was written into it at install time. See [Aliases and Channels](/versions/aliases) for why that matters.

<Callout type="warning">
Pinning a channel name pins *your machine's* idea of what that channel means. Two people can have the same `.dvmrc` saying `stable` and be on different SDKs. For a repository other people build, pin a concrete version.
</Callout>

## Where dvm looks

dvm walks **up** from the current directory to the filesystem root and uses the first `.dvmrc` it finds. That is what makes a monorepo work:

```text
my-monorepo/
  .dvmrc                { "dart": "3.9.0" }     <- applies to everything below
  packages/
    api/
    tools/
      .dvmrc            { "dart": "3.13.2" }    <- except here
```

`dart` in `packages/api` gets 3.9.0. `dart` in `packages/tools` gets 3.13.2. Nearest wins.

`dvm use` writes to the **current directory**. Running it inside one package of a monorepo pins that package, and the pin at the repository root stays exactly as it was.

## The other file: `.dvm/dart_sdk`

Alongside `.dvmrc`, `dvm use` creates a symlink:

```text
.dvm/dart_sdk -> ~/.dvm/versions/3.9.0
```

This is for IDEs and editors that want to be handed an SDK directory rather than a `dart` on `PATH`. Point your analyzer or plugin at `.dvm/dart_sdk` and it follows the pin along with everything else.

**Keep it out of version control.** It is an absolute path into your own home directory, so it means something on this machine and nowhere else. Ignore it:

```sh
dvm use 3.9.0 --gitignore
```

which appends:

```text
# dvm's per-project SDK symlink; .dvmrc is the part you commit.
.dvm/
```

dvm edits `.gitignore` when you pass `--gitignore`, and otherwise names the rule it would add and leaves the file to you. The repository is yours, so the edit is yours to ask for.

## A pin dvm cannot resolve is an error

If `.dvmrc` cannot be parsed, or names something dvm cannot resolve, resolution **fails** with a message rather than quietly falling through to your [global default](/commands/global):

```text
dvm: Dart 3.9.0 is pinned by /Users/you/code/api/.dvmrc, but it is not installed. Run: dvm install 3.9.0
```

So you always get the SDK the pin names, or a message naming the pin. A typo is reported where you made it, rather than turning up much later as a build that behaved oddly.

## Checking what applies

```sh
dvm which
```

names both the SDK and the `.dvmrc` that chose it. See [Resolution Order](/versions/resolution-order) for the full set of rules that surround this one.

---
title: The .dvmrc File
description: The one dvm file you commit — its format, where dvm looks for it, and what a pin is allowed to contain.
---

`.dvmrc` is how a project says which Dart SDK it wants. It is the only dvm file that belongs in version control.

## The format

Canonically it is JSON, so it can grow later without breaking anything already written:

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

The value is a *reference*, not necessarily a literal version. Three things are valid:

| Pin | Means |
| --- | --- |
| `3.9.0` | Exactly that version. |
| `work` | An [alias](/versions/aliases) you defined with `dvm alias work 3.9.0`. |
| `stable` | The version that channel resolved to when you last ran `dvm install stable`. |

Resolving an alias or a channel name costs no network access — aliases live in `~/.dvm/config.json`, and a channel's concrete version was written there at install time. See [Aliases and Channels](/versions/aliases) for why that matters.

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

`dvm use` writes to the **current directory**, never to the nearest existing `.dvmrc` above it. Running `dvm use` inside one package of a monorepo pins that package, rather than silently rewriting the pin at the repository root.

## The other file: `.dvm/dart_sdk`

Alongside `.dvmrc`, `dvm use` creates a symlink:

```text
.dvm/dart_sdk -> ~/.dvm/versions/3.9.0
```

This is for IDEs and editors that want to be handed an SDK directory rather than a `dart` on `PATH`. Point your analyzer or plugin at `.dvm/dart_sdk` and it follows the pin along with everything else.

**Do not commit it.** It is an absolute path into your own home directory, so committing it breaks every other checkout. Ignore it:

```sh
dvm use 3.9.0 --gitignore
```

which appends:

```text
# dvm's per-project SDK symlink; .dvmrc is the part you commit.
.dvm/
```

dvm only edits `.gitignore` when you pass `--gitignore`. Otherwise it says the rule is missing and moves on — editing a file you did not name, in a repository dvm does not own, is not something it does on its own.

## A malformed pin is an error, not a fallback

If `.dvmrc` cannot be parsed, or names something dvm cannot resolve, resolution **fails** with a message rather than quietly falling through to your [global default](/commands/global):

```text
dvm: Dart 3.9.0 is pinned by /Users/you/code/api/.dvmrc, but it is not installed. Run: dvm install 3.9.0
```

Falling back would be worse. A typo'd pin that silently runs a different SDK is a bug that shows up much later, somewhere else.

## Checking what applies

```sh
dvm which
```

names both the SDK and the `.dvmrc` that chose it. See [Resolution Order](/versions/resolution-order) for the full set of rules that surround this one.

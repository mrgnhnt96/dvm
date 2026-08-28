# dvm

A per-project Dart SDK version manager.

`dvm` keeps every Dart SDK you use in one central cache, lets you pin a version
per project with a committed `.dvmrc`, and makes `dart` resolve to the right SDK
automatically — the same way `fvm` does for Flutter.

```sh
brew install mrgnhnt96/tap/dvm

dvm install 3.13.2      # download into the central cache
dvm use 3.13.2          # pin this project, writes .dvmrc
dvm alias work 3.9.0    # name a version, then put `work` in .dvmrc
dart --version          # resolves per project, via the shim
```

Docs: <https://mrgnhnt96.github.io/dvm/>

## Status

Early development. See [the plan](https://github.com/mrgnhnt96/dvm) for scope.

## Why not the alternatives

- [`cbracken/dvm`](https://github.com/cbracken/dvm) installs multiple SDKs but has a
  single global environment — no per-project pin.
- [`dvmx`](https://pub.dev/packages/dvmx) does pin per project, but is dormant and has
  no version aliases.
- [`dsm`](https://github.com/Yakiyo/dsm) is Rust, and has no per-project version file.

## License

MIT

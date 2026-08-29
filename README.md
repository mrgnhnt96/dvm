# dvm

A per-project Dart SDK version manager.

`dvm` keeps every Dart SDK you use in one central cache, lets you pin a version
per project with a committed `.dvmrc`, and makes `dart` resolve to the right SDK
automatically — the same way `fvm` does for Flutter.

```sh
curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh

dvm install 3.13.2      # download into the central cache
dvm use 3.13.2          # pin this project, writes .dvmrc
dvm alias work 3.9.0    # name a version, then put `work` in .dvmrc
dart --version          # resolves per project, via the shim
dvm update              # update dvm itself
```

No Dart SDK is required to install dvm — the install script fetches a prebuilt
binary, which is the point: you cannot need Dart to install the thing that
installs Dart.

Docs: <https://mrgnhnt.com/dvm/>

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

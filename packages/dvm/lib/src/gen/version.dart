/// The version this build of dvm reports, and whether it is a release build.
///
/// GENERATED-ISH: `tool/stamp_version.sh` rewrites [kVersion] during the
/// release build so the binary reports the tag it was published under. It is
/// committed rather than produced by a build step because ARCHITECTURE.md
/// rules out codegen — `dart run bin/dvm.dart` from a fresh checkout has to
/// work with nothing generated first.
///
/// The value here must match `version:` in `packages/dvm/pubspec.yaml`;
/// `test/release/version_stamp_test.dart` fails when they drift, and the
/// release build refuses a tag that disagrees with either.
library;

/// The version of this build of dvm.
const String kVersion = '0.1.0';

/// What this build is, beyond its version — empty for every ordinary build.
///
/// Semver build metadata, appended by [version] as `<kVersion>+<kBuildTag>`,
/// so an alpha reports `0.1.0+alpha.g1a2b3c4` where a release reports `0.1.0`.
/// A user who no longer remembers typing `--alpha` can still answer "what am I
/// running?" months later, and that is the whole job.
///
/// SEPARATE FROM [kVersion] ON PURPOSE, and stamped by a separate script
/// (`tool/stamp_build_tag.sh`). `tool/stamp_version.sh` refuses a version the
/// pubspec does not claim, which is what makes a published binary unable to lie
/// about its version — so an alpha cannot express itself by widening
/// [kVersion], and nothing here asks it to. The alpha build stamps [kVersion]
/// from the pubspec, exactly as a dry run does, and puts its identity here.
///
/// Nothing compares this. `dvm update` and the version notice both read
/// [kVersion], so an alpha compares as the version it was cut from and no
/// version arithmetic anywhere has to learn about build metadata.
const String kBuildTag = '';

/// Whether this process is an AOT binary produced by the release build.
///
/// The release workflow passes `-D__DVM_COMPILED__=true` to `dart compile
/// exe`; nothing else does, so this is false under `dart test`, under `dart
/// run`, and for a binary someone compiled by hand. Everything that replaces
/// the binary on disk or talks to the GitHub releases API is gated on it:
/// there is no installed binary to update when dvm is running from source,
/// and a version notice comparing a checkout against published releases would
/// be noise at best.
const bool kIsCompiled = bool.fromEnvironment('__DVM_COMPILED__');

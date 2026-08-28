/// Errors dvm reports to a human at a terminal.
///
/// Every message here is printed verbatim by `lib/dvm.dart` — no stack trace,
/// no exception class name. Write them as sentences that say what is wrong and
/// what to run next.
abstract class DvmException implements Exception {
  const DvmException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A config file — `~/.dvm/config.json` or a project `.dvmrc` — is malformed.
///
/// Never thrown for a *missing* file: absence is a normal state that resolution
/// falls through, while a typo is something the user must be told about.
class ConfigException extends DvmException {
  const ConfigException(super.message);
}

/// No resolution rule produced an SDK. This is rule 5 of the resolution order.
class ResolutionException extends DvmException {
  const ResolutionException(super.message);
}

/// A version was pinned by an earlier rule but is not present in `versions/`.
///
/// Distinct from [ResolutionException] on purpose: a caller such as `dvm use`
/// may want to install the missing version rather than fail. Resolution itself
/// never falls through to a later rule here — a pin that silently ran a
/// different SDK than the one it names would be worse than an error.
class SdkNotInstalledException extends DvmException {
  const SdkNotInstalledException(
    super.message, {
    required this.version,
    this.source,
  });

  /// The concrete version that is missing, after aliases and channels.
  final String version;

  /// Where the pin came from — a `.dvmrc` path, an env var name, the config.
  final String? source;
}

/// The host OS/architecture combination has no published Dart SDK archive.
class UnsupportedPlatformException extends DvmException {
  const UnsupportedPlatformException(super.message);
}

/// A seam whose implementation belongs to a part of the CLI that is not built
/// yet. Thrown by the placeholder returned from the `create*` factories.
class NotImplementedException extends DvmException {
  const NotImplementedException(super.message);
}

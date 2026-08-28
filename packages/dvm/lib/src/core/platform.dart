import 'exceptions.dart';

/// The `<os>` and `<arch>` tokens that appear in a dart-archive filename.
///
/// Construct with [HostPlatform.detect] in production and with the constructor
/// in tests: the host is an input, not an ambient fact.
class HostPlatform {
  const HostPlatform({required this.os, required this.arch});

  /// `macos`, `linux` or `windows`.
  final String os;

  /// `x64`, `arm64`, and on linux also `arm` and `riscv64`.
  final String arch;

  /// What the archive bucket publishes, per ARCHITECTURE.md.
  static const Map<String, Set<String>> publishedArchitectures = {
    'macos': {'x64', 'arm64'},
    'linux': {'x64', 'arm64', 'arm', 'riscv64'},
    'windows': {'x64', 'arm64'},
  };

  /// Whether an SDK archive exists for this combination.
  bool get isPublished => publishedArchitectures[os]?.contains(arch) ?? false;

  /// The SDK archive filename, e.g. `dartsdk-macos-arm64-release.zip`.
  ///
  /// Throws [UnsupportedPlatformException] rather than [detect] doing so, so
  /// that `dvm --help` and `dvm doctor` still run on a host dvm cannot serve.
  /// Use [detectSupported] when you want the failure up front instead.
  String get archiveFileName {
    if (!isPublished) throw UnsupportedPlatformException(_unsupportedMessage());
    return 'dartsdk-$os-$arch-release.zip';
  }

  /// The sibling checksum filename. Its body is `<hex> *<filename>`.
  String get checksumFileName => '$archiveFileName.sha256sum';

  /// The host dvm is running on.
  ///
  /// [platformVersion] is `Platform.version`, whose tail is the only place
  /// dart:io exposes the architecture. Callers pass it in so this stays
  /// testable; `lib/dvm.dart` supplies the real one.
  factory HostPlatform.detect(String platformVersion) {
    final match = RegExp(r'on "([a-z0-9]+)_([a-z0-9]+)"').firstMatch(
      platformVersion,
    );
    if (match == null) {
      throw UnsupportedPlatformException(
        'Cannot tell what platform this is: the Dart version string '
        '"$platformVersion" does not end in the expected `on "<os>_<arch>"`.',
      );
    }
    return HostPlatform(
      os: match.group(1)!,
      // Dart reports compressed-pointer builds as `x64c` / `arm64c`. They run
      // the same archive as their uncompressed counterpart.
      arch: match.group(2)!.replaceFirst(RegExp(r'c$'), ''),
    );
  }

  /// Like [detect], but fails immediately on a host with no published SDK.
  factory HostPlatform.detectSupported(String platformVersion) {
    final platform = HostPlatform.detect(platformVersion);
    if (!platform.isPublished) {
      throw UnsupportedPlatformException(platform._unsupportedMessage());
    }
    return platform;
  }

  String _unsupportedMessage() {
    final supported = publishedArchitectures.entries
        .map((entry) => '${entry.key} ${entry.value.join('/')}')
        .join(', ');
    return 'Dart does not publish an SDK for $os/$arch, so dvm cannot install '
        'one here. Published platforms are: $supported.';
  }

  @override
  String toString() => '$os-$arch';

  @override
  bool operator ==(Object other) =>
      other is HostPlatform && other.os == os && other.arch == arch;

  @override
  int get hashCode => Object.hash(os, arch);
}

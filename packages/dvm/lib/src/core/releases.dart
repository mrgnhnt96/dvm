import 'channel.dart';
import 'exceptions.dart';
import 'platform.dart';

/// A downloadable SDK archive and the checksum that proves it arrived intact.
class ReleaseArtifact {
  const ReleaseArtifact({
    required this.version,
    required this.fileName,
    required this.archive,
    required this.checksum,
  });

  /// The concrete version this artifact contains.
  final String version;

  /// The archive's filename, e.g. `dartsdk-macos-arm64-release.zip`. It is
  /// also the name that appears in the checksum body, which is `<hex> *<name>`.
  final String fileName;

  /// Where to download the archive from.
  final Uri archive;

  /// The sibling `.sha256sum`.
  final Uri checksum;
}

/// dvm's view of the upstream `dart-archive` bucket.
///
/// This is the only seam allowed to touch the network, and it is deliberately
/// not reachable from `resolver.dart`. Implementations live outside `core/`.
abstract class ReleaseClient {
  /// Concrete semver releases published in [channel], newest first.
  ///
  /// The bucket also carries Dart 1 build numbers (`29803`) and a `latest`
  /// entry; implementations filter those out, so every element here is a
  /// version dvm can actually install.
  Future<List<String>> listReleases(Channel channel);

  /// The concrete version [channel] currently points at.
  ///
  /// Called only by `install` and `upgrade`. Version resolution must never
  /// call this: it reads the version the channel resolved to at install time
  /// out of `config.json` instead.
  Future<String> latestVersion(Channel channel);

  /// The first channel that publishes [version], probing stable, beta, dev.
  ///
  /// A version can exist in more than one channel, which is why a bare version
  /// string needs a lookup before its download URL can be built.
  Future<Channel> channelFor(String version);

  /// The download and checksum URLs for [version] on [platform].
  ///
  /// Pure string building — no I/O — so callers can show a user exactly what
  /// will be fetched before anything is fetched.
  ReleaseArtifact artifactFor({
    required Channel channel,
    required String version,
    required HostPlatform platform,
  });
}

/// The seam `lib/dvm.dart` calls to get a [ReleaseClient].
///
/// The archive client is built by its own part of the CLI. Replace this body
/// when it lands — `lib/dvm.dart` calls this function and must not have to
/// change.
ReleaseClient createReleaseClient() => const UnimplementedReleaseClient();

/// Stands in until a real [ReleaseClient] exists.
///
/// Every method throws; constructing it does not, so `dvm --help` still works.
class UnimplementedReleaseClient implements ReleaseClient {
  const UnimplementedReleaseClient();

  Never _unimplemented() => throw const NotImplementedException(
        'Talking to the Dart release archive is not implemented yet.',
      );

  @override
  Future<List<String>> listReleases(Channel channel) => _unimplemented();

  @override
  Future<String> latestVersion(Channel channel) => _unimplemented();

  @override
  Future<Channel> channelFor(String version) => _unimplemented();

  @override
  ReleaseArtifact artifactFor({
    required Channel channel,
    required String version,
    required HostPlatform platform,
  }) =>
      _unimplemented();
}

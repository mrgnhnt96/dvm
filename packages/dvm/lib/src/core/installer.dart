import 'package:file/file.dart';

import '../archive/sdk_installer.dart';
import 'channel.dart';
import 'exceptions.dart';
import 'paths.dart';
import 'platform.dart';
import 'releases.dart';

/// Puts SDKs into `~/.dvm/versions` and says whether one is already there.
///
/// Implementations download, verify the sha256, extract into `~/.dvm/cache`,
/// and `rename()` the result into place, so an interrupted install can never
/// leave a half-extracted directory that later looks installed.
abstract class Installer {
  /// Whether [version] is installed and usable.
  ///
  /// Stronger than "the directory exists": a directory without a `bin/dart`
  /// inside it is wreckage, not an installation.
  bool isInstalled(String version);

  /// Installs [version], returning its directory under `~/.dvm/versions`.
  ///
  /// Already-installed versions return immediately unless [force] is set.
  /// [channel] is optional because a bare version can be found by probing the
  /// channels; passing it when it is already known skips that lookup.
  Future<Directory> install(
    String version, {
    Channel? channel,
    bool force = false,
  });
}

/// The seam `DvmContext.wire` calls to get an [Installer].
///
/// It takes the collaborators an installer cannot do without — a real one has
/// to know where `~/.dvm` is and where to fetch archives from — so that
/// `lib/dvm.dart` still never names an implementation.
Installer createInstaller({
  required FileSystem fileSystem,
  required DvmPaths paths,
  required ReleaseClient releases,
  required HostPlatform Function() hostPlatform,
  required StringSink progress,
  required bool progressIsTerminal,
}) =>
    SdkInstaller(
      fileSystem: fileSystem,
      paths: paths,
      releases: releases,
      hostPlatform: hostPlatform,
      progress: progress,
      progressIsTerminal: progressIsTerminal,
    );

/// Stands in until a real [Installer] exists.
class UnimplementedInstaller implements Installer {
  const UnimplementedInstaller();

  Never _unimplemented() => throw const NotImplementedException(
        'Installing SDKs is not implemented yet.',
      );

  @override
  bool isInstalled(String version) => _unimplemented();

  @override
  Future<Directory> install(
    String version, {
    Channel? channel,
    bool force = false,
  }) =>
      _unimplemented();
}

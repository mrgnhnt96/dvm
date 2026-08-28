import 'package:file/file.dart';

import 'channel.dart';
import 'exceptions.dart';

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

/// The seam `lib/dvm.dart` calls to get an [Installer].
///
/// Replace this body when the installer lands; `lib/dvm.dart` calls this
/// function and must not have to change.
Installer createInstaller() => const UnimplementedInstaller();

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

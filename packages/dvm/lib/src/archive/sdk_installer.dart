import 'dart:math';

import 'package:file/file.dart';
import 'package:http/http.dart' as http;

import '../core/channel.dart';
import '../core/installer.dart';
import '../core/paths.dart';
import '../core/platform.dart';
import '../core/releases.dart';
import '../core/verbose.dart';
import 'dart_archive_client.dart';
import 'dart_archive_exception.dart';
import 'sdk_downloader.dart';
import 'sdk_extractor.dart';

/// The real [Installer]: download, verify, extract, rename into place.
///
/// Everything happens under `~/.dvm/cache` and only a single [Directory.rename]
/// publishes the result. That is what makes an install atomic — a failure at
/// any point before the rename leaves `versions/` exactly as it was, so a
/// half-extracted SDK can never be mistaken for an installed one.
class SdkInstaller implements Installer {
  SdkInstaller({
    required this.fileSystem,
    required this.paths,
    required this.releases,
    required HostPlatform Function() hostPlatform,
    required StringSink progress,
    bool progressIsTerminal = false,
    http.Client? httpClient,
    SdkDownloader? downloader,
    SdkExtractor? extractor,
    ModeApplier? modeApplier,
    VerboseLog? verbose,
  })  : _hostPlatform = hostPlatform,
        _verbose = verbose ?? VerboseLog.disabled,
        _progress = progress,
        _progressIsTerminal = progressIsTerminal,
        _injectedDownloader = downloader,
        _httpClient = httpClient,
        _extractor = extractor ?? const ZipSdkExtractor(),
        _modeApplier = modeApplier ?? const ChmodModeApplier();

  final FileSystem fileSystem;
  final DvmPaths paths;
  final ReleaseClient releases;

  final HostPlatform Function() _hostPlatform;
  final StringSink _progress;
  final bool _progressIsTerminal;
  final SdkExtractor _extractor;
  final ModeApplier _modeApplier;
  final SdkDownloader? _injectedDownloader;
  final http.Client? _httpClient;
  final VerboseLog _verbose;

  /// Built on first use; see [DartArchiveClient] for why that matters.
  late final SdkDownloader _downloader = _injectedDownloader ??
      SdkDownloader(
        fileSystem: fileSystem,
        progress: _progress,
        progressIsTerminal: _progressIsTerminal,
        httpClient: _httpClient,
        verbose: _verbose,
      );

  final Random _random = Random();

  @override
  bool isInstalled(String version) =>
      paths.dartExecutable(paths.versionDir(version)).existsSync();

  @override
  Future<Directory> install(
    String version, {
    Channel? channel,
    bool force = false,
  }) async {
    final target = paths.versionDir(version);
    if (!force && isInstalled(version)) {
      _verbose.log(
        VerboseArea.install,
        () => 'Dart $version is already at ${target.path}; nothing to do',
      );
      return target;
    }

    final platform = _hostPlatform();
    final resolvedChannel = channel ?? await releases.channelFor(version);
    final artifact = releases.artifactFor(
      channel: resolvedChannel,
      version: version,
      platform: platform,
    );
    _verbose.log(
      VerboseArea.install,
      () => 'installing Dart $version from ${resolvedChannel.token} for '
          '${platform.os}-${platform.arch}',
    );
    _verbose.log(VerboseArea.install, () => '  archive ${artifact.archive}');
    _verbose.log(VerboseArea.install, () => '  checksum ${artifact.checksum}');

    // One scratch directory per attempt, so two dvm processes installing
    // different versions at once cannot tread on each other's downloads.
    final scratch = fileSystem.directory(
      fileSystem.path.join(paths.cacheDir.path, _scratchName(version)),
    );
    scratch.createSync(recursive: true);
    _verbose.log(VerboseArea.fs, () => 'created scratch ${scratch.path}');

    try {
      final zip = fileSystem.file(
        fileSystem.path.join(scratch.path, artifact.fileName),
      );
      _progress.writeln('Downloading Dart $version (${platform.os}-'
          '${platform.arch}, ${resolvedChannel.token})');
      await _downloader.download(artifact, zip);

      final unpacked = fileSystem.directory(
        fileSystem.path.join(scratch.path, 'unpacked'),
      );
      _verbose.log(
        VerboseArea.install,
        () => 'extracting ${zip.path} into ${unpacked.path}',
      );
      final extracting = _verbose.stopwatch();
      final modes = await _extractor.extract(
        archive: zip,
        destination: unpacked,
      );
      _verbose.log(
        VerboseArea.install,
        () => '  ${modes.length} files in '
            '${extracting!.elapsedMilliseconds}ms',
      );
      final sdkRoot = sdkRootWithin(unpacked, paths.dartExecutableName);
      _verbose.log(VerboseArea.install, () => '  SDK root ${sdkRoot.path}');

      // Modes are applied before the rename so that what lands in versions/ is
      // already usable; an SDK published with a non-executable bin/dart would
      // otherwise be indistinguishable from a successful install.
      await _modeApplier.apply(modes);

      if (!paths.dartExecutable(sdkRoot).existsSync()) {
        throw DartArchiveException(
          'The extracted Dart $version has no '
          'bin/${paths.dartExecutableName}, so it would not be runnable.',
        );
      }

      paths.versionsDir.createSync(recursive: true);
      if (target.existsSync()) {
        if (!force) return target;
        target.deleteSync(recursive: true);
      }

      // The one publishing step. Both sides live under ~/.dvm, so this is a
      // same-filesystem rename and therefore atomic.
      sdkRoot.renameSync(target.path);
      _verbose.log(
        VerboseArea.fs,
        () => 'renamed ${sdkRoot.path} -> ${target.path} (the atomic publish)',
      );
      return target;
    } finally {
      // The scratch directory holds a ~225MB zip and a full extracted SDK.
      // Leaving either behind on failure would quietly fill the user's disk.
      if (scratch.existsSync()) {
        scratch.deleteSync(recursive: true);
        _verbose.log(
          VerboseArea.fs,
          () => 'removed scratch ${scratch.path}',
        );
      }
    }
  }

  String _scratchName(String version) {
    final suffix = _random.nextInt(1 << 32).toRadixString(36);
    return 'install-$version-$suffix';
  }
}

import 'dart:io' as io;

import 'package:archive/archive.dart';
import 'package:file/file.dart';

import 'dart_archive_exception.dart';

/// Unpacks an SDK zip into a directory.
///
/// A seam rather than a bare function call so that a test can make an extract
/// fail halfway through and assert that nothing was left behind.
abstract class SdkExtractor {
  /// Extracts [archive] into [destination].
  ///
  /// Returns the unix mode recorded in the zip for each extracted path. The
  /// modes are returned rather than applied because applying them is a
  /// platform-specific step the caller may skip entirely — see [ModeApplier].
  Future<Map<String, int>> extract({
    required File archive,
    required Directory destination,
  });
}

/// The real [SdkExtractor], over `package:archive`'s zip decoder.
class ZipSdkExtractor implements SdkExtractor {
  const ZipSdkExtractor();

  @override
  Future<Map<String, int>> extract({
    required File archive,
    required Directory destination,
  }) async {
    final Archive decoded;
    try {
      decoded = ZipDecoder().decodeBytes(archive.readAsBytesSync());
    } on Object catch (error) {
      throw DartArchiveException(
        'Could not unpack ${archive.basename}: $error',
      );
    }

    destination.createSync(recursive: true);
    final modes = <String, int>{};

    for (final entry in decoded) {
      final target = _safeJoin(destination, entry.name);
      // A zip entry naming `../` outside the destination is how an archive
      // escapes the directory it is supposed to be unpacked into. Skip it
      // rather than trusting the archive's own paths.
      if (target == null) continue;

      if (entry.isDirectory) {
        destination.fileSystem.directory(target).createSync(recursive: true);
        continue;
      }

      final file = destination.fileSystem.file(target);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(entry.readBytes() ?? const <int>[]);
      modes[target] = entry.mode;
    }

    return modes;
  }

  /// [name] resolved inside [destination], or null if it escapes it.
  String? _safeJoin(Directory destination, String name) {
    final context = destination.fileSystem.path;
    final root = context.canonicalize(destination.path);
    final target = context.canonicalize(
      context.join(destination.path, context.normalize(name)),
    );
    if (target == root || !context.isWithin(root, target)) return null;
    return target;
  }
}

/// Applies the unix modes an SDK zip carries.
///
/// `package:archive` records `ArchiveFile.mode` but the `Archive`-based
/// extraction helpers never apply it, so without this pass everything under
/// `bin/` lands non-executable and the installed SDK is inert.
abstract class ModeApplier {
  Future<void> apply(Map<String, int> modeByPath);
}

/// Applies modes by shelling out to `chmod`.
///
/// Dart exposes no `chmod`, so a subprocess is the only route that does not
/// pull in an FFI dependency. Paths are grouped by mode and passed in batches:
/// an SDK is a few thousand files but only a couple of distinct modes, so this
/// is two or three `chmod` calls rather than thousands.
class ChmodModeApplier implements ModeApplier {
  const ChmodModeApplier();

  /// How many paths to hand a single `chmod`, well under any ARG_MAX.
  static const int _batchSize = 500;

  @override
  Future<void> apply(Map<String, int> modeByPath) async {
    // Windows has no unix modes and no chmod; the zip's mode bits mean nothing
    // there and executability comes from the file extension instead.
    if (io.Platform.isWindows) return;

    final byMode = <int, List<String>>{};
    for (final entry in modeByPath.entries) {
      // Only the permission bits; the high bits are the file type.
      final permissions = entry.value & 0xFFF;
      if (permissions == 0) continue;
      byMode.putIfAbsent(permissions, () => <String>[]).add(entry.key);
    }

    for (final entry in byMode.entries) {
      final mode = entry.value.isEmpty
          ? null
          : entry.key.toRadixString(8).padLeft(3, '0');
      if (mode == null) continue;
      for (var i = 0; i < entry.value.length; i += _batchSize) {
        final batch = entry.value.sublist(
          i,
          (i + _batchSize).clamp(0, entry.value.length),
        );
        final result = await io.Process.run('chmod', [mode, ...batch]);
        if (result.exitCode != 0) {
          throw DartArchiveException(
            'Could not set permissions on the extracted SDK: '
            '${result.stderr}',
          );
        }
      }
    }
  }
}

/// A [ModeApplier] that does nothing, for hosts and tests without a real
/// filesystem underneath.
class NoopModeApplier implements ModeApplier {
  const NoopModeApplier();

  @override
  Future<void> apply(Map<String, int> modeByPath) async {}
}

/// The directory inside [extracted] that is actually the SDK root.
///
/// The published zips wrap everything in a single top-level `dart-sdk/`, so
/// renaming the extraction directory itself into `versions/<version>` would
/// give `versions/3.13.2/dart-sdk/bin/dart`. Finding `bin/` instead of
/// hardcoding the wrapper's name keeps this working if it is ever dropped.
Directory sdkRootWithin(Directory extracted, String dartExecutableName) {
  // The CANDIDATE's own path context, not the top-level `p`. The latter is
  // whatever style the host runs, and this function is handed a directory that
  // may belong to an injected filesystem with a style of its own. Joining with
  // the host's separator produced the literal filename `bin\dart` on a
  // posix-style filesystem when the suite first ran on Windows, and every
  // install in the suite failed with "no bin/dart was found in it".
  bool looksLikeSdk(Directory candidate) => candidate.fileSystem
      .file(candidate.fileSystem.path.join(
        candidate.path,
        'bin',
        dartExecutableName,
      ))
      .existsSync();

  if (looksLikeSdk(extracted)) return extracted;

  final children = extracted.listSync().whereType<Directory>();
  for (final child in children) {
    if (looksLikeSdk(child)) return child;
  }

  throw DartArchiveException(
    'The downloaded archive does not contain a Dart SDK: no '
    'bin/$dartExecutableName was found in it.',
  );
}

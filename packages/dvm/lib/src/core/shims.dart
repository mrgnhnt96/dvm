import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;

import '../archive/sdk_extractor.dart';
import 'exceptions.dart';
import 'paths.dart';

/// Writes and reads `~/.dvm/shims/dart`.
///
/// The shim is the whole PATH integration: two lines of shell that `exec` into
/// `dvm exec dart`, so the only cost per `dart` invocation is a shell start
/// plus dvm's own. `exec` matters — without it the shell stays alive as a
/// parent for the entire life of every Dart process on the machine.
///
/// The path to the dvm binary is baked in at write time rather than looked up
/// on PATH, because the shim's whole job is to run *before* PATH resolution is
/// trustworthy: a shim that said `exec dvm exec dart` would find whatever `dvm`
/// the user's shell resolves — which, on a machine carrying the older
/// cbracken/dvm, is a shell function that knows nothing about this tool.
class ShimWriter {
  ShimWriter({
    required this.fileSystem,
    required this.paths,
    ModeApplier? modes,
  }) : _modes = modes ?? _defaultModes(fileSystem);

  final FileSystem fileSystem;
  final DvmPaths paths;
  final ModeApplier _modes;

  /// `0755` — readable and executable by everyone, writable by the owner.
  ///
  /// Dart has no octal literals; this is the same number `chmod 755` sets.
  static const int shimMode = 0x1ED;

  /// Creates the shims directory and writes every shim for this platform.
  ///
  /// [dvmExecutable] must be the absolute path of the dvm binary — normally
  /// `Platform.resolvedExecutable`, resolved by the caller so that a dvm that
  /// was moved or reinstalled elsewhere writes a shim naming where it actually
  /// is.
  ///
  /// Returns the file it wrote.
  Future<File> write(String dvmExecutable) async {
    _validateTarget(dvmExecutable);

    final shim = paths.dartShim;
    shim.parent.createSync(recursive: true);
    shim.writeAsStringSync(body(dvmExecutable));

    // Windows has no mode bits: a `.bat` is executable because of its
    // extension, and there is no chmod to call.
    if (!_isWindows) {
      await _modes.apply({shim.path: shimMode});
    }
    return shim;
  }

  /// The contents of the shim naming [dvmExecutable].
  ///
  /// `"$@"` / `%*` forward the arguments with their word boundaries intact —
  /// unquoted, `dart run tool/x.dart --name "two words"` would arrive as four
  /// arguments.
  String body(String dvmExecutable) {
    if (_isWindows) {
      // No `exec` on cmd; the batch file's exit code is the last command's,
      // which is dvm's, which is the SDK's.
      return '@echo off\r\n"$dvmExecutable" exec dart %*\r\n';
    }
    return '#!/bin/sh\nexec "$dvmExecutable" exec dart "\$@"\n';
  }

  /// The dvm binary a shim at [file] names, or null when the file is not a
  /// shim this writer produced.
  ///
  /// Null is deliberately ambiguous between "not ours" and "hand-edited beyond
  /// recognition", because the remedy for both is the same: run `dvm setup`
  /// again. It is never returned for a file that could not be read — that
  /// throws, so a caller cannot mistake a permission error for a verdict.
  String? targetOf(File file) {
    final contents = file.readAsStringSync();
    final match = _targetPattern.firstMatch(contents);
    return match?.group(1);
  }

  /// The quoted path in `exec "<path>" exec dart` and its `.bat` equivalent.
  ///
  /// Anchored on the `exec dart` that follows it, so a shim carrying a comment
  /// or a `set -e` above the exec line still parses.
  static final RegExp _targetPattern = RegExp(r'"([^"\n]+)"\s+exec\s+dart\b');

  /// Rejects a target that cannot survive being written into a shell script.
  void _validateTarget(String dvmExecutable) {
    if (dvmExecutable.trim().isEmpty) {
      throw const ConfigException(
        'dvm does not know where its own binary is, so it cannot write a shim '
        'that runs it.',
      );
    }
    // The path is written inside double quotes. A path containing one would
    // end the quoting and turn the rest of the path into arguments — a shim
    // that runs something other than dvm is worse than no shim at all.
    if (dvmExecutable.contains('"') || dvmExecutable.contains('\n')) {
      throw ConfigException(
        'The path to the dvm binary contains a quote or a newline '
        '($dvmExecutable), which cannot be written into a shell script '
        'safely. Move dvm somewhere with a plainer path and run dvm setup '
        'again.',
      );
    }
    if (!fileSystem.path.isAbsolute(dvmExecutable)) {
      throw ConfigException(
        'The path to the dvm binary must be absolute, but it is '
        '"$dvmExecutable". A relative path in a shim resolves against '
        "whatever directory the user happens to be in when they type 'dart'.",
      );
    }
  }

  bool get _isWindows => fileSystem.path.style == p.Style.windows;

  /// chmod is an operation on the *real* filesystem.
  ///
  /// Running it against a path that came from a `MemoryFileSystem` would not
  /// fail harmlessly: `/etc/hosts` exists in a memory filesystem and on the
  /// machine, and the second one is the one chmod would find. So the real
  /// applier is used only when the filesystem being written to is the local
  /// one, which is also what keeps `dvm setup` testable end to end.
  static ModeApplier _defaultModes(FileSystem fileSystem) =>
      fileSystem is LocalFileSystem
          ? const ChmodModeApplier()
          : const NoopModeApplier();
}

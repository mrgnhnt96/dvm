import 'package:file/file.dart';
import 'package:path/path.dart' as p;

import 'exceptions.dart';

/// The `~/.dvm` layout, as a type.
///
/// Nothing else in the CLI may spell these paths by hand: a second spelling of
/// `versions/` is a bug that only shows up on someone else's machine.
class DvmPaths {
  DvmPaths({required this.fileSystem, required Map<String, String> environment})
      : _environment = environment;

  final FileSystem fileSystem;
  final Map<String, String> _environment;

  /// Overrides the dvm home. Set by tests, by CI, and by users who keep their
  /// SDKs on another volume.
  static const String homeVariable = 'DVM_HOME';

  /// The dvm home directory — `$DVM_HOME`, else `~/.dvm`.
  ///
  /// Lazy so that constructing [DvmPaths] never throws: `dvm --help` has to
  /// work on a machine with no `HOME` set.
  late final Directory home = _resolveHome();

  Directory get versionsDir => _child(home, 'versions');
  Directory get shimsDir => _child(home, 'shims');
  Directory get cacheDir => _child(home, 'cache');
  File get configFile => fileSystem.file(_join(home.path, 'config.json'));

  /// Where the SDK for [version] is installed. Existence is not implied.
  Directory versionDir(String version) => _child(versionsDir, version);

  /// The `dart` executable inside an extracted SDK at [sdkDir].
  File dartExecutable(Directory sdkDir) =>
      fileSystem.file(_join(sdkDir.path, 'bin', dartExecutableName));

  /// `dart` everywhere, `dart.exe` on Windows.
  String get dartExecutableName => isWindows ? 'dart.exe' : 'dart';

  /// The names a real `dart` can have on PATH, most likely first.
  ///
  /// Windows resolves a bare `dart` through PATHEXT, so both spellings have to
  /// be probed when scanning PATH by hand.
  List<String> get pathExecutableNames =>
      isWindows ? const ['dart.exe', 'dart.bat'] : const ['dart'];

  /// The shim dvm installs on PATH.
  File get dartShim =>
      fileSystem.file(_join(shimsDir.path, isWindows ? 'dart.bat' : 'dart'));

  /// The gitignored per-project directory holding the IDE symlink.
  Directory projectDvmDir(Directory project) => _child(project, '.dvm');

  /// The gitignored per-project symlink to the resolved SDK, for IDEs.
  Link projectSdkLink(Directory project) =>
      fileSystem.link(_join(project.path, '.dvm', 'dart_sdk'));

  /// The committed pin file for [project].
  File dvmrcFile(Directory project) =>
      fileSystem.file(_join(project.path, dvmrcFileName));

  /// The name of the per-project pin file.
  static const String dvmrcFileName = '.dvmrc';

  /// Whether the paths this resolves are Windows paths.
  ///
  /// The FILESYSTEM's style rather than the host's, because every path
  /// question here is about the filesystem being written to -- which under
  /// test is an injected one that may be styled differently from the machine
  /// running the suite.
  bool get isWindows => fileSystem.path.style == p.Style.windows;

  String _join(String a, [String? b, String? c]) =>
      fileSystem.path.join(a, b, c);

  Directory _child(Directory parent, String name) =>
      fileSystem.directory(_join(parent.path, name));

  Directory _resolveHome() {
    final override = _environment[homeVariable]?.trim();
    if (override != null && override.isNotEmpty) {
      return fileSystem.directory(_absolute(override));
    }

    // USERPROFILE first on Windows, HOME first elsewhere, but accept either:
    // Git Bash and MSYS set HOME on Windows, and some containers set only
    // USERPROFILE.
    final candidates = isWindows
        ? const ['USERPROFILE', 'HOME']
        : const ['HOME', 'USERPROFILE'];
    for (final variable in candidates) {
      final value = _environment[variable]?.trim();
      if (value != null && value.isNotEmpty) {
        return fileSystem.directory(_absolute(_join(value, '.dvm')));
      }
    }

    throw ConfigException(
      'Cannot work out where to keep your SDKs: neither $homeVariable nor '
      '${candidates.join(' nor ')} is set in the environment. '
      'Set $homeVariable to the directory dvm should use.',
    );
  }

  String _absolute(String path) {
    final normalized = fileSystem.path.normalize(path);
    if (fileSystem.path.isAbsolute(normalized)) return normalized;
    return fileSystem.path.normalize(
      _join(fileSystem.currentDirectory.path, normalized),
    );
  }
}

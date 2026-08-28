import 'package:file/file.dart';
import 'package:path/path.dart' as p;

import 'paths.dart';

/// The shell the user is in, as far as `$SHELL` can say.
enum ShellKind {
  zsh('zsh'),
  bash('bash'),
  fish('fish'),

  /// Anything else, including "the environment did not say".
  posix('sh');

  const ShellKind(this.token);

  /// How the shell is spelled in `$SHELL` and in output.
  final String token;
}

/// Why a line in a startup file would win over the shim on PATH.
enum ShadowKind {
  /// `dvm() { ... }` or fish's `function dvm`.
  function('a shell function named dvm'),

  /// `alias dvm=...`.
  alias('a shell alias named dvm'),

  /// Sourcing the older cbracken/dvm, which defines the function itself.
  legacySource("a line sourcing the older cbracken/dvm's shell script");

  const ShadowKind(this.description);

  /// A noun phrase that completes "… defines `<description>`".
  final String description;
}

/// One line in a startup file that shadows the `dvm` binary.
class ShellShadow {
  const ShellShadow({
    required this.kind,
    required this.file,
    required this.line,
    required this.text,
  });

  final ShadowKind kind;

  /// The startup file the line is in.
  final File file;

  /// Its 1-based line number, so the user can jump straight to it.
  final int line;

  /// The line itself, trimmed.
  final String text;

  /// `~/.zshrc:12: [ -s "$HOME/.dvm/scripts/dvm" ] && . …`
  String describe() => '${file.path}:$line: $text';
}

/// What a scan of the startup files found, including what it could not read.
///
/// [unreadable] is separate from an empty [shadows] on purpose: "there is no
/// shadowing function" and "we could not open the file that would have one" are
/// different answers, and reporting the second as the first is how a user ends
/// up being told everything is fine while their shell runs a different dvm.
class ShellScan {
  const ShellScan({required this.shadows, required this.unreadable});

  final List<ShellShadow> shadows;

  /// Files that exist but could not be read, with the reason.
  final Map<String, String> unreadable;

  bool get isClean => shadows.isEmpty && unreadable.isEmpty;
}

/// The remains of an older `cbracken/dvm` install in the same `~/.dvm`.
///
/// That tool keeps its SDKs in `darts/`, its shell function in `scripts/dvm`,
/// and per-project setups in `environments/`. dvm takes the directory over, so
/// these can sit alongside a working install — they only matter because the
/// shell function beats any binary on PATH.
class LegacyDvmInstall {
  const LegacyDvmInstall({required this.script, required this.directories});

  /// `~/.dvm/scripts/dvm`, when it is there. This is the file a `.zshrc` line
  /// sources, and the reason `dvm` can be a shell function.
  final File? script;

  /// The legacy directories that are present — `darts/`, `environments/`.
  final List<Directory> directories;

  bool get isPresent => script != null || directories.isNotEmpty;

  /// Looks for the legacy layout under the dvm home in [paths].
  static LegacyDvmInstall detect(DvmPaths paths) {
    final fileSystem = paths.fileSystem;
    final home = paths.home.path;

    final script = fileSystem.file(
      fileSystem.path.join(home, 'scripts', 'dvm'),
    );
    final directories = <Directory>[
      for (final name in const ['darts', 'environments'])
        fileSystem.directory(fileSystem.path.join(home, name)),
    ].where((directory) => directory.existsSync()).toList();

    return LegacyDvmInstall(
      script: script.existsSync() ? script : null,
      directories: directories,
    );
  }
}

/// The shell facts `setup` and `doctor` both need.
///
/// Everything here is derived from the injected environment and filesystem —
/// no `dart:io` — so a test can put a synthetic `$SHELL` and a fake `.zshrc` in
/// front of it without going near the real one.
class ShellFacts {
  ShellFacts({
    required this.fileSystem,
    required Map<String, String> environment,
  }) : _environment = environment;

  final FileSystem fileSystem;
  final Map<String, String> _environment;

  /// The raw `$SHELL`, or null when it is not set — which is normal in CI and
  /// in a `Process.start` with a hand-built environment.
  String? get shellPath {
    final value = _environment['SHELL']?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Which shell [shellPath] names, defaulting to [ShellKind.posix].
  late final ShellKind kind = _detectKind();

  /// The user's home directory, or null if the environment does not say.
  ///
  /// This is the plain home, not `~/.dvm`: startup files live in it.
  late final Directory? home = _detectHome();

  /// The startup file to add the PATH line to, or null with no home.
  ///
  /// One file, named for [kind], because `setup` has to print a single
  /// instruction. It may well not exist yet; that is not an error, a user with
  /// no `.zshrc` still needs to be told to create one.
  File? get primaryRcFile {
    final names = switch (kind) {
      ShellKind.zsh => const ['.zshrc'],
      ShellKind.bash => const ['.bashrc'],
      ShellKind.fish => const ['.config', 'fish', 'config.fish'],
      ShellKind.posix => const ['.profile'],
    };
    return _inHome(names);
  }

  /// Every startup file worth scanning for a shadowing definition.
  ///
  /// Deliberately not filtered by [kind]. A `dvm` function left in `.zshrc` is
  /// what breaks a zsh login even if `$SHELL` says something else right now,
  /// and `$SHELL` is exactly the variable that is wrong inside a subshell, an
  /// editor terminal, or a CI runner.
  List<File> get rcCandidates {
    const relative = <List<String>>[
      ['.zshrc'],
      ['.zshenv'],
      ['.zprofile'],
      ['.zlogin'],
      ['.bashrc'],
      ['.bash_profile'],
      ['.bash_login'],
      ['.profile'],
      ['.config', 'fish', 'config.fish'],
    ];
    return [
      for (final names in relative)
        if (_inHome(names) case final file?) file,
    ];
  }

  /// The line to add to [primaryRcFile] so the shims win.
  ///
  /// Prepending is the whole contract: a `dart` earlier on PATH is found first
  /// and the shim never runs.
  String pathLine(Directory shims) => switch (kind) {
        // fish_add_path is idempotent and does the right thing with the
        // universal path variable, which a bare `set -gx` does not.
        ShellKind.fish => 'fish_add_path --prepend ${shims.path}',
        _ => 'export PATH="${shims.path}:\$PATH"',
      };

  /// Reads every candidate startup file, looking for something that would win
  /// over the `dvm` binary on PATH.
  ShellScan scanForShadows() {
    final shadows = <ShellShadow>[];
    final unreadable = <String, String>{};

    for (final file in rcCandidates) {
      if (!file.existsSync()) continue;

      final List<String> lines;
      try {
        lines = file.readAsLinesSync();
      } on FileSystemException catch (error) {
        unreadable[file.path] = error.message;
        continue;
      }

      for (var index = 0; index < lines.length; index++) {
        final text = lines[index].trim();
        // A commented-out definition is what a user leaves behind after
        // fixing this, and reporting it would send them back to a file that
        // is already correct.
        if (text.isEmpty || text.startsWith('#')) continue;

        final kind = _classify(text);
        if (kind == null) continue;
        shadows.add(
          ShellShadow(
            kind: kind,
            file: file,
            line: index + 1,
            text: text,
          ),
        );
      }
    }

    return ShellScan(shadows: shadows, unreadable: unreadable);
  }

  /// Which kind of shadow [line] is, or null if it is an ordinary line.
  ShadowKind? _classify(String line) {
    if (_legacyScriptPattern.hasMatch(line)) return ShadowKind.legacySource;
    if (_aliasPattern.hasMatch(line)) return ShadowKind.alias;
    if (_functionPattern.hasMatch(line) ||
        _fishFunctionPattern.hasMatch(line)) {
      return ShadowKind.function;
    }
    return null;
  }

  /// `dvm() {`, `dvm ()`, and the `{` on the next line variant.
  static final RegExp _functionPattern = RegExp(r'^dvm\s*\(\s*\)');

  /// ksh/bash/fish `function dvm`.
  static final RegExp _fishFunctionPattern = RegExp(r'^function\s+dvm\b');

  static final RegExp _aliasPattern = RegExp(r'^alias\s+dvm\s*=');

  /// Any mention of the older tool's shell script, however it is sourced —
  /// `. "$HOME/.dvm/scripts/dvm"`, `source ~/.dvm/scripts/dvm`, and the
  /// `[ -s … ] &&` guard the old README hands out.
  static final RegExp _legacyScriptPattern =
      RegExp(r'\.dvm[/\\]scripts[/\\]dvm\b');

  ShellKind _detectKind() {
    final path = shellPath;
    if (path == null) return ShellKind.posix;
    // Basename, because $SHELL is a path: /bin/zsh, /opt/homebrew/bin/fish.
    final name = p.posix.basename(path).toLowerCase();
    for (final kind in ShellKind.values) {
      if (name == kind.token || name.endsWith(kind.token)) return kind;
    }
    return ShellKind.posix;
  }

  Directory? _detectHome() {
    for (final variable in const ['HOME', 'USERPROFILE']) {
      final value = _environment[variable]?.trim();
      if (value != null && value.isNotEmpty) {
        return fileSystem.directory(value);
      }
    }
    return null;
  }

  File? _inHome(List<String> names) {
    final directory = home;
    if (directory == null) return null;
    return fileSystem.file(
      fileSystem.path.joinAll([directory.path, ...names]),
    );
  }
}

import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:file/file.dart';

import '../core/context.dart';
import '../core/exceptions.dart';
import '../core/shell.dart';
import '../core/shims.dart';

/// `dvm setup` — Install the shims and print the PATH line to add.
///
/// Writes the shim, then tells the user the one line to add to their shell's
/// startup file. It deliberately does **not** edit that file: a version manager
/// that rewrites `.zshrc` behind someone's back is a version manager people
/// stop trusting, and the line differs enough between shells and setups that
/// getting it wrong silently breaks their login shell.
class SetupCommand extends Command<int> {
  SetupCommand({required this.context, String Function()? dvmExecutable})
      : _dvmExecutable = dvmExecutable ?? _resolvedExecutable {
    argParser.addOption(
      'dvm-path',
      valueHelp: 'path',
      help: 'The dvm binary to bake into the shim. Defaults to the running '
          'one; needed when running from source.',
    );
  }

  final DvmContext context;

  /// Where the running dvm binary is. Injected so a test can drive `setup`
  /// without the answer depending on how the test runner was launched.
  final String Function() _dvmExecutable;

  static String _resolvedExecutable() => io.Platform.resolvedExecutable;

  @override
  String get name => 'setup';

  @override
  String get description => 'Install the shims and print the PATH line to add.';

  @override
  Future<int> run() async {
    final binary = _resolveDvmBinary();
    final writer = ShimWriter(
      fileSystem: context.fileSystem,
      paths: context.paths,
    );
    final shim = await writer.write(binary.path);

    context.out
      ..writeln('Wrote ${shim.path}')
      ..writeln('  -> ${binary.path} exec dart')
      ..writeln();

    _printPathInstructions();
    final conflicts = _reportConflicts();

    context.out
      ..writeln()
      ..writeln('Then check it with: dvm doctor');

    // A conflict makes the shim inert, so `setup` reporting success would be
    // a lie the user only finds out about the next time they run `dart`.
    return conflicts ? 1 : 0;
  }

  /// The dvm binary to bake into the shim.
  ///
  /// `--dvm-path` wins, then the running executable. Running from source is
  /// refused rather than guessed at: under `dart run bin/dvm.dart`, the
  /// resolved executable is the *Dart VM*, and a shim reading `exec /…/dart
  /// exec dart "$@"` would hand `exec dart` to the SDK as arguments on every
  /// `dart` invocation on the machine.
  File _resolveDvmBinary() {
    final override = argResults!.option('dvm-path')?.trim();
    if (override != null && override.isNotEmpty) {
      final file = context.fileSystem.file(_absolute(override));
      if (!file.existsSync()) {
        throw ConfigException(
          '--dvm-path names ${file.path}, which does not exist.',
        );
      }
      return file;
    }

    final resolved = _dvmExecutable();
    if (_isDartVm(resolved)) {
      throw ConfigException(
        'dvm is running from source (via $resolved), so it cannot tell where '
        'a dvm binary lives, and a shim pointing at the Dart VM would break '
        'every `dart` on this machine.\n'
        'Compile it first:  dart compile exe bin/dvm.dart -o /usr/local/bin/dvm\n'
        'Or name the binary: dvm setup --dvm-path <path to dvm>',
      );
    }
    return context.fileSystem.file(resolved);
  }

  /// Whether [path] names the Dart VM rather than a dvm binary.
  ///
  /// The last segment after EITHER separator, rather than
  /// `context.fileSystem.path.basename`. [path] comes from
  /// `Platform.resolvedExecutable`, so it is always spelled the way the host
  /// spells paths, while the injected filesystem may be a memory one with a
  /// style of its own. Asking a posix-style context for the basename of
  /// `C:\...\bin\dart.exe` returns the whole string, this guard does not
  /// fire, and the user gets a confusing complaint about absolute paths from
  /// [ShimWriter] instead of the one sentence that tells them what to do.
  bool _isDartVm(String path) {
    final segment = path.split(RegExp(r'[/\\]')).last;
    return segment == 'dart' || segment == 'dart.exe';
  }

  /// The PATH line, named for the shell the user is actually in.
  void _printPathInstructions() {
    final shell = ShellFacts(
      fileSystem: context.fileSystem,
      environment: context.environment,
    );
    final line = shell.pathLine(context.paths.shimsDir);
    final rcFile = shell.primaryRcFile;

    if (rcFile == null) {
      // No HOME and no USERPROFILE: a container, or a hand-built environment.
      // There is no file to name, but the line is still the answer.
      context.out
        ..writeln('Add this to your shell startup file:')
        ..writeln()
        ..writeln('  $line');
      return;
    }

    final verb = rcFile.existsSync() ? 'Add this line to' : 'Create';
    context.out
      ..writeln('$verb ${rcFile.path} '
          '(${shell.shellPath ?? 'no \$SHELL set, assuming ${shell.kind.token}'}):')
      ..writeln()
      ..writeln('  $line')
      ..writeln()
      ..writeln('It has to go ahead of anything else that puts a dart on '
          'PATH, and it only takes effect in shells started after you save '
          'the file.');
  }

  /// Says loudly when something already on this machine will beat the shim.
  ///
  /// Returns whether anything was found. This is the case the maintainer's own
  /// machine is in: `~/.dvm` belongs to the older cbracken/dvm, whose `dvm` is
  /// a *shell function* sourced from `.zshrc`. A function beats every binary on
  /// PATH, so without this warning the user installs dvm, types `dvm`, and gets
  /// the other tool with nothing to explain why.
  bool _reportConflicts() {
    final shell = ShellFacts(
      fileSystem: context.fileSystem,
      environment: context.environment,
    );
    final scan = shell.scanForShadows();
    final legacy = LegacyDvmInstall.detect(context.paths);
    var found = false;

    if (scan.shadows.isNotEmpty) {
      found = true;
      context.err
        ..writeln()
        ..writeln('WARNING: your shell defines its own `dvm`, which will win '
            'over the binary you just set up — a shell function or alias is '
            'resolved before PATH is ever searched.');
      for (final shadow in scan.shadows) {
        context.err.writeln('  ${shadow.describe()}');
      }
      context.err.writeln(
        'Remove or comment out the line(s) above, then start a new shell.',
      );
    }

    for (final entry in scan.unreadable.entries) {
      // Not folded into "nothing found": a file we could not open may be
      // exactly the one with the function in it.
      found = true;
      context.err.writeln(
        'WARNING: could not read ${entry.key} (${entry.value}), so dvm cannot '
        'say whether it defines a conflicting `dvm`.',
      );
    }

    if (legacy.isPresent) {
      found = true;
      context.err
        ..writeln()
        ..writeln('WARNING: an older dvm (cbracken/dvm) shares '
            '${context.paths.home.path}:');
      if (legacy.script case final script?) {
        context.err
            .writeln('  ${script.path}  (the shell function it defines)');
      }
      for (final directory in legacy.directories) {
        context.err.writeln('  ${directory.path}');
      }
      context.err.writeln('Import its SDKs with: dvm migrate');
    }

    return found;
  }

  String _absolute(String path) {
    final fileSystem = context.fileSystem;
    if (fileSystem.path.isAbsolute(path)) return path;
    return fileSystem.path.normalize(
      fileSystem.path.join(context.workingDirectory.path, path),
    );
  }
}

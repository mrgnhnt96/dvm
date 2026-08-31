import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:file/file.dart';

import '../core/context.dart';
import '../core/exceptions.dart';
import '../core/path_line.dart';
import '../core/shell.dart';
import '../core/shims.dart';

/// `dvm setup` — Install the shims and print the PATH line to add.
///
/// Writes the shim, then tells the user the one line to add to their shell's
/// startup file. By default it deliberately does **not** edit that file: a
/// version manager that rewrites `.zshrc` behind someone's back is a version
/// manager people stop trusting, and the line differs enough between shells
/// and setups that getting it wrong silently breaks their login shell.
///
/// `--write-path-line` is the escape hatch for a user who would rather dvm did
/// it: it backs the file up, writes the line between markers so it can be
/// found again, and `--remove-path-line` takes it back out.
class SetupCommand extends Command<int> {
  SetupCommand({
    required this.context,
    String Function()? dvmExecutable,
    DateTime Function()? now,
  })  : _dvmExecutable = dvmExecutable ?? _resolvedExecutable,
        _now = now ?? DateTime.now {
    argParser
      ..addOption(
        'dvm-path',
        valueHelp: 'path',
        help: 'The dvm binary to bake into the shim. Defaults to the running '
            'one; needed when running from source.',
      )
      ..addFlag(
        'write-path-line',
        negatable: false,
        help: 'Add the PATH line to your shell startup file instead of just '
            'printing it. Backs the file up first, and does nothing if the '
            'line is already there. Not available for PowerShell, which takes '
            'PATH from your environment rather than a startup file.',
      )
      ..addFlag(
        'remove-path-line',
        negatable: false,
        help: 'Take the PATH line --write-path-line added back out, leaving '
            'the shims in place. A line you added by hand is left alone.',
      );
  }

  final DvmContext context;

  /// Where the running dvm binary is. Injected so a test can drive `setup`
  /// without the answer depending on how the test runner was launched.
  final String Function() _dvmExecutable;

  /// The clock behind the backup file's name, injected so a test can assert on
  /// the exact path the user is told about.
  final DateTime Function() _now;

  static String _resolvedExecutable() => io.Platform.resolvedExecutable;

  @override
  String get name => 'setup';

  @override
  String get description => 'Install the shims and print the PATH line to add.';

  @override
  Future<int> run() async {
    final results = argResults!;
    final write = results.flag('write-path-line');
    final remove = results.flag('remove-path-line');
    if (write && remove) {
      throw ConfigException(
        '--write-path-line and --remove-path-line ask for opposite things. '
        'Pass one of them.',
      );
    }

    // Removal is the inverse of the flag and nothing else: it does not write
    // shims, so it does not need a dvm binary to point them at, and it works
    // from a source checkout the way an undo should.
    if (remove) return _removePathLine();

    final binary = _resolveDvmBinary();
    final writer = ShimWriter(
      fileSystem: context.fileSystem,
      paths: context.paths,
      verbose: context.verbose,
    );
    final shim = await writer.write(binary.path);

    context.out
      ..writeln('Wrote ${context.display(shim.path)}')
      ..writeln('  -> ${context.display(binary.path)} exec dart')
      ..writeln();

    final shell = _shell();
    final scan = shell.scanForShadows();

    // A shadow beats PATH outright and an unreadable startup file may be the
    // one holding it, so writing would look like success while changing
    // nothing. `_reportConflicts` prints the specifics just below.
    //
    // Both branches read the same value on purpose: the branch that *offers*
    // `--write-path-line` must not offer it in the situation where the branch
    // that *performs* it would refuse, or the user is sent to a flag that is
    // guaranteed to decline.
    final blocked = scan.shadows.isNotEmpty || scan.unreadable.isNotEmpty;

    var declined = false;
    if (write) {
      declined = !_writePathLine(shell, blocked: blocked);
    } else {
      _printPathInstructions(shell, blocked: blocked);
    }

    final conflicts = _reportConflicts(scan);

    context.out
      ..writeln()
      ..writeln('Then check it with: dvm doctor');

    // A conflict makes the shim inert, so `setup` reporting success would be
    // a lie the user only finds out about the next time they run `dart`. A
    // `--write-path-line` that declined to write fails for the same reason:
    // the user asked for the line to be there and it is not.
    return conflicts || declined ? 1 : 0;
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
          '--dvm-path names ${context.display(file.path)}, which does not '
          'exist.',
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

  ShellFacts _shell() => ShellFacts(
        fileSystem: context.fileSystem,
        environment: context.environment,
      );

  /// The PATH line, named for the shell the user is actually in.
  ///
  /// [blocked] is the same fact [_writePathLine] refuses on, threaded through
  /// so the offer below cannot point at a flag that would decline.
  void _printPathInstructions(ShellFacts shell, {required bool blocked}) {
    final line = shell.pathLine(context.paths.shimsDir);
    final rcFile = shell.primaryRcFile;

    if (shell.kind == ShellKind.powershell) {
      context.out
        ..writeln('${shell.pathLineAction}:')
        ..writeln()
        ..writeln('  $line')
        ..writeln()
        ..writeln('That edits your user PATH, so it survives a reboot. It has '
            'to go ahead of anything else that puts a dart on PATH, and it '
            'only takes effect in terminals opened after you run it.')
        ..writeln()
        ..writeln('For the terminal you are in right now:')
        ..writeln()
        // ABSOLUTE, deliberately: this is a PATH value the user pastes into
        // a shell, not prose about a file. A relative entry on PATH is
        // resolved against whatever directory each process happens to be in.
        ..writeln('  \$env:Path = '
            "'${context.paths.shimsDir.path};' + \$env:Path");
      return;
    }

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
      ..writeln('$verb ${context.display(rcFile.path)} '
          '(${shell.shellPath ?? 'no \$SHELL set, assuming ${shell.kind.token}'}):')
      ..writeln()
      ..writeln('  $line')
      ..writeln()
      ..writeln('It has to go ahead of anything else that puts a dart on '
          'PATH, and it only takes effect in shells started after you save '
          'the file.')
      ..writeln();

    // Only for a shell with a startup file dvm can name: the PowerShell and
    // no-rc-file branches above return before here, because `--write-path-line`
    // has nothing to write in either.
    if (blocked) {
      // The flag would refuse in this exact state, so pointing at it as the
      // next step would send the user to a guaranteed no-op. The shadow comes
      // first; the flag is what to run once it is gone.
      context.out
        ..writeln('dvm could add that line for you, but not yet: something in '
            'your startup files would beat it, or dvm could not read a file '
            'that might — see the warnings below.')
        ..writeln('Clear that first and start a new shell, then run: '
            'dvm setup --write-path-line');
      return;
    }

    context.out
      ..writeln('Or let dvm add it for you: dvm setup --write-path-line')
      ..writeln('It backs ${context.display(rcFile.path)} up before touching '
          'it, and '
          'dvm setup --remove-path-line takes the line back out.');
  }

  /// Adds the PATH line to the startup file. Returns whether it got there.
  bool _writePathLine(ShellFacts shell, {required bool blocked}) {
    final editor = _editorFor(shell);
    if (editor == null) return false;

    if (blocked) {
      context.err
        ..writeln('Not writing the PATH line: something in your startup files '
            'would beat it, or dvm could not read a file that might. A shell '
            'function or alias is resolved before PATH is ever searched, so '
            'the line would change nothing while looking like it worked.')
        ..writeln('Sort out the warnings below, then run this again.');
      return false;
    }

    final result = editor.install();
    switch (result.outcome) {
      case PathLineOutcome.alreadyPresent:
        context.out.writeln(
          '${context.display(editor.rcFile.path)} already puts '
          '${context.display(context.paths.shimsDir.path)} on PATH '
          '(line ${result.line}), so there is nothing to add.',
        );
      case PathLineOutcome.created:
        context.out
          ..writeln('Created ${context.display(editor.rcFile.path)} with:')
          ..writeln()
          ..writeln('  ${editor.line}');
        _explainNextShell(editor);
      case PathLineOutcome.written:
        context.out
          ..writeln('Backed up ${context.display(editor.rcFile.path)} '
              '-> ${context.display(result.backup!.path)}')
          ..writeln(
              'Added this line to ${context.display(editor.rcFile.path)}:')
          ..writeln()
          ..writeln('  ${editor.line}');
        _explainNextShell(editor);
      case PathLineOutcome.removed:
      case PathLineOutcome.foreign:
      case PathLineOutcome.absent:
        throw StateError('install() cannot report ${result.outcome}');
    }
    return true;
  }

  void _explainNextShell(PathLineEditor editor) {
    context.out
      ..writeln()
      ..writeln('It takes effect in shells started after this. For the one '
          'you are in: source ${context.display(editor.rcFile.path)}')
      ..writeln('Undo it with: dvm setup --remove-path-line');
  }

  /// Takes dvm's PATH line back out. Returns the command's exit code.
  int _removePathLine() {
    final shell = _shell();
    final editor = _editorFor(shell);
    if (editor == null) return 1;

    final result = editor.remove();
    switch (result.outcome) {
      case PathLineOutcome.removed:
        context.out
          ..writeln('Backed up ${context.display(editor.rcFile.path)} '
              '-> ${context.display(result.backup!.path)}')
          ..writeln('Removed dvm\'s PATH line from '
              '${context.display(editor.rcFile.path)}.')
          ..writeln('Shells started after this will no longer find the shims. '
              'The shims themselves are still in '
              '${context.display(context.paths.shimsDir.path)}.');
      case PathLineOutcome.foreign:
        // Reported rather than removed, and still a success: the file is in
        // the state the user put it in, and the one thing dvm knows for sure
        // is that it did not write this line.
        context.out
          ..writeln('${context.display(editor.rcFile.path)} puts '
              '${context.display(context.paths.shimsDir.path)} on PATH at '
              'line ${result.line}, but dvm did not write that line — there '
              'are no dvm markers around it — so it has been left as it is.')
          ..writeln('Remove it by hand if you want it gone.');
      case PathLineOutcome.absent:
        context.out.writeln(
          'There is no dvm PATH line in '
          '${context.display(editor.rcFile.path)}, '
          'so there is nothing to remove.',
        );
      case PathLineOutcome.written:
      case PathLineOutcome.created:
      case PathLineOutcome.alreadyPresent:
        throw StateError('remove() cannot report ${result.outcome}');
    }
    return 0;
  }

  /// An editor for the shell's startup file, or null once it has said why
  /// there is no file to edit.
  PathLineEditor? _editorFor(ShellFacts shell) {
    if (shell.kind == ShellKind.powershell) {
      context.err
        ..writeln('PowerShell takes PATH from your environment rather than '
            'from a startup file, so there is no line for dvm to write. Run '
            'this once instead:')
        ..writeln()
        ..writeln('  ${shell.pathLine(context.paths.shimsDir)}');
      return null;
    }

    final rcFile = shell.primaryRcFile;
    if (rcFile == null) {
      // No HOME and no USERPROFILE: a container, or a hand-built environment.
      // Guessing at a path here is how dvm would write to somewhere nobody
      // reads, so name the line and let the user place it.
      context.err
        ..writeln('Neither \$HOME nor \$USERPROFILE is set, so dvm cannot tell '
            'which startup file is yours. Add this line to it yourself:')
        ..writeln()
        ..writeln('  ${shell.pathLine(context.paths.shimsDir)}');
      return null;
    }

    return PathLineEditor(
      fileSystem: context.fileSystem,
      rcFile: rcFile,
      line: shell.pathLine(context.paths.shimsDir),
      shimsPath: context.paths.shimsDir.path,
      homePath: shell.home?.path,
      now: _now,
    );
  }

  /// Says loudly when something already on this machine will beat the shim.
  ///
  /// Returns whether anything was found. This is the case the maintainer's own
  /// machine is in: `~/.dvm` belongs to the older cbracken/dvm, whose `dvm` is
  /// a *shell function* sourced from `.zshrc`. A function beats every binary on
  /// PATH, so without this warning the user installs dvm, types `dvm`, and gets
  /// the other tool with nothing to explain why.
  bool _reportConflicts(ShellScan scan) {
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
            '${context.display(context.paths.home.path)}:');
      if (legacy.script case final script?) {
        context.err.writeln('  ${context.display(script.path)}  '
            '(the shell function it defines)');
      }
      for (final directory in legacy.directories) {
        context.err.writeln('  ${context.display(directory.path)}');
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

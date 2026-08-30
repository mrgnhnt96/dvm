import 'package:args/command_runner.dart';
import 'package:dvm/dvm.dart';
import 'package:dvm/src/commands/setup_command.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

import 'harness.dart';

void main() {
  late CommandHarness harness;

  /// A dvm binary for the shim to point at.
  ///
  /// `setup` normally takes this from `Platform.resolvedExecutable`, which
  /// under `dart test` is the Dart VM — so every test here passes `--dvm-path`
  /// instead, and one test covers what happens when it does not.
  String installDvmBinary([String path = '/usr/local/bin/dvm']) {
    harness.fileSystem.file(path)
      ..createSync(recursive: true)
      ..writeAsStringSync('a compiled binary');
    return path;
  }

  setUp(() {
    harness = CommandHarness();
    harness.environment['SHELL'] = '/bin/zsh';
  });

  test('writes a shim that execs the named dvm binary', () async {
    final dvm = installDvmBinary();

    expect(await harness.run(['setup', '--dvm-path', dvm]), 0);

    expect(
      harness.fileSystem.file('/dvm/shims/dart').readAsStringSync(),
      '#!/bin/sh\nexec "/usr/local/bin/dvm" exec dart "\$@"\n',
    );
    expect(harness.output, contains('/dvm/shims/dart'));
  });

  test('prints the PATH line for the shell in use, naming its rc file',
      () async {
    harness.fileSystem.file('/home/dev/.zshrc')
      ..createSync(recursive: true)
      ..writeAsStringSync('export EDITOR=vim\n');

    expect(await harness.run(['setup', '--dvm-path', installDvmBinary()]), 0);

    expect(harness.output, contains('/home/dev/.zshrc'));
    expect(harness.output, contains(r'export PATH="/dvm/shims:$PATH"'));
  });

  test('does not touch the rc file itself', () async {
    final rcFile = harness.fileSystem.file('/home/dev/.zshrc')
      ..createSync(recursive: true)
      ..writeAsStringSync('export EDITOR=vim\n');

    await harness.run(['setup', '--dvm-path', installDvmBinary()]);

    expect(rcFile.readAsStringSync(), 'export EDITOR=vim\n');
    // Nor leaves a backup of it: with no flag, nothing about the user's home
    // is different afterwards.
    expect(
      harness.fileSystem
          .directory('/home/dev')
          .listSync()
          .map((entity) => entity.basename),
      ['.zshrc'],
    );
  });

  test('names the fish command when the shell is fish', () async {
    harness.environment['SHELL'] = '/opt/homebrew/bin/fish';

    expect(await harness.run(['setup', '--dvm-path', installDvmBinary()]), 0);

    expect(harness.output, contains('/home/dev/.config/fish/config.fish'));
    expect(harness.output, contains('fish_add_path --prepend /dvm/shims'));
  });

  test('warns loudly and fails when a dvm shell function shadows the binary',
      () async {
    harness.fileSystem.file('/home/dev/.zshrc')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        'export EDITOR=vim\n'
        '[ -s "\$HOME/.dvm/scripts/dvm" ] && . "\$HOME/.dvm/scripts/dvm"\n',
      );

    expect(await harness.run(['setup', '--dvm-path', installDvmBinary()]), 1);

    expect(harness.errors, contains('WARNING'));
    expect(harness.errors, contains('/home/dev/.zshrc:2:'));
    expect(harness.errors, contains('resolved before PATH'));
    // The shim is still written: the warning is about what wins, not about a
    // failure to install.
    expect(harness.fileSystem.file('/dvm/shims/dart').existsSync(), isTrue);
  });

  test('warns when the older cbracken dvm shares the same home', () async {
    harness.fileSystem.file('/dvm/scripts/dvm').createSync(recursive: true);
    harness.fileSystem.directory('/dvm/darts/1.24.3').createSync(
          recursive: true,
        );

    expect(await harness.run(['setup', '--dvm-path', installDvmBinary()]), 1);

    expect(harness.errors, contains('cbracken/dvm'));
    expect(harness.errors, contains('/dvm/darts'));
    expect(harness.errors, contains('dvm migrate'));
  });

  test('refuses to bake in a --dvm-path that does not exist', () async {
    expect(await harness.run(['setup', '--dvm-path', '/nope/dvm']), 1);

    expect(harness.errors, contains('/nope/dvm'));
    expect(harness.fileSystem.file('/dvm/shims/dart').existsSync(), isFalse);
  });

  test('recognises the Dart VM however the HOST spells the path to it',
      () async {
    // `Platform.resolvedExecutable` is spelled the way the machine running the
    // tests spells paths; the filesystem under this harness is posix-style
    // whatever machine that is. Asking the filesystem for the basename of a
    // Windows path therefore returns the whole string, the guard below does
    // not fire, and the user is told their path is not absolute instead of
    // being told the one thing they need to know.
    for (final vm in const [
      '/usr/lib/dart/bin/dart',
      r'C:\hostedtoolcache\windows\dart\3.13.2\x64\bin\dart.exe',
      r'C:/tools/dart/bin/dart.exe',
    ]) {
      final context = DvmContext.wire(
        fileSystem: harness.fileSystem,
        environment: harness.environment,
        platformVersion: '3.13.2 (stable) on "macos_arm64"',
        out: harness.out,
        err: harness.err,
      );
      final runner = CommandRunner<int>('dvm', 'test')
        ..addCommand(SetupCommand(context: context, dvmExecutable: () => vm));

      await expectLater(
        runner.run(['setup']),
        throwsA(
          isA<ConfigException>().having(
            (error) => error.message,
            'message',
            allOf(contains('running from source'), contains('--dvm-path')),
          ),
        ),
        reason: '$vm was not recognised as the Dart VM',
      );
    }
  });

  test('refuses to write a shim pointing at the Dart VM', () async {
    // No --dvm-path, so it falls back to Platform.resolvedExecutable, which
    // under `dart test` is the Dart VM. A shim naming it would pass
    // `exec dart` to the SDK on every dart invocation on the machine.
    expect(await harness.run(['setup']), 1);

    expect(harness.errors, contains('running from source'));
    expect(harness.errors, contains('--dvm-path'));
    expect(harness.fileSystem.file('/dvm/shims/dart').existsSync(), isFalse);
  });

  /// The copy `--write-path-line` and `--remove-path-line` take before they
  /// touch anything. Found by prefix because its name carries a timestamp, so
  /// a second edit cannot overwrite the copy taken before the first one.
  File backupOfZshrc() => harness.fileSystem
      .directory('/home/dev')
      .listSync()
      .whereType<File>()
      .firstWhere((file) => file.basename.startsWith('.zshrc.dvm-backup-'));

  group('--write-path-line', () {
    test('adds the PATH line between markers and backs the file up', () async {
      final rcFile = harness.fileSystem.file('/home/dev/.zshrc')
        ..createSync(recursive: true)
        ..writeAsStringSync('export EDITOR=vim\n');

      expect(
        await harness.run(
          ['setup', '--dvm-path', installDvmBinary(), '--write-path-line'],
        ),
        0,
      );

      expect(
        rcFile.readAsStringSync(),
        'export EDITOR=vim\n'
        '\n'
        '# >>> dvm >>>\n'
        'export PATH="/dvm/shims:\$PATH"\n'
        '# <<< dvm <<<\n',
      );
      expect(backupOfZshrc().readAsStringSync(), 'export EDITOR=vim\n');
      expect(harness.output, contains('Backed up /home/dev/.zshrc'));
      expect(harness.output, contains('dvm setup --remove-path-line'));
    });

    test('creates the startup file when there is not one yet', () async {
      expect(
        await harness.run(
          ['setup', '--dvm-path', installDvmBinary(), '--write-path-line'],
        ),
        0,
      );

      expect(
        harness.fileSystem.file('/home/dev/.zshrc').readAsStringSync(),
        '# >>> dvm >>>\n'
        'export PATH="/dvm/shims:\$PATH"\n'
        '# <<< dvm <<<\n',
      );
      expect(harness.output, contains('Created /home/dev/.zshrc'));
      // Nothing existed, so there was nothing to back up.
      expect(
        harness.fileSystem
            .directory('/home/dev')
            .listSync()
            .map((entity) => entity.basename),
        ['.zshrc'],
      );
    });

    test('a second run adds nothing', () async {
      final dvm = installDvmBinary();
      await harness.run(['setup', '--dvm-path', dvm, '--write-path-line']);
      final afterFirst =
          harness.fileSystem.file('/home/dev/.zshrc').readAsStringSync();
      harness.clearOutput();

      expect(
        await harness.run(['setup', '--dvm-path', dvm, '--write-path-line']),
        0,
      );

      expect(
        harness.fileSystem.file('/home/dev/.zshrc').readAsStringSync(),
        afterFirst,
      );
      expect(harness.output, contains('already puts /dvm/shims on PATH'));
      expect(harness.output, contains('nothing to add'));
    });

    test('leaves a hand-written PATH line alone, however it is spelled',
        () async {
      // Same instruction, different quoting and `$HOME` in place of the home
      // directory: appending dvm's own copy would put /dvm/shims on PATH twice.
      final rcFile = harness.fileSystem.file('/home/dev/.zshrc')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          'export EDITOR=vim\n'
          'export PATH=\$HOME/../../dvm/shims:\$PATH\n',
        );
      harness.environment['DVM_HOME'] = '/home/dev/../../dvm';

      expect(
        await harness.run(
          ['setup', '--dvm-path', installDvmBinary(), '--write-path-line'],
        ),
        0,
      );

      expect(
        rcFile.readAsStringSync(),
        'export EDITOR=vim\n'
        'export PATH=\$HOME/../../dvm/shims:\$PATH\n',
      );
      expect(harness.output, contains('line 2'));
    });

    test('declines to write when a shell function shadows dvm', () async {
      final rcFile = harness.fileSystem.file('/home/dev/.zshrc')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          'export EDITOR=vim\n'
          'dvm() { echo other; }\n',
        );

      expect(
        await harness.run(
          ['setup', '--dvm-path', installDvmBinary(), '--write-path-line'],
        ),
        1,
      );

      expect(harness.errors, contains('Not writing the PATH line'));
      expect(harness.errors, contains('/home/dev/.zshrc:2:'));
      expect(
        rcFile.readAsStringSync(),
        'export EDITOR=vim\n'
        'dvm() { echo other; }\n',
      );
    });

    test('declines to write when a startup file cannot be read', () async {
      // "Could not look" is not "nothing there": the file dvm cannot open may
      // be exactly the one defining a `dvm` function.
      final fileSystem = MemoryFileSystem.test(
        opHandle: (context, operation) {
          if (context == '/home/dev/.zprofile' &&
              operation == FileSystemOp.read) {
            throw const FileSystemException(
              'permission denied',
              '/home/dev/.zprofile',
            );
          }
        },
      );
      fileSystem.file('/usr/local/bin/dvm')
        ..createSync(recursive: true)
        ..writeAsStringSync('a compiled binary');
      fileSystem.file('/home/dev/.zprofile')
        ..createSync(recursive: true)
        ..writeAsStringSync('# something\n');
      final rcFile = fileSystem.file('/home/dev/.zshrc')
        ..createSync(recursive: true)
        ..writeAsStringSync('export EDITOR=vim\n');
      final out = StringBuffer();
      final err = StringBuffer();

      final code = await run(
        [
          'setup',
          '--dvm-path',
          '/usr/local/bin/dvm',
          '--write-path-line',
        ],
        fileSystem: fileSystem,
        environment: {
          'DVM_HOME': '/dvm',
          'HOME': '/home/dev',
          'PATH': '',
          'SHELL': '/bin/zsh',
        },
        platformVersion: '3.13.2 (stable) on "macos_arm64"',
        out: out,
        err: err,
      );

      expect(code, 1);
      expect(err.toString(), contains('Not writing the PATH line'));
      expect(err.toString(), contains('could not read /home/dev/.zprofile'));
      expect(rcFile.readAsStringSync(), 'export EDITOR=vim\n');
    });

    test('declines on PowerShell and names the command to run instead',
        () async {
      harness.environment['SHELL'] = '/usr/bin/powershell';

      expect(
        await harness.run(
          ['setup', '--dvm-path', installDvmBinary(), '--write-path-line'],
        ),
        1,
      );

      expect(
          harness.errors,
          contains('PowerShell takes PATH from your '
              'environment'));
      expect(harness.errors, contains('SetEnvironmentVariable'));
    });

    test('declines when the environment names no home', () async {
      harness.environment.remove('HOME');

      expect(
        await harness.run(
          ['setup', '--dvm-path', installDvmBinary(), '--write-path-line'],
        ),
        1,
      );

      expect(harness.errors, contains('cannot tell which startup file'));
      expect(harness.errors, contains(r'export PATH="/dvm/shims:$PATH"'));
    });
  });

  group('--remove-path-line', () {
    /// An rc file holding the block `--write-path-line` writes.
    File writtenRcFile() => harness.fileSystem.file('/home/dev/.zshrc')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        'export EDITOR=vim\n'
        '\n'
        '# >>> dvm >>>\n'
        'export PATH="/dvm/shims:\$PATH"\n'
        '# <<< dvm <<<\n',
      );

    test('takes the block back out and backs the file up', () async {
      final rcFile = writtenRcFile();
      final before = rcFile.readAsStringSync();

      // No --dvm-path: undoing the PATH line does not write shims, so it does
      // not need to know where the dvm binary is.
      expect(await harness.run(['setup', '--remove-path-line']), 0);

      expect(rcFile.readAsStringSync(), 'export EDITOR=vim\n');
      expect(backupOfZshrc().readAsStringSync(), before);
      expect(harness.output, contains("Removed dvm's PATH line"));
    });

    test('leaves a hand-written line alone', () async {
      final rcFile = harness.fileSystem.file('/home/dev/.zshrc')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          'export EDITOR=vim\n'
          'export PATH="/dvm/shims:\$PATH"\n',
        );

      expect(await harness.run(['setup', '--remove-path-line']), 0);

      expect(
        rcFile.readAsStringSync(),
        'export EDITOR=vim\n'
        'export PATH="/dvm/shims:\$PATH"\n',
      );
      expect(harness.output, contains('dvm did not write that line'));
      expect(harness.output, contains('line 2'));
    });

    test('is a no-op on a file with nothing of dvm in it', () async {
      final rcFile = harness.fileSystem.file('/home/dev/.zshrc')
        ..createSync(recursive: true)
        ..writeAsStringSync('export EDITOR=vim\n');

      expect(await harness.run(['setup', '--remove-path-line']), 0);

      expect(rcFile.readAsStringSync(), 'export EDITOR=vim\n');
      expect(harness.output, contains('nothing to remove'));
      expect(
        harness.fileSystem
            .directory('/home/dev')
            .listSync()
            .map((entity) => entity.basename),
        ['.zshrc'],
      );
    });

    test('is a no-op when there is no startup file at all', () async {
      expect(await harness.run(['setup', '--remove-path-line']), 0);

      expect(harness.output, contains('nothing to remove'));
      expect(harness.fileSystem.file('/home/dev/.zshrc').existsSync(), isFalse);
    });

    test('undoes exactly what --write-path-line did', () async {
      final rcFile = harness.fileSystem.file('/home/dev/.zshrc')
        ..createSync(recursive: true)
        ..writeAsStringSync('export EDITOR=vim\n');

      await harness.run(
        ['setup', '--dvm-path', installDvmBinary(), '--write-path-line'],
      );
      // The round trip only means anything if the first half changed the file.
      expect(rcFile.readAsStringSync(), contains('/dvm/shims'));

      await harness.run(['setup', '--remove-path-line']);

      expect(rcFile.readAsStringSync(), 'export EDITOR=vim\n');
    });
  });

  test('refuses to write and remove the PATH line in one run', () async {
    expect(
      await harness.run([
        'setup',
        '--dvm-path',
        installDvmBinary(),
        '--write-path-line',
        '--remove-path-line',
      ]),
      1,
    );

    expect(harness.errors, contains('opposite things'));
  });
}

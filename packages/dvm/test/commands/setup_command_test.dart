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

  group('advertising --write-path-line', () {
    // The incident behind this: a user was told to add a line to `.zshrc`,
    // did it by hand, and never learned that dvm would have done it for them,
    // backup included. The flag was not new — it was invisible.

    test('offers the flag alongside the line to copy, and says it backs up',
        () async {
      harness.fileSystem.file('/home/dev/.zshrc')
        ..createSync(recursive: true)
        ..writeAsStringSync('export EDITOR=vim\n');

      expect(await harness.run(['setup', '--dvm-path', installDvmBinary()]), 0);

      expect(harness.output, contains('dvm setup --write-path-line'));
      // A user is much likelier to accept an offer to edit their own startup
      // file when told what it does to it first.
      expect(harness.output, contains('backs /home/dev/.zshrc up'));
      expect(harness.output, contains('dvm setup --remove-path-line'));
    });

    test('offers the flag when the rc file does not exist yet', () async {
      // The `Create` branch: --write-path-line handles this too, so the offer
      // has to be there as well.
      expect(harness.fileSystem.file('/home/dev/.zshrc').existsSync(), isFalse);

      expect(await harness.run(['setup', '--dvm-path', installDvmBinary()]), 0);

      expect(harness.output, contains('Create /home/dev/.zshrc'));
      expect(harness.output, contains('dvm setup --write-path-line'));
    });

    test('does not offer the flag on PowerShell', () async {
      // The flag's own help says it is not available for PowerShell, which
      // takes PATH from the environment rather than a startup file, and
      // `_editorFor` refuses there. Naming it would be an offer that cannot
      // be taken up.
      harness.environment['SHELL'] = '/usr/bin/powershell';

      expect(await harness.run(['setup', '--dvm-path', installDvmBinary()]), 0);

      expect(harness.output, contains('SetEnvironmentVariable'));
      expect(harness.output, isNot(contains('--write-path-line')));
    });

    test('does not offer the flag when the environment names no home',
        () async {
      // No HOME and no USERPROFILE: there is no file to write, so the flag
      // cannot help.
      harness.environment.remove('HOME');

      expect(await harness.run(['setup', '--dvm-path', installDvmBinary()]), 0);

      expect(harness.output, contains('Add this to your shell startup file'));
      expect(harness.output, contains(r'export PATH="/dvm/shims:$PATH"'));
      expect(harness.output, isNot(contains('--write-path-line')));
    });

    test('under a shadowed shell, says clear the shadow before the flag',
        () async {
      // The regression guard. `--write-path-line` REFUSES while a shadow is
      // present, so offering it as the immediate next step would send the
      // user to a flag guaranteed to decline — reproducing the exact
      // confusion this change exists to remove.
      harness.fileSystem.file('/home/dev/.zshrc')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          'export EDITOR=vim\n'
          '[ -s "\$HOME/.dvm/scripts/dvm" ] && . "\$HOME/.dvm/scripts/dvm"\n',
        );

      expect(await harness.run(['setup', '--dvm-path', installDvmBinary()]), 1);

      expect(harness.output, isNot(contains('Or let dvm add it for you')));
      expect(harness.output, contains('not yet'));
      expect(harness.output, contains('Clear that first'));
      // The flag is still named — as what to run afterwards, not now.
      expect(harness.output, contains('dvm setup --write-path-line'));
      expect(harness.errors, contains('WARNING'));
    });

    test('does not offer the flag to a user who just passed it', () async {
      harness.fileSystem.file('/home/dev/.zshrc')
        ..createSync(recursive: true)
        ..writeAsStringSync('export EDITOR=vim\n');

      expect(
        await harness.run(
          ['setup', '--dvm-path', installDvmBinary(), '--write-path-line'],
        ),
        0,
      );

      expect(harness.output, contains('Added this line to /home/dev/.zshrc'));
      expect(harness.output, isNot(contains('--write-path-line')));
    });
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

  // dvm does not have to be on PATH to be RUN — install.sh knows the absolute
  // path of the binary it just wrote, so it can hand out one command that
  // finishes the whole setup. That is only honest if the line this writes
  // covers the dvm binary's own directory as well as the shims; before this,
  // running that command left a working `dart` and a `dvm` still not on PATH.
  group('the dvm binary directory', () {
    /// A dvm binary where an install puts it: `$DVM_HOME/bin/dvm`.
    String installedDvmBinary() => installDvmBinary('/dvm/bin/dvm');

    test('--write-path-line covers the shims AND the binary directory',
        () async {
      final rcFile = harness.fileSystem.file('/home/dev/.zshrc')
        ..createSync(recursive: true)
        ..writeAsStringSync('export EDITOR=vim\n');

      expect(
        await harness.run(
          ['setup', '--dvm-path', installedDvmBinary(), '--write-path-line'],
        ),
        0,
      );

      expect(
        rcFile.readAsStringSync(),
        'export EDITOR=vim\n'
        '\n'
        '# >>> dvm >>>\n'
        'export PATH="/dvm/shims:/dvm/bin:\$PATH"\n'
        '# <<< dvm <<<\n',
      );
      // ONE line, not two: the whole point is a setup with nothing left to
      // paste afterwards.
      expect(
        '# >>> dvm >>>\n'.allMatches(rcFile.readAsStringSync()).length,
        1,
      );
      // And it does not apologise for something it did do.
      expect(harness.output, isNot(contains('not `dvm` itself')));
    });

    test(r'the line it writes keeps $PATH literal', () async {
      harness.fileSystem.file('/home/dev/.zshrc')
        ..createSync(recursive: true)
        ..writeAsStringSync('export EDITOR=vim\n');

      await harness.run(
        ['setup', '--dvm-path', installedDvmBinary(), '--write-path-line'],
      );

      // Asserted against the BYTES in the file rather than the message: an
      // expanded PATH here would discard everything the user's own earlier
      // lines added, on every login, without an error anywhere.
      final written =
          harness.fileSystem.file('/home/dev/.zshrc').readAsStringSync();
      expect(written, contains(r'$PATH'));
      expect(written, endsWith('# <<< dvm <<<\n'));
    });

    test('writes the shims alone, and says why, from anywhere else', () async {
      final rcFile = harness.fileSystem.file('/home/dev/.zshrc')
        ..createSync(recursive: true)
        ..writeAsStringSync('export EDITOR=vim\n');

      // A binary in a Homebrew prefix, a checkout build, a copy in /tmp: dvm
      // cannot tell an install from any of them, so it adds nothing.
      expect(
        await harness.run([
          'setup',
          '--dvm-path',
          installDvmBinary('/opt/homebrew/bin/dvm'),
          '--write-path-line',
        ]),
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
      expect(rcFile.readAsStringSync(), isNot(contains('/opt/homebrew/bin')));
      // The guard has to be visible, or the user concludes the flag is broken.
      expect(harness.output, contains('not `dvm` itself'));
      expect(harness.output, contains('/opt/homebrew/bin/dvm'));
      expect(harness.output, contains('/dvm/bin'));
    });

    test('still refuses to write anything under a shadowed shell', () async {
      final rcFile = harness.fileSystem.file('/home/dev/.zshrc')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          'export EDITOR=vim\n'
          'alias dvm=/other/dvm\n',
        );

      expect(
        await harness.run(
          ['setup', '--dvm-path', installedDvmBinary(), '--write-path-line'],
        ),
        1,
      );

      // A shell alias beats PATH outright, so a line naming BOTH directories
      // would change nothing while looking like it worked.
      expect(harness.errors, contains('Not writing the PATH line'));
      expect(
        rcFile.readAsStringSync(),
        'export EDITOR=vim\n'
        'alias dvm=/other/dvm\n',
      );
    });

    test('plain setup prints one line naming both directories', () async {
      harness.fileSystem.file('/home/dev/.zshrc')
        ..createSync(recursive: true)
        ..writeAsStringSync('export EDITOR=vim\n');

      expect(
        await harness.run(['setup', '--dvm-path', installedDvmBinary()]),
        0,
      );

      expect(
        harness.output,
        contains(r'export PATH="/dvm/shims:/dvm/bin:$PATH"'),
      );
    });
  });

  // Requirement: never hand out an instruction that is already in effect.
  // `PathLineOutcome.alreadyPresent` answers this for the FILE's contents;
  // this is the environment's, and they are independent — a line in
  // `.zprofile` puts a directory on PATH without `.zshrc` mentioning it.
  group('a directory that is already on PATH', () {
    test('plain setup says so instead of printing a line to add', () async {
      harness.environment['PATH'] = '/dvm/shims:/dvm/bin';
      harness.fileSystem.file('/home/dev/.zshrc')
        ..createSync(recursive: true)
        ..writeAsStringSync('export EDITOR=vim\n');

      expect(
        await harness
            .run(['setup', '--dvm-path', installDvmBinary('/dvm/bin/dvm')]),
        0,
      );

      expect(harness.output, contains('already on your PATH'));
      expect(harness.output, contains('/dvm/shims'));
      expect(harness.output, isNot(contains('export PATH=')));
      expect(harness.output, isNot(contains('Add this line')));
    });

    test('a trailing separator and a redundant slash are the same entry',
        () async {
      // What a real PATH looks like after a few years of hand-editing.
      harness.environment['PATH'] = '/usr/bin:/dvm/shims/:';

      expect(
        await harness.run(
          ['setup', '--dvm-path', installDvmBinary('/usr/local/bin/dvm')],
        ),
        0,
      );

      expect(harness.output, contains('already on your PATH'));
      expect(harness.output, isNot(contains('export PATH=')));
    });

    test('names the half that is still missing, and only that half', () async {
      // The shims are on PATH from some other startup file; the binary's
      // directory is not. One of the two still needs a line.
      harness.environment['PATH'] = '/dvm/shims';
      harness.fileSystem.file('/home/dev/.zshrc')
        ..createSync(recursive: true)
        ..writeAsStringSync('export EDITOR=vim\n');

      expect(
        await harness.run(
          ['setup', '--dvm-path', installDvmBinary('/dvm/bin/dvm')],
        ),
        0,
      );

      expect(harness.output, contains(r'export PATH="/dvm/bin:$PATH"'));
      expect(harness.output, isNot(contains('/dvm/shims:/dvm/bin')));
    });

    test(
        '--write-path-line still writes it, because a shell PATH does not '
        'persist', () async {
      // The user asked for a line in a file. `$PATH` here may be one they
      // exported by hand in this session and it is gone at logout, so the
      // environment is not the idempotency guard — the file contents are.
      harness.environment['PATH'] = '/dvm/shims:/dvm/bin';
      final rcFile = harness.fileSystem.file('/home/dev/.zshrc')
        ..createSync(recursive: true)
        ..writeAsStringSync('export EDITOR=vim\n');

      expect(
        await harness.run([
          'setup',
          '--dvm-path',
          installDvmBinary('/dvm/bin/dvm'),
          '--write-path-line',
        ]),
        0,
      );

      expect(
        rcFile.readAsStringSync(),
        contains('export PATH="/dvm/shims:/dvm/bin:\$PATH"'),
      );
    });
  });

  /// The state this leaf exists for: a PATH line sitting in a startup file the
  /// running shell does not read.
  ///
  /// `$SHELL` is unset — the condition that makes `ShellFacts` assume `sh` and
  /// so pick `.profile` — the home holds a `.zshrc`, and the live `PATH` does
  /// not have the shims directory. Every one of those is what the reporter's
  /// machine looked like.
  group('a PATH line in a file this shell does not read', () {
    setUp(() {
      harness.environment.remove('SHELL');
      harness.fileSystem.file('/home/dev/.zshrc')
        ..createSync(recursive: true)
        ..writeAsStringSync('export EDITOR=vim\n');
      harness.environment['PATH'] = '/usr/bin';
    });

    test('--write-path-line refuses rather than writing to .profile', () async {
      expect(
        await harness.run(
          ['setup', '--write-path-line', '--dvm-path', installDvmBinary()],
        ),
        1,
      );

      // The whole point: nothing was written, so there is no misfiled line and
      // no backup beside it for the next run to find and call "already there".
      expect(
          harness.fileSystem.file('/home/dev/.profile').existsSync(), isFalse);
      expect(harness.errors, contains('Not writing the PATH line'));
      expect(harness.errors, contains(r'$SHELL is not set'));
      expect(harness.errors, contains('/home/dev/.zshrc  (zsh)'));
      expect(harness.errors, contains('would look like it worked'));
      expect(
        harness.errors,
        contains('SHELL=zsh dvm setup --write-path-line'),
      );
    });

    test(
        'an unrecognised \$SHELL is refused the same way, and says what it '
        'saw', () async {
      harness.environment['SHELL'] = '/usr/local/bin/nu';

      expect(
        await harness.run(
          ['setup', '--write-path-line', '--dvm-path', installDvmBinary()],
        ),
        1,
      );
      expect(
          harness.errors,
          contains(r'$SHELL says /usr/local/bin/nu, which dvm does not '
              'recognise'));
      expect(
          harness.fileSystem.file('/home/dev/.profile').existsSync(), isFalse);
    });

    test('plain setup names the ambiguity instead of naming .profile',
        () async {
      expect(await harness.run(['setup', '--dvm-path', installDvmBinary()]), 0);

      expect(harness.output,
          contains('cannot tell which startup file your shell reads'));
      expect(
          harness.output,
          contains('/home/dev/.profile  (sh, what dvm '
              'would have assumed)'));
      expect(harness.output, contains('/home/dev/.zshrc  (zsh)'));
      expect(
          harness.output,
          contains('Add this line to the one your shell '
              'actually reads:'));
      // The flag would decline in this exact state, so it must not be the
      // suggested next step — the same rule the shadow branch follows.
      expect(harness.output, isNot(contains('Or let dvm add it for you')));
    });

    test(
        'a line already in .profile is NOT reported as "nothing to add" and '
        'nothing else', () async {
      // The exact contradiction from the incident: an earlier dvm wrote the
      // block into .profile, the shell never sourced it, and the second run
      // said there was nothing to add while `dvm doctor` failed.
      harness.fileSystem.file('/home/dev/.profile')
        ..createSync(recursive: true)
        ..writeAsStringSync('# >>> dvm >>>\n'
            'export PATH="/dvm/shims:/dvm/bin:\$PATH"\n'
            '# <<< dvm <<<\n');
      // A recognised $SHELL, so the guess guard is out of the picture and the
      // ONLY thing that can catch this is the in-effect check.
      harness.environment['SHELL'] = '/bin/sh';

      expect(
        await harness.run(
          ['setup', '--write-path-line', '--dvm-path', installDvmBinary()],
        ),
        0,
      );

      expect(harness.output, contains('so there is nothing to add'));
      expect(harness.errors, contains('that line is not in effect'));
      expect(
          harness.errors,
          contains('/dvm/shims is not on the PATH of this '
              'shell'));
      expect(harness.errors, contains('does not read /home/dev/.profile'));
      expect(
          harness.errors,
          contains('/home/dev/.zshrc is here too, and zsh '
              'does not read /home/dev/.profile.'));
      expect(harness.errors, contains('Check with: dvm doctor'));
    });

    test('a line that IS in effect says nothing extra', () async {
      harness.fileSystem.file('/home/dev/.profile')
        ..createSync(recursive: true)
        ..writeAsStringSync(r'export PATH="/dvm/shims:$PATH"' '\n');
      harness.environment['SHELL'] = '/bin/sh';
      harness.environment['PATH'] = '/dvm/shims:/usr/bin';

      expect(
        await harness.run(
          ['setup', '--write-path-line', '--dvm-path', installDvmBinary()],
        ),
        0,
      );

      expect(harness.output, contains('so there is nothing to add'));
      expect(harness.errors, isNot(contains('not in effect')));
    });

    test('--remove-path-line is NOT guarded, so the mess stays undoable',
        () async {
      // A user who already has the misfiled line has to be able to take it out,
      // and the guard that stops dvm creating another one must not stand in
      // the way of cleaning up the first.
      harness.fileSystem.file('/home/dev/.profile')
        ..createSync(recursive: true)
        ..writeAsStringSync('# >>> dvm >>>\n'
            r'export PATH="/dvm/shims:$PATH"'
            '\n# <<< dvm <<<\n');

      expect(await harness.run(['setup', '--remove-path-line']), 0);

      expect(harness.output, contains("Removed dvm's PATH line"));
      expect(
        harness.fileSystem.file('/home/dev/.profile').readAsStringSync(),
        isEmpty,
      );
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

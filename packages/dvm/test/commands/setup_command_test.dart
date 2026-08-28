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

  test('refuses to write a shim pointing at the Dart VM', () async {
    // No --dvm-path, so it falls back to Platform.resolvedExecutable, which
    // under `dart test` is the Dart VM. A shim naming it would pass
    // `exec dart` to the SDK on every dart invocation on the machine.
    expect(await harness.run(['setup']), 1);

    expect(harness.errors, contains('running from source'));
    expect(harness.errors, contains('--dvm-path'));
    expect(harness.fileSystem.file('/dvm/shims/dart').existsSync(), isFalse);
  });
}

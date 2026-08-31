import 'package:dvm/dvm.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// `which` is the debugging tool for the whole resolution contract, so every
/// one of the five rules in ARCHITECTURE.md gets a test that checks it names
/// the right rule — not just that it printed a path.
void main() {
  late CommandHarness harness;

  setUp(() => harness = CommandHarness());

  test('rule 1: DVM_DART_VERSION in the environment', () async {
    harness
      ..installVersion('3.9.0')
      ..environment['DVM_DART_VERSION'] = '3.9.0';

    expect(await harness.run(['which']), 0);

    expect(harness.output, contains('/dvm/versions/3.9.0/bin/dart'));
    expect(harness.output, contains('rule 1 of 5'));
    expect(harness.output, contains('DVM_DART_VERSION'));
  });

  test('rule 2: the nearest .dvmrc', () async {
    harness.installVersion('3.9.0');
    await harness.run(['use', '3.9.0']);
    harness.clearOutput();

    expect(await harness.run(['which']), 0);

    expect(harness.output, contains('rule 2 of 5'));
    // Relative: the .dvmrc is in the working directory. The first line, the
    // one `dvm which | head -1` takes, stays absolute — pinned separately
    // below in "the machine-readable paths stay absolute".
    expect(harness.output, contains('pinned by .dvmrc'));
    expect(harness.output, isNot(contains('pinned by /project/.dvmrc')));
  });

  test('rule 2 finds a .dvmrc in a parent directory', () async {
    harness.installVersion('3.9.0');
    harness.fileSystem.file('/project/.dvmrc').writeAsStringSync('3.9.0');
    harness.fileSystem
        .directory('/project/packages/app')
        .createSync(recursive: true);
    harness.fileSystem.currentDirectory = '/project/packages/app';

    expect(await harness.run(['which']), 0);
    // ABSOLUTE, and this is the point of the test: the governing .dvmrc is
    // ABOVE the working directory, so it is not under it and the display rule
    // leaves it alone. Nobody should later "fix" this into `../..`.
    expect(harness.output, contains('pinned by /project/.dvmrc'));
  });

  test('rule 3: the global default', () async {
    harness
      ..installVersion('3.13.2')
      ..writeConfig(const DvmConfig(global: '3.13.2'));

    expect(await harness.run(['which']), 0);

    expect(harness.output, contains('rule 3 of 5'));
    expect(harness.output, contains('global default'));
    expect(harness.output, contains('/dvm/config.json'));
  });

  test('rule 4: the next dart on PATH', () async {
    harness.putDartOnPath();

    expect(await harness.run(['which']), 0);

    expect(harness.output, contains('/usr/bin/dart'));
    expect(harness.output, contains('rule 4 of 5'));
    expect(harness.output, contains('not managed by dvm'));
  });

  test('rule 5: nothing applies, and it says what to run', () async {
    expect(await harness.run(['which']), 1);

    expect(harness.errors, contains('No Dart SDK applies'));
    expect(harness.errors, contains('DVM_DART_VERSION is not set'));
    expect(harness.errors, contains('no .dvmrc'));
    expect(harness.errors, contains('dvm use <version>'));
  });

  test('a .dvmrc naming an alias explains the hop', () async {
    harness
      ..installVersion('3.9.0')
      ..writeConfig(const DvmConfig(aliases: {'work': '3.9.0'}));
    harness.fileSystem.file('/project/.dvmrc').writeAsStringSync('work');

    expect(await harness.run(['which']), 0);

    expect(harness.output, contains('rule 2 of 5'));
    expect(harness.output, contains('an alias for 3.9.0'));
  });

  test('a .dvmrc naming a channel explains where the version came from',
      () async {
    harness
      ..installVersion('3.13.2')
      ..writeConfig(const DvmConfig(channels: {'stable': '3.13.2'}));
    harness.fileSystem.file('/project/.dvmrc').writeAsStringSync('stable');

    expect(await harness.run(['which']), 0);
    expect(harness.output, contains('the channel that was recorded as 3.13.2'));
  });

  test('--path prints only the executable, for scripting', () async {
    harness
      ..installVersion('3.9.0')
      ..writeConfig(const DvmConfig(global: '3.9.0'));

    expect(await harness.run(['which', '--path']), 0);
    expect(harness.output.trim(), '/dvm/versions/3.9.0/bin/dart');
  });

  group("which's machine-readable paths stay absolute", () {
    /// The carve-out from the relative-path display rule, and the reason it
    /// exists: these two lines are captured by scripts and IDEs, which run
    /// with a working directory of their own. A relative path resolves against
    /// the CALLER's directory rather than dvm's, so a consumer handed
    /// `.dvm/dart_sdk/bin/dart` silently points at nothing. Every other path
    /// `which` prints is prose for a human and follows the normal rule.
    ///
    /// The SDK is pinned INSIDE the working directory here on purpose: that is
    /// the one arrangement where the display rule would fire, so a test using
    /// the usual `/dvm/versions/...` store could not tell the carve-out from
    /// a path that was simply never under the working directory.
    void sdkInsideTheWorkingDirectory() {
      const inside = '/project/sdk/3.9.0';
      harness.paths.dartExecutable(harness.fileSystem.directory(inside))
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\n');
      harness.environment['DVM_HOME'] = '/project/sdk-home';
      harness.fileSystem
          .directory('/project/sdk-home/versions')
          .createSync(recursive: true);
      harness.fileSystem
          .link('/project/sdk-home/versions/3.9.0')
          .createSync(inside);
      harness.writeConfig(const DvmConfig(global: '3.9.0'));
    }

    test(
        '--path prints an absolute path even when the SDK is under the '
        'working directory', () async {
      sdkInsideTheWorkingDirectory();

      expect(await harness.run(['which', '--path']), 0);

      final printed = harness.output.trim();
      expect(printed, startsWith('/'),
          reason: 'a script capturing this resolves it from its own directory');
      expect(printed, '/project/sdk-home/versions/3.9.0/bin/dart');
    });

    test(
        'the first line of default output — what `dvm which | head -1` '
        'takes — is absolute too', () async {
      sdkInsideTheWorkingDirectory();

      expect(await harness.run(['which']), 0);

      final firstLine = harness.output.split('\n').first;
      expect(firstLine, startsWith('/'));
      expect(firstLine, '/project/sdk-home/versions/3.9.0/bin/dart');
    });

    test('the human-readable SDK: line does follow the normal rule', () async {
      sdkInsideTheWorkingDirectory();

      expect(await harness.run(['which']), 0);

      // Under /project, which is the working directory, so relative — this is
      // what makes the two assertions above a real carve-out rather than a
      // restatement of what the rule would have done anyway.
      expect(harness.output, contains('SDK: sdk-home/versions/3.9.0'));
    });
  });

  test('`current` is the same command', () async {
    harness
      ..installVersion('3.9.0')
      ..writeConfig(const DvmConfig(global: '3.9.0'));

    expect(await harness.run(['current']), 0);
    expect(harness.output, contains('rule 3 of 5'));
  });

  test('a pin naming an SDK that is not installed says so', () async {
    harness.fileSystem.file('/project/.dvmrc').writeAsStringSync('3.9.0');

    expect(await harness.run(['which']), 1);
    expect(harness.errors, contains('not installed'));
    expect(harness.errors, contains('dvm install 3.9.0'));
  });
}

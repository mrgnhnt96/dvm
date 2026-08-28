import 'package:dvm_cli/dvm.dart';
import 'package:test/test.dart';

import 'harness.dart';

void main() {
  late CommandHarness harness;

  /// The state `dvm setup` leaves behind on a working machine: a dvm binary, a
  /// shim naming it, and the shims directory first on PATH.
  void makeHealthy() {
    harness.fileSystem.file('/usr/local/bin/dvm')
      ..createSync(recursive: true)
      ..writeAsStringSync('a compiled binary');
    harness.fileSystem.file('/dvm/shims/dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(
          '#!/bin/sh\nexec "/usr/local/bin/dvm" exec dart "\$@"\n');
    harness.environment['PATH'] = '/dvm/shims:/usr/bin';
  }

  /// A real, non-shim `dart` in [directory].
  void putDartIn(String directory) {
    harness.fileSystem.file('$directory/dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('a multi-megabyte binary, in spirit');
  }

  setUp(() {
    harness = CommandHarness();
    harness.environment['SHELL'] = '/bin/zsh';
  });

  test('passes on a machine that is set up correctly', () async {
    makeHealthy();

    expect(await harness.run(['doctor']), 0);
    expect(harness.output, contains('Everything checks out.'));
    expect(harness.output, isNot(contains('FAIL')));
  });

  group('PATH', () {
    test('fails when the shims are not on PATH at all', () async {
      makeHealthy();
      harness.environment['PATH'] = '/usr/bin';
      putDartIn('/usr/bin');

      expect(await harness.run(['doctor']), 1);
      expect(harness.output, contains('/dvm/shims is not on PATH'));
      expect(harness.output, contains(r'export PATH="/dvm/shims:$PATH"'));
    });

    test('fails when another dart comes first, and reports the order',
        () async {
      makeHealthy();
      harness.environment['PATH'] = '/opt/dart/bin:/usr/bin:/dvm/shims';
      putDartIn('/opt/dart/bin');

      expect(await harness.run(['doctor']), 1);
      expect(harness.output, contains('the shim is never reached'));
      expect(harness.output, contains('PATH order'));
      expect(harness.output, contains('1. /opt/dart/bin'));
      expect(harness.output, contains('3. /dvm/shims  <- dvm shims'));
    });

    test('does not count a copy of the shim as a dart that beats it', () async {
      makeHealthy();
      // What `cp ~/.dvm/shims/dart ~/.local/bin/` leaves behind. It still goes
      // through dvm, so it is not a problem the user can act on.
      harness.fileSystem.file('/home/dev/.local/bin/dart')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '#!/bin/sh\nexec "/usr/local/bin/dvm" exec dart "\$@"\n',
        );
      harness.environment['PATH'] = '/home/dev/.local/bin:/dvm/shims';

      expect(await harness.run(['doctor']), 0);
    });
  });

  group('shims', () {
    test('fails when the shim is not there', () async {
      harness.environment['PATH'] = '/dvm/shims';

      expect(await harness.run(['doctor']), 1);
      expect(harness.output, contains('/dvm/shims/dart does not exist'));
      expect(harness.output, contains('dvm setup'));
    });

    test('fails when the shim runs a dvm binary that is gone', () async {
      makeHealthy();
      harness.fileSystem.file('/usr/local/bin/dvm').deleteSync();

      expect(await harness.run(['doctor']), 1);
      expect(
        harness.output,
        contains('runs /usr/local/bin/dvm, which no longer exists'),
      );
    });

    test('fails when the shim is not recognisable as one of ours', () async {
      makeHealthy();
      harness.fileSystem
          .file('/dvm/shims/dart')
          .writeAsStringSync('#!/bin/sh\necho hello\n');

      expect(await harness.run(['doctor']), 1);
      expect(harness.output, contains('not recognisable as a dvm shim'));
    });
  });

  group('shell', () {
    test('fails on a dvm shell function, naming the file and the line',
        () async {
      makeHealthy();
      harness.fileSystem.file('/home/dev/.zshrc')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          'export EDITOR=vim\n'
          '[ -s "\$HOME/.dvm/scripts/dvm" ] && . "\$HOME/.dvm/scripts/dvm"\n',
        );

      expect(await harness.run(['doctor']), 1);
      expect(harness.output, contains('/home/dev/.zshrc:2:'));
      expect(harness.output, contains('resolved before PATH is searched'));
      expect(harness.output, contains('cbracken/dvm'));
    });

    test('warns, without failing, about an older dvm sharing the home',
        () async {
      makeHealthy();
      harness.fileSystem.directory('/dvm/darts/1.24.3').createSync(
            recursive: true,
          );

      expect(await harness.run(['doctor']), 0);
      expect(harness.output, contains('warn'));
      expect(harness.output, contains('/dvm/darts'));
      expect(harness.output, contains('dvm migrate'));
    });
  });

  group('config', () {
    test('fails when the global default is not installed', () async {
      makeHealthy();
      harness.writeConfig(const DvmConfig(global: '3.13.2'));

      expect(await harness.run(['doctor']), 1);
      expect(
        harness.output,
        contains('the global default is Dart 3.13.2, which is not installed'),
      );
      expect(harness.output, contains('dvm install 3.13.2'));
    });

    test('fails on a config.json that is not valid JSON', () async {
      makeHealthy();
      harness.fileSystem.file('/dvm/config.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"global": ');

      expect(await harness.run(['doctor']), 1);
      expect(harness.output, contains('not valid JSON'));
    });

    test('passes when the global default is installed', () async {
      makeHealthy();
      harness
        ..installVersion('3.13.2')
        ..writeConfig(const DvmConfig(global: '3.13.2'));

      expect(await harness.run(['doctor']), 0);
      expect(
          harness.output,
          contains('the global default Dart 3.13.2 is '
              'installed'));
    });
  });

  group('project', () {
    test('fails when the version this project pins is not installed', () async {
      makeHealthy();
      harness.fileSystem.file('/project/.dvmrc').writeAsStringSync('3.9.0');

      expect(await harness.run(['doctor']), 1);
      expect(
        harness.output,
        contains('/project/.dvmrc pins Dart 3.9.0, which is not installed'),
      );
    });

    test('fails on a stale .dvm/dart_sdk symlink', () async {
      makeHealthy();
      harness.installVersion('3.9.0');
      harness.fileSystem.file('/project/.dvmrc').writeAsStringSync('3.9.0');
      // What `dvm remove` of a version some project still points at leaves:
      // the link outlives the directory it names.
      harness.fileSystem
          .link('/project/.dvm/dart_sdk')
          .createSync('/dvm/versions/3.7.0', recursive: true);

      expect(await harness.run(['doctor']), 1);
      expect(harness.output, contains('is a stale symlink'));
      expect(harness.output, contains('/dvm/versions/3.7.0'));
      expect(harness.output, contains('dvm use 3.9.0'));
    });

    test('warns when the symlink points somewhere other than the pin',
        () async {
      makeHealthy();
      harness
        ..installVersion('3.9.0')
        ..installVersion('3.13.2');
      harness.fileSystem.file('/project/.dvmrc').writeAsStringSync('3.9.0');
      harness.fileSystem
          .link('/project/.dvm/dart_sdk')
          .createSync('/dvm/versions/3.13.2', recursive: true);

      expect(await harness.run(['doctor']), 0);
      expect(harness.output, contains('but this project pins Dart 3.9.0'));
    });

    test('is quiet about projects with no pin', () async {
      makeHealthy();

      expect(await harness.run(['doctor']), 0);
      expect(harness.output, contains('no .dvmrc at or above /project'));
    });
  });

  test('reports several problems in one run', () async {
    // Nothing set up at all: no shim, no PATH entry, and a global pointing at
    // a version that is not there.
    harness.writeConfig(const DvmConfig(global: '3.13.2'));

    expect(await harness.run(['doctor']), 1);
    expect(harness.output, contains('3 problems, 0 warnings.'));
  });
}

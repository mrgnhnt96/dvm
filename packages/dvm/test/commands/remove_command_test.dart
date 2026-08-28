import 'package:dvm_cli/dvm.dart';
import 'package:test/test.dart';

import 'harness.dart';

void main() {
  late CommandHarness harness;

  setUp(() => harness = CommandHarness());

  test('deletes the SDK from the cache', () async {
    harness
      ..installVersion('3.9.0')
      ..installVersion('3.13.2');

    expect(await harness.run(['remove', '3.9.0']), 0);

    expect(harness.fileSystem.directory('/dvm/versions/3.9.0').existsSync(),
        isFalse);
    expect(harness.fileSystem.directory('/dvm/versions/3.13.2').existsSync(),
        isTrue);
    expect(harness.output, contains('Removed Dart 3.9.0'));
  });

  test('a version that is not installed is reported, not crashed on', () async {
    expect(await harness.run(['remove', '3.9.0']), 1);
    expect(harness.errors, contains('not installed'));
    expect(harness.errors, contains('dvm list'));
  });

  group('refusing to break something', () {
    test('refuses a version an alias points at, naming the alias', () async {
      harness
        ..installVersion('3.9.0')
        ..writeConfig(const DvmConfig(aliases: {'work': '3.9.0'}));

      expect(await harness.run(['remove', '3.9.0']), 1);

      expect(harness.errors, contains('Refusing to remove Dart 3.9.0'));
      expect(harness.errors, contains('the alias "work"'));
      expect(harness.errors, contains('--force'));
      expect(harness.fileSystem.directory('/dvm/versions/3.9.0').existsSync(),
          isTrue,
          reason: 'a refusal must not delete anything');
    });

    test('refuses when an alias reaches it through another alias', () async {
      harness
        ..installVersion('3.9.0')
        ..writeConfig(
          const DvmConfig(aliases: {'work': '3.9.0', 'current': 'work'}),
        );

      expect(await harness.run(['remove', '3.9.0']), 1);
      expect(harness.errors, contains('the alias "current"'));
    });

    test('refuses the global default, naming it', () async {
      harness
        ..installVersion('3.9.0')
        ..writeConfig(const DvmConfig(global: '3.9.0'));

      expect(await harness.run(['remove', '3.9.0']), 1);
      expect(harness.errors, contains('the global default'));
      expect(harness.fileSystem.directory('/dvm/versions/3.9.0').existsSync(),
          isTrue);
    });

    test('--force removes it anyway and says what now dangles', () async {
      harness
        ..installVersion('3.9.0')
        ..writeConfig(
          const DvmConfig(global: '3.9.0', aliases: {'work': '3.9.0'}),
        );

      expect(await harness.run(['remove', '3.9.0', '--force']), 0);

      expect(harness.fileSystem.directory('/dvm/versions/3.9.0').existsSync(),
          isFalse);
      expect(
          harness.errors,
          contains('now point at a version that is not '
              'installed'));
      expect(harness.errors, contains('the alias "work"'));
    });

    test('a channel record does not block removal', () async {
      harness
        ..installVersion('3.13.2')
        ..writeConfig(const DvmConfig(channels: {'stable': '3.13.2'}));

      expect(await harness.run(['remove', '3.13.2']), 0);
    });
  });

  test('removing a channel version forgets the stale record', () async {
    harness
      ..installVersion('3.13.2')
      ..writeConfig(
        const DvmConfig(
            channels: {'stable': '3.13.2', 'beta': '3.14.0-1.beta'}),
      );

    await harness.run(['remove', '3.13.2']);

    // A record naming a version that is gone would make `dvm use stable`
    // claim to know exactly which SDK stable is, then fail to find it.
    expect(harness.readConfig().channels, {'beta': '3.14.0-1.beta'});
    expect(harness.output, contains('dvm install stable'));
  });

  test('an alias can be used to name what to remove', () async {
    harness
      ..installVersion('3.9.0')
      ..writeConfig(const DvmConfig(aliases: {'work': '3.9.0'}));

    // The alias still counts as a dependent, so this needs --force: the point
    // is that the name resolves to the right directory.
    expect(await harness.run(['remove', 'work', '--force']), 0);
    expect(harness.fileSystem.directory('/dvm/versions/3.9.0').existsSync(),
        isFalse);
  });

  test('warns when this project pinned the version just removed', () async {
    harness.installVersion('3.9.0');
    harness.fileSystem.file('/project/.dvmrc').writeAsStringSync('3.9.0');

    expect(await harness.run(['remove', '3.9.0']), 0);
    expect(
        harness.errors,
        contains('/project/.dvmrc pins the version just '
            'removed'));
  });

  group('bad usage', () {
    test('naming nothing is a usage error', () async {
      expect(await harness.run(['remove']), usageExitCode);
      expect(harness.errors, contains('Name a version to remove'));
    });

    test('naming two versions is a usage error', () async {
      expect(await harness.run(['remove', '3.9.0', '3.13.2']), usageExitCode);
      expect(harness.errors, contains('one version at a time'));
    });
  });
}

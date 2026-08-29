import 'package:dvm_cli/dvm.dart';
import 'package:test/test.dart';

import 'harness.dart';

void main() {
  late CommandHarness harness;

  setUp(() => harness = CommandHarness());

  group('pinning a project', () {
    test('writes the canonical JSON .dvmrc and a working symlink', () async {
      harness.installVersion('3.9.0');

      expect(await harness.run(['use', '3.9.0']), 0);

      // The canonical form, byte for byte: a `.dvmrc` is committed and read by
      // other tools, so what `use` writes is part of the contract.
      expect(harness.readDvmrc(), '{\n  "dart": "3.9.0"\n}\n');

      final link = harness.fileSystem.link('/project/.dvm/dart_sdk');
      expect(link.targetSync(), '/dvm/versions/3.9.0');
      // Working, not merely present: the SDK has to be reachable *through* the
      // link, which is the only thing an IDE pointed at it cares about.
      expect(
        harness.fileSystem.file('/project/.dvm/dart_sdk/bin/dart').existsSync(),
        isTrue,
      );
    });

    test('says what to commit and what to ignore', () async {
      harness.installVersion('3.9.0');
      await harness.run(['use', '3.9.0']);

      expect(harness.output, contains('/project/.dvmrc'));
      expect(harness.output, contains('commit this'));
      expect(harness.output, contains('.dvm/'));
      expect(harness.output, contains('--gitignore'));
    });

    test('repinning moves the symlink instead of failing on it', () async {
      harness
        ..installVersion('3.9.0')
        ..installVersion('3.13.2');
      await harness.run(['use', '3.9.0']);

      expect(await harness.run(['use', '3.13.2']), 0);
      expect(
        harness.fileSystem.link('/project/.dvm/dart_sdk').targetSync(),
        '/dvm/versions/3.13.2',
      );
      expect(harness.readDvmrc(), contains('3.13.2'));
    });

    test('a .dvm/dart_sdk that is not a symlink is refused, not clobbered',
        () async {
      harness.installVersion('3.9.0');
      harness.fileSystem.file('/project/.dvm/dart_sdk')
        ..createSync(recursive: true)
        ..writeAsStringSync('someone else put this here');

      expect(await harness.run(['use', '3.9.0']), 1);
      expect(harness.errors, contains('is not a symlink'));
      expect(
        harness.fileSystem.file('/project/.dvm/dart_sdk').readAsStringSync(),
        'someone else put this here',
      );
    });
  });

  group('the one governing .dvmrc', () {
    /// A nested package with an existing pin at the repository root, and the
    /// user standing in the package. This is the shape every test here needs.
    void nestedUnderPinnedRoot({String rootPin = '3.13.2'}) {
      harness.fileSystem.file('/project/.dvmrc').writeAsStringSync(rootPin);
      harness.fileSystem
          .directory('/project/packages/app')
          .createSync(recursive: true);
      harness.fileSystem.currentDirectory = '/project/packages/app';
    }

    test('updates the ancestor .dvmrc instead of creating a nested one',
        () async {
      harness.installVersion('3.9.0');
      nestedUnderPinnedRoot();

      expect(await harness.run(['use', '3.9.0']), 0);

      expect(harness.readDvmrc('/project/.dvmrc'), contains('3.9.0'),
          reason: 'the pin that governs this directory is the one that must '
              'change');
      // Explicitly absent: a second .dvmrc here would shadow the one above it,
      // and nothing would say so.
      expect(
        harness.fileSystem.file('/project/packages/app/.dvmrc').existsSync(),
        isFalse,
        reason: 'a nested .dvmrc must never appear by accident',
      );
    });

    test('what it pinned resolves from the directory it was run in', () async {
      harness.installVersion('3.9.0');
      nestedUnderPinnedRoot();

      await harness.run(['use', '3.9.0']);
      harness.clearOutput();

      // The point of the whole leaf: write and read agree. `which` runs the
      // resolver, so this is rule 2 answering with the pin `use` just wrote.
      expect(await harness.run(['which']), 0);
      expect(harness.output, contains('3.9.0'));
      expect(harness.output, contains('/project/.dvmrc'));
    });

    test('names the file it changed, by absolute path', () async {
      harness.installVersion('3.9.0');
      nestedUnderPinnedRoot();

      await harness.run(['use', '3.9.0']);

      expect(harness.output, contains('/project/.dvmrc'));
      expect(harness.output, contains('/project/packages/app'),
          reason: 'the user is standing three levels below the file that '
              'changed and must not have to guess');
    });

    test('the symlink and the gitignore notice follow the .dvmrc', () async {
      harness.installVersion('3.9.0');
      nestedUnderPinnedRoot();

      await harness.run(['use', '3.9.0']);

      // Beside the pin, which is also where `dvm doctor` looks for it.
      expect(
        harness.fileSystem.link('/project/.dvm/dart_sdk').targetSync(),
        '/dvm/versions/3.9.0',
      );
      expect(
        harness.fileSystem.directory('/project/packages/app/.dvm').existsSync(),
        isFalse,
      );
      expect(harness.output, contains('/project/.gitignore'));
    });

    test('--gitignore writes beside the .dvmrc, not beside the user', () async {
      harness.installVersion('3.9.0');
      nestedUnderPinnedRoot();

      expect(await harness.run(['use', '3.9.0', '--gitignore']), 0);

      expect(
        harness.fileSystem.file('/project/.gitignore').readAsStringSync(),
        contains('.dvm/'),
      );
      expect(
        harness.fileSystem
            .file('/project/packages/app/.gitignore')
            .existsSync(),
        isFalse,
      );
    });

    test('with no .dvmrc anywhere above, one is created where you stand',
        () async {
      harness.installVersion('3.9.0');
      harness.fileSystem
          .directory('/project/packages/app')
          .createSync(recursive: true);
      harness.fileSystem.currentDirectory = '/project/packages/app';

      expect(await harness.run(['use', '3.9.0']), 0);

      expect(
          harness.readDvmrc('/project/packages/app/.dvmrc'), contains('3.9.0'));
      expect(harness.fileSystem.file('/project/.dvmrc').existsSync(), isFalse);
    });

    test('the walk reaches the filesystem root without crashing', () async {
      harness.installVersion('3.9.0');
      // Standing at the root itself: `parent` of `/` is `/`, which is where a
      // walk that does not check for a fixed point spins forever.
      harness.fileSystem.currentDirectory = '/';

      expect(await harness.run(['use', '3.9.0']), 0);
      expect(harness.readDvmrc('/.dvmrc'), contains('3.9.0'));
    });

    test('--here creates the nested pin the monorepo case wants', () async {
      harness.installVersion('3.9.0');
      nestedUnderPinnedRoot();

      expect(await harness.run(['use', '3.9.0', '--here']), 0);

      expect(
          harness.readDvmrc('/project/packages/app/.dvmrc'), contains('3.9.0'));
      expect(harness.readDvmrc('/project/.dvmrc'), '3.13.2',
          reason: 'the repository root keeps its own pin');
      expect(
        harness.fileSystem
            .link('/project/packages/app/.dvm/dart_sdk')
            .targetSync(),
        '/dvm/versions/3.9.0',
        reason: 'the symlink follows the .dvmrc, which is now the nested one',
      );
    });

    test('--here says that the new pin shadows the one above it', () async {
      harness.installVersion('3.9.0');
      nestedUnderPinnedRoot();

      await harness.run(['use', '3.9.0', '--here']);

      expect(harness.output, contains('shadows'));
      expect(harness.output, contains('/project/.dvmrc'),
          reason: 'the ancestor that stopped applying has to be named');
    });

    test('--here on a directory that already holds the pin just updates it',
        () async {
      harness
        ..installVersion('3.9.0')
        ..installVersion('3.13.2');
      await harness.run(['use', '3.13.2']);
      harness.clearOutput();

      expect(await harness.run(['use', '3.9.0', '--here']), 0);
      expect(harness.readDvmrc(), contains('3.9.0'));
      expect(harness.output, isNot(contains('shadows')),
          reason: 'nothing was shadowed; the same file was rewritten');
    });

    test('--global never goes looking for a .dvmrc', () async {
      harness.installVersion('3.9.0');
      nestedUnderPinnedRoot();

      expect(await harness.run(['use', '3.9.0', '--global']), 0);

      expect(harness.readConfig().global, '3.9.0');
      expect(harness.readDvmrc('/project/.dvmrc'), '3.13.2',
          reason: 'a machine default must not rewrite a project pin');
      expect(
        harness.fileSystem.file('/project/packages/app/.dvmrc').existsSync(),
        isFalse,
      );
    });
  });

  group('auto-install', () {
    test('installs a version that is not in the cache', () async {
      expect(await harness.run(['use', '3.9.0']), 0);

      expect(harness.installer.requests.single.version, '3.9.0');
      expect(harness.output, contains('not installed yet'));
      expect(
          harness.fileSystem.file('/dvm/versions/3.9.0/bin/dart').existsSync(),
          isTrue);
    });

    test('does not install a version that is already there', () async {
      harness.installVersion('3.9.0');

      expect(await harness.run(['use', '3.9.0']), 0);
      expect(harness.installer.requests, isEmpty);
    });

    test('an installer that produces nothing is a failure, not a success',
        () async {
      harness.installer.produceNothing = true;

      expect(await harness.run(['use', '3.9.0']), 1);
      expect(harness.errors, contains('without leaving an SDK'));
      expect(harness.fileSystem.file('/project/.dvmrc').existsSync(), isFalse,
          reason: 'nothing should be pinned to an SDK that is not there');
    });
  });

  group('names', () {
    test('an alias is followed and the concrete version is written', () async {
      harness
        ..installVersion('3.9.0')
        ..writeConfig(const DvmConfig(aliases: {'work': '3.9.0'}));

      expect(await harness.run(['use', 'work']), 0);

      // The concrete version, not the alias: `.dvmrc` is committed, and the
      // alias only exists in this machine's config.json.
      expect(harness.readDvmrc(), '{\n  "dart": "3.9.0"\n}\n');
      expect(harness.output, contains('work -> 3.9.0'));
    });

    test('a channel uses the version recorded at install time', () async {
      harness
        ..installVersion('3.13.2')
        ..writeConfig(const DvmConfig(channels: {'stable': '3.13.2'}));

      expect(await harness.run(['use', 'stable']), 0);
      expect(harness.readDvmrc(), contains('3.13.2'));
    });

    test('a channel with nothing recorded says what to install', () async {
      expect(await harness.run(['use', 'stable']), 1);
      expect(harness.errors, contains('dvm install stable'));
      expect(harness.installer.requests, isEmpty,
          reason: 'dvm cannot know what version to install for a channel it '
              'has never installed');
    });

    test('installing for a channel passes the channel through', () async {
      harness.writeConfig(const DvmConfig(channels: {'beta': '3.14.0-172.2'}));

      expect(await harness.run(['use', 'beta']), 0);
      expect(harness.installer.requests.single.channel, Channel.beta);
    });
  });

  group('--gitignore', () {
    test('appends the rule to an existing .gitignore', () async {
      harness.installVersion('3.9.0');
      harness.fileSystem
          .file('/project/.gitignore')
          .writeAsStringSync('build/\n');

      expect(await harness.run(['use', '3.9.0', '--gitignore']), 0);

      final contents =
          harness.fileSystem.file('/project/.gitignore').readAsStringSync();
      expect(contents, startsWith('build/\n'));
      expect(contents, contains('.dvm/'));
      expect(harness.output, contains('Added `.dvm/`'));
    });

    test('creates a .gitignore when there is none', () async {
      harness.installVersion('3.9.0');

      await harness.run(['use', '3.9.0', '--gitignore']);

      expect(
        harness.fileSystem.file('/project/.gitignore').readAsStringSync(),
        contains('.dvm/'),
      );
    });

    test('an already-ignored project is left alone', () async {
      harness.installVersion('3.9.0');
      harness.fileSystem
          .file('/project/.gitignore')
          .writeAsStringSync('# stuff\n.dvm/\n');

      await harness.run(['use', '3.9.0', '--gitignore']);

      expect(
        harness.fileSystem.file('/project/.gitignore').readAsStringSync(),
        '# stuff\n.dvm/\n',
      );
      expect(harness.output, contains('already ignored'));
    });

    test('without the flag nothing is written to .gitignore', () async {
      harness.installVersion('3.9.0');
      harness.fileSystem
          .file('/project/.gitignore')
          .writeAsStringSync('build/\n');

      await harness.run(['use', '3.9.0']);

      expect(
        harness.fileSystem.file('/project/.gitignore').readAsStringSync(),
        'build/\n',
      );
    });
  });

  group('--global', () {
    test('sets the default instead of pinning the project', () async {
      harness.installVersion('3.9.0');

      expect(await harness.run(['use', '3.9.0', '--global']), 0);

      expect(harness.readConfig().global, '3.9.0');
      expect(harness.fileSystem.file('/project/.dvmrc').existsSync(), isFalse);
      expect(
        harness.fileSystem.directory('/project/.dvm').existsSync(),
        isFalse,
      );
    });

    test('records the concrete version an alias led to', () async {
      harness
        ..installVersion('3.9.0')
        ..writeConfig(const DvmConfig(aliases: {'work': '3.9.0'}));

      await harness.run(['use', 'work', '--global']);

      expect(harness.readConfig().global, '3.9.0');
    });
  });

  group('bad usage', () {
    test('naming nothing is a usage error', () async {
      expect(await harness.run(['use']), usageExitCode);
      expect(harness.errors, contains('Name a version'));
    });

    test('naming two versions is a usage error', () async {
      expect(await harness.run(['use', '3.9.0', '3.13.2']), usageExitCode);
      expect(harness.errors, contains('one version at a time'));
    });
  });
}

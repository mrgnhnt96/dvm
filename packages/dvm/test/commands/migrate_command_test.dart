import 'package:args/command_runner.dart';
import 'package:dvm_cli/dvm.dart';
import 'package:dvm_cli/src/commands/migrate_command.dart';
import 'package:dvm_cli/src/core/migrate.dart';
import 'package:file/file.dart';
import 'package:test/test.dart';

import 'harness.dart';

/// Everything here runs against [CommandHarness]'s `MemoryFileSystem` with
/// `DVM_HOME=/dvm`. Nothing can reach the real `~/.dvm`, which on the
/// maintainer's machine holds the only copy of three Dart SDKs — the exact
/// thing this command exists to not destroy.
void main() {
  late CommandHarness harness;

  setUp(() => harness = CommandHarness());

  /// Rebuilds the cbracken/dvm layout as it actually is on disk: a git
  /// checkout with the downloaded SDKs sitting untracked in `darts/`.
  void writeLegacyInstall({
    Map<String, String?> darts = const {
      '3.9.0': '3.9.0',
      '3.12.0': '3.12.0',
      '3.13.2': '3.13.2',
    },
    String? activeVersion = '3.13.2',
  }) {
    final fs = harness.fileSystem;
    const home = CommandHarness.dvmHome;

    fs.file('$home/.git/config')
      ..createSync(recursive: true)
      ..writeAsStringSync('[core]\n');
    fs.file('$home/.gitignore')
      ..createSync(recursive: true)
      ..writeAsStringSync('# DVM\ndarts\nenvironments/default\n');
    fs.file('$home/LICENSE')
      ..createSync(recursive: true)
      ..writeAsStringSync('Apache 2.0\n');
    fs.file('$home/README.md')
      ..createSync(recursive: true)
      ..writeAsStringSync('# dvm\n');
    fs.file('$home/VERSION')
      ..createSync(recursive: true)
      ..writeAsStringSync('1.4.0\n');
    fs.file('$home/scripts/dvm')
      ..createSync(recursive: true)
      ..writeAsStringSync('dvm() { : ; }\n');

    if (activeVersion != null) {
      // Verbatim shape of the real file: a shell snippet, not a version.
      fs.file('$home/environments/default')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          'export DVM_ROOT; DVM_ROOT="\$DVM_ROOT"\n'
          'export DART_SDK; DART_SDK="$home/darts/$activeVersion"\n'
          'PATH="\$DVM_ROOT/darts/$activeVersion/bin:\$PATH"\n',
        );
    }

    for (final entry in darts.entries) {
      final sdk = '$home/darts/${entry.key}';
      fs.file('$sdk/bin/dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\n');
      fs.file('$sdk/lib/core/core.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('library core;\n');
      if (entry.value case final version?) {
        fs.file('$sdk/version')
          ..createSync(recursive: true)
          ..writeAsStringSync('$version\n');
      }
    }
  }

  /// Every path under [root], sorted, for before/after comparison.
  List<String> treeOf(String root) {
    final directory = harness.fileSystem.directory(root);
    if (!directory.existsSync()) return const [];
    return [
      for (final entity in directory.listSync(recursive: true))
        '${entity.path}${entity is Directory ? '/' : ''}',
    ]..sort();
  }

  /// Runs `dvm migrate` with the prompts answered from [answers].
  ///
  /// The real entrypoint reads answers from stdin, which a test must never
  /// depend on, so the command is built here with the reader injected. It is
  /// the same [MigrateCommand] `lib/dvm.dart` registers, driven through a
  /// `CommandRunner` so the flags are parsed exactly as they are in
  /// production.
  Future<int> runMigrate(
    List<String> args, {
    List<String> answers = const [],
  }) async {
    final pending = List.of(answers);
    final context = DvmContext.wire(
      fileSystem: harness.fileSystem,
      environment: harness.environment,
      platformVersion: '3.13.2 (stable) on "macos_arm64"',
      out: harness.out,
      err: harness.err,
      installer: harness.installer,
    );
    final runner = CommandRunner<int>('dvm', 'test')
      ..addCommand(
        MigrateCommand(
          context: context,
          readLine: () => pending.isEmpty ? null : pending.removeAt(0),
        ),
      );
    return await runner.run(['migrate', ...args]) ?? 0;
  }

  group('detection', () {
    test('says there is nothing to migrate on a fresh install', () async {
      final code = await harness.run(['migrate']);

      expect(code, 0);
      expect(harness.output, contains('Nothing to migrate'));
      expect(harness.output, contains(CommandHarness.dvmHome));
      expect(harness.errors, isEmpty);
    });

    test('an ordinary dvm home with only versions/ is not a cbracken install',
        () async {
      harness.installVersion('3.9.0');

      final code = await harness.run(['migrate']);

      expect(code, 0);
      expect(harness.output, contains('Nothing to migrate'));
      // The SDK dvm itself installed must not be reported as legacy.
      expect(harness.output, isNot(contains('3.9.0')));
    });

    test('reports the cbracken signature it found', () async {
      writeLegacyInstall();

      await runMigrate(['--dry-run']);

      expect(harness.output, contains('Found an older dvm (cbracken/dvm)'));
      for (final marker in const [
        'darts/',
        'scripts/',
        'environments/',
        '.git/',
        'VERSION',
        'LICENSE',
        'README.md',
        '.gitignore',
      ]) {
        expect(harness.output, contains(marker), reason: 'missing $marker');
      }
    });
  });

  group('--dry-run', () {
    test('changes nothing at all', () async {
      writeLegacyInstall();
      final before = treeOf(CommandHarness.dvmHome);

      final code = await runMigrate(['--dry-run']);

      expect(code, 0);
      expect(treeOf(CommandHarness.dvmHome), before);
      expect(
        harness.fileSystem.directory('${CommandHarness.dvmHome}/versions')
            .existsSync(),
        isFalse,
      );
      expect(harness.readConfig().global, isNull);
      expect(harness.output, contains('Nothing was changed.'));
    });

    test('lists every move and every deletion a --clean would make', () async {
      writeLegacyInstall();

      await runMigrate(['--dry-run']);
      final out = harness.output;

      expect(out, contains('Would move:'));
      for (final version in const ['3.9.0', '3.12.0', '3.13.2']) {
        expect(
          out,
          contains('/dvm/darts/$version  ->  /dvm/versions/$version'),
        );
      }

      expect(out, contains('Would delete'));
      for (final leftover in const [
        '/dvm/scripts',
        '/dvm/environments',
        '/dvm/.git',
        '/dvm/VERSION',
        '/dvm/LICENSE',
        '/dvm/README.md',
        '/dvm/.gitignore',
      ]) {
        expect(out, contains(leftover), reason: 'missing $leftover');
      }
      // darts/ still holds SDKs, so it is not on the deletion list yet.
      expect(out, contains('darts/ itself stays until every SDK'));
    });

    test('previews the global question instead of asking it', () async {
      writeLegacyInstall();

      // No answers queued: reaching a real prompt would take "no" and the
      // assertion below would still pass, so assert on the wording too.
      await runMigrate(['--dry-run']);

      expect(harness.output, contains('Would ask whether to make Dart 3.13.2'));
      expect(harness.readConfig().global, isNull);
    });
  });

  group('migrating', () {
    test('moves every SDK across and leaves darts/ empty', () async {
      writeLegacyInstall();

      final code = await runMigrate([], answers: ['y']);

      expect(code, 0);
      for (final version in const ['3.9.0', '3.12.0', '3.13.2']) {
        final moved = harness.paths.versionDir(version);
        expect(moved.existsSync(), isTrue, reason: '$version did not arrive');
        expect(
          harness.paths.dartExecutable(moved).existsSync(),
          isTrue,
          reason: "$version arrived without its bin/dart",
        );
        expect(
          harness.fileSystem.directory('/dvm/darts/$version').existsSync(),
          isFalse,
          reason: '$version is still in darts/',
        );
        expect(harness.output, contains('Moved Dart $version'));
      }
      expect(harness.fileSystem.directory('/dvm/darts').listSync(), isEmpty);
    });

    test('skips a version already in versions/ instead of overwriting it',
        () async {
      writeLegacyInstall();
      // A different SDK under the same version number, to prove which copy
      // survives.
      harness.installVersion('3.12.0');
      harness.fileSystem.file('/dvm/versions/3.12.0/MARKER')
        ..createSync(recursive: true)
        ..writeAsStringSync('the copy dvm already had');

      final code = await runMigrate([], answers: ['y']);

      expect(code, 0);
      expect(
        harness.fileSystem.file('/dvm/versions/3.12.0/MARKER').existsSync(),
        isTrue,
        reason: 'the installed 3.12.0 was overwritten',
      );
      expect(
        harness.fileSystem.directory('/dvm/darts/3.12.0').existsSync(),
        isTrue,
        reason: 'the legacy 3.12.0 should be left where it is, not deleted',
      );
      expect(
        harness.output,
        contains('SKIP: Dart 3.12.0 is already installed'),
      );
      // The other two still move.
      expect(harness.paths.versionDir('3.9.0').existsSync(), isTrue);
      expect(harness.paths.versionDir('3.13.2').existsSync(), isTrue);
    });

    test('believes the version file over the directory name', () async {
      // The directory says 3.9.0; the SDK inside says 3.10.4.
      writeLegacyInstall(darts: {'3.9.0': '3.10.4'}, activeVersion: null);

      final code = await runMigrate([]);

      expect(code, 0);
      expect(harness.paths.versionDir('3.10.4').existsSync(), isTrue);
      expect(harness.paths.versionDir('3.9.0').existsSync(), isFalse);
      expect(
        harness.output,
        contains('its version file says 3.10.4, not 3.9.0'),
      );
      expect(harness.output, contains('Moved Dart 3.10.4'));
    });

    test('migrates an SDK with no version file under its directory name',
        () async {
      writeLegacyInstall(darts: {'3.9.0': null}, activeVersion: null);

      final code = await runMigrate([]);

      expect(code, 0);
      expect(harness.paths.versionDir('3.9.0').existsSync(), isTrue);
      expect(harness.output, contains('no version file'));
    });

    test('refuses to let two entries claim the same version', () async {
      // darts/3.9.0 holds a 3.12.0 SDK, and darts/3.12.0 holds one too.
      writeLegacyInstall(
        darts: {'3.9.0': '3.12.0', '3.12.0': '3.12.0'},
        activeVersion: null,
      );

      final code = await runMigrate([]);

      expect(code, 0);
      expect(harness.paths.versionDir('3.12.0').existsSync(), isTrue);
      // Exactly one of them moved; the other is untouched, not overwritten.
      final remaining = harness.fileSystem
          .directory('/dvm/darts')
          .listSync()
          .map((e) => e.basename)
          .toList();
      expect(remaining, hasLength(1));
      expect(harness.output, contains('and dvm will not overwrite it'));
    });

    test('never deletes the cbracken files as part of the move', () async {
      writeLegacyInstall();

      await runMigrate([], answers: ['y']);

      for (final leftover in const [
        '/dvm/scripts/dvm',
        '/dvm/environments/default',
        '/dvm/VERSION',
        '/dvm/LICENSE',
        '/dvm/README.md',
        '/dvm/.gitignore',
      ]) {
        expect(
          harness.fileSystem.file(leftover).existsSync(),
          isTrue,
          reason: '$leftover was deleted by a plain migrate',
        );
      }
      expect(harness.fileSystem.directory('/dvm/.git').existsSync(), isTrue);
      expect(harness.output, contains('dvm migrate --clean'));
    });

    test('prints the shell rc reminder', () async {
      writeLegacyInstall();

      await runMigrate([], answers: ['y']);

      expect(harness.output, contains(r'. "$HOME/.dvm/scripts/dvm"'));
      expect(harness.output, contains('a function beats any binary on PATH'));
    });

    test('names the startup file that actually sources the older dvm',
        () async {
      writeLegacyInstall();
      harness.fileSystem.file('/home/dev/.zshrc')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          'export EDITOR=vim\n'
          '[ -s "\$HOME/.dvm/scripts/dvm" ] && . "\$HOME/.dvm/scripts/dvm"\n',
        );

      await runMigrate([], answers: ['y']);

      expect(harness.output, contains('/home/dev/.zshrc:2'));
    });
  });

  group('the global default', () {
    test('offers the version the older tool had active, and sets it on yes',
        () async {
      writeLegacyInstall();

      final code = await runMigrate([], answers: ['y']);

      expect(code, 0);
      expect(harness.output, contains('The older tool had Dart 3.13.2 active'));
      expect(harness.readConfig().global, '3.13.2');
      expect(harness.output, contains('Dart 3.13.2 is now your dvm default.'));
    });

    test('leaves the default alone on no', () async {
      writeLegacyInstall();

      await runMigrate([], answers: ['n']);

      expect(harness.readConfig().global, isNull);
      expect(harness.output, contains('Left the default alone'));
    });

    test('takes no answer as no', () async {
      writeLegacyInstall();

      await runMigrate([]);

      expect(harness.readConfig().global, isNull);
      expect(harness.errors, contains('taking that as no'));
    });

    test('--yes answers it without a terminal', () async {
      writeLegacyInstall();

      await runMigrate(['--yes']);

      expect(harness.readConfig().global, '3.13.2');
    });

    test('says the version is already the default rather than asking',
        () async {
      writeLegacyInstall();
      harness.writeConfig(const DvmConfig(global: '3.13.2'));

      await runMigrate([]);

      expect(harness.output, contains('already your dvm default'));
      expect(harness.readConfig().global, '3.13.2');
    });

    test('does not set a default naming an SDK that did not arrive', () async {
      // environments/default points at a version with no SDK behind it.
      writeLegacyInstall(darts: {'3.9.0': '3.9.0'}, activeVersion: '3.13.2');

      await runMigrate(['--yes']);

      expect(harness.readConfig().global, isNull);
      expect(harness.errors, contains('is not in /dvm/versions'));
    });

    test('reports an environments/default it cannot understand', () async {
      writeLegacyInstall(activeVersion: null);
      harness.fileSystem.file('/dvm/environments/default')
        ..createSync(recursive: true)
        ..writeAsStringSync('this file has been\nreplaced by prose\n');

      await runMigrate(['--yes']);

      expect(harness.readConfig().global, isNull);
      expect(harness.errors, contains('does not name a version'));
    });
  });

  group('--clean', () {
    test('refuses while any SDK is still in darts/', () async {
      writeLegacyInstall();

      final code = await runMigrate(['--clean'], answers: ['y']);

      expect(code, 1);
      expect(harness.errors, contains('refusing to clean up'));
      expect(harness.errors, contains('Run `dvm migrate` first.'));
      expect(harness.fileSystem.file('/dvm/scripts/dvm').existsSync(), isTrue);
      expect(harness.fileSystem.directory('/dvm/darts/3.9.0').existsSync(),
          isTrue);
    });

    test('deletes nothing without a yes', () async {
      writeLegacyInstall();
      await runMigrate(['--yes']);
      harness.clearOutput();

      final code = await runMigrate(['--clean'], answers: ['n']);

      expect(code, 0);
      expect(harness.output, contains('Left them alone.'));
      expect(harness.fileSystem.file('/dvm/scripts/dvm').existsSync(), isTrue);
      expect(harness.fileSystem.directory('/dvm/.git').existsSync(), isTrue);
    });

    test('deletes nothing when there is nobody to ask', () async {
      writeLegacyInstall();
      await runMigrate(['--yes']);
      harness.clearOutput();

      await runMigrate(['--clean']);

      expect(harness.fileSystem.file('/dvm/scripts/dvm').existsSync(), isTrue);
      expect(harness.errors, contains('taking that as no'));
    });

    test('removes the leftovers once the SDKs are across', () async {
      writeLegacyInstall();
      await runMigrate(['--yes']);
      harness.clearOutput();

      final code = await runMigrate(['--clean'], answers: ['y']);

      expect(code, 0);
      for (final leftover in const [
        '/dvm/scripts',
        '/dvm/environments',
        '/dvm/.git',
        '/dvm/VERSION',
        '/dvm/LICENSE',
        '/dvm/README.md',
        '/dvm/.gitignore',
        '/dvm/darts',
      ]) {
        expect(
          harness.fileSystem.typeSync(leftover, followLinks: false),
          FileSystemEntityType.notFound,
          reason: '$leftover survived --clean',
        );
      }
      // And the whole point: the SDKs are still there.
      for (final version in const ['3.9.0', '3.12.0', '3.13.2']) {
        expect(harness.paths.versionDir(version).existsSync(), isTrue);
      }
    });

    test('--clean --dry-run lists the deletions and changes nothing',
        () async {
      writeLegacyInstall();
      await runMigrate(['--yes']);
      harness.clearOutput();
      final before = treeOf(CommandHarness.dvmHome);

      final code = await runMigrate(['--clean', '--dry-run']);

      expect(code, 0);
      expect(harness.output, contains('These will be deleted'));
      expect(harness.output, contains('Nothing was changed.'));
      expect(treeOf(CommandHarness.dvmHome), before);
    });

    test('leaves darts/ alone when it still holds a skipped SDK', () async {
      writeLegacyInstall();
      harness.installVersion('3.12.0');
      await runMigrate(['--yes']);
      harness.clearOutput();

      // darts/3.12.0 was skipped, so it is still an unmigrated SDK... except
      // it is not: 3.12.0 IS installed. Cleaning must still not take darts/
      // with it, because that directory is somebody's only copy.
      final code = await runMigrate(['--clean'], answers: ['y']);

      expect(code, 0);
      expect(
        harness.fileSystem.directory('/dvm/darts/3.12.0').existsSync(),
        isTrue,
        reason: 'a non-empty darts/ was deleted',
      );
      expect(harness.fileSystem.file('/dvm/scripts/dvm').existsSync(), isFalse);
    });
  });

  group('Migrator', () {
    test('parses the version out of the real environments/default snippet',
        () {
      writeLegacyInstall();
      final migrator = Migrator(
        fileSystem: harness.fileSystem,
        paths: harness.paths,
      );

      expect(migrator.plan().activeVersion, '3.13.2');
    });

    test('a plan reads nothing into existence', () {
      writeLegacyInstall();
      final before = treeOf(CommandHarness.dvmHome);

      Migrator(fileSystem: harness.fileSystem, paths: harness.paths).plan();

      expect(treeOf(CommandHarness.dvmHome), before);
    });

    test('only reports a move once the destination is really there', () {
      writeLegacyInstall(darts: {'3.9.0': '3.9.0'}, activeVersion: null);
      final migrator = Migrator(
        fileSystem: harness.fileSystem,
        paths: harness.paths,
      );
      final plan = migrator.plan();

      final outcomes = migrator.apply(plan);

      expect(outcomes, hasLength(1));
      expect(outcomes.single.moved, isTrue);
      expect(outcomes.single.failure, isNull);
      expect(
        harness.paths.versionDir('3.9.0').listSync(),
        isNotEmpty,
      );
    });
  });
}

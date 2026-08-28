import 'package:dvm_cli/dvm.dart';
import 'package:dvm_cli/src/core/shell.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

void main() {
  late MemoryFileSystem fileSystem;

  ShellFacts factsFor(Map<String, String> environment) => ShellFacts(
        fileSystem: fileSystem,
        environment: {'HOME': '/home/dev', ...environment},
      );

  void writeRc(String path, String contents) => fileSystem.file(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

  setUp(() => fileSystem = MemoryFileSystem.test());

  group('shell detection', () {
    test(r'names the rc file for the shell in $SHELL', () {
      expect(factsFor({'SHELL': '/bin/zsh'}).primaryRcFile?.path,
          '/home/dev/.zshrc');
      expect(factsFor({'SHELL': '/bin/bash'}).primaryRcFile?.path,
          '/home/dev/.bashrc');
      expect(
        factsFor({'SHELL': '/opt/homebrew/bin/fish'}).primaryRcFile?.path,
        '/home/dev/.config/fish/config.fish',
      );
    });

    test('falls back to .profile when the environment does not say', () {
      final facts = factsFor(const {});

      expect(facts.shellPath, isNull);
      expect(facts.kind, ShellKind.posix);
      expect(facts.primaryRcFile?.path, '/home/dev/.profile');
    });

    test('has no rc file to name without a home directory', () {
      final facts = ShellFacts(
        fileSystem: fileSystem,
        environment: const {'SHELL': '/bin/zsh'},
      );

      expect(facts.home, isNull);
      expect(facts.primaryRcFile, isNull);
    });

    test('prepends the shims directory, in the shell being used', () {
      final shims = fileSystem.directory('/dvm/shims');

      expect(
        factsFor({'SHELL': '/bin/zsh'}).pathLine(shims),
        r'export PATH="/dvm/shims:$PATH"',
      );
      expect(
        factsFor({'SHELL': '/usr/bin/fish'}).pathLine(shims),
        'fish_add_path --prepend /dvm/shims',
      );
    });
  });

  group('shadow scan', () {
    test('finds the line that sources the older cbracken dvm', () {
      writeRc(
        '/home/dev/.zshrc',
        'export EDITOR=vim\n'
            '[ -s "\$HOME/.dvm/scripts/dvm" ] && . "\$HOME/.dvm/scripts/dvm"\n',
      );

      final scan = factsFor({'SHELL': '/bin/zsh'}).scanForShadows();

      expect(scan.shadows, hasLength(1));
      expect(scan.shadows.single.kind, ShadowKind.legacySource);
      expect(scan.shadows.single.line, 2);
      expect(scan.shadows.single.describe(), startsWith('/home/dev/.zshrc:2:'));
    });

    test('finds a dvm function and a dvm alias', () {
      writeRc('/home/dev/.bashrc', 'dvm() {\n  echo old\n}\n');
      writeRc('/home/dev/.profile', 'alias dvm="/opt/old/dvm"\n');

      final scan = factsFor({'SHELL': '/bin/bash'}).scanForShadows();

      expect(
        scan.shadows.map((shadow) => shadow.kind),
        containsAll([ShadowKind.function, ShadowKind.alias]),
      );
    });

    test('finds fish function syntax too', () {
      writeRc(
          '/home/dev/.config/fish/config.fish', 'function dvm\n  old\nend\n');

      final scan = factsFor({'SHELL': '/usr/bin/fish'}).scanForShadows();

      expect(scan.shadows.single.kind, ShadowKind.function);
    });

    test('scans every shell\'s startup files, not just the current one', () {
      // $SHELL is the variable that is wrong inside an editor terminal or a
      // CI runner; a function left in .zshrc still breaks the next login.
      writeRc('/home/dev/.zshrc', 'dvm() { echo old; }\n');

      final scan = factsFor({'SHELL': '/bin/bash'}).scanForShadows();

      expect(scan.shadows.single.file.path, '/home/dev/.zshrc');
    });

    test('ignores commented-out definitions', () {
      writeRc(
        '/home/dev/.zshrc',
        '# dvm() { echo old; }\n'
            '#[ -s "\$HOME/.dvm/scripts/dvm" ] && . "\$HOME/.dvm/scripts/dvm"\n',
      );

      expect(factsFor({'SHELL': '/bin/zsh'}).scanForShadows().isClean, isTrue);
    });

    test('says nothing about a machine with clean startup files', () {
      writeRc('/home/dev/.zshrc', 'export PATH="/dvm/shims:\$PATH"\n');

      final scan = factsFor({'SHELL': '/bin/zsh'}).scanForShadows();

      expect(scan.shadows, isEmpty);
      expect(scan.unreadable, isEmpty);
    });
  });

  group('legacy install', () {
    DvmPaths pathsFor() => DvmPaths(
          fileSystem: fileSystem,
          environment: const {'DVM_HOME': '/dvm'},
        );

    test('is not reported when only this dvm is there', () {
      fileSystem.directory('/dvm/versions/3.9.0').createSync(recursive: true);

      expect(LegacyDvmInstall.detect(pathsFor()).isPresent, isFalse);
    });

    test('names the script and the directories cbracken dvm leaves', () {
      fileSystem.file('/dvm/scripts/dvm').createSync(recursive: true);
      fileSystem.directory('/dvm/darts/1.24.3').createSync(recursive: true);

      final legacy = LegacyDvmInstall.detect(pathsFor());

      expect(legacy.isPresent, isTrue);
      expect(legacy.script?.path, '/dvm/scripts/dvm');
      expect(
        legacy.directories.map((directory) => directory.path),
        ['/dvm/darts'],
      );
    });
  });
}

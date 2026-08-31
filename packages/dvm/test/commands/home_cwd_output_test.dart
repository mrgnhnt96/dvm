import 'package:test/test.dart';

import 'harness.dart';

/// What `doctor` and `setup` print when the working directory is `$HOME`.
///
/// The case nobody tried. `DvmContext.display` renders a path relative when it
/// lies under the working directory, and that was approved on the reasoning
/// that `~/.dvm/shims` is "never under the working directory". Standing in
/// `$HOME` — which is exactly where people stand to run `dvm setup` and `dvm
/// doctor` — it is, so doctor printed `.dvm/shims is not on PATH` three lines
/// above the absolute `export PATH="/home/dev/.dvm/shims:$PATH"` that fixes it.
///
/// The rule these pin: a path that names a PATH ENTRY, a shell startup file, or
/// anything in the dvm home prints ABSOLUTE, wherever the user is standing.
/// Project files — `.dvmrc`, `.dvm/dart_sdk` — keep the relative rendering, and
/// the last group here is the guard on that half.
void main() {
  late CommandHarness harness;

  const home = '/home/dev';
  const dvmHome = '$home/.dvm';
  const shims = '$dvmHome/shims';
  const binary = '$dvmHome/bin/dvm';

  /// A machine set up the way `install.sh` leaves one, with `$HOME` as the
  /// working directory and the dvm home inside it.
  void standInHome() {
    harness.environment['DVM_HOME'] = dvmHome;
    harness.environment['SHELL'] = '/bin/zsh';
    harness.fileSystem.directory(home).createSync(recursive: true);
    harness.fileSystem.currentDirectory = home;
    harness.fileSystem.file(binary)
      ..createSync(recursive: true)
      ..writeAsStringSync('a compiled binary');
    harness.fileSystem.file('$shims/dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('#!/bin/sh\nexec "$binary" exec dart "\$@"\n');
  }

  setUp(() => harness = CommandHarness());

  group('doctor, standing in \$HOME', () {
    test('names the PATH entry absolutely, in the same spelling as the fix',
        () async {
      standInHome();
      harness.environment['PATH'] = '/usr/bin';

      expect(await harness.run(['doctor']), 1);

      expect(harness.output, contains('$shims is not on PATH'));
      // The bug itself: the summary and the remedy naming one directory two
      // ways, three lines apart. A relative PATH entry is not merely ugly —
      // a shell resolves it against whatever directory each process is in.
      expect(harness.output,
          contains(r'export PATH="/home/dev/.dvm/shims:$PATH"'));
      expect(harness.output, isNot(contains(' .dvm/shims is not on PATH')));
    });

    test('names the shim and the dvm binary absolutely', () async {
      standInHome();
      harness.environment['PATH'] = shims;

      await harness.run(['doctor']);

      expect(harness.output, contains('$shims/dart runs $binary.'));
      expect(harness.output, isNot(contains(' .dvm/shims/dart runs')));
    });

    test('names the SDK store and config.json absolutely', () async {
      standInHome();
      harness.environment['PATH'] = shims;
      harness.fileSystem.file('$dvmHome/config.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"global":"3.13.2"}');

      expect(await harness.run(['doctor']), 1);

      expect(
          harness.output, contains('Nothing is at $dvmHome/versions/3.13.2'));
      expect(harness.output, isNot(contains('Nothing is at .dvm/versions')));
    });

    test('names the older dvm\'s home and files absolutely', () async {
      standInHome();
      harness.environment['PATH'] = shims;
      harness.fileSystem.file('$dvmHome/scripts/dvm')
        ..createSync(recursive: true)
        ..writeAsStringSync('dvm() { :; }\n');

      await harness.run(['doctor']);

      expect(
          harness.output,
          contains('an older dvm (cbracken/dvm) shares '
              '$dvmHome.'));
      expect(harness.output, contains('$dvmHome/scripts/dvm'));
    });
  });

  group('setup, standing in \$HOME', () {
    test('names the shim, the binary and the startup file absolutely',
        () async {
      standInHome();

      expect(
        await harness.run(['setup', '--dvm-path', binary, '--write-path-line']),
        0,
      );

      expect(harness.output, contains('Wrote $shims/dart'));
      expect(harness.output, contains('  -> $binary exec dart'));
      expect(harness.output, contains('Created $home/.zshrc with:'));
      // `source .zshrc` is a command the user pastes. It happens to work from
      // $HOME and silently does the wrong thing from anywhere else.
      expect(harness.output, contains('source $home/.zshrc'));
      expect(harness.output, isNot(contains('source .zshrc')));
    });

    test('names the backup absolutely', () async {
      standInHome();
      harness.fileSystem.file('$home/.zshrc')
        ..createSync(recursive: true)
        ..writeAsStringSync('export EDITOR=vim\n');

      await harness.run(['setup', '--dvm-path', binary, '--write-path-line']);

      expect(
          harness.output,
          contains('Backed up $home/.zshrc -> $home/.zshrc'
              '.dvm-backup-'));
    });

    test('names both PATH directories absolutely in the line it prints',
        () async {
      standInHome();

      expect(await harness.run(['setup', '--dvm-path', binary]), 0);

      expect(harness.output, contains('Create $home/.zshrc'));
      expect(
        harness.output,
        contains(
            r'export PATH="/home/dev/.dvm/shims:/home/dev/.dvm/bin:$PATH"'),
      );
    });

    test('names the shims absolutely when it says they are already on PATH',
        () async {
      standInHome();
      harness.environment['PATH'] = '$shims:$dvmHome/bin';

      expect(await harness.run(['setup', '--dvm-path', binary]), 0);

      expect(harness.output,
          contains('$shims and $dvmHome/bin are already on your PATH'));
    });
  });

  group('project files keep the relative rendering', () {
    // The half of the relative-path work that was right and must not regress.
    // A `.dvmrc` in `$HOME` is under the working directory in the sense the
    // rule is about — it is a file in the directory the reader is standing in.
    test('a .dvmrc in \$HOME still prints relative', () async {
      standInHome();
      harness.environment['PATH'] = shims;
      harness.fileSystem.file('$home/.dvmrc').writeAsStringSync('3.13.2\n');
      harness.paths.dartExecutable(
        harness.fileSystem.directory('$dvmHome/versions/3.13.2'),
      )
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\n');

      expect(await harness.run(['doctor']), 0);

      expect(harness.output, contains('.dvmrc pins Dart 3.13.2'));
      expect(harness.output, isNot(contains('$home/.dvmrc pins')));
    });

    test(
        'the .dvm/dart_sdk symlink still prints relative, and its target does '
        'not', () async {
      standInHome();
      harness.environment['PATH'] = shims;
      final version = harness.fileSystem.directory('$dvmHome/versions/3.13.2');
      harness.paths.dartExecutable(version)
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\n');
      harness.fileSystem.file('$home/.dvmrc').writeAsStringSync('3.13.2\n');
      harness.fileSystem.link('$home/.dvm/dart_sdk');

      await harness.run(['use', '3.13.2']);
      harness.clearOutput();

      expect(await harness.run(['doctor']), 0);

      // The link is a project file and reads relative; what it POINTS AT is
      // the SDK store and reads absolute. Both in one sentence.
      expect(harness.output,
          contains('.dvm/dart_sdk points at $dvmHome/versions/3.13.2.'));
    });
  });
}

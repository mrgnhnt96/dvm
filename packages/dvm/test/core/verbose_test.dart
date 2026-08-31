import 'package:dvm/dvm.dart';
import 'package:test/test.dart';

import '../commands/harness.dart';
import '../exec/support.dart';

/// dvm explaining itself.
///
/// The incident this exists for: `dvm use <version>` appeared to do nothing,
/// because an older `dvm` shell function was shadowing the binary and the real
/// dvm never ran. Nothing in the output could have shown that. So the contract
/// under test is two-sided — a verbose run has to say what it decided and why,
/// and a NON-verbose run has to stay byte-for-byte what it was, on stdout and
/// on stderr both.
void main() {
  late CommandHarness harness;

  setUp(() {
    harness = CommandHarness();
    harness.installVersion('3.9.0');
    harness.fileSystem.file('/project/.dvmrc').writeAsStringSync('3.9.0');
  });

  /// Every verbose line, which is every line carrying the `[dvm …]` prefix.
  List<String> verboseLines(String text) => [
        for (final line in text.split('\n'))
          if (line.startsWith('[dvm ')) line,
      ];

  group('activation', () {
    test('the -v flag turns it on', () async {
      expect(await harness.run(['-v', 'which']), 0);
      expect(verboseLines(harness.errors), isNotEmpty);
    });

    test('the --verbose flag turns it on', () async {
      expect(await harness.run(['--verbose', 'which']), 0);
      expect(verboseLines(harness.errors), isNotEmpty);
    });

    test('DVM_VERBOSE=1 turns it on', () async {
      harness.environment['DVM_VERBOSE'] = '1';

      expect(await harness.run(['which']), 0);
      expect(verboseLines(harness.errors), isNotEmpty);
    });

    test('any other non-empty value turns it on', () async {
      // Whatever somebody reaches for in a CI file. The variable exists for
      // the case where nobody is typing a dvm command line, so it should not
      // also demand they guess the one spelling that works.
      for (final value in ['true', 'yes', 'on', '2']) {
        final each = CommandHarness()..installVersion('3.9.0');
        each.fileSystem.file('/project/.dvmrc').writeAsStringSync('3.9.0');
        each.environment['DVM_VERBOSE'] = value;

        expect(await each.run(['which']), 0);
        expect(
          verboseLines(each.errors),
          isNotEmpty,
          reason: 'DVM_VERBOSE=$value should turn verbose output on',
        );
      }
    });

    test('DVM_VERBOSE=0 does NOT turn it on', () async {
      harness.environment['DVM_VERBOSE'] = '0';

      expect(await harness.run(['which']), 0);
      expect(verboseLines(harness.errors), isEmpty);
    });

    test('DVM_VERBOSE=false does NOT turn it on', () async {
      harness.environment['DVM_VERBOSE'] = 'false';

      expect(await harness.run(['which']), 0);
      expect(verboseLines(harness.errors), isEmpty);
    });

    test('an EMPTY DVM_VERBOSE does NOT turn it on', () async {
      // `export DVM_VERBOSE=` is how a shell profile clears an inherited
      // value, so an empty string has to read as off rather than as set.
      harness.environment['DVM_VERBOSE'] = '';

      expect(await harness.run(['which']), 0);
      expect(verboseLines(harness.errors), isEmpty);
    });

    test('neither flag nor variable: nothing extra at all', () async {
      expect(await harness.run(['which']), 0);
      expect(verboseLines(harness.errors), isEmpty);
    });

    test('--verbose is listed in the top-level help', () async {
      await harness.run(['--help']);

      expect(harness.output, contains('--verbose'));
      expect(harness.output, contains('DVM_VERBOSE'));
    });
  });

  group('it goes to stderr, never stdout', () {
    test('a verbose run leaves stdout byte-for-byte unchanged', () async {
      final quiet = CommandHarness()..installVersion('3.9.0');
      quiet.fileSystem.file('/project/.dvmrc').writeAsStringSync('3.9.0');
      await quiet.run(['which']);

      await harness.run(['--verbose', 'which']);

      // The whole reason verbose is on stderr: `dvm which` is read by
      // scripts, and so is everything behind the PATH shim.
      expect(harness.output, quiet.output);
      expect(harness.output, isNot(contains('[dvm ')));
      expect(verboseLines(harness.errors), isNotEmpty);
    });

    test('a NON-verbose run adds nothing to stdout OR stderr', () async {
      // The other half of "this changes no behaviour": the instrumentation is
      // invisible unless asked for, on both streams.
      expect(await harness.run(['which']), 0);

      expect(harness.output, contains('/dvm/versions/3.9.0/bin/dart'));
      expect(harness.errors, isEmpty);
    });
  });

  group('version resolution', () {
    test('reports the .dvmrc walk, the file that won, and its contents',
        () async {
      // Two directories below the pin, so the walk has steps to report rather
      // than finding the answer where it started.
      harness.fileSystem.directory('/project/pkg/sub').createSync(
            recursive: true,
          );
      harness.fileSystem.currentDirectory = '/project/pkg/sub';

      expect(await harness.run(['-v', 'which']), 0);
      final lines = verboseLines(harness.errors).join('\n');

      expect(lines, contains('.dvmrc walk starts at /project/pkg/sub'));
      expect(lines, contains('/project/pkg/sub -> none'));
      expect(lines, contains('/project/pkg -> none'));
      expect(lines, contains('/project -> found /project/.dvmrc'));
      // The RAW contents, so a pin that is not what the user thinks it is
      // shows up as what is literally in the file.
      expect(lines, contains('read /project/.dvmrc: 3.9.0'));
      expect(lines, contains('rule 2 (.dvmrc): /project/.dvmrc pins "3.9.0"'));
      expect(lines, contains('selected /dvm/versions/3.9.0'));
    });

    test('reports each rule it tried and did not match', () async {
      expect(await harness.run(['-v', 'which']), 0);
      final lines = verboseLines(harness.errors).join('\n');

      expect(lines, contains('rule 1 (DVM_DART_VERSION): not set'));
      expect(lines, contains('rule 2 (.dvmrc)'));
    });

    test('reports the alias trail an alias resolved through', () async {
      harness.writeConfig(
        const DvmConfig(aliases: {'work': 'team', 'team': '3.9.0'}),
      );
      harness.fileSystem.file('/project/.dvmrc').writeAsStringSync('work');

      expect(await harness.run(['-v', 'which']), 0);

      expect(
        verboseLines(harness.errors).join('\n'),
        contains('"work" is Dart 3.9.0 (work -> team -> 3.9.0'),
      );
    });

    test('reports a channel resolving out of config.json, not the network',
        () async {
      harness.writeConfig(const DvmConfig(channels: {'stable': '3.9.0'}));
      harness.fileSystem.file('/project/.dvmrc').writeAsStringSync('stable');

      expect(await harness.run(['-v', 'which']), 0);

      expect(
        verboseLines(harness.errors).join('\n'),
        contains('"stable" is Dart 3.9.0 (stable -> 3.9.0; "stable" is a '
            'channel'),
      );
    });

    test('reports the global default applying when no .dvmrc does', () async {
      harness.fileSystem.file('/project/.dvmrc').deleteSync();
      harness.writeConfig(const DvmConfig(global: '3.9.0'));

      expect(await harness.run(['-v', 'which']), 0);
      final lines = verboseLines(harness.errors).join('\n');

      expect(lines, contains('rule 2 (.dvmrc): no pin applies'));
      expect(
        lines,
        contains('rule 3 (global default): /dvm/config.json says "3.9.0"'),
      );
    });

    test('reports WHY a dart on PATH was skipped for being a shim', () async {
      // The shape of the original incident: something that looks like `dart`
      // is found first and is not the one that runs. Rule 4 skips it silently
      // in production; verbose is where that decision becomes visible.
      harness.fileSystem.file('/project/.dvmrc').deleteSync();
      harness.fileSystem.file('/fake/bin/dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\nexec "/somewhere/dvm" exec dart "\$@"');
      harness.environment['PATH'] = '/fake/bin';

      // Rule 5: the shim is skipped, so nothing on PATH answers.
      expect(await harness.run(['-v', 'which']), 1);
      final lines = verboseLines(harness.errors).join('\n');

      expect(
        lines,
        contains('/fake/bin/dart -> skipped, its contents are a copy of a '
            'dvm shim'),
      );
      expect(lines, contains('rule 5: nothing applies'));
    });
  });

  group('the shim / exec path', () {
    late FakeProcessRunner processes;

    setUp(() => processes = FakeProcessRunner());

    test('DVM_VERBOSE says which SDK binary ran and which .dvmrc chose it',
        () async {
      // This is the CI-log case, and the reason DVM_VERBOSE exists at all:
      // `~/.dvm/shims/dart` is `exec dvm exec dart "$@"`, so nobody types a
      // dvm command line here and the flag can never be passed.
      harness.environment['DVM_VERBOSE'] = '1';

      expect(
        await runWith(harness, ['exec', 'dart', '--version'],
            processes: processes),
        0,
      );

      final lines = verboseLines(harness.errors).join('\n');
      expect(lines, contains('running /dvm/versions/3.9.0/bin/dart'));
      expect(lines, contains('chosen by .dvmrc (/project/.dvmrc), Dart 3.9.0'));
      // And it did not disturb what the child was actually asked to run.
      expect(processes.only.executable, '/dvm/versions/3.9.0/bin/dart');
      expect(processes.only.arguments, ['--version']);
    });

    test('nothing reaches stdout on the exec path', () async {
      // A tool parsing `dart --version` gets dvm's stdio handed straight to
      // the child; a single stray line on stdout would break it.
      harness.environment['DVM_VERBOSE'] = '1';

      await runWith(harness, ['exec', 'dart', '--version'],
          processes: processes);

      expect(harness.output, isEmpty);
      expect(verboseLines(harness.errors), isNotEmpty);
    });

    test('`dvm dart` explains itself the same way `dvm exec` does', () async {
      // The two ways into an SDK must not be able to disagree about how they
      // report themselves — the shim only exercises one of them.
      await runWith(harness, ['-v', 'dart', '--version'], processes: processes);

      expect(
        verboseLines(harness.errors).join('\n'),
        contains('running /dvm/versions/3.9.0/bin/dart'),
      );
    });

    test('reports the child PATH search that found the command', () async {
      harness.environment['DVM_VERBOSE'] = '1';
      harness.fileSystem.file('/opt/pub/melos')
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\n');
      harness.environment['PATH'] = '/opt/pub';

      await runWith(harness, ['exec', 'melos', 'bootstrap'],
          processes: processes);

      final lines = verboseLines(harness.errors).join('\n');
      expect(
        lines,
        contains('looking for "melos" on the CHILD PATH: '
            '/dvm/versions/3.9.0/bin:/opt/pub'),
      );
      expect(lines, contains('found at /opt/pub/melos'));
    });

    test('an exec run without -v prints nothing on either stream', () async {
      expect(
        await runWith(harness, ['exec', 'dart', '--version'],
            processes: processes),
        0,
      );

      expect(harness.output, isEmpty);
      expect(harness.errors, isEmpty);
    });
  });

  group('filesystem writes', () {
    test('`use` reports the .dvmrc it wrote and the link it made', () async {
      expect(await harness.run(['-v', 'use', '3.9.0']), 0);
      final lines = verboseLines(harness.errors).join('\n');

      expect(
        lines,
        contains('wrote /project/.dvmrc: {"dart": "3.9.0"}'),
      );
      expect(
        lines,
        contains('linked /project/.dvm/dart_sdk -> /dvm/versions/3.9.0'),
      );
    });

    test('a non-verbose `use` still prints only what it always printed',
        () async {
      final quiet = CommandHarness()..installVersion('3.9.0');
      quiet.fileSystem.file('/project/.dvmrc').writeAsStringSync('3.9.0');
      await quiet.run(['use', '3.9.0']);

      await harness.run(['--verbose', 'use', '3.9.0']);

      expect(harness.output, quiet.output);
      expect(quiet.errors, isEmpty);
    });
  });

  group('VerboseLog itself', () {
    test('a message is not built while the log is off', () async {
      // The hot path runs on every `dart` invocation on the machine, so a
      // silent run must not pay to produce text it discards.
      var built = 0;
      VerboseLog(sink: StringBuffer()).log('resolve', () {
        built++;
        return 'expensive';
      });

      expect(built, 0);
    });

    test('enable() makes it write, and a sinkless log stays off', () {
      final sink = StringBuffer();
      final log = VerboseLog(sink: sink)..enable();
      log.log('resolve', () => 'hello');
      expect(sink.toString(), '[dvm resolve] hello\n');

      // Nowhere to write means nothing can turn it on — the shape every
      // collaborator constructed outside `lib/dvm.dart` gets by default.
      final none = VerboseLog.disabled..enable();
      expect(none.enabled, isFalse);
    });

    test('stopwatch() is null while the log is off', () {
      expect(VerboseLog.disabled.stopwatch(), isNull);
      expect(
          (VerboseLog(sink: StringBuffer())..enable()).stopwatch(), isNotNull);
    });
  });
}

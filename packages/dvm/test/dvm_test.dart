import 'package:dvm_cli/dvm.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

/// Every command in ARCHITECTURE.md's command-surface table.
///
/// Other parts of the CLI fill these in one file at a time; if one of them ever
/// has to touch `lib/dvm.dart` to be reachable, this list was wrong.
const List<String> commandSurface = [
  'install',
  'use',
  'list',
  'list-remote',
  'remove',
  'alias',
  'unalias',
  'global',
  'which',
  'dart',
  'exec',
  'setup',
  'migrate',
  'doctor',
];

/// The two spellings the table gives as alternatives.
const Map<String, String> commandAliases = {'ls': 'list', 'current': 'which'};

void main() {
  late MemoryFileSystem fs;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() {
    fs = MemoryFileSystem.test();
    out = StringBuffer();
    err = StringBuffer();
  });

  /// Drives the real entrypoint against a memory filesystem and a fake
  /// environment, so no test can reach the real ~/.dvm.
  Future<int> runDvm(List<String> args) => run(
        args,
        fileSystem: fs,
        environment: {'HOME': '/home/dev'},
        platformVersion: '3.13.2 (stable) (Tue Aug 25 2026) on "macos_arm64"',
        out: out,
        err: err,
      );

  test('run returns a success exit code', () async {
    expect(await runDvm([]), 0);
  });

  test('--help lists every command in the surface', () async {
    expect(await runDvm(['--help']), 0);

    // Anchored to the start of a line: a bare `contains('dart')` would pass
    // on the word appearing anywhere in the prose.
    for (final command in commandSurface) {
      expect(
        out.toString(),
        matches(RegExp('^\\s+$command\\s', multiLine: true)),
        reason: '`$command` is missing from dvm --help',
      );
    }
  });

  test('every command in the surface is registered', () {
    final runner = DvmCommandRunner(
      DvmContext.wire(
        fileSystem: fs,
        environment: {'HOME': '/home/dev'},
        platformVersion: 'on "macos_arm64"',
        out: out,
        err: err,
      ),
    );

    for (final command in commandSurface) {
      expect(runner.commands, contains(command));
    }
    for (final entry in commandAliases.entries) {
      expect(runner.commands[entry.key]?.name, entry.value);
    }
  });

  test('every command still to be written reports that, rather than crashing',
      () async {
    final runner = DvmCommandRunner(
      DvmContext.wire(
        fileSystem: fs,
        environment: {'HOME': '/home/dev'},
        platformVersion: 'on "macos_arm64"',
        out: out,
        err: err,
      ),
    );

    // Asking the command object whether it still carries the placeholder,
    // rather than listing the unwritten commands here, is what keeps this test
    // from having to be edited every time one of them becomes real.
    for (final command in commandSurface) {
      if (runner.commands[command] is! NotImplementedCommand) continue;
      out.clear();
      err.clear();

      expect(
        await runDvm([command]),
        notImplementedExitCode,
        reason: '`dvm $command` should exit $notImplementedExitCode for now',
      );
      expect(err.toString(), contains('not implemented yet'));
    }
  });

  test('an unknown command is a usage error, not a crash', () async {
    expect(await runDvm(['nope']), usageExitCode);
    expect(err.toString(), contains('Could not find a command named "nope"'));
  });

  test('--version prints the build version', () async {
    expect(await runDvm(['--version']), 0);
    expect(out.toString().trim(), 'dvm ${version()}');
  });

  test('dart and exec pass their arguments through untouched', () {
    final runner = DvmCommandRunner(
      DvmContext.wire(
        fileSystem: fs,
        environment: {'HOME': '/home/dev'},
        platformVersion: 'on "macos_arm64"',
        out: out,
        err: err,
      ),
    );

    // Without allowAnything(), `--version` here would be parsed as dvm's own
    // flag instead of being handed to the child.
    for (final name in ['dart', 'exec']) {
      final results = runner.commands[name]!.argParser.parse([
        '--version',
        'run',
        '--define=x=1',
      ]);
      expect(results.rest, ['--version', 'run', '--define=x=1']);
    }
  });
}

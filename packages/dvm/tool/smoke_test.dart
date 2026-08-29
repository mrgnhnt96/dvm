// An end-to-end smoke test for a COMPILED dvm on a REAL filesystem.
//
// `dart test` drives dvm against a `MemoryFileSystem`, which answers questions
// about path spelling and nothing else. A memory filesystem has no PATHEXT, no
// ACLs, no junctions, no `cmd.exe`, and it creates a symlink wherever it is
// asked to — so every question that is actually about the operating system is
// invisible to it. This script asks those questions instead: it compiles the
// binary, installs a real SDK from the archive, and runs the commands a person
// runs, checking what appeared on the console.
//
// Run it from the repository root:
//
//     dart run packages/dvm/tool/smoke_test.dart [--sdk-version 3.5.4]
//
// Every check runs even after an earlier one fails, and the summary at the end
// lists them all. One red CI job then reports every broken thing on that
// platform rather than only the first, which is the difference between one
// round trip to a Windows runner and six.
import 'dart:io';

/// The SDK this installs when `--sdk-version` is not given.
///
/// Pinned rather than `stable`: the assertions quote the version back, and a
/// moving target would make a failure ambiguous between "dvm is broken" and
/// "the channel moved".
const String defaultSdkVersion = '3.5.4';

Future<int> main(List<String> arguments) async {
  final sdkVersion =
      _optionValue(arguments, '--sdk-version') ?? defaultSdkVersion;
  final repoRoot = Directory.current;
  final scratch = Directory.systemTemp.createTempSync('dvm-smoke-');
  final dvmHome = Directory('${scratch.path}${Platform.pathSeparator}home');
  final project = Directory('${scratch.path}${Platform.pathSeparator}project')
    ..createSync(recursive: true);

  final smoke = _Smoke(
    dvmHome: dvmHome,
    project: project,
    sdkVersion: sdkVersion,
  );

  stdout.writeln('== dvm smoke test ==');
  stdout.writeln('platform    ${Platform.operatingSystem} '
      '(${Platform.operatingSystemVersion})');
  stdout.writeln('dart        ${Platform.version}');
  stdout.writeln('scratch     ${scratch.path}');
  stdout.writeln('sdk version $sdkVersion');
  stdout.writeln('');

  try {
    final binary = await smoke.compile(repoRoot, scratch);
    if (binary == null) {
      stdout.writeln('Compiling dvm failed, so nothing else could be run.');
      return 1;
    }
    await smoke.runChecks(binary);
  } finally {
    smoke.report();
    _deleteQuietly(scratch);
  }

  return smoke.failed ? 1 : 0;
}

/// The checks, and what each of them observed.
class _Smoke {
  _Smoke({
    required this.dvmHome,
    required this.project,
    required this.sdkVersion,
  });

  final Directory dvmHome;
  final Directory project;
  final String sdkVersion;

  final List<_Result> _results = <_Result>[];

  bool get failed => _results.any((result) => !result.ok);

  /// `dvm.exe` on Windows, `dvm` everywhere else.
  static String get _dvmName => Platform.isWindows ? 'dvm.exe' : 'dvm';

  /// Builds the binary under test. Returns null when the build itself failed.
  Future<File?> compile(Directory repoRoot, Directory scratch) async {
    final output = File('${scratch.path}${Platform.pathSeparator}$_dvmName');
    final result = await _run(
      'compile dvm',
      Platform.resolvedExecutable,
      <String>[
        'compile',
        'exe',
        'packages/dvm/bin/dvm.dart',
        '-o',
        output.path,
      ],
      workingDirectory: repoRoot.path,
    );
    if (!result.ok || !output.existsSync()) return null;
    return output;
  }

  Future<void> runChecks(File dvm) async {
    await _version(dvm);
    await _setup(dvm);
    final installed = await _install(dvm);
    await _list(dvm);
    await _use(dvm);
    await _which(dvm);
    await _dart(dvm);
    await _exec(dvm);
    await _shim(dvm);
    await _doctor(dvm);
    if (!installed) {
      stdout.writeln(
        'NOTE: the SDK install failed, so every check after it was asking a '
        'question that could not be answered. Read the install failure first.',
      );
    }
  }

  Future<void> _version(File dvm) async {
    final result = await _dvm(dvm, 'dvm --version', <String>['--version']);
    _expect(result, contains: 'dvm ');
  }

  Future<void> _setup(File dvm) async {
    final result = await _dvm(
      dvm,
      'dvm setup',
      <String>['setup', '--dvm-path', dvm.path],
    );
    _expect(result, contains: 'Wrote ');

    // The shim is the whole PATH integration, and its NAME is platform
    // specific: a `dart` with no extension is not executable on Windows.
    final shim = File(
      <String>[
        dvmHome.path,
        'shims',
        Platform.isWindows ? 'dart.bat' : 'dart',
      ].join(Platform.pathSeparator),
    );
    _record(
      'the shim exists at ${shim.path}',
      shim.existsSync(),
      shim.existsSync() ? shim.readAsStringSync() : 'no such file',
    );
  }

  Future<bool> _install(File dvm) async {
    final result = await _dvm(
      dvm,
      'dvm install $sdkVersion',
      <String>['install', sdkVersion],
    );
    return _expect(result, contains: sdkVersion);
  }

  Future<void> _list(File dvm) async {
    final result = await _dvm(dvm, 'dvm list', <String>['list']);
    _expect(result, contains: sdkVersion);
  }

  Future<void> _use(File dvm) async {
    final result = await _dvm(
      dvm,
      'dvm use $sdkVersion',
      <String>['use', sdkVersion],
      workingDirectory: project.path,
    );
    _expect(result, contains: 'Pinned Dart $sdkVersion');

    final rc = File('${project.path}${Platform.pathSeparator}.dvmrc');
    _record(
      '.dvmrc says $sdkVersion',
      rc.existsSync() && rc.readAsStringSync().trim() == sdkVersion,
      rc.existsSync() ? rc.readAsStringSync().trim() : 'no .dvmrc',
    );

    // Reached THROUGH the link, which is the only thing an IDE does with it.
    // A symlink and a junction are indistinguishable from here, and that is
    // the point: what matters is that the SDK is reachable at this path.
    final linked = File(
      <String>[
        project.path,
        '.dvm',
        'dart_sdk',
        'bin',
        Platform.isWindows ? 'dart.exe' : 'dart',
      ].join(Platform.pathSeparator),
    );
    _record(
      '.dvm/dart_sdk reaches the SDK',
      linked.existsSync(),
      linked.existsSync() ? linked.path : 'nothing at ${linked.path}',
    );
  }

  Future<void> _which(File dvm) async {
    final result = await _dvm(
      dvm,
      'dvm which',
      <String>['which'],
      workingDirectory: project.path,
    );
    _expect(result, contains: sdkVersion);

    final path = await _dvm(
      dvm,
      'dvm which --path',
      <String>['which', '--path'],
      workingDirectory: project.path,
    );
    final named = path.stdout.trim();
    _record(
      'dvm which --path names a file that exists',
      named.isNotEmpty && File(named).existsSync(),
      named.isEmpty ? '(printed nothing)' : named,
    );
  }

  Future<void> _dart(File dvm) async {
    final result = await _dvm(
      dvm,
      'dvm dart --version',
      <String>['dart', '--version'],
      workingDirectory: project.path,
    );
    _expect(result, contains: 'Dart SDK version: $sdkVersion');
  }

  Future<void> _exec(File dvm) async {
    final result = await _dvm(
      dvm,
      'dvm exec dart --version',
      <String>['exec', 'dart', '--version'],
      workingDirectory: project.path,
    );
    _expect(result, contains: 'Dart SDK version: $sdkVersion');

    // A launcher has to answer the way the thing it stands in for answers.
    final missing = await _dvm(
      dvm,
      'dvm exec no-such-command',
      <String>['exec', 'definitely-not-a-real-command'],
      workingDirectory: project.path,
      expectedExitCode: 127,
    );
    _record(
      'dvm exec returns 127 for a command that is not there',
      missing.exitCode == 127,
      'exit ${missing.exitCode}',
    );

    // The exit code of the CHILD, not of dvm. A version manager that turns a
    // failing build into a passing one breaks every CI downstream of it.
    final failing = await _dvm(
      dvm,
      'dvm dart (a script that exits 3)',
      <String>['dart', 'run', _exitScript().path],
      workingDirectory: project.path,
      expectedExitCode: 3,
    );
    _record(
      'the child exit code is forwarded',
      failing.exitCode == 3,
      'exit ${failing.exitCode}',
    );
  }

  /// Runs the shim the way a shell resolves it, with the shims directory on
  /// PATH and only the bare word `dart` typed.
  Future<void> _shim(File dvm) async {
    final shims = '${dvmHome.path}${Platform.pathSeparator}shims';
    final separator = Platform.isWindows ? ';' : ':';
    final path = '$shims$separator${Platform.environment['PATH'] ?? ''}';

    if (Platform.isWindows) {
      // cmd.exe finds `dart.bat` through PATHEXT; nothing on the command line
      // says `.bat`, which is the whole question.
      final viaCmd = await _run(
        'dart --version through cmd.exe',
        'cmd.exe',
        <String>['/c', 'dart', '--version'],
        workingDirectory: project.path,
        environment: <String, String>{'PATH': path, 'Path': path},
      );
      _expect(viaCmd, contains: 'Dart SDK version: $sdkVersion');

      final viaPowerShell = await _run(
        'dart --version through PowerShell',
        'powershell.exe',
        <String>['-NoProfile', '-Command', 'dart --version'],
        workingDirectory: project.path,
        environment: <String, String>{'PATH': path, 'Path': path},
      );
      _expect(viaPowerShell, contains: 'Dart SDK version: $sdkVersion');
      return;
    }

    final viaSh = await _run(
      'dart --version through sh',
      'sh',
      <String>['-c', 'dart --version'],
      workingDirectory: project.path,
      environment: <String, String>{'PATH': path},
    );
    _expect(viaSh, contains: 'Dart SDK version: $sdkVersion');
  }

  Future<void> _doctor(File dvm) async {
    // Doctor reports, so its exit code is a verdict about the machine rather
    // than about dvm. What is asserted is that it ran and said something.
    final result = await _dvm(
      dvm,
      'dvm doctor',
      <String>['doctor'],
      workingDirectory: project.path,
      expectedExitCode: null,
    );
    _record(
      'dvm doctor produced a report',
      result.output.trim().isNotEmpty,
      'exit ${result.exitCode}',
    );
  }

  /// A tiny Dart program whose only job is to exit non-zero.
  File _exitScript() {
    final file = File('${project.path}${Platform.pathSeparator}exit3.dart');
    if (!file.existsSync()) {
      file.writeAsStringSync(
        "import 'dart:io';\n\nvoid main() => exit(3);\n",
      );
    }
    return file;
  }

  /// Runs dvm with the scratch home, never the real `~/.dvm`.
  Future<_Result> _dvm(
    File dvm,
    String label,
    List<String> arguments, {
    String? workingDirectory,
    int? expectedExitCode = 0,
  }) =>
      _run(
        label,
        dvm.path,
        // The update check is a network round trip to GitHub that says nothing
        // about the platform and can fail for reasons of its own.
        <String>[...arguments, '--no-version-check'],
        workingDirectory: workingDirectory,
        environment: <String, String>{'DVM_HOME': dvmHome.path},
        expectedExitCode: expectedExitCode,
      );

  Future<_Result> _run(
    String label,
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    int? expectedExitCode = 0,
  }) async {
    stdout.writeln('--- $label');
    stdout.writeln('\$ $executable ${arguments.join(' ')}');
    final ProcessResult process;
    try {
      process = await Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        runInShell: false,
      );
    } on ProcessException catch (error) {
      stdout.writeln('could not start: ${error.message}');
      final result = _Result(label, -1, '', 'could not start: $error');
      _record(label, false, 'could not start: ${error.message}');
      return result;
    }

    final result = _Result(
      label,
      process.exitCode,
      '${process.stdout}',
      '${process.stderr}',
    );
    stdout.writeln(result.output.trimRight());
    stdout.writeln('exit ${result.exitCode}');
    stdout.writeln('');

    if (expectedExitCode != null && result.exitCode != expectedExitCode) {
      _record(
        '$label exits $expectedExitCode',
        false,
        'exit ${result.exitCode}',
      );
    }
    return result;
  }

  /// Asserts on what the command PRINTED. An exit code of zero says a process
  /// ended; it does not say it did the thing.
  bool _expect(_Result result, {required String contains}) {
    final ok = result.output.contains(contains);
    _record(
      '${result.label} says "$contains"',
      ok,
      ok ? 'found' : 'not in ${result.output.length} bytes of output',
    );
    return ok;
  }

  void _record(String what, bool ok, String detail) {
    _results.add(_Result.check(what, ok, detail));
  }

  void report() {
    stdout.writeln('');
    stdout.writeln('== summary (${Platform.operatingSystem}) ==');
    for (final result in _results) {
      stdout.writeln('${result.ok ? 'ok  ' : 'FAIL'}  ${result.label}'
          '${result.ok ? '' : '  <- ${result.detail}'}');
    }
    final bad = _results.where((result) => !result.ok).length;
    stdout.writeln('');
    stdout.writeln(
      bad == 0
          ? '${_results.length} checks, all passed.'
          : '${_results.length} checks, $bad failed.',
    );
  }
}

/// One command that ran, or one check that was made about the result.
class _Result {
  _Result(this.label, this.exitCode, this.stdout, this.stderr)
      : ok = true,
        detail = '';

  _Result.check(this.label, this.ok, this.detail)
      : exitCode = 0,
        stdout = '',
        stderr = '';

  final String label;
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool ok;
  final String detail;

  /// Both streams. `dart --version` has moved between them across SDKs, and a
  /// check that read only one would pass or fail on that alone.
  String get output => '$stdout$stderr';
}

String? _optionValue(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index == -1 || index + 1 >= arguments.length) return null;
  return arguments[index + 1];
}

void _deleteQuietly(Directory directory) {
  try {
    directory.deleteSync(recursive: true);
  } on FileSystemException {
    // A leftover temp directory on a CI runner costs nothing, and failing the
    // smoke test on cleanup would report a problem that is not there.
  }
}

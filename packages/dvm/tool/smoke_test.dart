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
import 'dart:async';
import 'dart:io';

/// The SDK this installs when `--sdk-version` is not given.
///
/// Pinned rather than `stable`: the assertions quote the version back, and a
/// moving target would make a failure ambiguous between "dvm is broken" and
/// "the channel moved".
const String defaultSdkVersion = '3.5.4';

Future<void> main(List<String> arguments) async {
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
    } else {
      await smoke.runChecks(binary);
    }
  } finally {
    smoke.report();
    _deleteQuietly(scratch);
  }

  // `exitCode`, not `return`: the Dart VM ignores what `main` returns, so a
  // script that returned 1 here would report every failure it found and then
  // exit 0, and CI would go green on a red smoke test. That is exactly what
  // this script did on its first run.
  exitCode = smoke.failed ? 1 : 0;
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
    _reportSymlinkPrivilege();
    await _version(dvm);
    await _setup(dvm);
    final installed = await _install(dvm);
    await _unknownVersion(dvm);
    await _list(dvm);
    await _use(dvm);
    await _which(dvm);
    await _dart(dvm);
    await _exec(dvm);
    await _shim(dvm);
    await _replaceRunningBinary(dvm);
    await _doctor(dvm);
    // Last of all, because it deletes the SDK every check above needs.
    await _remove(dvm);
    if (!installed) {
      stdout.writeln(
        'NOTE: the SDK install failed, so every check after it was asking a '
        'question that could not be answered. Read the install failure first.',
      );
    }
  }

  /// Says whether THIS machine can create a plain directory symlink.
  ///
  /// Reported rather than asserted, and it is the reason `dvm use` does not
  /// simply call `Link.createSync` on Windows. Creating a symlink there needs
  /// either Developer Mode or an elevated process, and a CI runner is not
  /// evidence about a stock machine in either direction: an elevated runner
  /// would go green on a call that fails for the user, and an unelevated one
  /// would go red on a call that works for a developer with Developer Mode on.
  /// So this line exists to say WHICH kind of machine produced the log below.
  void _reportSymlinkPrivilege() {
    final target = Directory(
      '${project.path}${Platform.pathSeparator}symlink-probe-target',
    )..createSync(recursive: true);
    final link = Link(
      '${project.path}${Platform.pathSeparator}symlink-probe',
    );
    String verdict;
    try {
      link.createSync(target.path);
      verdict = 'yes';
      link.deleteSync();
    } on FileSystemException catch (error) {
      verdict = 'no (${error.osError?.message ?? error.message})';
    }
    target.deleteSync(recursive: true);
    stdout.writeln('--- can this machine create a plain directory symlink?');
    stdout.writeln(verdict);
    stdout.writeln('');
  }

  Future<void> _version(File dvm) async {
    final result = await _dvm(dvm, 'dvm --version', <String>['--version']);
    _expect(result, contains: 'dvm ');
  }

  Future<void> _setup(File dvm) async {
    // The exit code is deliberately not asserted. `setup` returns 1 when
    // something on THIS machine will shadow the shim -- a `dvm` shell function
    // in a startup file, an older cbracken/dvm in the same home -- which is a
    // fact about the machine, not about dvm. A clean runner exits 0; the
    // maintainer's own laptop exits 1 and is right to.
    final result = await _dvm(
      dvm,
      'dvm setup',
      <String>['setup', '--dvm-path', dvm.path],
      expectedExitCode: null,
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

    // The canonical form is `{"dart": "<version>"}`; a bare version is only
    // ever ACCEPTED on read, never written.
    final rc = File('${project.path}${Platform.pathSeparator}.dvmrc');
    final written = rc.existsSync() ? rc.readAsStringSync() : '';
    _record(
      '.dvmrc pins $sdkVersion',
      written.contains('"dart"') && written.contains('"$sdkVersion"'),
      rc.existsSync() ? written.trim() : 'no .dvmrc',
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

    // Again, over the link that is already there. Replacing a link is a
    // different operation from creating one, and on Windows the thing being
    // replaced may be a junction rather than a symlink.
    final again = await _dvm(
      dvm,
      'dvm use $sdkVersion, over the link already there',
      <String>['use', sdkVersion],
      workingDirectory: project.path,
    );
    _expect(again, contains: 'Pinned Dart $sdkVersion');
    _record(
      '.dvm/dart_sdk still reaches the SDK after a second pin',
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
    // DVM_HOME travels WITH the PATH override. Without it the shim's dvm reads
    // the real ~/.dvm, finds nothing installed, and reports the pin as
    // uninstalled -- a failure that looks like a resolution bug and is really
    // the harness handing the child half an environment.
    final environment = <String, String>{
      'PATH': path,
      if (Platform.isWindows) 'Path': path,
      'DVM_HOME': dvmHome.path,
    };

    if (Platform.isWindows) {
      // cmd.exe finds `dart.bat` through PATHEXT; nothing on the command line
      // says `.bat`, which is the whole question.
      final viaCmd = await _run(
        'dart --version through cmd.exe',
        'cmd.exe',
        <String>['/c', 'dart', '--version'],
        workingDirectory: project.path,
        environment: environment,
      );
      _expect(viaCmd, contains: 'Dart SDK version: $sdkVersion');

      final viaPowerShell = await _run(
        'dart --version through PowerShell',
        'powershell.exe',
        <String>['-NoProfile', '-Command', 'dart --version'],
        workingDirectory: project.path,
        environment: environment,
      );
      _expect(viaPowerShell, contains: 'Dart SDK version: $sdkVersion');
      return;
    }

    final viaSh = await _run(
      'dart --version through sh',
      'sh',
      <String>['-c', 'dart --version'],
      workingDirectory: project.path,
      environment: environment,
    );
    _expect(viaSh, contains: 'Dart SDK version: $sdkVersion');
  }

  /// Puts ARCHITECTURE.md's claim about `dvm update` in front of the OS.
  ///
  /// It says POSIX can `rename` over a running executable because the inode
  /// stays alive, and that Windows cannot replace a running `.exe` and needs
  /// the old one renamed aside first. `Updater` is built entirely on that
  /// distinction and it had never been executed on either platform -- the
  /// updater's own tests run against a memory filesystem, where nothing is
  /// ever really running.
  ///
  /// So this runs a copy of dvm, keeps it running, and tries both.
  Future<void> _replaceRunningBinary(File dvm) async {
    final directory = Directory(
      '${project.path}${Platform.pathSeparator}update',
    )..createSync(recursive: true);
    final running = dvm.copySync(
      '${directory.path}${Platform.pathSeparator}$_dvmName',
    );

    // A child that stays alive long enough to be replaced underneath, and
    // exits on its own if anything here goes wrong.
    final sleeper = File('${directory.path}${Platform.pathSeparator}wait.dart')
      ..writeAsStringSync(
        "import 'dart:io';\n\n"
        'Future<void> main() async {\n'
        "  File(r'${directory.path}${Platform.pathSeparator}ready')"
        ".writeAsStringSync('up');\n"
        '  await Future<void>.delayed(const Duration(seconds: 30));\n'
        '}\n',
      );

    stdout.writeln('--- replacing a RUNNING dvm binary');
    final process = await Process.start(
      running.path,
      <String>['dart', 'run', sleeper.path, '--no-version-check'],
      workingDirectory: project.path,
      environment: <String, String>{'DVM_HOME': dvmHome.path},
      mode: ProcessStartMode.detachedWithStdio,
    );
    // Drained rather than read: a child whose pipe fills up stops, and this
    // one is meant to sit still until it is replaced underneath.
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());

    final ready = File('${directory.path}${Platform.pathSeparator}ready');
    for (var i = 0; i < 300 && !ready.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!ready.existsSync()) {
      process.kill();
      _record(
        'a copy of dvm was running to be replaced',
        false,
        'the child never came up',
      );
      return;
    }

    // The way an unaware updater would do it.
    String? overwriteFailure;
    try {
      running.writeAsBytesSync(const <int>[0], flush: true);
    } on FileSystemException catch (error) {
      overwriteFailure = error.osError?.message ?? error.message;
    }
    // REPORTED, not asserted, and the reason is that the three platforms give
    // three different answers: Linux refuses with "Text file busy", Windows
    // refuses with "being used by another process", and macOS allows it. An
    // updater that wrote in place would therefore work on the machine of
    // whoever wrote it and fail for two thirds of its users -- which is why
    // `Updater` renames on every platform instead, and why the check below is
    // the one that has to pass.
    stdout.writeln(
      'overwriting it in place: ${overwriteFailure ?? 'allowed'}',
    );

    // The way Updater does it: aside, then into place.
    final incoming = File('${running.path}.new');
    dvm.copySync(incoming.path);
    String? replaceFailure;
    try {
      if (Platform.isWindows) {
        running.renameSync('${running.path}.old');
      }
      incoming.renameSync(running.path);
    } on FileSystemException catch (error) {
      replaceFailure = error.osError?.message ?? error.message;
    }
    stdout.writeln('renaming a new one into place: '
        '${replaceFailure ?? 'ok'}');
    _record(
      'a new binary can be renamed into place while the old one runs',
      replaceFailure == null,
      replaceFailure ?? 'ok',
    );

    process.kill();

    // The point of all of it: what is at that path now has to RUN.
    final replaced = await _dvm(
      File(running.path),
      'the replaced binary runs',
      <String>['--version'],
    );
    _expect(replaced, contains: 'dvm ');
    stdout.writeln('');
  }

  /// The failure path: a version that is not published anywhere.
  ///
  /// Every other check here asks whether dvm works when handed something it
  /// can do. This one asks what a user sees when they typo a version, which is
  /// the more common experience and the easiest one to regress -- an unhandled
  /// exception here would print a stack trace and exit 255, and no check that
  /// only ever passes good input would notice.
  ///
  /// The unit suite covers this ground against a fake archive server. What it
  /// cannot cover is that the REAL archive still answers 404 for an absent
  /// version: if it ever served a friendly HTML page instead, `channelFor`
  /// would take its non-404 branch and the message below would change without
  /// a line of dvm changing. Costs three 404s and no download.
  Future<void> _unknownVersion(File dvm) async {
    const absent = '99.99.99';
    final result = await _dvm(
      dvm,
      'dvm install $absent',
      <String>['install', absent],
      expectedExitCode: 1,
    );
    // Both halves, deliberately. What makes an error actionable is the
    // sentence saying what to do next, and that is the half most likely to be
    // lost to a well-meaning rewording of the first.
    _expect(result, contains: 'Dart $absent is not published in any channel');
    _expect(
      result,
      contains: 'Run `dvm list-remote` to see what is available.',
    );
    _record(
      'dvm install $absent exits 1 rather than crashing',
      result.exitCode == 1,
      'exit ${result.exitCode}',
    );
  }

  /// `dvm remove`, against a real cache directory.
  ///
  /// Deleting a tree in a `MemoryFileSystem` cannot fail the way deleting a
  /// real one can. This SDK was extracted from an archive and then EXECUTED a
  /// few checks ago, so on Windows the question is whether anything still
  /// holds a handle on a binary that just ran -- which is precisely the case a
  /// memory filesystem has no way to represent.
  Future<void> _remove(File dvm) async {
    final result = await _dvm(
      dvm,
      'dvm remove $sdkVersion',
      <String>['remove', sdkVersion],
      workingDirectory: project.path,
    );
    _expect(result, contains: 'Removed Dart $sdkVersion');

    // A `.dvmrc` is project data, not machine state, so it never blocks the
    // removal -- but the user is about to hit an error in this very directory,
    // and hearing it from the command that caused it is part of the contract.
    _expect(result, contains: 'pins the version just removed');

    // Really gone, not merely reported gone. `remove` printing its success
    // line is an assertion about dvm's control flow; this is one about disk.
    final versionDir = Directory(
      <String>[
        dvmHome.path,
        'versions',
        sdkVersion,
      ].join(Platform.pathSeparator),
    );
    _record(
      'the SDK directory is gone from the cache',
      !versionDir.existsSync(),
      versionDir.existsSync() ? 'still at ${versionDir.path}' : 'gone',
    );

    // And dvm agrees with the disk. A delete that left dvm still offering the
    // version would pass the check above and strand the next `dvm use`.
    final list = await _dvm(
      dvm,
      'dvm list, after the remove',
      <String>['list'],
    );
    _record(
      'dvm list no longer offers $sdkVersion',
      !list.output.contains(sdkVersion),
      list.output.trim().isEmpty ? '(printed nothing)' : list.output.trim(),
    );
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

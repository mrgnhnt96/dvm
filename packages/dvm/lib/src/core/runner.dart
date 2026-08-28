import 'dart:async';
import 'dart:io';

import 'package:file/file.dart';
import 'package:path/path.dart' as p;

import 'process.dart';
import 'resolver.dart';

/// The real [ProcessRunner]: the code path every `dart` invocation on the
/// machine goes through once the shim is installed.
///
/// Dart has no `exec()`, so dvm cannot replace itself with the child and has to
/// impersonate it instead. Three things make that impersonation convincing, and
/// all three are load-bearing:
///
/// * `inheritStdio` hands the child dvm's own file descriptors, so the child is
///   talking to the real terminal. Anything that asks "am I a tty?" — `dart
///   run` with a prompt, progress bars, colour — gets the right answer, and
///   dvm never sits between the two copying bytes.
/// * the child's exit code becomes dvm's. A version manager that turns a failing
///   `dart test` into a success breaks CI for everyone downstream of it.
/// * SIGINT and SIGTERM are forwarded. Ctrl-C at a terminal already reaches the
///   whole foreground process group, but a `kill` aimed at dvm by a supervisor
///   or a script does not; without forwarding that kills the wrapper and leaves
///   the real work orphaned.
class OsProcessRunner implements ProcessRunner {
  const OsProcessRunner();

  /// The signals a wrapper is expected to pass on.
  ///
  /// SIGKILL is deliberately absent: it cannot be caught, so there is nothing
  /// to forward. Windows supports watching neither of these the way POSIX does,
  /// which [_forward] handles by simply not installing a handler.
  static const List<ProcessSignal> _signals = [
    ProcessSignal.sigint,
    ProcessSignal.sigterm,
  ];

  @override
  Future<int> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? workingDirectory,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      environment: environment,
      workingDirectory: workingDirectory,
      mode: ProcessStartMode.inheritStdio,
    );

    final forwarding = <StreamSubscription<ProcessSignal>>[];
    for (final signal in _signals) {
      final subscription = _forward(signal, process);
      if (subscription != null) forwarding.add(subscription);
    }

    try {
      return await process.exitCode;
    } finally {
      // Cancelling puts the default disposition back. It matters because
      // watching SIGINT is what stopped Ctrl-C from killing dvm itself while
      // the child was running; leaving the watch in place would make a dvm
      // that outlived its child unkillable by Ctrl-C.
      for (final subscription in forwarding) {
        await subscription.cancel();
      }
    }
  }

  StreamSubscription<ProcessSignal>? _forward(
    ProcessSignal signal,
    Process process,
  ) {
    try {
      return signal.watch().listen((received) {
        // The child may already have exited between the signal arriving and
        // this line; killing a dead process is a false, not a throw, but the
        // platform is entitled to complain and it must not become dvm's
        // problem.
        try {
          process.kill(received);
        } on Object {
          // Nothing useful to say: the child is gone, which is the outcome the
          // signal was asking for anyway.
        }
      });
    } on SignalException {
      // This platform cannot watch this signal — Windows only supports a
      // subset. Forwarding what we can beats refusing to run.
      return null;
    }
  }
}

/// How a child process sees the SDK that dvm resolved for it.
///
/// `dvm dart` and `dvm exec` differ only in what they run, never in what the
/// child's world looks like, so the environment is built here rather than in
/// either command: a difference between them would be a bug that only shows up
/// in whichever one was written second.
class SdkInvocation {
  SdkInvocation({
    required this.fileSystem,
    required this.sdk,
    required Map<String, String> environment,
  }) : _parent = environment;

  final FileSystem fileSystem;
  final ResolvedSdk sdk;
  final Map<String, String> _parent;

  /// The directory holding the resolved `dart`.
  ///
  /// Taken from the executable rather than composed as `sdkDir/bin`, because
  /// resolution rule 4 picks up an SDK dvm did not lay out and reaches it
  /// through whatever symlinks the machine happens to have.
  late final String binDir = fileSystem.path.dirname(sdk.executable.path);

  /// The PATH the child gets: [binDir] first, then everything the parent had.
  ///
  /// First is the whole point. `dvm exec melos bootstrap` only means anything
  /// if the `dart` that melos goes on to spawn is the pinned one.
  late final String path = _prefixed();

  /// What to change about the parent environment for the child.
  ///
  /// Overrides only — `Process.start` merges these over the real environment,
  /// and a child handed a hand-built environment instead of the user's own
  /// would be missing HOME, TERM and everything else it needs.
  late final Map<String, String> environment = {
    _pathKey: path,
    // Absent under rule 4, where the SDK is not dvm-managed and pinning a
    // version dvm did not choose would be a lie a nested dvm then acts on.
    if (sdk.version case final version?)
      VersionResolver.versionVariable: version,
  };

  /// Where [command] resolves on the child's [path], or null if nothing there
  /// matches.
  ///
  /// dvm does the lookup itself rather than handing a bare name to
  /// `Process.start`, because the point of `exec` is to search the PATH the
  /// *child* is about to get, and the platform would search the one dvm has.
  File? lookup(String command) {
    if (command.isEmpty) return null;

    // The shell's rule: a name with a separator in it is a path, and is used
    // as given rather than searched for.
    if (_isPathLike(command)) {
      final file = fileSystem.file(command);
      return file.existsSync() ? file : null;
    }

    for (final entry in path.split(_separator)) {
      final directory = entry.trim();
      if (directory.isEmpty) continue;
      for (final name in _candidateNames(command)) {
        final candidate = fileSystem.file(
          fileSystem.path.join(directory, name),
        );
        if (candidate.existsSync()) return candidate;
      }
    }
    return null;
  }

  /// The parent's own spelling of PATH.
  ///
  /// Windows environment variables are case-insensitive and real ones arrive as
  /// `Path`; writing `PATH` back would leave the child with the old value under
  /// the old name on any platform that disagrees.
  String get _pathKey {
    for (final key in _parent.keys) {
      if (key.toLowerCase() == 'path') return key;
    }
    return 'PATH';
  }

  String _prefixed() {
    final existing = _parent[_pathKey];
    if (existing == null || existing.isEmpty) return binDir;

    // A nested invocation inherits a PATH this function already prefixed. Left
    // alone, `dvm exec` inside `dvm exec` inside a build script grows PATH by
    // one entry per level for the whole tree.
    final first = existing.split(_separator).first.trim();
    if (fileSystem.path.equals(first, binDir)) return existing;

    return '$binDir$_separator$existing';
  }

  List<String> _candidateNames(String command) {
    if (!_isWindows) return [command];
    // Windows resolves a bare name through PATHEXT; a name that already has an
    // extension is used as written.
    if (fileSystem.path.extension(command).isNotEmpty) return [command];
    return ['$command.exe', '$command.bat', '$command.cmd', command];
  }

  bool _isPathLike(String command) =>
      command.contains('/') || (_isWindows && command.contains(r'\'));

  String get _separator => _isWindows ? ';' : ':';

  bool get _isWindows => fileSystem.path.style == p.Style.windows;
}

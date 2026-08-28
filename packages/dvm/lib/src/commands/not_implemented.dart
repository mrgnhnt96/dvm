import 'package:args/command_runner.dart';

import '../core/context.dart';

/// The exit code every unimplemented command returns.
///
/// 70 is `EX_SOFTWARE` from sysexits(3): the command exists and was invoked
/// correctly, the program just cannot do it yet. A shell script can tell that
/// apart from 64 (bad usage) and 127 (no such command).
const int notImplementedExitCode = 70;

/// The body every command in this CLI starts life with.
///
/// A command becomes real by dropping this mixin and writing its own [run].
/// Registration in `lib/dvm.dart` does not change when that happens.
mixin NotImplementedCommand on Command<int> {
  /// The collaborators this command was constructed with.
  DvmContext get context;

  @override
  Future<int> run() async {
    context.err.writeln('dvm $name: not implemented yet');
    return notImplementedExitCode;
  }
}

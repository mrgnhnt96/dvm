// Not a test: the program the real-process tests spawn.
//
// `OsProcessRunner` can only be shown to inherit stdio and to forward signals
// from a process that has its own stdio and its own signals, so this puts it in
// one. It runs whatever it is told to and exits with that child's exit code —
// exactly what `dvm dart` and `dvm exec` do, minus the resolution.
import 'dart:io';

import 'package:dvm_cli/src/core/runner.dart';

Future<void> main(List<String> args) async {
  exitCode = await const OsProcessRunner().run(args.first, args.sublist(1));
}

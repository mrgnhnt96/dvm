/// A per-project Dart SDK version manager.
library;

import 'dart:io';

/// Runs the `dvm` CLI with [args] and resolves to the process exit code.
Future<int> run(List<String> args) async {
  stdout.writeln('dvm ${version()}');
  return 0;
}

/// The version of this build of dvm.
String version() => '0.1.0-dev';

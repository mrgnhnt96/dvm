import 'dart:io';

import 'package:dvm_cli/dvm.dart';

Future<void> main(List<String> args) async {
  exitCode = await run(args);
}

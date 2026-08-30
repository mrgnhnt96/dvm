import 'dart:io';

import 'package:dvm/dvm.dart';

Future<void> main(List<String> args) async {
  exitCode = await run(args);
}

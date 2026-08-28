import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../core/context.dart';
import 'not_implemented.dart';

/// `dvm dart` — Run dart from the resolved SDK.
class DartCommand extends Command<int> with NotImplementedCommand {
  DartCommand({required this.context});

  @override
  final DvmContext context;

  @override
  String get name => 'dart';

  @override
  String get description => 'Run dart from the resolved SDK.';

  @override
  String get invocation => 'dvm dart <args...>';

  // Everything after the command name belongs to the child process,
  // including flags that would otherwise look like dvm's own.
  @override
  final ArgParser argParser = ArgParser.allowAnything();
}

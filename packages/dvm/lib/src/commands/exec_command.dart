import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../core/context.dart';
import 'not_implemented.dart';

/// `dvm exec` — Run a command with the resolved SDK first on PATH.
class ExecCommand extends Command<int> with NotImplementedCommand {
  ExecCommand({required this.context});

  @override
  final DvmContext context;

  @override
  String get name => 'exec';

  @override
  String get description =>
      'Run a command with the resolved SDK first on PATH.';

  @override
  String get invocation => 'dvm exec <command> [args...]';

  // Everything after the command name belongs to the child process,
  // including flags that would otherwise look like dvm's own.
  @override
  final ArgParser argParser = ArgParser.allowAnything();
}

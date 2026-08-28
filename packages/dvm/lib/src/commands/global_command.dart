import 'package:args/command_runner.dart';

import '../core/context.dart';
import 'not_implemented.dart';

/// `dvm global` — Set the version used when no .dvmrc applies.
class GlobalCommand extends Command<int> with NotImplementedCommand {
  GlobalCommand({required this.context});

  @override
  final DvmContext context;

  @override
  String get name => 'global';

  @override
  String get description => 'Set the version used when no .dvmrc applies.';

  @override
  String get invocation => 'dvm global <version>';
}

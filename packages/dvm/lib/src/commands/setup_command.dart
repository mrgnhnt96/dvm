import 'package:args/command_runner.dart';

import '../core/context.dart';
import 'not_implemented.dart';

/// `dvm setup` — Install the shims and print the PATH line to add.
class SetupCommand extends Command<int> with NotImplementedCommand {
  SetupCommand({required this.context});

  @override
  final DvmContext context;

  @override
  String get name => 'setup';

  @override
  String get description => 'Install the shims and print the PATH line to add.';
}

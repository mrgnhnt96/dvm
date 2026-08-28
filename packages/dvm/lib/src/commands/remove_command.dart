import 'package:args/command_runner.dart';

import '../core/context.dart';
import 'not_implemented.dart';

/// `dvm remove` — Delete an installed SDK.
class RemoveCommand extends Command<int> with NotImplementedCommand {
  RemoveCommand({required this.context});

  @override
  final DvmContext context;

  @override
  String get name => 'remove';

  @override
  String get description => 'Delete an installed SDK.';

  @override
  String get invocation => 'dvm remove <version> [--force]';
}

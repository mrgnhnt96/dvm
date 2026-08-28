import 'package:args/command_runner.dart';

import '../core/context.dart';
import 'not_implemented.dart';

/// `dvm unalias` — Remove a named version.
class UnaliasCommand extends Command<int> with NotImplementedCommand {
  UnaliasCommand({required this.context});

  @override
  final DvmContext context;

  @override
  String get name => 'unalias';

  @override
  String get description => 'Remove a named version.';

  @override
  String get invocation => 'dvm unalias <name>';
}

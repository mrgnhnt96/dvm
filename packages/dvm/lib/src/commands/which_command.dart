import 'package:args/command_runner.dart';

import '../core/context.dart';
import 'not_implemented.dart';

/// `dvm which` — Print the resolved SDK and which rule chose it. (alias: current)
class WhichCommand extends Command<int> with NotImplementedCommand {
  WhichCommand({required this.context});

  @override
  final DvmContext context;

  @override
  String get name => 'which';

  @override
  String get description =>
      'Print the resolved SDK and which rule chose it. (alias: current)';

  @override
  List<String> get aliases => const ['current'];
}

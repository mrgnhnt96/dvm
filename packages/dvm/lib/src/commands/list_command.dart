import 'package:args/command_runner.dart';

import '../core/context.dart';
import 'not_implemented.dart';

/// `dvm list` — List installed SDKs, marking the global and the current project. (alias: ls)
class ListCommand extends Command<int> with NotImplementedCommand {
  ListCommand({required this.context});

  @override
  final DvmContext context;

  @override
  String get name => 'list';

  @override
  String get description =>
      'List installed SDKs, marking the global and the current project. (alias: ls)';

  @override
  List<String> get aliases => const ['ls'];
}

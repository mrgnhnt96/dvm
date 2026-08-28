import 'package:args/command_runner.dart';

import '../core/context.dart';
import 'not_implemented.dart';

/// `dvm migrate` — Import SDKs from the older cbracken/dvm layout.
class MigrateCommand extends Command<int> with NotImplementedCommand {
  MigrateCommand({required this.context});

  @override
  final DvmContext context;

  @override
  String get name => 'migrate';

  @override
  String get description => 'Import SDKs from the older cbracken/dvm layout.';
}

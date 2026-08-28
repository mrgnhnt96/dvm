import 'package:args/command_runner.dart';

import '../core/context.dart';
import 'not_implemented.dart';

/// `dvm use` — Pin a version for this project and write .dvmrc.
class UseCommand extends Command<int> with NotImplementedCommand {
  UseCommand({required this.context});

  @override
  final DvmContext context;

  @override
  String get name => 'use';

  @override
  String get description => 'Pin a version for this project and write .dvmrc.';

  @override
  String get invocation => 'dvm use <version> [--global]';
}

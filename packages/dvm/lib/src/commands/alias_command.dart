import 'package:args/command_runner.dart';

import '../core/context.dart';
import 'not_implemented.dart';

/// `dvm alias` — Give a version a name, or list the names you have.
class AliasCommand extends Command<int> with NotImplementedCommand {
  AliasCommand({required this.context});

  @override
  final DvmContext context;

  @override
  String get name => 'alias';

  @override
  String get description =>
      'Give a version a name, or list the names you have.';

  @override
  String get invocation => 'dvm alias <name> <version> | alias list';
}

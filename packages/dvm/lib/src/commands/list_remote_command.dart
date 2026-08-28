import 'package:args/command_runner.dart';

import '../core/context.dart';
import 'not_implemented.dart';

/// `dvm list-remote` — List the releases available from the Dart archive.
class ListRemoteCommand extends Command<int> with NotImplementedCommand {
  ListRemoteCommand({required this.context});

  @override
  final DvmContext context;

  @override
  String get name => 'list-remote';

  @override
  String get description =>
      'List the releases available from the Dart archive.';
}

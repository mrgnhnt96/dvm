import 'package:args/command_runner.dart';

import '../core/context.dart';
import 'not_implemented.dart';

/// `dvm install` — Download, verify and install a Dart SDK.
class InstallCommand extends Command<int> with NotImplementedCommand {
  InstallCommand({required this.context});

  @override
  final DvmContext context;

  @override
  String get name => 'install';

  @override
  String get description => 'Download, verify and install a Dart SDK.';

  @override
  String get invocation => 'dvm install <version|channel|alias>';
}

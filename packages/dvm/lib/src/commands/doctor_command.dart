import 'package:args/command_runner.dart';

import '../core/context.dart';
import 'not_implemented.dart';

/// `dvm doctor` — Check PATH order, shim health, symlinks and config validity.
class DoctorCommand extends Command<int> with NotImplementedCommand {
  DoctorCommand({required this.context});

  @override
  final DvmContext context;

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check PATH order, shim health, symlinks and config validity.';
}

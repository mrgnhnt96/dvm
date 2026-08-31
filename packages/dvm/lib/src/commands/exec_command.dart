import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../core/context.dart';
import '../core/runner.dart';
import 'dart_command.dart';

/// What a shell returns when a command is not on PATH.
///
/// `dvm exec` is a launcher, so it answers the way the thing it stands in for
/// answers: a script testing for 127 must not be told 1 instead.
const int commandNotFoundExitCode = 127;

/// `dvm exec` — Run a command with the resolved SDK first on PATH.
class ExecCommand extends Command<int> {
  ExecCommand({required this.context});

  final DvmContext context;

  @override
  String get name => 'exec';

  @override
  String get description =>
      'Run a command with the resolved SDK first on PATH.';

  @override
  String get invocation => 'dvm exec <command> [args...]';

  // Everything after the command name belongs to the child process,
  // including flags that would otherwise look like dvm's own.
  @override
  final ArgParser argParser = ArgParser.allowAnything();

  @override
  Future<int> run() async {
    final arguments = childArguments(argResults?.rest ?? const []);
    if (arguments.isEmpty) {
      throw UsageException('exec needs a command to run.', usage);
    }

    final sdk = context.resolver.resolve(from: context.workingDirectory);
    final invocation = SdkInvocation(
      fileSystem: context.fileSystem,
      sdk: sdk,
      environment: context.environment,
      verbose: context.verbose,
    );
    // The line the whole DVM_VERBOSE story exists for. A build script or a CI
    // job reaches dvm through the PATH shim — `exec dvm exec dart "$@"` — and
    // this is where a log can be made to say which SDK actually answered, and
    // which file said so.
    describeSdkChoice(context, sdk);

    final command = arguments.first;
    final executable = invocation.lookup(command);
    if (executable == null) {
      context.err.writeln('dvm exec: command not found: $command');
      return commandNotFoundExitCode;
    }

    return context.processes.run(
      executable.path,
      arguments.sublist(1),
      environment: invocation.environment,
      workingDirectory: context.workingDirectory.path,
    );
  }
}

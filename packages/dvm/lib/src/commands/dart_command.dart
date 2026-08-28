import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../core/context.dart';
import '../core/runner.dart';

/// `dvm dart` — Run dart from the resolved SDK.
class DartCommand extends Command<int> {
  DartCommand({required this.context});

  final DvmContext context;

  @override
  String get name => 'dart';

  @override
  String get description => 'Run dart from the resolved SDK.';

  @override
  String get invocation => 'dvm dart <args...>';

  // Everything after the command name belongs to the child process,
  // including flags that would otherwise look like dvm's own.
  @override
  final ArgParser argParser = ArgParser.allowAnything();

  @override
  Future<int> run() async {
    final sdk = context.resolver.resolve(from: context.workingDirectory);
    final invocation = SdkInvocation(
      fileSystem: context.fileSystem,
      sdk: sdk,
      environment: context.environment,
    );

    return context.processes.run(
      sdk.executable.path,
      childArguments(argResults?.rest ?? const []),
      environment: invocation.environment,
      workingDirectory: context.workingDirectory.path,
    );
  }
}

/// What actually reaches the child, given everything after the dvm command.
///
/// `ArgParser.allowAnything()` hands over the arguments verbatim, which is what
/// makes `dvm dart --version` report the SDK's version instead of dvm's. That
/// leaves one thing to do here: drop a leading `--`. A user writing
/// `dvm dart -- --version` is using the terminator to say "stop reading these",
/// and passing the terminator itself through would make dart parse an argument
/// the user meant for dvm.
List<String> childArguments(List<String> rest) =>
    rest.isNotEmpty && rest.first == '--' ? rest.sublist(1) : rest;

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../core/context.dart';
import '../core/resolver.dart';
import '../core/runner.dart';
import '../core/verbose.dart';

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
      verbose: context.verbose,
    );
    describeSdkChoice(context, sdk);

    return context.processes.run(
      sdk.executable.path,
      childArguments(argResults?.rest ?? const []),
      environment: invocation.environment,
      workingDirectory: context.workingDirectory.path,
    );
  }
}

/// Says on the verbose channel which SDK is about to run, and what chose it.
///
/// Shared by `dvm dart` and `dvm exec` because they are the two ways into an
/// SDK and a log that only covered one of them would be worse than none: the
/// shim goes through `exec`, so that is the path a CI log sees, and the two
/// must not be able to disagree about how they report themselves.
void describeSdkChoice(DvmContext context, ResolvedSdk sdk) {
  context.verbose.log(
    VerboseArea.exec,
    () => 'running ${sdk.executable.path}',
  );
  context.verbose.log(
    VerboseArea.exec,
    () => '  chosen by ${sdk.rule.label}'
        '${sdk.source == null ? '' : ' (${sdk.source})'}'
        '${sdk.version == null ? '' : ', Dart ${sdk.version}'}',
  );
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

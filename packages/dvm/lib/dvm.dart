/// A per-project Dart SDK version manager.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';

import 'src/commands/alias_command.dart';
import 'src/commands/dart_command.dart';
import 'src/commands/doctor_command.dart';
import 'src/commands/exec_command.dart';
import 'src/commands/global_command.dart';
import 'src/commands/install_command.dart';
import 'src/commands/list_command.dart';
import 'src/commands/list_remote_command.dart';
import 'src/commands/migrate_command.dart';
import 'src/commands/remove_command.dart';
import 'src/commands/setup_command.dart';
import 'src/commands/unalias_command.dart';
import 'src/commands/use_command.dart';
import 'src/commands/which_command.dart';
import 'src/core/context.dart';
import 'src/core/exceptions.dart';
import 'src/core/installer.dart';
import 'src/core/process.dart';
import 'src/core/releases.dart';

export 'src/commands/not_implemented.dart';
export 'src/core/channel.dart';
export 'src/core/config.dart';
export 'src/core/context.dart';
export 'src/core/exceptions.dart';
export 'src/core/installer.dart';
export 'src/core/paths.dart';
export 'src/core/platform.dart';
export 'src/core/process.dart';
export 'src/core/releases.dart';
export 'src/core/resolver.dart';

/// Bad usage — `EX_USAGE` from sysexits(3).
const int usageExitCode = 64;

/// Runs the `dvm` CLI with [args] and resolves to the process exit code.
///
/// Everything the CLI touches is a parameter with a real-world default, so a
/// test can drive the whole binary against a `MemoryFileSystem` and a fake
/// environment without going near the real `~/.dvm`.
Future<int> run(
  List<String> args, {
  FileSystem? fileSystem,
  Map<String, String>? environment,
  String? platformVersion,
  StringSink? out,
  StringSink? err,
  ReleaseClient? releases,
  Installer? installer,
  ProcessRunner? processes,
}) async {
  final output = out ?? stdout;
  final errors = err ?? stderr;

  final context = DvmContext.wire(
    fileSystem: fileSystem ?? const LocalFileSystem(),
    environment: environment ?? Platform.environment,
    platformVersion: platformVersion ?? Platform.version,
    out: output,
    err: errors,
    releases: releases,
    installer: installer,
    processes: processes,
  );

  try {
    return await DvmCommandRunner(context).run(args) ?? 0;
  } on UsageException catch (error) {
    errors
      ..writeln(error.message)
      ..writeln()
      ..writeln(error.usage);
    return usageExitCode;
  } on DvmException catch (error) {
    // The message is already written for a human; a stack trace would only
    // bury it.
    errors.writeln('dvm: ${error.message}');
    return 1;
  }
}

/// The `dvm` command surface.
///
/// Every command in ARCHITECTURE.md's table is registered here, so a command
/// becoming real is a change to its own file and never to this one.
class DvmCommandRunner extends CommandRunner<int> {
  DvmCommandRunner(this.context)
      : super('dvm', 'A per-project Dart SDK version manager.') {
    argParser.addFlag(
      'version',
      negatable: false,
      help: 'Print the dvm version.',
    );

    addCommand(InstallCommand(context: context));
    addCommand(UseCommand(context: context));
    addCommand(ListCommand(context: context));
    addCommand(ListRemoteCommand(context: context));
    addCommand(RemoveCommand(context: context));
    addCommand(AliasCommand(context: context));
    addCommand(UnaliasCommand(context: context));
    addCommand(GlobalCommand(context: context));
    addCommand(WhichCommand(context: context));
    addCommand(DartCommand(context: context));
    addCommand(ExecCommand(context: context));
    addCommand(SetupCommand(context: context));
    addCommand(MigrateCommand(context: context));
    addCommand(DoctorCommand(context: context));
  }

  final DvmContext context;

  /// Writes usage to the injected sink instead of the process's stdout, so a
  /// test can assert on what `--help` printed.
  @override
  void printUsage() => context.out.writeln(usage);

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults.flag('version')) {
      context.out.writeln('dvm ${version()}');
      return 0;
    }
    return super.runCommand(topLevelResults);
  }
}

/// The version of this build of dvm.
String version() => '0.1.0-dev';

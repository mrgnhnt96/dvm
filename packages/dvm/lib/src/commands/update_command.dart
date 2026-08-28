import 'package:args/command_runner.dart';

import '../core/context.dart';

/// `dvm update` — Update dvm itself to the newest release.
class UpdateCommand extends Command<int> {
  UpdateCommand({required this.context}) {
    argParser.addFlag(
      'check',
      negatable: false,
      help: 'Report whether a newer dvm exists, without installing anything.',
    );
  }

  final DvmContext context;

  /// The name this command is registered under, so `lib/dvm.dart` can exclude
  /// it from the ambient version check without spelling it a second time.
  static const String commandName = 'update';

  @override
  String get name => commandName;

  @override
  String get description => 'Update dvm itself to the newest release.';

  @override
  String get invocation => 'dvm update [version]';

  @override
  Future<int> run() async {
    final results = argResults!;
    final version = switch (results.rest) {
      [] => null,
      [final String only] => only,
      final rest => throw UsageException(
          'dvm update takes at most one version, got ${rest.length}.',
          usage,
        ),
    };

    final check = results.flag('check');
    final updater = context.updater;

    try {
      final outcome = await updater.update(
        executablePath: context.executablePath,
        version: version,
        check: check,
      );

      if (outcome.isUpToDate) {
        context.out.writeln('dvm ${outcome.from} is already up to date.');
        return 0;
      }

      if (!outcome.installed) {
        context.out
          ..writeln('A newer dvm is available: ${outcome.from} -> '
              '${outcome.to}')
          ..writeln('Run `dvm update` to install it.');
        return 0;
      }

      context.out.writeln(
        'Updated dvm ${outcome.from} -> ${outcome.to} '
        '(${context.executablePath}).',
      );
      return 0;
    } finally {
      // The HTTP client would otherwise keep the VM alive for as long as its
      // idle connections do.
      updater.close();
    }
  }
}

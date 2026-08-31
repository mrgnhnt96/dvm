import 'package:args/command_runner.dart';

import '../core/context.dart';
import '../core/updater.dart';

/// `dvm update` — Update dvm itself to the newest release.
class UpdateCommand extends Command<int> {
  UpdateCommand({required this.context}) {
    argParser
      ..addFlag(
        'check',
        negatable: false,
        help: 'Report whether a newer dvm exists, without installing anything.',
      )
      ..addFlag(
        'alpha',
        negatable: false,
        help: 'Update to the newest alpha (the latest main) instead of the '
            'newest release. Per-invocation: nothing is remembered, and the '
            'next plain `dvm update` is a plain `dvm update`.',
      )
      ..addFlag(
        'stable',
        negatable: false,
        help: 'Return to the newest stable release, even from an alpha that '
            'is ahead of it. This is the way back off the alpha channel.',
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

    final wantsAlpha = results.flag('alpha');
    final wantsStable = results.flag('stable');
    // REFUSED, NOT RANKED. Each flag names a channel, they name different
    // ones, and picking either would leave the user told that the update they
    // did not ask for succeeded.
    if (wantsAlpha && wantsStable) {
      throw UsageException(
        '--alpha and --stable ask for two different channels. Pass one.',
        usage,
      );
    }

    final channel = switch ((wantsAlpha, wantsStable)) {
      (true, _) => UpdateChannel.alpha,
      (_, true) => UpdateChannel.stable,
      _ => UpdateChannel.newest,
    };

    final check = results.flag('check');
    final updater = context.updater;
    // Read before the update, because installing changes the answer on disk
    // but not in this process — and the message below is about the build that
    // is being replaced.
    final wasAlpha = updater.isAlphaBuild;

    try {
      final outcome = await updater.update(
        executablePath: context.executablePath,
        version: version,
        check: check,
        channel: channel,
      );

      switch (outcome.status) {
        case UpdateStatus.upToDate:
          context.out.writeln(
            channel == UpdateChannel.alpha
                ? 'dvm ${outcome.from} is already the newest alpha.'
                : 'dvm ${outcome.from} is already up to date.',
          );

        case UpdateStatus.alphaAheadOfStable:
          // NOT "up to date", which is what this used to say and what left
          // people stuck on an alpha with no way back that the tool named.
          context.out
            ..writeln('dvm ${outcome.from} is an ALPHA build, and the newest '
                'release (${outcome.to}) is not ahead of it.')
            ..writeln('Nothing was installed: replacing an alpha with an '
                'older codebase is not something to do quietly.')
            ..writeln()
            ..writeln('  a fresher alpha:            dvm update --alpha')
            ..writeln('  back to the newest release: dvm update --stable');

        case UpdateStatus.available:
          context.out
            ..writeln(
              channel == UpdateChannel.alpha
                  ? 'A newer dvm alpha is available: ${outcome.from} -> '
                      '${outcome.to}'
                  : 'A newer dvm is available: ${outcome.from} -> '
                      '${outcome.to}',
            )
            ..writeln(
              channel == UpdateChannel.alpha
                  ? 'Run `dvm update --alpha` to install it.'
                  : 'Run `dvm update` to install it.',
            );

        case UpdateStatus.installed:
          context.out.writeln(
            'Updated dvm ${outcome.from} -> ${outcome.to} '
            '(${context.executablePath}).',
          );
          // Said out loud rather than left to be discovered in `dvm --version`
          // later: the alpha they installed on purpose is gone.
          if (wasAlpha && channel != UpdateChannel.alpha) {
            context.out.writeln(
              'That is a stable release: you are no longer on the alpha '
              'channel.',
            );
          }
      }

      return 0;
    } finally {
      // The HTTP client would otherwise keep the VM alive for as long as its
      // idle connections do.
      updater.close();
    }
  }
}

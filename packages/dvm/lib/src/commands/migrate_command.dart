import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:file/file.dart';

import '../core/context.dart';
import '../core/migrate.dart';
import '../core/shell.dart';

/// `dvm migrate` — Import SDKs from the older cbracken/dvm layout.
///
/// The older tool keeps its SDKs in `~/.dvm/darts/<version>`, extracted, in
/// exactly the shape this dvm keeps them in `~/.dvm/versions/<version>`. So
/// migration is a **move**, and that is the point: nobody should have to
/// re-download 600MB of SDK they already have.
///
/// The whole command is written around one hazard. Those three directories may
/// be the user's only copy of those SDKs, so: the move happens before anything
/// is deleted, a version already in `versions/` is skipped rather than
/// overwritten, a move is only reported as done once the destination is
/// verified, and removing the older tool's own files is a separate `--clean`
/// run that has to be asked for and then confirmed.
class MigrateCommand extends Command<int> {
  MigrateCommand({required this.context, String? Function()? readLine})
      : _readLine = readLine ?? _stdinLine {
    argParser
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Print everything that would move and everything a later '
            '--clean would delete, and change nothing.',
      )
      ..addFlag(
        'clean',
        negatable: false,
        help: "Remove the older tool's own files, once its SDKs have been "
            'migrated. Never happens as part of a plain `dvm migrate`.',
      )
      ..addFlag(
        'yes',
        abbr: 'y',
        negatable: false,
        help: 'Answer yes to the questions this command would ask.',
      );
  }

  final DvmContext context;

  /// Reads one line of the user's answer. Injected so a test can drive the
  /// prompts without a terminal, and so that "there is no terminal" is a
  /// value rather than a call into `dart:io` from the middle of the logic.
  final String? Function() _readLine;

  /// Null when there is nobody to ask, which every prompt reads as "no".
  static String? _stdinLine() =>
      io.stdin.hasTerminal ? io.stdin.readLineSync() : null;

  @override
  String get name => 'migrate';

  @override
  String get description => 'Import SDKs from the older cbracken/dvm layout.';

  @override
  String get invocation => 'dvm migrate [--dry-run] [--clean]';

  @override
  Future<int> run() async {
    final dryRun = argResults!.flag('dry-run');
    final migrator = Migrator(
      fileSystem: context.fileSystem,
      paths: context.paths,
    );
    final plan = migrator.plan();

    if (!plan.isPresent) {
      context.out.writeln(
        'Nothing to migrate: no older dvm (cbracken/dvm) install in '
        '${context.display(plan.home.path)}.\n'
        'That directory would have a scripts/dvm and a darts/ in it.',
      );
      return 0;
    }

    _reportFound(plan);
    if (argResults!.flag('clean')) return _clean(migrator, plan, dryRun);

    _reportInventory(plan);
    if (dryRun) return _reportDryRun(plan);

    return _migrate(migrator, plan);
  }

  /// Says what was found before doing anything, so the user can recognise
  /// their own machine in the output before dvm touches it.
  void _reportFound(MigrationPlan plan) {
    context.out
      ..writeln('Found an older dvm (cbracken/dvm) in '
          '${context.display(plan.home.path)}:')
      ..writeln('  ${plan.markers.join('  ')}')
      ..writeln();
  }

  /// Lists every `darts/*` entry and what dvm believes it is.
  void _reportInventory(MigrationPlan plan) {
    if (plan.entries.isEmpty) {
      context.out.writeln(
        plan.hasDartsDir
            ? 'darts/ is empty — there are no SDKs to move.'
            : 'There is no darts/ directory, so there are no SDKs to move.',
      );
      context.out.writeln();
      return;
    }

    final count = plan.entries.length;
    context.out.writeln('${count == 1 ? '1 SDK' : '$count SDKs'} in darts/:');
    for (final entry in plan.entries) {
      final sdk = entry.sdk;
      final detail = switch (entry.action) {
        MigrationAction.move => '-> ${context.display(entry.destination.path)}',
        MigrationAction.alreadyInstalled =>
          'SKIP: Dart ${sdk.version} is already installed at '
              '${context.display(entry.destination.path)}',
        MigrationAction.duplicate =>
          'SKIP: ${entry.note}, and dvm will not overwrite it',
      };
      context.out.writeln('  darts/${sdk.directoryName}  $detail');

      if (sdk.nameDisagrees) {
        context.out.writeln(
          '    its version file says ${sdk.recordedVersion}, not '
          '${sdk.directoryName} — dvm believes the version file',
        );
      }
      if (sdk.problem case final problem?) {
        context.out.writeln('    $problem');
      }
    }
    context.out.writeln();
  }

  /// `--dry-run`: the complete account, including the part a plain run would
  /// only offer later. Somebody cautious reaches for this flag first, so it
  /// has to show the deletions too or it is not the answer they asked for.
  int _reportDryRun(MigrationPlan plan) {
    final moves = plan.moves;
    if (moves.isEmpty) {
      context.out.writeln('Would move: nothing.');
    } else {
      context.out.writeln('Would move:');
      for (final entry in moves) {
        context.out.writeln(
          '  ${context.display(entry.sdk.directory.path)}  ->  '
          '${context.display(entry.destination.path)}',
        );
      }
    }

    context.out.writeln();
    _reportGlobalPreview(plan);

    context.out.writeln();
    if (plan.leftovers.isEmpty) {
      context.out.writeln(
        'Would delete: nothing. `dvm migrate --clean` has nothing left to '
        'remove.',
      );
    } else {
      context.out.writeln(
        'Would delete, only if you then run `dvm migrate --clean` and confirm '
        'it — a plain `dvm migrate` never deletes any of this:',
      );
      for (final entity in plan.leftovers) {
        context.out.writeln('  ${context.display(entity.path)}');
      }
      if (!plan.hasUnmigratedSdks) {
        final darts = LegacyDvmPaths(context.paths).emptyDartsDir();
        if (darts != null) {
          context.out.writeln('  ${context.display(darts.path)}');
        }
      } else {
        context.out.writeln(
          '  (darts/ itself stays until every SDK above has moved)',
        );
      }
    }

    context.out
      ..writeln()
      ..writeln('Nothing was changed. Run `dvm migrate` to do it.');
    _reportShellReminder();
    return 0;
  }

  /// The plain run: move the SDKs, then offer the global default, then point
  /// at `--clean` without doing any of it.
  int _migrate(Migrator migrator, MigrationPlan plan) {
    final outcomes = migrator.apply(plan);
    var failed = false;

    for (final outcome in outcomes) {
      if (outcome.moved) {
        context.out.writeln(
          'Moved Dart ${outcome.entry.sdk.version} to '
          '${context.display(outcome.entry.destination.path)}',
        );
      } else {
        failed = true;
        context.err.writeln('dvm: ${outcome.failure}');
      }
    }

    if (outcomes.isEmpty) {
      context.out.writeln('No SDKs needed moving.');
    }
    context.out.writeln();

    _offerGlobal(plan);

    context.out.writeln();
    if (plan.leftovers.isEmpty) {
      context.out.writeln("The older tool's own files are already gone.");
    } else if (failed) {
      context.err.writeln(
        "Not offering to remove the older tool's files: an SDK above did not "
        'move, and those files are the only record of where it came from.',
      );
    } else {
      context.out
        ..writeln(
          "The older tool's own files are still in "
          '${context.display(plan.home.path)} and are now unused:',
        )
        ..writeln('  ${plan.leftovers.map((e) => e.basename).join('  ')}')
        ..writeln(
          'Remove them when you are ready — it is a separate step, on '
          'purpose:\n'
          '  dvm migrate --clean',
        );
    }

    _reportShellReminder();
    return failed ? 1 : 0;
  }

  /// `--clean`: the second, explicitly-asked-for step.
  int _clean(Migrator migrator, MigrationPlan plan, bool dryRun) {
    // The guard that matters. Anything still in darts/ is an SDK that has not
    // made it across, and `.git`/`VERSION` are how a human works out what
    // these directories were.
    if (plan.hasUnmigratedSdks) {
      context.err.writeln(
        'dvm: refusing to clean up — '
        '${plan.moves.length} SDK(s) in darts/ have not been migrated yet:\n'
        '${plan.moves.map((e) => '  ${context.display(e.sdk.directory.path)}').join('\n')}\n'
        'Run `dvm migrate` first.',
      );
      return 1;
    }

    final targets = <FileSystemEntity>[
      ...plan.leftovers,
      if (LegacyDvmPaths(context.paths).emptyDartsDir() case final darts?)
        darts,
    ];
    if (targets.isEmpty) {
      context.out.writeln('Nothing to clean up.');
      return 0;
    }

    context.out.writeln(
        'These will be deleted from ${context.display(plan.home.path)}:');
    for (final entity in targets) {
      context.out.writeln('  ${context.display(entity.path)}');
    }
    context.out.writeln();

    if (dryRun) {
      context.out.writeln('Nothing was changed.');
      return 0;
    }

    if (!_confirm('Delete them?')) {
      context.out.writeln('Left them alone.');
      return 0;
    }

    final outcomes = migrator.clean(targets);
    var failed = false;
    for (final outcome in outcomes) {
      if (outcome.removed) {
        context.out.writeln('Removed ${context.display(outcome.entity.path)}');
      } else {
        failed = true;
        context.err.writeln(
          'dvm: could not remove ${context.display(outcome.entity.path)}: '
          '${outcome.failure}',
        );
      }
    }

    _reportShellReminder();
    return failed ? 1 : 0;
  }

  /// Offers to carry the older tool's active version over as `global`.
  void _offerGlobal(MigrationPlan plan) {
    final version = plan.activeVersion;
    if (version == null) {
      if (plan.activeVersionProblem case final problem?) {
        context.err.writeln(
          'dvm could not tell which version the older tool had active: '
          '$problem. Set the default yourself with: dvm global <version>',
        );
      }
      return;
    }

    if (!context.paths.versionDir(version).existsSync()) {
      context.err.writeln(
        'The older tool had Dart $version active, but it is not in '
        '${context.display(context.paths.versionsDir.path)}, so dvm is not '
        'making it the default. Install it with: dvm install $version',
      );
      return;
    }

    final config = context.config.read();
    if (config.global == version) {
      context.out.writeln(
        'Dart $version was the older tool\'s active version, and it is '
        'already your dvm default.',
      );
      return;
    }

    final replacing = config.global;
    final question = replacing == null
        ? 'The older tool had Dart $version active. Make it your dvm default?'
        : 'The older tool had Dart $version active. Make it your dvm default, '
            'replacing $replacing?';

    if (!_confirm(question)) {
      context.out.writeln(
        'Left the default alone. Set it later with: dvm global $version',
      );
      return;
    }

    context.config.write(config.copyWith(global: version));
    context.out.writeln('Dart $version is now your dvm default.');
  }

  /// What `--dry-run` says instead of asking the global question.
  void _reportGlobalPreview(MigrationPlan plan) {
    final version = plan.activeVersion;
    if (version == null) {
      context.out.writeln(
        plan.activeVersionProblem == null
            ? 'Would ask about the global default: nothing to ask — the older '
                'tool has no active version recorded.'
            : 'Would ask about the global default: nothing to ask — '
                '${plan.activeVersionProblem}.',
      );
      return;
    }
    context.out.writeln(
      'Would ask whether to make Dart $version — the version the older tool '
      'has active — your dvm default.',
    );
  }

  /// Item seven, and the reason a successful migration can still look broken:
  /// the older tool installs `dvm` as a *shell function*, and a shell function
  /// is resolved before PATH is ever searched. Until that line comes out of
  /// the startup file, every `dvm` the user types is still the old one.
  void _reportShellReminder() {
    final shell = ShellFacts(
      fileSystem: context.fileSystem,
      environment: context.environment,
    );
    final scan = shell.scanForShadows();

    context.out
      ..writeln()
      ..writeln(
        'One more thing: take the line that sources the older dvm out of your '
        'shell startup file —',
      )
      ..writeln('  . "\$HOME/.dvm/scripts/dvm"')
      ..writeln(
        'It defines `dvm` as a shell function, and a function beats any binary '
        'on PATH, so until it is gone you are still running the old tool.',
      );

    if (scan.shadows.isNotEmpty) {
      context.out.writeln('Found it:');
      for (final shadow in scan.shadows) {
        context.out.writeln('  ${shadow.describe()}');
      }
    }
    for (final entry in scan.unreadable.entries) {
      // "We could not open the file" is not "the file is clean".
      context.err.writeln(
        'dvm could not read ${entry.key} (${entry.value}), so it cannot say '
        'whether that file sources the older dvm.',
      );
    }
  }

  /// Asks [question], defaulting to no.
  ///
  /// No terminal means no answer, and no answer means no — a migration run
  /// from a script must never take silence for consent about anything.
  bool _confirm(String question) {
    if (argResults!.flag('yes')) {
      context.out.writeln('$question [y/N] y');
      return true;
    }

    context.out.write('$question [y/N] ');
    final answer = _readLine();
    context.out.writeln();

    if (answer == null) {
      context.err.writeln(
        'Nothing to read the answer from, so dvm is taking that as no. '
        'Pass --yes to answer yes without being asked.',
      );
      return false;
    }
    return const {'y', 'yes'}.contains(answer.trim().toLowerCase());
  }
}

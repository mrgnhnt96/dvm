import 'package:args/command_runner.dart';

import '../core/channel.dart';
import '../core/context.dart';
import '../core/resolver.dart';

/// `dvm which` — Print the resolved SDK and which rule chose it. (alias: current)
class WhichCommand extends Command<int> {
  WhichCommand({required this.context}) {
    argParser.addFlag(
      'path',
      negatable: false,
      help: 'Print only the path to the dart executable, for scripting.',
    );
  }

  final DvmContext context;

  @override
  String get name => 'which';

  @override
  String get description =>
      'Print the resolved SDK and which rule chose it. (alias: current)';

  @override
  List<String> get aliases => const ['current'];

  @override
  Future<int> run() async {
    // Rule 5 throws out of here with the message that enumerates all five
    // rules and what to run, which is exactly what `which` would print.
    final resolved = context.resolver.resolve(from: context.workingDirectory);

    if (argResults!.flag('path')) {
      context.out.writeln(resolved.executable.path);
      return 0;
    }

    context.out.writeln(resolved.executable.path);
    if (resolved.version != null) {
      context.out.writeln('Dart ${resolved.version}');
    }
    context.out.writeln(_explainRule(resolved));

    final indirection = _explainIndirection(resolved);
    if (indirection != null) context.out.writeln('  $indirection');

    context.out.writeln('SDK: ${resolved.sdkDir.path}');
    if (!resolved.isManaged) {
      context.out.writeln(
        'This SDK is not managed by dvm. Pin one for this directory with: '
        'dvm use <version>',
      );
    }
    return 0;
  }

  /// The whole point of the command: which of the five rules answered, said
  /// the way a person would say it.
  String _explainRule(ResolvedSdk resolved) => switch (resolved.rule) {
        ResolutionRule.environmentVariable =>
          'Chosen by rule 1 of 5: ${VersionResolver.versionVariable} is set in '
              'the environment, which overrides everything on disk.',
        ResolutionRule.dvmrc =>
          'Chosen by rule 2 of 5: pinned by ${resolved.source}.',
        ResolutionRule.globalDefault =>
          'Chosen by rule 3 of 5: no .dvmrc applies here, so the global '
              'default in ${resolved.source} was used.',
        ResolutionRule.pathFallback =>
          'Chosen by rule 4 of 5: nothing pins a version here and no global '
              'default is set, so this is the next dart on PATH, found in '
              '${resolved.source}.',
      };

  /// The hop from what was written down to what it turned out to mean.
  String? _explainIndirection(ResolvedSdk resolved) {
    final requested = resolved.requested;
    final version = resolved.version;
    if (requested == null || version == null || requested == version) {
      return null;
    }

    final channel = Channel.tryParse(requested);
    if (channel != null) {
      return 'It says "$requested", the channel that was recorded as '
          '$version when it was last installed.';
    }
    return 'It says "$requested", an alias for $version in '
        '${context.paths.configFile.path}.';
  }
}

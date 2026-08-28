import 'package:args/command_runner.dart';

import '../core/context.dart';
import '../core/exceptions.dart';
import 'version_ref.dart';

/// `dvm remove` — Delete an installed SDK.
class RemoveCommand extends Command<int> {
  RemoveCommand({required this.context}) {
    argParser.addFlag(
      'force',
      abbr: 'f',
      negatable: false,
      help: 'Remove it even if something still points at it.',
    );
  }

  final DvmContext context;

  @override
  String get name => 'remove';

  @override
  String get description => 'Delete an installed SDK.';

  @override
  String get invocation => 'dvm remove <version> [--force]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw UsageException('Name a version to remove.', usage);
    }
    if (rest.length > 1) {
      throw UsageException(
        'Remove takes one version at a time, but got: ${rest.join(' ')}',
        usage,
      );
    }

    final ref = resolveVersionRef(context, rest.single);
    final version = ref.version;
    final directory = context.paths.versionDir(version);

    if (!directory.existsSync()) {
      context.err.writeln(
        'Dart $version is not installed, so there is nothing to remove. '
        'See what is: dvm list',
      );
      return 1;
    }

    final dependents = _dependents(version);
    final force = argResults!.flag('force');
    if (dependents.isNotEmpty && !force) {
      final count = dependents.length == 1
          ? 'something still points'
          : '${dependents.length} things still point';
      context.err.writeln(
        'Refusing to remove Dart $version: $count at it.\n'
        '${dependents.map((d) => '  - $d').join('\n')}\n'
        'Repoint them first, or remove it anyway with: '
        'dvm remove ${rest.single} --force',
      );
      return 1;
    }

    directory.deleteSync(recursive: true);
    context.out.writeln('Removed Dart $version (${directory.path}).');

    _dropStaleChannelRecords(version);
    if (dependents.isNotEmpty) {
      context.err.writeln(
        'These now point at a version that is not installed:\n'
        '${dependents.map((d) => '  - $d').join('\n')}',
      );
    }
    _warnAboutProjectPin(version);
    return 0;
  }

  /// What still names [version] and would break if it went away.
  ///
  /// Channel records are deliberately not in here. Every SDK installed with
  /// `dvm install stable` has one, so counting them would make `remove` refuse
  /// almost everything; the stale record is dropped after the delete instead.
  List<String> _dependents(String version) {
    final config = context.config.read();
    final dependents = <String>[];

    final global = config.global;
    if (global != null && _resolvesTo(global, version)) {
      dependents.add(
        'the global default${global == version ? '' : ' ("$global")'} in '
        '${context.paths.configFile.path}',
      );
    }

    for (final entry in config.aliases.entries) {
      if (_resolvesTo(entry.key, version)) {
        dependents.add(
          'the alias "${entry.key}" -> ${entry.value}'
          '${entry.value == version ? '' : ' -> $version'}',
        );
      }
    }
    return dependents;
  }

  /// Whether [pin] ends up at [version] once aliases and channels are
  /// followed. A pin that cannot be resolved at all points at nothing, so it
  /// is not a dependent.
  bool _resolvesTo(String pin, String version) {
    try {
      return resolveVersionRef(context, pin).version == version;
    } on DvmException {
      return false;
    }
  }

  /// Forgets `channels.<token>` entries naming the version just deleted.
  ///
  /// Leaving one behind means `dvm use stable` reports that stable is not
  /// installed while claiming to know exactly which version it is. The
  /// record is only meaningful while the SDK it names is on disk.
  void _dropStaleChannelRecords(String version) {
    final config = context.config.read();
    final stale = [
      for (final entry in config.channels.entries)
        if (entry.value == version) entry.key,
    ];
    if (stale.isEmpty) return;

    context.config.write(
      config.copyWith(
        channels: {
          for (final entry in config.channels.entries)
            if (entry.value != version) entry.key: entry.value,
        },
      ),
    );
    for (final channel in stale) {
      context.out.writeln(
        'dvm no longer knows which version "$channel" is. '
        'Run: dvm install $channel',
      );
    }
  }

  /// A `.dvmrc` is project data, not machine state, so it never blocks a
  /// removal — but the user is about to hit an error in that directory and
  /// should hear it from the command that caused it.
  void _warnAboutProjectPin(String version) {
    final rcFile = context.dvmrc.findNearest(context.workingDirectory);
    if (rcFile == null) return;

    final String? pin;
    try {
      pin = context.dvmrc.read(rcFile);
    } on DvmException {
      return;
    }
    if (pin == null || !_resolvesTo(pin, version)) return;

    context.err.writeln(
      '${rcFile.path} pins the version just removed. '
      'Run: dvm use <version>',
    );
  }
}

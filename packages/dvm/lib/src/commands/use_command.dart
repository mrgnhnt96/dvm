import 'package:args/command_runner.dart';
import 'package:file/file.dart';

import '../core/context.dart';
import '../core/exceptions.dart';
import 'version_ref.dart';

/// `dvm use` — Pin a version for this project and write .dvmrc.
class UseCommand extends Command<int> {
  UseCommand({required this.context}) {
    argParser
      ..addFlag(
        'global',
        abbr: 'g',
        negatable: false,
        help: 'Set the machine-wide default instead of pinning this project.',
      )
      ..addFlag(
        'gitignore',
        negatable: false,
        help: "Also add `$_ignoreRule` to this project's .gitignore.",
      );
  }

  final DvmContext context;

  @override
  String get name => 'use';

  @override
  String get description => 'Pin a version for this project and write .dvmrc.';

  @override
  String get invocation => 'dvm use <version> [--global]';

  /// What has to be ignored: the symlink is per-machine and points into
  /// `~/.dvm`, so committing it breaks every other checkout.
  static const String _ignoreRule = '.dvm/';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw UsageException(
        'Name a version, channel or alias to use.',
        usage,
      );
    }
    if (rest.length > 1) {
      throw UsageException(
        'Use takes one version at a time, but got: ${rest.join(' ')}',
        usage,
      );
    }

    final ref = resolveVersionRef(context, rest.single);
    await ensureInstalled(context, ref);

    if (argResults!.flag('global')) {
      writeGlobal(context, ref);
      return 0;
    }

    // The working directory, not the nearest existing .dvmrc: `dvm use` in a
    // package of a monorepo has to pin that package, not silently rewrite the
    // pin at the repository root.
    final project = context.workingDirectory;
    final rcFile = context.paths.dvmrcFile(project);
    context.dvmrc.write(rcFile, ref.version);
    final link = _linkProjectSdk(project, ref.version);

    final via = ref.isDirect ? '' : ' (${ref.trail})';
    context.out
      ..writeln('Pinned Dart ${ref.version} for ${project.path}$via.')
      ..writeln('  ${rcFile.path} -> commit this')
      ..writeln(
          '  ${link.path} -> ${context.paths.versionDir(ref.version).path}'
          ' (for your IDE; do not commit it)');

    _reportGitignore(project);
    return 0;
  }

  /// Points `.dvm/dart_sdk` at the pinned SDK, replacing whatever link was
  /// there before.
  Link _linkProjectSdk(Directory project, String version) {
    final target = context.paths.versionDir(version);
    final link = context.paths.projectSdkLink(project);
    context.paths.projectDvmDir(project).createSync(recursive: true);

    // followLinks: false — an existing link whose target was removed still
    // has to be replaced, and following it would report it as missing.
    final existing = context.fileSystem.typeSync(link.path, followLinks: false);
    if (existing == FileSystemEntityType.link) {
      link.deleteSync();
    } else if (existing != FileSystemEntityType.notFound) {
      throw ConfigException(
        '${link.path} already exists and is not a symlink, so dvm will not '
        'replace it. Delete it and run this again.',
      );
    }

    link.createSync(target.path);
    return link;
  }

  /// Says whether `.dvm/` is ignored, and adds it when asked to.
  ///
  /// The rule is only ever appended on an explicit `--gitignore`: editing a
  /// file the user did not name, in a repository dvm does not own, is not
  /// something to do behind their back. There is no prompt because commands
  /// here have no stdin — output sinks are injected precisely so that every
  /// command stays runnable from a test and from CI.
  void _reportGitignore(Directory project) {
    final gitignore = context.fileSystem.file(
      context.fileSystem.path.join(project.path, '.gitignore'),
    );

    if (_ignoresDvmDir(gitignore)) {
      context.out.writeln('`$_ignoreRule` is already ignored by '
          '${gitignore.path}.');
      return;
    }

    if (!argResults!.flag('gitignore')) {
      context.out.writeln(
        '`$_ignoreRule` is not ignored yet. Add it with: '
        'dvm use ${argResults!.rest.single} --gitignore',
      );
      return;
    }

    final existing = gitignore.existsSync() ? gitignore.readAsStringSync() : '';
    final separator = existing.isEmpty || existing.endsWith('\n') ? '' : '\n';
    gitignore.writeAsStringSync(
      '$existing$separator'
      "# dvm's per-project SDK symlink; .dvmrc is the part you commit.\n"
      '$_ignoreRule\n',
    );
    context.out.writeln('Added `$_ignoreRule` to ${gitignore.path}.');
  }

  /// Whether [gitignore] already covers the `.dvm` directory.
  ///
  /// Deliberately literal: it recognises the handful of spellings a person
  /// actually writes, and treats anything cleverer as "not ignored", which
  /// costs an unnecessary line rather than an unignored symlink.
  bool _ignoresDvmDir(File gitignore) {
    if (!gitignore.existsSync()) return false;
    const spellings = {
      '.dvm',
      '.dvm/',
      '/.dvm',
      '/.dvm/',
      '.dvm/*',
      '**/.dvm/'
    };
    return gitignore
        .readAsLinesSync()
        .map((line) => line.trim())
        .any(spellings.contains);
  }
}

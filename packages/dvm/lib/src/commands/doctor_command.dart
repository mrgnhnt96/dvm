import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;

import '../core/context.dart';
import '../core/exceptions.dart';
import '../core/shell.dart';
import '../core/shims.dart';
import 'version_ref.dart';

/// How bad a finding is.
///
/// Only [fail] changes the exit code. The split exists so that `doctor` can be
/// run in CI as a gate — `dvm doctor || exit 1` — without a machine that merely
/// still has the old tool's directories lying around failing the build.
enum DoctorSeverity {
  ok('ok  '),
  warn('warn'),
  fail('FAIL');

  const DoctorSeverity(this.label);

  /// A fixed-width marker, so the findings line up in a terminal.
  final String label;
}

/// One thing `doctor` looked at, and what it found.
class DoctorFinding {
  DoctorFinding({
    required this.severity,
    required this.area,
    required this.summary,
    this.details = const [],
    this.remedy,
  });

  final DoctorSeverity severity;

  /// Which check produced this — `PATH`, `shims`, `config`, `project`.
  final String area;

  /// One line saying what is true.
  final String summary;

  /// Supporting lines: the actual PATH order, the offending rc lines.
  final List<String> details;

  /// What to run or edit. Present on everything that is not [DoctorSeverity.ok].
  final String? remedy;
}

/// `dvm doctor` — Check PATH order, shim health, symlinks and config validity.
///
/// Every finding names the file it is about and what to do about it. The single
/// most valuable check is the shadowing one: on a machine that carried the
/// older cbracken/dvm, `dvm` is a shell *function* sourced from `.zshrc`, and a
/// shell function is resolved before PATH is ever searched — so the newly
/// installed binary is never reached and nothing on screen says why.
class DoctorCommand extends Command<int> {
  DoctorCommand({required this.context});

  final DvmContext context;

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check PATH order, shim health, symlinks and config validity.';

  @override
  Future<int> run() async {
    final shell = ShellFacts(
      fileSystem: context.fileSystem,
      environment: context.environment,
    );

    final findings = <DoctorFinding>[
      ..._checkPath(shell),
      ..._checkShims(),
      ..._checkShell(shell),
      ..._checkConfig(),
      ..._checkProject(),
    ];

    context.out.writeln('dvm doctor');
    for (final finding in findings) {
      context.out.writeln(
        '  ${finding.severity.label}  ${finding.area}: ${finding.summary}',
      );
      for (final detail in finding.details) {
        context.out.writeln('          $detail');
      }
      if (finding.remedy case final remedy?) {
        context.out.writeln('          -> $remedy');
      }
    }

    final failures = findings
        .where((finding) => finding.severity == DoctorSeverity.fail)
        .length;
    final warnings = findings
        .where((finding) => finding.severity == DoctorSeverity.warn)
        .length;

    context.out.writeln();
    if (failures == 0 && warnings == 0) {
      context.out.writeln('Everything checks out.');
      return 0;
    }
    context.out.writeln(
      '${_count(failures, 'problem')}, ${_count(warnings, 'warning')}.',
    );
    return failures == 0 ? 0 : 1;
  }

  String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

  /// Is the shims directory on PATH, and is it ahead of every other `dart`?
  ///
  /// Membership is not the question. A `dart` in an earlier entry is found
  /// first and the shim never runs, which looks exactly like dvm doing nothing.
  List<DoctorFinding> _checkPath(ShellFacts shell) {
    final shims = context.paths.shimsDir;
    final line = shell.pathLine(shims);
    final raw = context.environment['PATH'] ?? context.environment['Path'];

    if (raw == null || raw.isEmpty) {
      return [
        DoctorFinding(
          severity: DoctorSeverity.fail,
          area: 'PATH',
          summary: 'PATH is not set in this environment, so nothing can find '
              'the shims.',
          remedy: line,
        ),
      ];
    }

    final entries = raw
        .split(_isWindows ? ';' : ':')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();

    final shimsCanonical = _canonical(shims.path);
    final shimsIndex =
        entries.indexWhere((entry) => _canonical(entry) == shimsCanonical);

    // Every entry that would answer a bare `dart`, in the order PATH searches
    // them. This is what gets printed: "is it on PATH" is not actionable,
    // "these three come first" is.
    final providers = <int>[
      for (var index = 0; index < entries.length; index++)
        if (index != shimsIndex && _hasDart(entries[index])) index,
    ];

    List<String> order() => [
          'PATH order (entries that provide a dart):',
          if (shimsIndex >= 0)
            '  ${shimsIndex + 1}. ${entries[shimsIndex]}  <- dvm shims',
          for (final index in providers) '  ${index + 1}. ${entries[index]}',
        ];

    if (shimsIndex < 0) {
      return [
        DoctorFinding(
          severity: DoctorSeverity.fail,
          area: 'PATH',
          summary: '${shims.path} is not on PATH, so `dart` does not go '
              'through dvm.',
          details: order(),
          remedy: '${shell.pathLineAction}: $line',
        ),
      ];
    }

    final ahead = providers.where((index) => index < shimsIndex).toList();
    if (ahead.isNotEmpty) {
      return [
        DoctorFinding(
          severity: DoctorSeverity.fail,
          area: 'PATH',
          summary: '${shims.path} is on PATH but '
              '${ahead.length == 1 ? 'an entry ahead of it provides' : '${ahead.length} entries ahead of it provide'} '
              'a dart, so the shim is never reached.',
          details: order(),
          remedy: 'Put the shims first: $line',
        ),
      ];
    }

    return [
      DoctorFinding(
        severity: DoctorSeverity.ok,
        area: 'PATH',
        summary: '${shims.path} is on PATH ahead of every other dart.',
        details: providers.isEmpty ? const [] : order(),
      ),
    ];
  }

  /// Does the shim exist, can it run, and does it still name a real dvm?
  List<DoctorFinding> _checkShims() {
    final shim = context.paths.dartShim;
    final writer = ShimWriter(
      fileSystem: context.fileSystem,
      paths: context.paths,
    );

    if (!shim.existsSync()) {
      return [
        DoctorFinding(
          severity: DoctorSeverity.fail,
          area: 'shims',
          summary: '${shim.path} does not exist.',
          remedy: 'Run: dvm setup',
        ),
      ];
    }

    final String? target;
    try {
      target = writer.targetOf(shim);
    } on FileSystemException catch (error) {
      // Could not look. Reporting this as "not a dvm shim" would be inventing
      // a fact out of a failed read.
      return [
        DoctorFinding(
          severity: DoctorSeverity.fail,
          area: 'shims',
          summary: '${shim.path} exists but could not be read '
              '(${error.message}), so dvm cannot say what it runs.',
          remedy: 'Check its permissions, then run: dvm setup',
        ),
      ];
    }

    if (target == null) {
      return [
        DoctorFinding(
          severity: DoctorSeverity.fail,
          area: 'shims',
          summary: '${shim.path} is not recognisable as a dvm shim.',
          remedy: 'Overwrite it with: dvm setup',
        ),
      ];
    }

    final findings = <DoctorFinding>[];
    if (!context.fileSystem.file(target).existsSync()) {
      findings.add(
        DoctorFinding(
          severity: DoctorSeverity.fail,
          area: 'shims',
          summary: '${shim.path} runs $target, which no longer exists.',
          details: const [
            'Every `dart` on this machine fails until this is fixed.',
          ],
          remedy: 'Re-point it at the dvm you have now: dvm setup',
        ),
      );
    }

    // Windows executability comes from the extension, and there is no mode to
    // inspect; asking for one would report a false problem on every machine.
    if (!_isWindows && !_isExecutable(shim)) {
      findings.add(
        DoctorFinding(
          severity: DoctorSeverity.fail,
          area: 'shims',
          summary: '${shim.path} is not executable.',
          remedy: 'chmod 755 ${shim.path}  (or run: dvm setup)',
        ),
      );
    }

    if (findings.isEmpty) {
      findings.add(
        DoctorFinding(
          severity: DoctorSeverity.ok,
          area: 'shims',
          summary: '${shim.path} runs $target.',
        ),
      );
    }
    return findings;
  }

  /// Is something in the user's shell going to win over the dvm binary?
  List<DoctorFinding> _checkShell(ShellFacts shell) {
    final scan = shell.scanForShadows();
    final legacy = LegacyDvmInstall.detect(context.paths);
    final findings = <DoctorFinding>[];

    if (scan.shadows.isEmpty) {
      findings.add(
        DoctorFinding(
          severity: DoctorSeverity.ok,
          area: 'shell',
          summary: 'no shell function or alias named `dvm` in your startup '
              'files.',
        ),
      );
    } else {
      findings.add(
        DoctorFinding(
          severity: DoctorSeverity.fail,
          area: 'shell',
          summary: 'your shell defines its own `dvm`, which is resolved before '
              'PATH is searched — so this dvm never runs.',
          details: [
            for (final shadow in scan.shadows)
              '${shadow.describe()}   (${shadow.kind.description})',
          ],
          remedy: 'Remove or comment out the line(s) above, then start a new '
              'shell.',
        ),
      );
    }

    for (final entry in scan.unreadable.entries) {
      findings.add(
        DoctorFinding(
          severity: DoctorSeverity.warn,
          area: 'shell',
          summary: 'could not read ${entry.key} (${entry.value}), so dvm '
              'cannot say whether it defines a conflicting `dvm`.',
          remedy: 'Check the file by hand for a `dvm` function or alias.',
        ),
      );
    }

    if (legacy.isPresent) {
      findings.add(
        DoctorFinding(
          severity: DoctorSeverity.warn,
          area: 'shell',
          summary: 'an older dvm (cbracken/dvm) shares '
              '${context.paths.home.path}.',
          details: [
            if (legacy.script case final script?)
              '${script.path}  (sourcing this is what defines the function)',
            for (final directory in legacy.directories) directory.path,
          ],
          remedy: 'Import its SDKs with: dvm migrate',
        ),
      );
    }

    return findings;
  }

  /// Is `~/.dvm/config.json` readable, and does its global still exist?
  List<DoctorFinding> _checkConfig() {
    final file = context.paths.configFile;
    if (!file.existsSync()) {
      return [
        DoctorFinding(
          severity: DoctorSeverity.ok,
          area: 'config',
          summary: 'no ${file.path} yet, which is the normal state before a '
              'global default is set.',
        ),
      ];
    }

    final String? global;
    try {
      global = context.config.read().global;
    } on DvmException catch (error) {
      return [
        DoctorFinding(
          severity: DoctorSeverity.fail,
          area: 'config',
          summary: error.message,
          remedy: 'Fix ${file.path}, or delete it to start over.',
        ),
      ];
    }

    if (global == null) {
      return [
        DoctorFinding(
          severity: DoctorSeverity.ok,
          area: 'config',
          summary: '${file.path} is valid; no global default is set.',
        ),
      ];
    }

    // A global naming a version that is gone is what `dvm remove --force`
    // leaves behind, and it breaks every directory that has no .dvmrc.
    final VersionRef ref;
    try {
      ref = resolveVersionRef(context, global);
    } on DvmException catch (error) {
      return [
        DoctorFinding(
          severity: DoctorSeverity.fail,
          area: 'config',
          summary: 'the global default "$global" cannot be resolved: '
              '${error.message}',
          remedy: 'Set it again: dvm global <version>',
        ),
      ];
    }

    if (!_isInstalled(ref.version)) {
      return [
        DoctorFinding(
          severity: DoctorSeverity.fail,
          area: 'config',
          summary: 'the global default is Dart ${ref.version}'
              '${ref.isDirect ? '' : ' (${ref.trail})'}, which is not '
              'installed.',
          details: [
            'Nothing is at ${context.paths.versionDir(ref.version).path}',
            'Every directory without a .dvmrc fails until this is fixed.',
          ],
          remedy: 'dvm install ${ref.version}  (or: dvm global <version>)',
        ),
      ];
    }

    return [
      DoctorFinding(
        severity: DoctorSeverity.ok,
        area: 'config',
        summary: '${file.path} is valid; the global default Dart '
            '${ref.version} is installed.',
      ),
    ];
  }

  /// Is this project's pin installed, and is its IDE symlink still good?
  List<DoctorFinding> _checkProject() {
    final rcFile = context.dvmrc.findNearest(context.workingDirectory);
    if (rcFile == null) {
      return [
        DoctorFinding(
          severity: DoctorSeverity.ok,
          area: 'project',
          summary: 'no .dvmrc at or above ${context.workingDirectory.path}, so '
              'the global default applies here.',
        ),
        ..._checkProjectLink(context.workingDirectory, null),
      ];
    }

    final project = rcFile.parent;
    final String pin;
    try {
      pin = context.dvmrc.read(rcFile)!;
    } on DvmException catch (error) {
      return [
        DoctorFinding(
          severity: DoctorSeverity.fail,
          area: 'project',
          summary: error.message,
          remedy: 'Rewrite it with: dvm use <version>',
        ),
      ];
    }

    final VersionRef ref;
    try {
      ref = resolveVersionRef(context, pin);
    } on DvmException catch (error) {
      return [
        DoctorFinding(
          severity: DoctorSeverity.fail,
          area: 'project',
          summary: '${rcFile.path} pins "$pin", which cannot be resolved: '
              '${error.message}',
          remedy: 'Pin a version that exists: dvm use <version>',
        ),
      ];
    }

    final findings = <DoctorFinding>[];
    if (_isInstalled(ref.version)) {
      findings.add(
        DoctorFinding(
          severity: DoctorSeverity.ok,
          area: 'project',
          summary: '${rcFile.path} pins Dart ${ref.version}'
              '${ref.isDirect ? '' : ' (${ref.trail})'}, which is installed.',
        ),
      );
    } else {
      findings.add(
        DoctorFinding(
          severity: DoctorSeverity.fail,
          area: 'project',
          summary: '${rcFile.path} pins Dart ${ref.version}'
              '${ref.isDirect ? '' : ' (${ref.trail})'}, which is not '
              'installed.',
          remedy: 'dvm install ${ref.version}',
        ),
      );
    }

    findings.addAll(_checkProjectLink(project, ref.version));
    return findings;
  }

  /// The gitignored `.dvm/dart_sdk` symlink IDEs are pointed at.
  ///
  /// It is per-machine and never committed, so it long outlives the version it
  /// names: `dvm remove` the pinned SDK and the IDE keeps following a link into
  /// a directory that is not there any more, which shows up as an analyzer that
  /// stopped working for no visible reason.
  List<DoctorFinding> _checkProjectLink(Directory project, String? version) {
    final link = context.paths.projectSdkLink(project);
    final fileSystem = context.fileSystem;

    final type = fileSystem.typeSync(link.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return const [];
    if (type != FileSystemEntityType.link) {
      return [
        DoctorFinding(
          severity: DoctorSeverity.warn,
          area: 'project',
          summary: '${link.path} exists but is not a symlink, so dvm will not '
              'replace it.',
          remedy: 'Delete it, then run: dvm use <version>',
        ),
      ];
    }

    final target = link.targetSync();
    // followLinks defaults to true, so this is the question "does what it
    // points at exist?" rather than "does the link exist?".
    if (fileSystem.typeSync(link.path) == FileSystemEntityType.notFound) {
      return [
        DoctorFinding(
          severity: DoctorSeverity.fail,
          area: 'project',
          summary: '${link.path} is a stale symlink: it points at $target, '
              'which has been removed.',
          details: const [
            'An IDE following it will report a broken or missing SDK.',
          ],
          remedy: version == null
              ? 'Pin a version here: dvm use <version>'
              : 'Re-point it: dvm use $version',
        ),
      ];
    }

    if (version != null) {
      final expected = context.paths.versionDir(version).path;
      if (!fileSystem.path.equals(target, expected)) {
        return [
          DoctorFinding(
            severity: DoctorSeverity.warn,
            area: 'project',
            summary: '${link.path} points at $target, but this project pins '
                'Dart $version.',
            details: ['Expected it to point at $expected'],
            remedy: 'Re-point it: dvm use $version',
          ),
        ];
      }
    }

    return [
      DoctorFinding(
        severity: DoctorSeverity.ok,
        area: 'project',
        summary: '${link.path} points at $target.',
      ),
    ];
  }

  /// Whether [version] is present and usable, checked the way resolution
  /// checks it: the directory alone is not enough, an interrupted install
  /// leaves one behind with no `bin/dart` in it.
  bool _isInstalled(String version) => context.paths
      .dartExecutable(context.paths.versionDir(version))
      .existsSync();

  /// Whether [file] has any execute bit set.
  ///
  /// Any, not the owner's: a shim installed by a system package or copied
  /// under a different uid is still executable by the person running it.
  bool _isExecutable(File file) {
    try {
      return file.statSync().mode & _anyExecuteBit != 0;
    } on FileSystemException {
      // Could not stat it. The read check above already reported anything
      // that matters here, and a guess would be worse than silence.
      return true;
    }
  }

  /// `0111`.
  static const int _anyExecuteBit = 0x49;

  bool get _isWindows => context.fileSystem.path.style == p.Style.windows;

  /// A comparable spelling of [path], symlinks followed where possible.
  ///
  /// The same normalization the resolver applies when it skips the shims
  /// directory, so `doctor` and resolution agree about which PATH entry is the
  /// shims one — `$HOME/.dvm/shims`, `~/.dvm/./shims/` and the absolute path
  /// all turn up in real PATHs.
  String _canonical(String path) {
    final fileSystem = context.fileSystem;
    try {
      return fileSystem.path
          .canonicalize(fileSystem.file(path).resolveSymbolicLinksSync());
    } on FileSystemException {
      return fileSystem.path.canonicalize(path);
    }
  }

  /// Whether [entry] contains a `dart` that is not one of dvm's own shims.
  ///
  /// A *copy* of the shim earlier on PATH — what `ln`/`cp` into `~/.local/bin`
  /// leaves behind — still goes through dvm, so counting it as something that
  /// beats the shims would report a problem the user cannot act on. This is the
  /// same content test the resolver uses to avoid re-entering itself.
  bool _hasDart(String entry) {
    final fileSystem = context.fileSystem;
    final writer = ShimWriter(fileSystem: fileSystem, paths: context.paths);

    for (final name in context.paths.pathExecutableNames) {
      final candidate = fileSystem.file(fileSystem.path.join(entry, name));
      if (!candidate.existsSync()) continue;
      try {
        // A real dart is megabytes; the length check keeps this from reading
        // one. An unreadable or binary file is not one of our shims.
        if (candidate.lengthSync() <= 512 &&
            writer.targetOf(candidate) != null) {
          continue;
        }
      } on FileSystemException {
        // Fall through: it exists, so it answers `dart`.
      }
      return true;
    }
    return false;
  }
}

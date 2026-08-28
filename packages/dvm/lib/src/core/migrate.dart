import 'package:file/file.dart';

import 'paths.dart';

/// The on-disk layout of the older `cbracken/dvm`, which shares `~/.dvm`.
///
/// That tool is a git checkout: `~/.dvm` is its working tree, with the SDKs it
/// downloaded sitting untracked in `darts/`. dvm takes the directory over
/// rather than picking a new one, so every path here is a *sibling* of the
/// paths in [DvmPaths] and nothing may spell them by hand elsewhere.
///
/// `ShellFacts`' `LegacyDvmInstall` answers the cheaper question `setup` and
/// `doctor` ask — "is something else living here?". This class is the one that
/// has to be right about *what* is living here, because `migrate` moves and
/// deletes based on it.
class LegacyDvmPaths {
  LegacyDvmPaths(this.paths);

  final DvmPaths paths;

  FileSystem get _fileSystem => paths.fileSystem;

  /// The shared home. `migrate` never looks outside it.
  Directory get home => paths.home;

  /// Where the older tool keeps its extracted SDKs, one per directory.
  Directory get dartsDir => _directory(['darts']);

  /// The shell function the old README tells users to source. Its presence is
  /// the strongest single signal that the older tool is installed.
  File get script => _file(['scripts', 'dvm']);

  /// The snippet naming the SDK the older tool currently activates.
  File get defaultEnvironment => _file(['environments', 'default']);

  /// The `version` file inside an extracted SDK — the SDK's own account of
  /// what it is, which outranks the directory somebody put it in.
  File versionFile(Directory sdk) =>
      _fileSystem.file(_fileSystem.path.join(sdk.path, 'version'));

  /// Everything the older tool leaves in `~/.dvm` that this dvm has no use
  /// for, in the order they are worth showing a human.
  ///
  /// `darts/` is deliberately absent: it holds the SDKs, so it is only ever
  /// removed once it is empty, and that is [emptyDartsDir]'s job.
  static const List<List<String>> leftoverNames = [
    ['scripts'],
    ['environments'],
    ['.git'],
    ['VERSION'],
    ['LICENSE'],
    ['README.md'],
    ['.gitignore'],
  ];

  /// The leftovers that are actually on disk right now.
  List<FileSystemEntity> leftovers() {
    final found = <FileSystemEntity>[];
    for (final names in leftoverNames) {
      final path = _fileSystem.path.joinAll([home.path, ...names]);
      final directory = _fileSystem.directory(path);
      if (directory.existsSync()) {
        found.add(directory);
        continue;
      }
      final file = _fileSystem.file(path);
      if (file.existsSync()) found.add(file);
    }
    return found;
  }

  /// `darts/`, but only when it exists and holds nothing — the one state in
  /// which removing it cannot destroy an SDK.
  Directory? emptyDartsDir() {
    final directory = dartsDir;
    if (!directory.existsSync()) return null;
    return directory.listSync().isEmpty ? directory : null;
  }

  Directory _directory(List<String> names) =>
      _fileSystem.directory(_fileSystem.path.joinAll([home.path, ...names]));

  File _file(List<String> names) =>
      _fileSystem.file(_fileSystem.path.joinAll([home.path, ...names]));
}

/// One `darts/<name>` entry and what inspecting it revealed.
class LegacySdk {
  const LegacySdk({
    required this.directory,
    required this.directoryName,
    this.recordedVersion,
    this.problem,
  });

  /// `~/.dvm/darts/<directoryName>`.
  final Directory directory;

  /// The name somebody gave the directory. A hint, not an answer.
  final String directoryName;

  /// The contents of the entry's own `version` file, or null when it could
  /// not be read.
  final String? recordedVersion;

  /// Why [recordedVersion] is null. Non-null only when something was actually
  /// wrong — a missing, empty, or unreadable `version` file.
  final String? problem;

  /// What this SDK actually is, preferring its own account of itself.
  String get version => recordedVersion ?? directoryName;

  /// Whether the SDK disagrees with the directory it is sitting in. Worth
  /// saying out loud: it is the difference between the destination the user
  /// expects and the one they get.
  bool get nameDisagrees =>
      recordedVersion != null && recordedVersion != directoryName;
}

/// What `migrate` intends to do with one [LegacySdk].
enum MigrationAction {
  /// Move it into `versions/`.
  move,

  /// Leave it alone: `versions/<version>` is already there. Never overwrite —
  /// the installed copy may be the one in use.
  alreadyInstalled,

  /// Leave it alone: an earlier entry in the same run already claims this
  /// version, so moving this one would overwrite that.
  duplicate,
}

/// One entry of a [MigrationPlan].
class PlannedMigration {
  const PlannedMigration({
    required this.sdk,
    required this.destination,
    required this.action,
    this.note,
  });

  final LegacySdk sdk;

  /// `versions/<version>`, whether or not the move will happen.
  final Directory destination;

  final MigrationAction action;

  /// Extra context for a skip, phrased for a human.
  final String? note;

  bool get willMove => action == MigrationAction.move;
}

/// Everything `migrate` found, and what it would do — computed without
/// changing a single byte, so `--dry-run` and the real run share it.
class MigrationPlan {
  const MigrationPlan({
    required this.home,
    required this.markers,
    required this.hasDartsDir,
    required this.entries,
    required this.leftovers,
    required this.activeVersion,
    required this.activeVersionProblem,
  });

  /// The shared `~/.dvm`.
  final Directory home;

  /// The legacy files and directories that were found, relative to [home],
  /// as evidence for "this really is a cbracken install".
  final List<String> markers;

  final bool hasDartsDir;

  /// One per `darts/*` entry, in the order they were found.
  final List<PlannedMigration> entries;

  /// The cbracken files a later `--clean` would remove.
  final List<FileSystemEntity> leftovers;

  /// The version `environments/default` activates, or null if there is none
  /// to read or it could not be understood.
  final String? activeVersion;

  /// Why [activeVersion] is null, when something was actually wrong. Kept
  /// apart from "there is no active version" on purpose: a file we could not
  /// parse is not the same observation as a file that is not there.
  final String? activeVersionProblem;

  List<PlannedMigration> get moves => [
        for (final entry in entries)
          if (entry.willMove) entry
      ];

  List<PlannedMigration> get skips => [
        for (final entry in entries)
          if (!entry.willMove) entry
      ];

  /// Whether there is a cbracken install here at all.
  bool get isPresent => hasDartsDir || leftovers.isNotEmpty;

  /// Whether anything is left in `darts/` that has not made it across. Guards
  /// the cleanup: leftovers are only safe to delete once this is false.
  bool get hasUnmigratedSdks => moves.isNotEmpty;
}

/// The result of trying to move one SDK.
class MigrationOutcome {
  const MigrationOutcome({
    required this.entry,
    required this.moved,
    this.failure,
  });

  final PlannedMigration entry;

  /// True only when the SDK is verifiably at its destination.
  final bool moved;

  /// Why it is not, phrased for a human. Null when [moved].
  final String? failure;
}

/// The result of trying to delete one leftover.
class CleanupOutcome {
  const CleanupOutcome({
    required this.entity,
    required this.removed,
    this.failure,
  });

  final FileSystemEntity entity;
  final bool removed;
  final String? failure;
}

/// Reads the cbracken layout, plans a migration, and carries it out.
///
/// Split from the command so that the dangerous part — deciding what moves and
/// what gets deleted — is testable without going through argument parsing, and
/// so that `--dry-run` runs the same [plan] the real migration acts on rather
/// than a second description of it that could drift.
class Migrator {
  Migrator({required this.fileSystem, required DvmPaths paths})
      : paths = paths,
        legacy = LegacyDvmPaths(paths);

  final FileSystem fileSystem;
  final DvmPaths paths;
  final LegacyDvmPaths legacy;

  /// Inspects `~/.dvm` and works out what a migration would do. Reads only.
  MigrationPlan plan() {
    final leftovers = legacy.leftovers();
    final dartsDir = legacy.dartsDir;
    final hasDartsDir = dartsDir.existsSync();

    final markers = <String>[
      if (hasDartsDir) 'darts/',
      for (final entity in leftovers)
        fileSystem.path.relative(entity.path, from: legacy.home.path) +
            (entity is Directory ? '/' : ''),
    ];

    final entries = <PlannedMigration>[];
    if (hasDartsDir) {
      // Sorted so that the report, and which of two colliding entries is
      // treated as the duplicate, do not depend on directory iteration order.
      final children = dartsDir.listSync().whereType<Directory>().toList()
        ..sort((a, b) => a.basename.compareTo(b.basename));

      final claimed = <String, String>{};
      for (final child in children) {
        final sdk = _inspect(child);
        final destination = paths.versionDir(sdk.version);

        final claimant = claimed[sdk.version];
        if (claimant != null) {
          entries.add(
            PlannedMigration(
              sdk: sdk,
              destination: destination,
              action: MigrationAction.duplicate,
              note: 'darts/$claimant is also Dart ${sdk.version}',
            ),
          );
          continue;
        }

        if (destination.existsSync()) {
          entries.add(
            PlannedMigration(
              sdk: sdk,
              destination: destination,
              action: MigrationAction.alreadyInstalled,
            ),
          );
          continue;
        }

        claimed[sdk.version] = sdk.directoryName;
        entries.add(
          PlannedMigration(
            sdk: sdk,
            destination: destination,
            action: MigrationAction.move,
          ),
        );
      }
    }

    final active = _readActiveVersion();
    return MigrationPlan(
      home: legacy.home,
      markers: markers,
      hasDartsDir: hasDartsDir,
      entries: entries,
      leftovers: leftovers,
      activeVersion: active.version,
      activeVersionProblem: active.problem,
    );
  }

  /// Moves every [MigrationAction.move] entry of [plan] into `versions/`.
  ///
  /// One outcome per move, in order, so the caller can report each SDK
  /// individually: a failure on one must not take the others down with it.
  List<MigrationOutcome> apply(MigrationPlan plan) =>
      [for (final entry in plan.moves) _move(entry)];

  /// Deletes [entities]. The caller is responsible for having confirmed this
  /// and for having checked [MigrationPlan.hasUnmigratedSdks] first.
  List<CleanupOutcome> clean(List<FileSystemEntity> entities) {
    final outcomes = <CleanupOutcome>[];
    for (final entity in entities) {
      try {
        if (entity is Directory) {
          entity.deleteSync(recursive: true);
        } else {
          entity.deleteSync();
        }
        outcomes.add(CleanupOutcome(entity: entity, removed: true));
      } on FileSystemException catch (error) {
        outcomes.add(
          CleanupOutcome(
            entity: entity,
            removed: false,
            failure: error.message,
          ),
        );
      }
    }
    return outcomes;
  }

  /// Reads a `darts/<name>` entry's own `version` file.
  ///
  /// A directory whose `version` file is missing or unreadable is still
  /// migrated, under its directory name — those SDKs are the whole point, and
  /// refusing to move one because a metadata file is absent would leave the
  /// user worse off than doing nothing. The problem is reported instead.
  LegacySdk _inspect(Directory directory) {
    final name = directory.basename;
    final file = legacy.versionFile(directory);

    if (!file.existsSync()) {
      return LegacySdk(
        directory: directory,
        directoryName: name,
        problem: 'no version file, so dvm is trusting the directory name',
      );
    }

    final String raw;
    try {
      raw = file.readAsStringSync();
    } on FileSystemException catch (error) {
      return LegacySdk(
        directory: directory,
        directoryName: name,
        problem: 'could not read ${file.path} (${error.message}), so dvm is '
            'trusting the directory name',
      );
    }

    // Dart's own `version` file is one bare version and a newline. Anything
    // with whitespace inside it is not a version, and using it would produce
    // a `versions/` entry nothing could ever resolve to.
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) {
      return LegacySdk(
        directory: directory,
        directoryName: name,
        problem: '${file.path} does not contain a bare version, so dvm is '
            'trusting the directory name',
      );
    }

    return LegacySdk(
      directory: directory,
      directoryName: name,
      recordedVersion: trimmed,
    );
  }

  /// Moves one SDK, and only reports success once the destination is really
  /// there.
  ///
  /// `rename` only — never copy-then-delete. Source and destination are both
  /// inside `~/.dvm`, so they are always on one filesystem and the rename
  /// cannot fail for being cross-device; and a copy fallback on POSIX risks
  /// dropping the executable bit off everything under `bin/`, which would
  /// hand the user an SDK that looks installed and cannot run. A rename that
  /// fails leaves the SDK exactly where it was, which is the safe outcome.
  MigrationOutcome _move(PlannedMigration entry) {
    final source = entry.sdk.directory;
    final destination = entry.destination;

    try {
      destination.parent.createSync(recursive: true);
      source.renameSync(destination.path);
    } on FileSystemException catch (error) {
      return MigrationOutcome(
        entry: entry,
        moved: false,
        failure: 'could not move ${source.path} to ${destination.path}: '
            '${error.message}. It has been left where it is.',
      );
    }

    // Believing `rename` returned is not the same as knowing the SDK arrived.
    if (!destination.existsSync() || destination.listSync().isEmpty) {
      return MigrationOutcome(
        entry: entry,
        moved: false,
        failure: '${destination.path} is missing or empty after the move. '
            'Check ${source.path} before doing anything else.',
      );
    }

    return MigrationOutcome(entry: entry, moved: true);
  }

  /// Works out which version `environments/default` activates.
  ///
  /// That file is **not** a version string, despite its name: cbracken/dvm
  /// writes a shell snippet into it, and on a real install it reads
  ///
  /// ```sh
  /// export DVM_ROOT; DVM_ROOT="$DVM_ROOT"
  /// export DART_SDK; DART_SDK="/Users/me/.dvm/darts/3.13.2"
  /// PATH="$DVM_ROOT/darts/3.13.2/bin:$PATH"
  /// ```
  ///
  /// So the version is pulled out of the `darts/<version>` path it mentions.
  /// A bare version on one line is accepted too, for any layout that wrote
  /// one — but a multi-line file with no `darts/` path in it is reported as
  /// unreadable rather than guessed at. Carrying three lines of shell over as
  /// someone's `global` default would be worse than not carrying anything.
  ({String? version, String? problem}) _readActiveVersion() {
    final file = legacy.defaultEnvironment;
    if (!file.existsSync()) return (version: null, problem: null);

    final String raw;
    try {
      raw = file.readAsStringSync();
    } on FileSystemException catch (error) {
      return (
        version: null,
        problem: 'could not read ${file.path} (${error.message})',
      );
    }

    final match = _dartsPathPattern.firstMatch(raw);
    if (match != null) return (version: match.group(1), problem: null);

    final trimmed = raw.trim();
    if (trimmed.isNotEmpty && !trimmed.contains(RegExp(r'\s'))) {
      return (version: trimmed, problem: null);
    }
    if (trimmed.isEmpty) return (version: null, problem: null);

    return (
      version: null,
      problem: '${file.path} does not name a version dvm recognises',
    );
  }

  /// `darts/3.13.2` in any of the forms the snippet spells it, on either path
  /// separator, stopping at a quote or a `:` so `.../bin:$PATH` does not bleed
  /// into the captured version.
  static final RegExp _dartsPathPattern =
      RegExp(r"""darts[/\\]([^/\\\s"':]+)""");
}

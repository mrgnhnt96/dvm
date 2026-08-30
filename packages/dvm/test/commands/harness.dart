import 'package:dvm/dvm.dart';
// The entrypoint is `run`, and so is this harness's method for calling it.
import 'package:dvm/dvm.dart' as dvm;
import 'package:file/file.dart';
import 'package:file/memory.dart';

/// Drives the real `dvm` entrypoint against a memory filesystem.
///
/// `DVM_HOME` is set, so nothing here can reach the real `~/.dvm` even if a
/// command asks for the home directory by hand. The environment is mutable
/// because two of the five resolution rules are environment facts.
class CommandHarness {
  CommandHarness() {
    fileSystem = MemoryFileSystem.test();
    fileSystem.directory(projectPath).createSync(recursive: true);
    fileSystem.currentDirectory = projectPath;
    paths = DvmPaths(fileSystem: fileSystem, environment: environment);
    config = ConfigStore(fileSystem: fileSystem, paths: paths);
    installer = FakeInstaller(fileSystem: fileSystem, paths: paths);
  }

  static const String projectPath = '/project';
  static const String dvmHome = '/dvm';

  late final MemoryFileSystem fileSystem;
  late final DvmPaths paths;
  late final ConfigStore config;
  late final FakeInstaller installer;

  final Map<String, String> environment = {
    'DVM_HOME': dvmHome,
    'HOME': '/home/dev',
    // Empty rather than absent: rule 4 must not find whatever `dart` happens
    // to be on the machine running the tests.
    'PATH': '',
  };

  final StringBuffer out = StringBuffer();
  final StringBuffer err = StringBuffer();

  String get output => out.toString();
  String get errors => err.toString();

  Future<int> run(List<String> args) => dvm.run(
        args,
        fileSystem: fileSystem,
        environment: environment,
        platformVersion: '3.13.2 (stable) on "macos_arm64"',
        out: out,
        err: err,
        installer: installer,
      );

  /// Puts a usable SDK in the cache, the way a real install leaves it.
  Directory installVersion(String version) {
    final directory = paths.versionDir(version);
    paths.dartExecutable(directory)
      ..createSync(recursive: true)
      ..writeAsStringSync('#!/bin/sh\n');
    return directory;
  }

  /// A directory under `versions/` with no `bin/dart` in it — what an
  /// interrupted removal or a hand-edited cache leaves behind.
  Directory breakVersion(String version) =>
      paths.versionDir(version)..createSync(recursive: true);

  /// A real, non-shim `dart` on PATH, for rule 4.
  File putDartOnPath({String directory = '/usr/bin'}) {
    final executable = fileSystem.file('$directory/dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('not a shim, just bytes');
    environment['PATH'] = directory;
    return executable;
  }

  void writeConfig(DvmConfig value) => config.write(value);

  DvmConfig readConfig() => config.read();

  String readDvmrc([String path = '$projectPath/.dvmrc']) =>
      fileSystem.file(path).readAsStringSync();

  void clearOutput() {
    out.clear();
    err.clear();
  }
}

/// An [Installer] that records what it was asked for and creates the same
/// files a real install would.
///
/// The point of the recording is that `use` promising to auto-install is only
/// worth anything if it actually asks; the point of creating `bin/dart` is
/// that `isInstalled` here means the same thing it means in production.
class FakeInstaller implements Installer {
  FakeInstaller({required this.fileSystem, required this.paths});

  final FileSystem fileSystem;
  final DvmPaths paths;

  /// One entry per [install] call, in order.
  final List<InstallRequest> requests = [];

  /// When set, [install] throws this instead of installing.
  Object? failure;

  /// When true, [install] returns without leaving an SDK behind — the "the
  /// installer said yes and produced nothing" case.
  bool produceNothing = false;

  @override
  bool isInstalled(String version) =>
      paths.dartExecutable(paths.versionDir(version)).existsSync();

  @override
  Future<Directory> install(
    String version, {
    Channel? channel,
    bool force = false,
  }) async {
    requests.add(
      InstallRequest(version: version, channel: channel, force: force),
    );
    final error = failure;
    if (error != null) throw error;

    final directory = paths.versionDir(version);
    if (!produceNothing) {
      paths.dartExecutable(directory)
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\n');
    }
    return directory;
  }
}

/// One call to [FakeInstaller.install].
class InstallRequest {
  const InstallRequest({
    required this.version,
    required this.channel,
    required this.force,
  });

  final String version;
  final Channel? channel;
  final bool force;
}

import 'package:file/file.dart';

import 'config.dart';
import 'installer.dart';
import 'paths.dart';
import 'platform.dart';
import 'process.dart';
import 'releases.dart';
import 'resolver.dart';

/// Everything a command is allowed to touch, handed to it at construction.
///
/// ARCHITECTURE.md asks for constructor injection and no service locators. This
/// is that: an immutable value passed as a constructor parameter, holding no
/// global state and looking nothing up by name at call time. It exists as one
/// object rather than fifteen separate parameters so that a command gaining a
/// collaborator does not force an edit to `lib/dvm.dart`, where every command
/// is registered.
///
/// Nothing here imports `dart:io`. `lib/dvm.dart` is the composition root and
/// supplies the real filesystem, environment, and output sinks.
class DvmContext {
  DvmContext({
    required this.fileSystem,
    required this.environment,
    required this.paths,
    required this.config,
    required this.dvmrc,
    required this.resolver,
    required this.releases,
    required this.installer,
    required this.processes,
    required this.hostPlatform,
    required this.out,
    required this.err,
  });

  /// Builds a context from the pieces that vary, wiring up the rest.
  ///
  /// [platformVersion] is `Platform.version`; it is the only place dart:io
  /// exposes the host architecture.
  factory DvmContext.wire({
    required FileSystem fileSystem,
    required Map<String, String> environment,
    required String platformVersion,
    required StringSink out,
    required StringSink err,
    ReleaseClient? releases,
    Installer? installer,
    ProcessRunner? processes,
  }) {
    final paths = DvmPaths(fileSystem: fileSystem, environment: environment);
    final config = ConfigStore(fileSystem: fileSystem, paths: paths);
    final dvmrc = DvmrcStore(fileSystem: fileSystem);
    return DvmContext(
      fileSystem: fileSystem,
      environment: environment,
      paths: paths,
      config: config,
      dvmrc: dvmrc,
      resolver: VersionResolver(
        fileSystem: fileSystem,
        paths: paths,
        config: config,
        dvmrc: dvmrc,
        environment: environment,
      ),
      releases: releases ?? createReleaseClient(),
      installer: installer ?? createInstaller(),
      processes: processes ?? createProcessRunner(),
      // Lazy: an unsupported host must not stop `dvm --help` from printing.
      hostPlatform: () => HostPlatform.detect(platformVersion),
      out: out,
      err: err,
    );
  }

  final FileSystem fileSystem;
  final Map<String, String> environment;
  final DvmPaths paths;
  final ConfigStore config;
  final DvmrcStore dvmrc;
  final VersionResolver resolver;
  final ReleaseClient releases;
  final Installer installer;
  final ProcessRunner processes;

  /// The host OS/arch, computed on demand so that detection failures surface
  /// in the command that needs an archive rather than at startup.
  final HostPlatform Function() hostPlatform;

  /// Normal output. Injected so tests can read what a command printed.
  final StringSink out;

  /// Errors and diagnostics.
  final StringSink err;

  /// The directory commands act relative to — `.dvmrc` lookup starts here.
  Directory get workingDirectory => fileSystem.currentDirectory;
}

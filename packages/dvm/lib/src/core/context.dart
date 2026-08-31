import 'package:file/file.dart';

import 'config.dart';
import 'installer.dart';
import 'paths.dart';
import 'platform.dart';
import 'process.dart';
import 'releases.dart';
import 'resolver.dart';
import 'updater.dart';
import 'verbose.dart';

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
    required this.updater,
    required this.executablePath,
    required this.hostPlatform,
    required this.out,
    required this.err,
    required this.outIsTerminal,
    required this.verbose,
  });

  /// Builds a context from the pieces that vary, wiring up the rest.
  ///
  /// [platformVersion] is `Platform.version`; it is the only place dart:io
  /// exposes the host architecture. [executablePath] is
  /// `Platform.resolvedExecutable` — the binary `dvm update` replaces.
  factory DvmContext.wire({
    required FileSystem fileSystem,
    required Map<String, String> environment,
    required String platformVersion,
    required StringSink out,
    required StringSink err,
    bool outIsTerminal = false,
    String executablePath = '',
    VerboseLog? verbose,
    ReleaseClient? releases,
    Installer? installer,
    ProcessRunner? processes,
    Updater? updater,
  }) {
    // Built here when the caller did not supply one so that a context wired
    // by a test is verbose-capable without every test having to say so. It
    // starts off unless the environment asks otherwise; `dvm --verbose` flips
    // it in [DvmCommandRunner], after this point.
    final log = verbose ??
        VerboseLog(sink: err, enabled: VerboseLog.enabledIn(environment));

    final paths = DvmPaths(fileSystem: fileSystem, environment: environment);
    final config =
        ConfigStore(fileSystem: fileSystem, paths: paths, verbose: log);
    final dvmrc = DvmrcStore(fileSystem: fileSystem, verbose: log);
    // Lazy: an unsupported host must not stop `dvm --help` from printing.
    HostPlatform hostPlatform() => HostPlatform.detect(platformVersion);
    final releaseClient = releases ?? createReleaseClient(verbose: log);
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
        verbose: log,
      ),
      releases: releaseClient,
      installer: installer ??
          createInstaller(
            fileSystem: fileSystem,
            paths: paths,
            releases: releaseClient,
            hostPlatform: hostPlatform,
            // Download progress is normal output, not a diagnostic.
            progress: out,
            progressIsTerminal: outIsTerminal,
            verbose: log,
          ),
      processes: processes ?? createProcessRunner(verbose: log),
      updater: updater ??
          Updater(
            fileSystem: fileSystem,
            hostPlatform: hostPlatform,
            environment: environment,
          ),
      executablePath: executablePath,
      hostPlatform: hostPlatform,
      out: out,
      err: err,
      outIsTerminal: outIsTerminal,
      verbose: log,
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

  /// dvm's own releases: what is newest, and how to become it.
  final Updater updater;

  /// The path to the running `dvm` binary, which `dvm update` replaces.
  ///
  /// Empty when dvm is not running as a compiled binary — nothing reads it in
  /// that case, because [Updater] refuses to update a source checkout.
  final String executablePath;

  /// The host OS/arch, computed on demand so that detection failures surface
  /// in the command that needs an archive rather than at startup.
  final HostPlatform Function() hostPlatform;

  /// Normal output. Injected so tests can read what a command printed.
  final StringSink out;

  /// Errors and diagnostics.
  final StringSink err;

  /// The verbose channel: off unless `--verbose` or `DVM_VERBOSE` asked for
  /// it, and always writing to stderr so that no command's stdout changes.
  final VerboseLog verbose;

  /// Whether [out] is a terminal a human is watching, rather than a file, a
  /// pipe or a CI log.
  ///
  /// Only progress that repaints itself may depend on this. A carriage return
  /// sent anywhere but a terminal does not overwrite the line, it extends it,
  /// so `dvm install` captured to a file would otherwise be one 20KB line
  /// holding every percentage it ever printed. Defaults to false: a sink whose
  /// nature is unknown gets the output that is readable either way.
  final bool outIsTerminal;

  /// The directory commands act relative to — `.dvmrc` lookup starts here.
  Directory get workingDirectory => fileSystem.currentDirectory;
}

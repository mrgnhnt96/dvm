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

  /// A path as it should be PRINTED: relative to [workingDirectory] when it
  /// lies under it, and byte-for-byte unchanged otherwise.
  ///
  /// The signal in `Pinned Dart 3.13.2 for …/zonai` and
  /// `…/zonai/.dvmrc -> commit this` is WHICH file, and the repeated prefix in
  /// front of it is the directory the reader is already standing in. So
  /// `.dvmrc`, `.dvm/dart_sdk`, `packages/api/.dvmrc` — with no `./` on the
  /// front, which is noise for the same reason the prefix was.
  ///
  /// Deliberately only that one case. A path in a PARENT directory stays
  /// absolute rather than becoming `../..`, and a path under `$HOME` stays
  /// absolute rather than becoming `~/…`: both were considered and declined,
  /// because counting `..` segments is work the absolute path does not ask for.
  ///
  /// WHAT MUST NEVER COME THROUGH HERE — three kinds of path, and the rule is
  /// about what the path NAMES, not where it happens to sit:
  ///
  ///  * a PATH entry (`~/.dvm/shims`, `~/.dvm/bin`),
  ///  * a shell startup file, or a backup of one (`~/.zshrc`, `~/.profile`),
  ///  * anything in the dvm home — the SDK store, `config.json`, the shim, the
  ///    dvm binary itself.
  ///
  /// This USED to be phrased as "the SDK store needs no special case, it is
  /// never inside a project". That reasoning was wrong, and it shipped: it
  /// assumed nobody's working directory is `$HOME`, when `$HOME` is exactly
  /// where people stand to run `dvm setup` and `dvm doctor`. Standing there,
  /// `~/.dvm/shims` IS under the working directory, so doctor printed
  /// `FAIL PATH: .dvm/shims is not on PATH` three lines above the absolute
  /// `export PATH="/Users/…/.dvm/shims:\$PATH"` that fixes it — one directory,
  /// two spellings, and the relative one is not a thing the reader can paste
  /// anywhere. `setup` printed `source .profile` the same way.
  ///
  /// A relative PATH entry is worse than ugly: a shell resolves it against
  /// whatever directory each process happens to be in.
  ///
  /// So `commands/setup_command.dart` calls this NOWHERE — every path it names
  /// is one of the three above — and `commands/doctor_command.dart` calls it
  /// only for `.dvmrc` and `.dvm/dart_sdk`, which are project files and are the
  /// case this method exists for. `test/commands/home_cwd_output_test.dart`
  /// pins both commands' output with the working directory set to `\$HOME`,
  /// which is the case nobody thought to try.
  ///
  /// The working directory ITSELF is not under itself, so it keeps its absolute
  /// path. `Pinned Dart 3.13.2 for .` names the pin worse than the directory's
  /// own name does.
  ///
  /// The one degenerate case is the filesystem ROOT. Everything is under `/`,
  /// so the literal rule would turn every path dvm prints into a relative one
  /// the moment somebody runs a command from there — `/dvm/versions/3.13.2`
  /// becomes `dvm/versions/3.13.2`, which reads like it could be anywhere. The
  /// prefix this rule exists to remove is noise the reader already knows; at
  /// the root that prefix is one separator, and it is the character carrying
  /// the only thing the path was telling you for certain. So a root working
  /// directory formats nothing, and output from `/` is byte-for-byte what it
  /// was before this method existed.
  ///
  /// Purely lexical, and no filesystem is touched: this runs on output, and
  /// two spellings of one file is a display question, not a resolution one.
  ///
  /// This is the ONLY place output-formatting a path is allowed to happen.
  /// `dvm which`'s machine-readable lines are the carve-out and they do not
  /// call it; see `which_command.dart`. Anything dvm WRITES — `.dvmrc`
  /// contents, the `.dvm/dart_sdk` target, the PATH line — is not output and
  /// must never come through here.
  String display(String path) {
    final context = fileSystem.path;
    final base = context.normalize(workingDirectory.absolute.path);
    if (context.equals(context.rootPrefix(base), base)) return path;

    final target = context.normalize(
      context.isAbsolute(path) ? path : context.join(base, path),
    );
    if (!context.isWithin(base, target)) return path;
    return context.relative(target, from: base);
  }
}

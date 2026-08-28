import 'exceptions.dart';
import 'runner.dart';

/// Runs the resolved SDK's binaries.
///
/// A seam rather than a direct `Process.start` so that commands stay testable.
/// Implementations must start the child with `ProcessStartMode.inheritStdio`,
/// forward its exit code, and forward SIGINT/SIGTERM to it — Dart has no
/// `exec()`, and getting this wrong is what makes `dvm dart run` feel broken.
abstract class ProcessRunner {
  /// Runs [executable] with [arguments] and completes with its exit code.
  Future<int> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? workingDirectory,
  });
}

/// The seam `lib/dvm.dart` calls to get a [ProcessRunner].
ProcessRunner createProcessRunner() => const OsProcessRunner();

/// Stands in until a real [ProcessRunner] exists.
class UnimplementedProcessRunner implements ProcessRunner {
  const UnimplementedProcessRunner();

  @override
  Future<int> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? workingDirectory,
  }) =>
      throw const NotImplementedException(
        'Running the resolved SDK is not implemented yet.',
      );
}

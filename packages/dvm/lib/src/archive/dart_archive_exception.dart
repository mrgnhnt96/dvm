import '../core/exceptions.dart';

/// Something went wrong talking to, or unpacking, the Dart release archive.
///
/// A [DvmException] so that `lib/dvm.dart` prints the message on its own and
/// exits 1, rather than dumping a stack trace at a user whose wifi dropped.
class DartArchiveException extends DvmException {
  const DartArchiveException(super.message);
}

import 'package:dvm/dvm.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

/// `DvmContext.display` is the ONE place a path is formatted for output, so
/// the whole rule is pinned here rather than inferred from what each command
/// happens to print. Every command test downstream of this file is asserting
/// on the same function.
void main() {
  /// A context whose working directory is [workingDirectory].
  DvmContext contextAt(
    String workingDirectory, {
    FileSystemStyle style = FileSystemStyle.posix,
  }) {
    final fileSystem = MemoryFileSystem.test(style: style);
    fileSystem.directory(workingDirectory).createSync(recursive: true);
    fileSystem.currentDirectory = workingDirectory;
    return DvmContext.wire(
      fileSystem: fileSystem,
      environment: const {'DVM_HOME': '/dvm', 'HOME': '/home/dev', 'PATH': ''},
      platformVersion: '3.13.2 (stable) on "macos_arm64"',
      out: StringBuffer(),
      err: StringBuffer(),
    );
  }

  group('under the working directory', () {
    test('prints relative, with no ./ in front of it', () {
      final context = contextAt('/home/dev/code/zonai');

      expect(context.display('/home/dev/code/zonai/.dvmrc'), '.dvmrc');
      expect(
        context.display('/home/dev/code/zonai/.dvm/dart_sdk'),
        '.dvm/dart_sdk',
      );
    });

    test('keeps however many segments are genuinely below', () {
      final context = contextAt('/home/dev/code/zonai');

      expect(
        context.display('/home/dev/code/zonai/packages/api/.dvmrc'),
        'packages/api/.dvmrc',
      );
    });

    test('an unnormalized path still comes out normalized and relative', () {
      final context = contextAt('/home/dev/code/zonai');

      expect(
        context.display('/home/dev/code/zonai/packages/../.dvmrc'),
        '.dvmrc',
      );
    });
  });

  group('everything else stays exactly as it was', () {
    test('the working directory itself keeps its absolute path', () {
      final context = contextAt('/home/dev/code/zonai');

      // A bare `.` in "Pinned Dart 3.13.2 for ." reads worse than the
      // directory's own name, and this is the line that would print it.
      expect(
        context.display('/home/dev/code/zonai'),
        '/home/dev/code/zonai',
      );
    });

    test('a parent directory does NOT become ..', () {
      final context = contextAt('/home/dev/code/zonai/packages/api');

      expect(context.display('/home/dev/code/zonai/.dvmrc'),
          '/home/dev/code/zonai/.dvmrc');
      expect(context.display('/home/dev/code/zonai/.dvmrc'),
          isNot(contains('..')));
    });

    test('a sibling directory stays absolute', () {
      final context = contextAt('/home/dev/code/zonai');

      expect(context.display('/home/dev/code/other/.dvmrc'),
          '/home/dev/code/other/.dvmrc');
    });

    test('a path under \$HOME does NOT become ~', () {
      final context = contextAt('/home/dev/code/zonai');

      expect(context.display('/home/dev/.dvm/versions/3.13.2'),
          '/home/dev/.dvm/versions/3.13.2');
      expect(context.display('/home/dev/.zshrc'), isNot(contains('~')));
    });

    test('the SDK store needs no special case — it is never under a project',
        () {
      final context = contextAt('/home/dev/code/zonai');

      expect(context.display('/dvm/versions/3.13.2'), '/dvm/versions/3.13.2');
    });

    test('a directory whose name merely starts the same is not inside', () {
      final context = contextAt('/home/dev/code/zonai');

      // Lexically `/home/dev/code/zonai-old` shares a prefix with the working
      // directory without being under it. A naive `startsWith` would print
      // `-old/.dvmrc` here.
      expect(context.display('/home/dev/code/zonai-old/.dvmrc'),
          '/home/dev/code/zonai-old/.dvmrc');
    });
  });

  group('the filesystem root', () {
    test('formats nothing, because there is no prefix worth removing', () {
      final context = contextAt('/');

      // Everything is under `/`. Relativizing here would strip the one
      // character telling the reader the path is absolute, turning
      // `/dvm/versions/3.13.2` into `dvm/versions/3.13.2`.
      expect(context.display('/dvm/versions/3.13.2'), '/dvm/versions/3.13.2');
      expect(context.display('/.dvmrc'), '/.dvmrc');
    });

    test('a drive root on Windows is a root too', () {
      final context = contextAt(r'C:\', style: FileSystemStyle.windows);

      expect(
          context.display(r'C:\dvm\versions\3.9.0'), r'C:\dvm\versions\3.9.0');
    });
  });

  test('windows paths relativize with windows separators', () {
    final context = contextAt(r'C:\code\zonai', style: FileSystemStyle.windows);

    expect(context.display(r'C:\code\zonai\.dvmrc'), '.dvmrc');
    expect(context.display(r'C:\code\zonai\.dvm\dart_sdk'), r'.dvm\dart_sdk');
    expect(context.display(r'C:\code\other\.dvmrc'), r'C:\code\other\.dvmrc');
  });
}

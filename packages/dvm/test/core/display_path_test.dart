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
    String home = '/dvm',
  }) {
    final fileSystem = MemoryFileSystem.test(style: style);
    fileSystem.directory(workingDirectory).createSync(recursive: true);
    fileSystem.currentDirectory = workingDirectory;
    return DvmContext.wire(
      fileSystem: fileSystem,
      environment: {'DVM_HOME': home, 'HOME': '/home/dev', 'PATH': ''},
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

    test('the SDK store stays absolute when it is nowhere near the project',
        () {
      final context = contextAt('/home/dev/code/zonai');

      // This used to be named "the SDK store needs no special case — it is
      // never under a project", which was the assumption that shipped the bug.
      // It IS under the working directory whenever the user stands in $HOME.
      // The case is still worth keeping; only its reasoning was wrong.
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

  /// The rule made structural rather than remembered.
  ///
  /// Before this, a dvm-home path printed relative whenever the user happened
  /// to be standing above it, and the only thing stopping that was each call
  /// site choosing not to call [DvmContext.display]. `setup` and `doctor` made
  /// that choice; `install`, `list`, `remove`, `global`, `alias`, `which` and
  /// `use` did not, and all seven printed the store or `config.json` relative
  /// from `\$HOME`. A caller cannot reintroduce that now without bypassing this
  /// method entirely.
  group('the dvm home is never relativized', () {
    /// The `\$HOME`-as-working-directory arrangement, which is where every one
    /// of these paths falls under the working directory.
    DvmContext standingInHome() =>
        contextAt('/home/dev', home: '/home/dev/.dvm');

    test('the SDK store', () {
      final context = standingInHome();

      expect(context.display('/home/dev/.dvm/versions/3.13.2'),
          '/home/dev/.dvm/versions/3.13.2');
    });

    test('config.json', () {
      expect(standingInHome().display('/home/dev/.dvm/config.json'),
          '/home/dev/.dvm/config.json');
    });

    test('the PATH entries — the ones a shell would resolve wrongly', () {
      final context = standingInHome();

      // A relative PATH entry is not merely ugly: a shell resolves it against
      // whatever directory each process happens to be in.
      expect(context.display('/home/dev/.dvm/shims'), '/home/dev/.dvm/shims');
      expect(context.display('/home/dev/.dvm/bin'), '/home/dev/.dvm/bin');
    });

    test('the shim, the cache and the dvm binary itself', () {
      final context = standingInHome();

      expect(context.display('/home/dev/.dvm/shims/dart'),
          '/home/dev/.dvm/shims/dart');
      expect(context.display('/home/dev/.dvm/cache'), '/home/dev/.dvm/cache');
      expect(
          context.display('/home/dev/.dvm/bin/dvm'), '/home/dev/.dvm/bin/dvm');
    });

    test('the home directory itself', () {
      expect(standingInHome().display('/home/dev/.dvm'), '/home/dev/.dvm');
    });

    test('an unnormalized store path comes out absolute AND normalized', () {
      expect(
          standingInHome().display('/home/dev/.dvm/versions/../versions/3.9.0'),
          '/home/dev/.dvm/versions/3.9.0');
    });

    test('a project file beside the dvm home still prints relative', () {
      final context = standingInHome();

      // The half of the rule that must not regress. `.dvmrc` in \$HOME is a
      // file in the directory the reader is standing in, and it is not inside
      // `~/.dvm`, so nothing about the home rule touches it.
      expect(context.display('/home/dev/.dvmrc'), '.dvmrc');
    });

    test(
        'the one collision: a project rooted at \$HOME owns no .dvm of its own',
        () {
      final context = standingInHome();

      // `.dvm/dart_sdk` is normally a PROJECT file and prints relative — see
      // the group above. It stops being one only in this degenerate
      // arrangement, where the project root IS \$HOME and the dvm home is
      // `\$HOME/.dvm`, so the per-project directory and the dvm home are
      // literally the same directory. dvm's own home wins, and the path prints
      // absolute.
      //
      // Deliberately not carved out. The whole value of this rule is that it
      // is structural rather than remembered, and "except these two filenames"
      // is the kind of exception the old convention died of. The absolute
      // rendering is still correct here, only longer — whereas relativizing
      // the SDK store is the bug this fixes.
      expect(context.display('/home/dev/.dvm/dart_sdk'),
          '/home/dev/.dvm/dart_sdk');

      // Anywhere else — the normal case, a project below \$HOME — it is a
      // project file and reads relative, exactly as before.
      final normal = contextAt('/home/dev/code/zonai', home: '/home/dev/.dvm');
      expect(normal.display('/home/dev/code/zonai/.dvm/dart_sdk'),
          '.dvm/dart_sdk');
    });

    test('a directory whose name merely starts the same is not the home', () {
      final context = standingInHome();

      // `.dvm-backup` shares a prefix with the dvm home without being inside
      // it. A naive `startsWith` would wrongly keep this absolute.
      expect(
          context.display('/home/dev/.dvm-backup/notes'), '.dvm-backup/notes');
    });

    test('windows: the home is recognised with windows separators', () {
      final context = contextAt(r'C:\Users\dev',
          style: FileSystemStyle.windows, home: r'C:\Users\dev\.dvm');

      expect(context.display(r'C:\Users\dev\.dvm\versions\3.9.0'),
          r'C:\Users\dev\.dvm\versions\3.9.0');
      expect(context.display(r'C:\Users\dev\.dvmrc'), '.dvmrc');
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

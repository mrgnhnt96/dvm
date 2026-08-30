import 'package:dvm/dvm.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

void main() {
  group('DvmPaths', () {
    test('defaults to ~/.dvm and lays out the documented directories', () {
      final fs = MemoryFileSystem.test();
      final paths = DvmPaths(
        fileSystem: fs,
        environment: {'HOME': '/home/dev'},
      );

      expect(paths.home.path, '/home/dev/.dvm');
      expect(paths.versionsDir.path, '/home/dev/.dvm/versions');
      expect(paths.shimsDir.path, '/home/dev/.dvm/shims');
      expect(paths.cacheDir.path, '/home/dev/.dvm/cache');
      expect(paths.configFile.path, '/home/dev/.dvm/config.json');
      expect(paths.versionDir('3.9.0').path, '/home/dev/.dvm/versions/3.9.0');
    });

    test('DVM_HOME overrides the default', () {
      final fs = MemoryFileSystem.test();
      final paths = DvmPaths(
        fileSystem: fs,
        environment: {'HOME': '/home/dev', 'DVM_HOME': '/volumes/big/dvm'},
      );

      expect(paths.home.path, '/volumes/big/dvm');
      expect(paths.versionDir('3.9.0').path, '/volumes/big/dvm/versions/3.9.0');
    });

    test('a relative DVM_HOME is made absolute', () {
      final fs = MemoryFileSystem.test();
      fs.directory('/work').createSync(recursive: true);
      fs.currentDirectory = '/work';
      final paths = DvmPaths(fileSystem: fs, environment: {'DVM_HOME': 'sdks'});

      expect(paths.home.path, '/work/sdks');
    });

    test('a blank DVM_HOME falls back to HOME rather than being used', () {
      final fs = MemoryFileSystem.test();
      final paths = DvmPaths(
        fileSystem: fs,
        environment: {'HOME': '/home/dev', 'DVM_HOME': '  '},
      );

      expect(paths.home.path, '/home/dev/.dvm');
    });

    test('with no home variable at all it says what to set', () {
      final paths = DvmPaths(
        fileSystem: MemoryFileSystem.test(),
        environment: const {},
      );

      expect(
        () => paths.home,
        throwsA(
          isA<ConfigException>().having(
            (e) => e.message,
            'message',
            allOf(contains('DVM_HOME'), contains('HOME')),
          ),
        ),
      );
    });

    test('constructing never throws, so --help works without a HOME', () {
      expect(
        () => DvmPaths(
          fileSystem: MemoryFileSystem.test(),
          environment: const {},
        ),
        returnsNormally,
      );
    });

    test('the dart executable sits under bin/ in an SDK', () {
      final fs = MemoryFileSystem.test();
      final paths = DvmPaths(
        fileSystem: fs,
        environment: {'HOME': '/home/dev'},
      );

      expect(
        paths.dartExecutable(paths.versionDir('3.9.0')).path,
        '/home/dev/.dvm/versions/3.9.0/bin/dart',
      );
    });

    test('per-project paths match the documented layout', () {
      final fs = MemoryFileSystem.test();
      final paths = DvmPaths(
        fileSystem: fs,
        environment: {'HOME': '/home/dev'},
      );
      final project = fs.directory('/code/app');

      expect(paths.dvmrcFile(project).path, '/code/app/.dvmrc');
      expect(paths.projectSdkLink(project).path, '/code/app/.dvm/dart_sdk');
    });

    test('Windows uses USERPROFILE, dart.exe and the .bat shim', () {
      final fs = MemoryFileSystem.test(style: FileSystemStyle.windows);
      final paths = DvmPaths(
        fileSystem: fs,
        environment: {r'USERPROFILE': r'C:\Users\dev'},
      );

      expect(paths.home.path, r'C:\Users\dev\.dvm');
      expect(paths.dartExecutableName, 'dart.exe');
      expect(paths.dartShim.path, r'C:\Users\dev\.dvm\shims\dart.bat');
    });
  });
}

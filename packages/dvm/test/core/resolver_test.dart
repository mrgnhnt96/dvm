import 'package:dvm_cli/dvm.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

/// The two-line POSIX shim dvm writes to `~/.dvm/shims/dart`.
const String shimBody = '#!/bin/sh\nexec /usr/local/bin/dvm exec dart "\$@"\n';

void main() {
  late MemoryFileSystem fs;
  late Map<String, String> environment;
  late DvmPaths paths;
  late ConfigStore config;
  late DvmrcStore dvmrc;

  /// Builds a resolver over the *current* [environment] map.
  VersionResolver resolverFor() => VersionResolver(
        fileSystem: fs,
        paths: paths,
        config: config,
        dvmrc: dvmrc,
        environment: environment,
      );

  setUp(() {
    fs = MemoryFileSystem.test();
    environment = {'HOME': '/home/dev'};
    paths = DvmPaths(fileSystem: fs, environment: environment);
    config = ConfigStore(fileSystem: fs, paths: paths);
    dvmrc = DvmrcStore(fileSystem: fs);
  });

  /// Creates a plausible installed SDK under `~/.dvm/versions/<version>`.
  Directory installSdk(String version) {
    final dir = paths.versionDir(version);
    paths.dartExecutable(dir)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('#!/not/a/real/binary');
    dir.childFile('version').writeAsStringSync('$version\n');
    return dir;
  }

  /// Creates a non-dvm SDK, e.g. one installed by Homebrew.
  File installUnmanagedSdk(String root) {
    final dart = fs.file('$root/bin/dart');
    dart
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('#!/not/a/real/binary');
    return dart;
  }

  void writeDvmrc(String at, String contents) {
    final file = fs.file('$at/.dvmrc');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  Directory project(String path) {
    final dir = fs.directory(path)..createSync(recursive: true);
    return dir;
  }

  group('rule 1 — DVM_DART_VERSION', () {
    test('wins over everything else', () {
      installSdk('3.9.0');
      installSdk('3.13.2');
      writeDvmrc('/code/app', '{"dart": "3.13.2"}');
      config.write(const DvmConfig(global: '3.13.2'));
      environment['DVM_DART_VERSION'] = '3.9.0';

      final resolved = resolverFor().resolve(from: project('/code/app'));

      expect(resolved.rule, ResolutionRule.environmentVariable);
      expect(resolved.version, '3.9.0');
      expect(resolved.source, 'DVM_DART_VERSION');
      expect(resolved.sdkDir.path, '/home/dev/.dvm/versions/3.9.0');
      expect(resolved.isManaged, isTrue);
    });

    test('an empty value is ignored rather than treated as a pin', () {
      installSdk('3.13.2');
      config.write(const DvmConfig(global: '3.13.2'));
      environment['DVM_DART_VERSION'] = '  ';

      expect(
        resolverFor().resolve(from: project('/code/app')).rule,
        ResolutionRule.globalDefault,
      );
    });
  });

  group('rule 2 — the nearest .dvmrc', () {
    test('wins over the global default and reports which file matched', () {
      installSdk('3.9.0');
      installSdk('3.13.2');
      writeDvmrc('/code/app', '{"dart": "3.9.0"}');
      config.write(const DvmConfig(global: '3.13.2'));

      final resolved = resolverFor().resolve(from: project('/code/app/lib'));

      expect(resolved.rule, ResolutionRule.dvmrc);
      expect(resolved.version, '3.9.0');
      expect(resolved.source, '/code/app/.dvmrc');
    });

    test('a bare-version .dvmrc resolves the same as the JSON form', () {
      installSdk('3.9.0');
      writeDvmrc('/code/app', '3.9.0\n');

      final resolved = resolverFor().resolve(from: project('/code/app'));

      expect(resolved.rule, ResolutionRule.dvmrc);
      expect(resolved.version, '3.9.0');
    });

    test('a malformed .dvmrc errors instead of falling through to global', () {
      installSdk('3.13.2');
      config.write(const DvmConfig(global: '3.13.2'));
      writeDvmrc('/code/app', '{"dart": "3.9.0"');

      expect(
        () => resolverFor().resolve(from: project('/code/app')),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.message,
            'message',
            contains('/code/app/.dvmrc'),
          ),
        ),
      );
    });

    test('a pinned but uninstalled version errors, naming what to run', () {
      installSdk('3.13.2');
      config.write(const DvmConfig(global: '3.13.2'));
      writeDvmrc('/code/app', '{"dart": "3.9.0"}');

      expect(
        () => resolverFor().resolve(from: project('/code/app')),
        throwsA(
          isA<SdkNotInstalledException>()
              .having((e) => e.version, 'version', '3.9.0')
              .having((e) => e.source, 'source', '/code/app/.dvmrc')
              .having(
                (e) => e.message,
                'message',
                contains('dvm install 3.9.0'),
              ),
        ),
      );
    });

    test('a version directory with no bin/dart is wreckage, not an install',
        () {
      paths.versionDir('3.9.0').createSync(recursive: true);
      writeDvmrc('/code/app', '{"dart": "3.9.0"}');

      expect(
        () => resolverFor().resolve(from: project('/code/app')),
        throwsA(
          isA<SdkNotInstalledException>().having(
            (e) => e.message,
            'message',
            contains('no dart executable'),
          ),
        ),
      );
    });
  });

  group('rule 3 — the global default', () {
    test('applies when there is no .dvmrc anywhere above', () {
      installSdk('3.13.2');
      config.write(const DvmConfig(global: '3.13.2'));

      final resolved = resolverFor().resolve(from: project('/code/app'));

      expect(resolved.rule, ResolutionRule.globalDefault);
      expect(resolved.version, '3.13.2');
      expect(resolved.source, '/home/dev/.dvm/config.json');
    });
  });

  group('rule 4 — the next dart on PATH', () {
    test('finds a non-dvm SDK and reports it as unmanaged', () {
      installUnmanagedSdk('/opt/dart-sdk');
      environment['PATH'] = '/usr/bin:/opt/dart-sdk/bin';

      final resolved = resolverFor().resolve(from: project('/code/app'));

      expect(resolved.rule, ResolutionRule.pathFallback);
      expect(resolved.sdkDir.path, '/opt/dart-sdk');
      expect(resolved.version, isNull);
      expect(resolved.isManaged, isFalse);
      expect(resolved.source, '/opt/dart-sdk/bin');
    });

    test('SKIPS dvm\'s own shims directory and keeps looking', () {
      // This is the loop: PATH puts ~/.dvm/shims first (that is the whole
      // point of the shim), the shim runs `dvm exec dart`, and a scan that
      // takes the first `dart` it finds re-enters here and forks forever.
      paths.dartShim
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(shimBody);
      installUnmanagedSdk('/opt/dart-sdk');
      environment['PATH'] = '/home/dev/.dvm/shims:/opt/dart-sdk/bin';

      final resolved = resolverFor().resolve(from: project('/code/app'));

      expect(resolved.sdkDir.path, '/opt/dart-sdk');
      expect(resolved.executable.path, isNot(contains('shims')));
    });

    test('skips the shims directory however it is spelled on PATH', () {
      paths.dartShim
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(shimBody);
      installUnmanagedSdk('/opt/dart-sdk');
      environment['PATH'] =
          '/home/dev/.dvm/./shims/:/home/dev/.dvm/versions/../shims'
          ':/opt/dart-sdk/bin';

      expect(
        resolverFor().resolve(from: project('/code/app')).sdkDir.path,
        '/opt/dart-sdk',
      );
    });

    test('skips a symlink that points into the shims directory', () {
      paths.dartShim
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(shimBody);
      fs.directory('/home/dev/.local/bin').createSync(recursive: true);
      fs
          .link('/home/dev/.local/bin/dart')
          .createSync('/home/dev/.dvm/shims/dart');
      installUnmanagedSdk('/opt/dart-sdk');
      environment['PATH'] = '/home/dev/.local/bin:/opt/dart-sdk/bin';

      expect(
        resolverFor().resolve(from: project('/code/app')).sdkDir.path,
        '/opt/dart-sdk',
      );
    });

    test('skips a COPY of the shim, which no path check could catch', () {
      fs.file('/usr/local/bin/dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(shimBody);
      installUnmanagedSdk('/opt/dart-sdk');
      environment['PATH'] = '/usr/local/bin:/opt/dart-sdk/bin';

      expect(
        resolverFor().resolve(from: project('/code/app')).sdkDir.path,
        '/opt/dart-sdk',
      );
    });

    test('when the shim is the ONLY dart on PATH it fails, never loops', () {
      paths.dartShim
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(shimBody);
      environment['PATH'] = '/home/dev/.dvm/shims';

      expect(
        () => resolverFor().resolve(from: project('/code/app')),
        throwsA(isA<ResolutionException>()),
      );
    });

    test('follows a symlink to report the real SDK root', () {
      installUnmanagedSdk('/opt/homebrew/Cellar/dart/3.13.2');
      fs.directory('/opt/homebrew/bin').createSync(recursive: true);
      fs
          .link('/opt/homebrew/bin/dart')
          .createSync('/opt/homebrew/Cellar/dart/3.13.2/bin/dart');
      environment['PATH'] = '/opt/homebrew/bin';

      expect(
        resolverFor().resolve(from: project('/code/app')).sdkDir.path,
        '/opt/homebrew/Cellar/dart/3.13.2',
      );
    });

    test('a real binary is not misread as a shim', () {
      // Larger than the shim-sniffing size cap and not valid UTF-8.
      fs.file('/opt/dart-sdk/bin/dart')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(List<int>.filled(4096, 0xff));
      environment['PATH'] = '/opt/dart-sdk/bin';

      expect(
        resolverFor().resolve(from: project('/code/app')).sdkDir.path,
        '/opt/dart-sdk',
      );
    });

    test('empty and non-existent PATH entries are skipped', () {
      installUnmanagedSdk('/opt/dart-sdk');
      environment['PATH'] = ':/nope::/also/nope:/opt/dart-sdk/bin';

      expect(
        resolverFor().resolve(from: project('/code/app')).sdkDir.path,
        '/opt/dart-sdk',
      );
    });
  });

  group('rule 5 — nothing applies', () {
    test('names each rule that did not fire and what to run', () {
      final error = () {
        try {
          resolverFor().resolve(from: project('/code/app'));
        } on ResolutionException catch (e) {
          return e;
        }
        fail('expected a ResolutionException');
      }();

      expect(error.message, contains('/code/app'));
      expect(error.message, contains('DVM_DART_VERSION'));
      expect(error.message, contains('.dvmrc'));
      expect(error.message, contains('/home/dev/.dvm/config.json'));
      expect(error.message, contains('dvm use <version>'));
      expect(error.message, contains('dvm global <version>'));
    });
  });

  group('aliases', () {
    test('a .dvmrc naming an alias resolves through the config', () {
      installSdk('3.9.0');
      config.write(const DvmConfig(aliases: {'work': '3.9.0'}));
      writeDvmrc('/code/app', 'work');

      final resolved = resolverFor().resolve(from: project('/code/app'));

      expect(resolved.version, '3.9.0');
      expect(resolved.requested, 'work');
      expect(resolved.describe(), contains('via "work"'));
    });

    test('the global default may be an alias', () {
      installSdk('3.9.0');
      config.write(
        const DvmConfig(global: 'work', aliases: {'work': '3.9.0'}),
      );

      expect(
        resolverFor().resolve(from: project('/code/app')).version,
        '3.9.0',
      );
    });

    test('an alias may point at another alias', () {
      installSdk('3.9.0');
      config.write(
        const DvmConfig(aliases: {'work': 'client', 'client': '3.9.0'}),
      );
      writeDvmrc('/code/app', 'work');

      expect(
        resolverFor().resolve(from: project('/code/app')).version,
        '3.9.0',
      );
    });

    test('an alias may point at a channel', () {
      installSdk('3.13.2');
      config.write(
        const DvmConfig(
          aliases: {'latest': 'stable'},
          channels: {'stable': '3.13.2'},
        ),
      );
      writeDvmrc('/code/app', 'latest');

      expect(
        resolverFor().resolve(from: project('/code/app')).version,
        '3.13.2',
      );
    });

    test('a self-referential alias errors instead of hanging', () {
      config.write(const DvmConfig(aliases: {'work': 'work'}));
      writeDvmrc('/code/app', 'work');

      expect(
        () => resolverFor().resolve(from: project('/code/app')),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.message,
            'message',
            contains('points at itself'),
          ),
        ),
      );
    });

    test('an alias cycle errors instead of hanging', () {
      config.write(const DvmConfig(aliases: {'a': 'b', 'b': 'a'}));
      writeDvmrc('/code/app', 'a');

      expect(
        () => resolverFor().resolve(from: project('/code/app')),
        throwsA(isA<ConfigException>()),
      );
    });
  });

  group('channels', () {
    test('resolve to the version recorded at install time', () {
      installSdk('3.13.2');
      config.write(const DvmConfig(channels: {'stable': '3.13.2'}));
      writeDvmrc('/code/app', '{"dart": "stable"}');

      final resolved = resolverFor().resolve(from: project('/code/app'));

      expect(resolved.version, '3.13.2');
      expect(resolved.requested, 'stable');
    });

    test('beta and dev resolve independently of stable', () {
      installSdk('3.14.0-beta');
      config.write(
        const DvmConfig(
          channels: {'stable': '3.13.2', 'beta': '3.14.0-beta'},
        ),
      );
      writeDvmrc('/code/app', 'beta');

      expect(
        resolverFor().resolve(from: project('/code/app')).version,
        '3.14.0-beta',
      );
    });

    test('an uninstalled channel says to install it, not to guess', () {
      writeDvmrc('/code/app', 'stable');

      expect(
        () => resolverFor().resolve(from: project('/code/app')),
        throwsA(
          isA<SdkNotInstalledException>().having(
            (e) => e.message,
            'message',
            contains('dvm install stable'),
          ),
        ),
      );
    });
  });

  group('describe', () {
    test('names the rule, the path and the source', () {
      installSdk('3.9.0');
      writeDvmrc('/code/app', '3.9.0');

      final description =
          resolverFor().resolve(from: project('/code/app')).describe();

      expect(description, contains('.dvmrc'));
      expect(description, contains('/home/dev/.dvm/versions/3.9.0'));
      expect(description, contains('Dart 3.9.0'));
      expect(description, contains('/code/app/.dvmrc'));
    });
  });
}

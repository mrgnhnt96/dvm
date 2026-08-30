import 'package:dvm/dvm.dart';
import 'package:dvm/src/archive/sdk_extractor.dart';
import 'package:dvm/src/core/shims.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

void main() {
  late MemoryFileSystem fileSystem;
  late DvmPaths paths;
  late RecordingModeApplier modes;
  late ShimWriter writer;

  ShimWriter build(MemoryFileSystem fs, String home) {
    paths = DvmPaths(fileSystem: fs, environment: {'DVM_HOME': home});
    modes = RecordingModeApplier();
    return ShimWriter(fileSystem: fs, paths: paths, modes: modes);
  }

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    writer = build(fileSystem, '/dvm');
  });

  test('writes a two-line POSIX shim that execs the given dvm binary',
      () async {
    final shim = await writer.write('/usr/local/bin/dvm');

    expect(shim.path, '/dvm/shims/dart');
    expect(
      shim.readAsStringSync(),
      '#!/bin/sh\nexec "/usr/local/bin/dvm" exec dart "\$@"\n',
    );
  });

  test('asks for mode 0755 on the shim it wrote', () async {
    final shim = await writer.write('/usr/local/bin/dvm');

    expect(modes.applied, [
      {shim.path: 0x1ED},
    ]);
    expect(ShimWriter.shimMode.toRadixString(8), '755');
  });

  test('creates the shims directory when it is not there yet', () async {
    expect(fileSystem.directory('/dvm/shims').existsSync(), isFalse);

    await writer.write('/usr/local/bin/dvm');

    expect(fileSystem.directory('/dvm/shims').existsSync(), isTrue);
  });

  test('the shim it writes is what the resolver recognises as a shim', () {
    // The resolver skips dvm's own shims when it scans PATH, by content as
    // well as by location. A shim this writer produced that the resolver did
    // not recognise would make `dart` fork until the machine gave up.
    final body = writer.body('/usr/local/bin/dvm');
    expect(body.length, lessThan(512), reason: 'the resolver only reads 512B');

    final onPath = fileSystem.file('/usr/bin/dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(body);
    final resolver = VersionResolver(
      fileSystem: fileSystem,
      paths: paths,
      config: ConfigStore(fileSystem: fileSystem, paths: paths),
      dvmrc: DvmrcStore(fileSystem: fileSystem),
      environment: const {'PATH': '/usr/bin'},
    );

    expect(onPath.existsSync(), isTrue);
    expect(
      resolver.findDartOnPath(),
      isNull,
      reason: 'a copy of the shim on PATH must not be taken for a real dart',
    );
  });

  test('reads back the binary a shim runs', () async {
    final shim = await writer.write('/opt/dvm/bin/dvm');

    expect(writer.targetOf(shim), '/opt/dvm/bin/dvm');
  });

  test('reads back nothing from a file that is not one of its shims', () {
    final other = fileSystem.file('/usr/local/bin/dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('#!/bin/sh\nexec /usr/lib/dart/bin/dart "\$@"\n');

    expect(writer.targetOf(other), isNull);
  });

  test('refuses a relative dvm path', () async {
    await expectLater(
      writer.write('bin/dvm'),
      throwsA(
        isA<ConfigException>().having(
          (error) => error.message,
          'message',
          contains('must be absolute'),
        ),
      ),
    );
  });

  test('refuses a dvm path that would break out of the quoting', () async {
    await expectLater(
      writer.write('/opt/"; rm -rf /; "/dvm'),
      throwsA(isA<ConfigException>()),
    );
    expect(paths.dartShim.existsSync(), isFalse);
  });

  test('writes a .bat that forwards its arguments on Windows', () async {
    final windows = MemoryFileSystem.test(style: FileSystemStyle.windows);
    final windowsWriter = build(windows, r'C:\dvm');

    final shim = await windowsWriter.write(r'C:\Users\dev\.dvm\bin\dvm.exe');

    expect(shim.path, r'C:\dvm\shims\dart.bat');
    expect(
      shim.readAsStringSync(),
      '@echo off\r\n"C:\\Users\\dev\\.dvm\\bin\\dvm.exe" exec dart %*\r\n',
    );
    expect(
      modes.applied,
      isEmpty,
      reason: 'Windows has no mode bits and no chmod',
    );
  });
}

/// A [ModeApplier] that records what it was asked to apply.
///
/// The real one shells out to `chmod`, which acts on the machine's filesystem
/// and not on the [MemoryFileSystem] these tests write to.
class RecordingModeApplier implements ModeApplier {
  final List<Map<String, int>> applied = [];

  @override
  Future<void> apply(Map<String, int> modeByPath) async {
    applied.add(modeByPath);
  }
}

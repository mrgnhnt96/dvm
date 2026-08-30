import 'dart:io' as io;

import 'package:dvm/dvm.dart';
import 'package:dvm/src/archive/dart_archive_client.dart';
import 'package:dvm/src/archive/sdk_extractor.dart';
import 'package:dvm/src/archive/sdk_installer.dart';
import 'package:file/local.dart';
import 'package:test/test.dart';

import 'fake_archive_server.dart';

/// ARCHITECTURE.md: `package:archive`'s zip decoder carries unix permissions in
/// `ArchiveFile.mode` but the `Archive`-based extraction helpers never apply
/// them, so without an explicit pass everything under `bin/` lands
/// non-executable and the installed SDK is inert.
///
/// This is the one file in the suite that uses a real filesystem, because the
/// executable bit is exactly what a `MemoryFileSystem` does not have. It works
/// inside a throwaway temp directory pointed at by `$DVM_HOME`; the real
/// `~/.dvm` is never touched.
void main() {
  late FakeArchiveServer server;
  late io.Directory home;
  late DvmPaths paths;

  const platform = HostPlatform(os: 'macos', arch: 'arm64');

  setUp(() async {
    server = await FakeArchiveServer.start();
    home = io.Directory.systemTemp.createTempSync('dvm_modes_test');
    paths = DvmPaths(
      fileSystem: const LocalFileSystem(),
      environment: {'DVM_HOME': home.path},
    );
  });

  tearDown(() async {
    await server.close();
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  test('extracted files come out with the modes the archive recorded',
      () async {
    server.publish(
      channel: 'stable',
      version: '3.13.2',
      fileName: platform.archiveFileName,
      // 0755 on bin/dart, 0644 on everything else, as the real zips carry.
      bytes: fakeSdkZip(),
    );

    final installer = SdkInstaller(
      fileSystem: const LocalFileSystem(),
      paths: paths,
      releases: DartArchiveClient(
        objectBase: server.objectBase,
        listApi: server.listApi,
      ),
      hostPlatform: () => platform,
      progress: StringBuffer(),
    );

    final sdk = await installer.install('3.13.2');

    final dart = io.File('${sdk.path}/bin/dart');
    expect(dart.existsSync(), isTrue);
    expect(
      _mode(dart.path),
      '755',
      reason: 'bin/dart must be executable or the installed SDK is inert',
    );
    expect(_mode('${sdk.path}/version'), '644');
  }, onPlatform: {
    'windows': const Skip('unix modes and chmod do not exist on Windows'),
  });

  test('without the mode pass bin/dart is not executable', () async {
    // The control for the test above: a passing assertion about permissions
    // proves nothing unless the same setup without the pass fails it. This is
    // the inert SDK ARCHITECTURE.md warns about, reproduced.
    server.publish(
      channel: 'stable',
      version: '3.13.2',
      fileName: platform.archiveFileName,
      bytes: fakeSdkZip(),
    );

    final installer = SdkInstaller(
      fileSystem: const LocalFileSystem(),
      paths: paths,
      releases: DartArchiveClient(
        objectBase: server.objectBase,
        listApi: server.listApi,
      ),
      hostPlatform: () => platform,
      progress: StringBuffer(),
      modeApplier: const NoopModeApplier(),
    );

    final sdk = await installer.install('3.13.2');

    expect(_mode('${sdk.path}/bin/dart'), isNot('755'));
    expect(
      io.File('${sdk.path}/bin/dart').statSync().mode & 0x49,
      0,
      reason: 'no execute bit for user, group or other',
    );
  }, onPlatform: {
    'windows': const Skip('unix modes and chmod do not exist on Windows'),
  });
}

/// The permission bits of [path], as octal — read back through `stat`, not
/// through whatever wrote them.
String _mode(String path) {
  // BSD stat and GNU stat spell the permission bits differently.
  final result = io.Process.runSync(
    'stat',
    io.Platform.isMacOS ? ['-f', '%Lp', path] : ['-c', '%a', path],
  );
  if (result.exitCode != 0) {
    throw StateError('stat failed for $path: ${result.stderr}');
  }
  return (result.stdout as String).trim();
}

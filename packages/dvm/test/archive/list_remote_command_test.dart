import 'package:dvm/dvm.dart';
import 'package:dvm/src/archive/dart_archive_client.dart';
import 'package:dvm/src/archive/sdk_extractor.dart';
import 'package:dvm/src/archive/sdk_installer.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

import 'fake_archive_server.dart';

void main() {
  late FakeArchiveServer server;
  late MemoryFileSystem fs;
  late DvmPaths paths;
  late StringBuffer out;
  late StringBuffer err;

  const platform = HostPlatform(os: 'macos', arch: 'arm64');
  final environment = {'DVM_HOME': '/dvm', 'HOME': '/home/dev'};

  setUp(() async {
    server = await FakeArchiveServer.start();
    fs = MemoryFileSystem.test();
    paths = DvmPaths(fileSystem: fs, environment: environment);
    out = StringBuffer();
    err = StringBuffer();
  });

  tearDown(() => server.close());

  Future<int> runDvm(List<String> args) {
    final releases = DartArchiveClient(
      objectBase: server.objectBase,
      listApi: server.listApi,
    );
    return run(
      args,
      fileSystem: fs,
      environment: environment,
      platformVersion: '3.13.2 (stable) on "macos_arm64"',
      out: out,
      err: err,
      releases: releases,
      installer: SdkInstaller(
        fileSystem: fs,
        paths: paths,
        releases: releases,
        hostPlatform: () => platform,
        progress: out,
        modeApplier: const NoopModeApplier(),
      ),
    );
  }

  /// The version on each printed line, in order.
  List<String> listedVersions() => [
        for (final line in out.toString().split('\n'))
          if (RegExp(r'^\s+\d').hasMatch(line)) line.trim().split(' ').first,
      ];

  test('lists stable newest first, semantically', () async {
    server.prefixes['stable'] = ['3.9.0', '3.13.0', '3.10.1', '2.19.6'];

    expect(await runDvm(['list-remote']), 0);
    expect(listedVersions(), ['3.13.0', '3.10.1', '3.9.0', '2.19.6']);
  });

  test('the Dart 1 build numbers and latest never reach the output', () async {
    server.prefixes['stable'] = ['29803', '41096', 'latest', '3.13.0'];

    expect(await runDvm(['list-remote']), 0);
    expect(listedVersions(), ['3.13.0']);
    expect(out.toString(), isNot(contains('29803')));
    expect(out.toString(), isNot(contains('latest')));
  });

  test('--channel lists a different channel', () async {
    server.prefixes['stable'] = ['3.13.0'];
    server.prefixes['beta'] = ['3.14.0-172.2.beta'];

    expect(await runDvm(['list-remote', '--channel', 'beta']), 0);
    expect(listedVersions(), ['3.14.0-172.2.beta']);
  });

  test('an unknown channel is a usage error', () async {
    expect(
        await runDvm(['list-remote', '--channel', 'nightly']), usageExitCode);
    expect(err.toString(), contains('nightly'));
  });

  test('installed versions are marked', () async {
    server.publish(
      channel: 'stable',
      version: '3.13.2',
      fileName: platform.archiveFileName,
      bytes: fakeSdkZip(),
    );
    server.prefixes['stable']!.add('3.9.0');
    await runDvm(['install', '3.13.2']);
    out.clear();

    expect(await runDvm(['list-remote']), 0);
    expect(out.toString(), contains('3.13.2  (installed)'));
    expect(out.toString(), contains('  3.9.0\n'));
  });

  group('when there are more releases than fit on a screen', () {
    setUp(() {
      // Stable really does carry ~177 of these.
      server.prefixes['stable'] = [
        for (var minor = 0; minor < 40; minor++) '3.$minor.0',
      ];
    });

    test('only the newest are shown, and it says so', () async {
      expect(await runDvm(['list-remote']), 0);

      final listed = listedVersions();
      expect(listed, hasLength(25));
      expect(listed.first, '3.39.0');
      expect(out.toString(), contains('newest 25 of 40'));
    });

    test('--all shows every one of them', () async {
      expect(await runDvm(['list-remote', '--all']), 0);

      expect(listedVersions(), hasLength(40));
      expect(out.toString(), isNot(contains('Pass --all')));
    });
  });

  test('a channel with nothing published says so rather than printing nothing',
      () async {
    expect(await runDvm(['list-remote', '--channel', 'dev']), 0);
    expect(out.toString(), contains('no dev releases'));
  });
}

import 'dart:convert';

import 'package:dvm_cli/dvm.dart';
import 'package:dvm_cli/src/archive/dart_archive_client.dart';
import 'package:dvm_cli/src/archive/sdk_extractor.dart';
import 'package:dvm_cli/src/archive/sdk_installer.dart';
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
  const platformVersion = '3.13.2 (stable) on "macos_arm64"';
  final environment = {'DVM_HOME': '/dvm', 'HOME': '/home/dev'};

  setUp(() async {
    server = await FakeArchiveServer.start();
    fs = MemoryFileSystem.test();
    paths = DvmPaths(fileSystem: fs, environment: environment);
    out = StringBuffer();
    err = StringBuffer();
  });

  tearDown(() => server.close());

  DartArchiveClient client() => DartArchiveClient(
        objectBase: server.objectBase,
        listApi: server.listApi,
      );

  Future<int> runDvm(List<String> args) {
    final releases = client();
    return run(
      args,
      fileSystem: fs,
      environment: environment,
      platformVersion: platformVersion,
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

  void publish(String version, {String channel = 'stable'}) {
    server.publish(
      channel: channel,
      version: version,
      fileName: platform.archiveFileName,
      bytes: fakeSdkZip(version: version),
    );
  }

  Map<String, Object?> readConfig() => jsonDecode(
        paths.configFile.readAsStringSync(),
      ) as Map<String, Object?>;

  test('a bare version installs and does not touch the channel record',
      () async {
    publish('3.13.2');

    expect(await runDvm(['install', '3.13.2']), 0);
    expect(out.toString(), contains('Installed Dart 3.13.2'));
    expect(fs.file('/dvm/versions/3.13.2/bin/dart').existsSync(), isTrue);

    // `dvm install 3.13.2` happening to find 3.13.2 in the stable channel must
    // not rewrite what `stable` points at.
    expect(paths.configFile.existsSync(), isFalse);
  });

  group('installing a channel', () {
    test('records the version it resolved to, so `use stable` can work offline',
        () async {
      publish('3.13.2');
      server.latest['stable'] = '3.13.2';

      expect(await runDvm(['install', 'stable']), 0);

      expect(readConfig()['channels'], {'stable': '3.13.2'});
    });

    test('the recorded version is what version resolution then finds',
        () async {
      publish('3.13.2');
      server.latest['stable'] = '3.13.2';
      await runDvm(['install', 'stable']);

      // The end the recording exists for: resolution reads the channel out of
      // config.json with no network involved at all.
      final resolver = VersionResolver(
        fileSystem: fs,
        paths: paths,
        config: ConfigStore(fileSystem: fs, paths: paths),
        dvmrc: DvmrcStore(fileSystem: fs),
        environment: {...environment, 'DVM_DART_VERSION': 'stable'},
      );

      final resolved = resolver.resolve(
          from: fs.directory('/project')..createSync(recursive: true));
      expect(resolved.version, '3.13.2');
      expect(resolved.requested, 'stable');
    });

    test('moves the record on when the channel has advanced', () async {
      publish('3.13.2');
      server.latest['stable'] = '3.13.2';
      await runDvm(['install', 'stable']);

      publish('3.14.0');
      server.latest['stable'] = '3.14.0';
      out.clear();
      expect(await runDvm(['install', 'stable']), 0);

      expect(readConfig()['channels'], {'stable': '3.14.0'});
      expect(fs.file('/dvm/versions/3.13.2/bin/dart').existsSync(), isTrue,
          reason: 'the older SDK stays installed');
    });

    test('records the channel even when that version is already installed',
        () async {
      publish('3.13.2');
      server.latest['stable'] = '3.13.2';
      await runDvm(['install', '3.13.2']);
      expect(paths.configFile.existsSync(), isFalse);

      out.clear();
      expect(await runDvm(['install', 'stable']), 0);

      expect(out.toString(), contains('already installed'));
      expect(readConfig()['channels'], {'stable': '3.13.2'});
    });

    test('other channels are resolved too', () async {
      publish('3.14.0-172.2.beta', channel: 'beta');
      server.latest['beta'] = '3.14.0-172.2.beta';

      expect(await runDvm(['install', 'beta']), 0);
      expect(readConfig()['channels'], {'beta': '3.14.0-172.2.beta'});
    });
  });

  test('an alias installs what it points at', () async {
    publish('3.9.0');
    ConfigStore(fileSystem: fs, paths: paths)
        .write(const DvmConfig(aliases: {'work': '3.9.0'}));

    expect(await runDvm(['install', 'work']), 0);
    expect(fs.file('/dvm/versions/3.9.0/bin/dart').existsSync(), isTrue);
  });

  test('an alias pointing at a channel is followed through to it', () async {
    publish('3.13.2');
    server.latest['stable'] = '3.13.2';
    ConfigStore(fileSystem: fs, paths: paths)
        .write(const DvmConfig(aliases: {'latest': 'stable'}));

    expect(await runDvm(['install', 'latest']), 0);
    expect(readConfig()['channels'], {'stable': '3.13.2'});
  });

  test('an alias that points at itself is reported, not looped on', () async {
    ConfigStore(fileSystem: fs, paths: paths)
        .write(const DvmConfig(aliases: {'work': 'work'}));

    expect(await runDvm(['install', 'work']), 1);
    expect(err.toString(), contains('points at itself'));
  });

  test('installing something already present is a no-op, not an error',
      () async {
    publish('3.13.2');
    expect(await runDvm(['install', '3.13.2']), 0);
    server.requests.clear();
    out.clear();

    expect(await runDvm(['install', '3.13.2']), 0);
    expect(out.toString(), contains('already installed'));
    expect(out.toString(), contains('/dvm/versions/3.13.2'));
    expect(server.requests, isEmpty, reason: 'nothing should be re-downloaded');
  });

  test('--force reinstalls over what is there', () async {
    publish('3.13.2');
    await runDvm(['install', '3.13.2']);
    fs.file('/dvm/versions/3.13.2/scribble').writeAsStringSync('stale');
    out.clear();

    expect(await runDvm(['install', '3.13.2', '--force']), 0);
    expect(out.toString(), contains('Installed Dart 3.13.2'));
    expect(fs.file('/dvm/versions/3.13.2/scribble').existsSync(), isFalse);
    expect(fs.file('/dvm/versions/3.13.2/bin/dart').existsSync(), isTrue);
  });

  group('bad usage', () {
    test('naming nothing is a usage error', () async {
      expect(await runDvm(['install']), usageExitCode);
      expect(err.toString(), contains('Name a version, channel or alias'));
    });

    test('naming two versions is a usage error', () async {
      expect(await runDvm(['install', '3.9.0', '3.13.2']), usageExitCode);
      expect(err.toString(), contains('one version at a time'));
    });
  });

  test('a version nobody publishes is reported, not crashed on', () async {
    expect(await runDvm(['install', '9.9.9']), 1);
    expect(err.toString(), contains('dvm: '));
    expect(err.toString(), contains('not published in any channel'));
    expect(fs.directory('/dvm/versions').existsSync(), isFalse);
  });
}

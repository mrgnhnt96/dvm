import 'package:dvm/dvm.dart';
import 'package:dvm/src/archive/dart_archive_client.dart';
import 'package:dvm/src/archive/dart_archive_exception.dart';
import 'package:test/test.dart';

import 'fake_archive_server.dart';

void main() {
  late FakeArchiveServer server;
  late DartArchiveClient client;

  setUp(() async {
    server = await FakeArchiveServer.start();
    client = DartArchiveClient(
      objectBase: server.objectBase,
      listApi: server.listApi,
    );
  });

  tearDown(() => server.close());

  group('listReleases', () {
    test('drops the Dart 1 build numbers and the latest alias', () async {
      // A sample of the real bucket: 28 of stable's ~205 prefixes are Dart 1
      // build numbers rather than versions, and one is `latest`.
      server.prefixes['stable'] = [
        '29803',
        '41096',
        '1.24.3',
        'latest',
        '2.19.6',
        '3.9.0',
      ];

      expect(
        await client.listReleases(Channel.stable),
        ['3.9.0', '2.19.6', '1.24.3'],
      );
    });

    test('sorts semantically, not lexically', () async {
      // The whole point: as strings "3.9.0" sorts above "3.13.0", which would
      // present a two-year-old SDK as the newest release available.
      server.prefixes['stable'] = ['3.13.0', '3.9.0', '3.10.1', '3.2.0'];

      final releases = await client.listReleases(Channel.stable);
      expect(releases, ['3.13.0', '3.10.1', '3.9.0', '3.2.0']);
      expect(
        releases.indexOf('3.13.0'),
        lessThan(releases.indexOf('3.9.0')),
        reason: '3.13.0 is newer than 3.9.0',
      );
    });

    test('orders a prerelease below the release it leads to', () async {
      server.prefixes['dev'] = ['3.14.0', '3.14.0-1.0.dev', '3.14.0-2.0.dev'];

      expect(
        await client.listReleases(Channel.dev),
        ['3.14.0', '3.14.0-2.0.dev', '3.14.0-1.0.dev'],
      );
    });

    test('asks for the channel it was given', () async {
      server.prefixes['beta'] = ['3.14.0-172.2.beta'];

      expect(await client.listReleases(Channel.beta), ['3.14.0-172.2.beta']);
      expect(
        server.requests.single,
        contains('prefix=channels%2Fbeta%2Frelease%2F'),
      );
    });

    test('a channel with nothing published is empty, not an error', () async {
      expect(await client.listReleases(Channel.dev), isEmpty);
    });
  });

  group('latestVersion', () {
    test('reads the version out of latest/VERSION', () async {
      server.latest['stable'] = '3.13.2';

      expect(await client.latestVersion(Channel.stable), '3.13.2');
    });

    test('a missing channel is a DvmException, not a crash', () async {
      expect(
        () => client.latestVersion(Channel.beta),
        throwsA(isA<DartArchiveException>().having(
          (e) => e.message,
          'message',
          contains('404'),
        )),
      );
    });
  });

  group('channelFor', () {
    test('probes stable, then beta, then dev, and stops at the first hit',
        () async {
      server.prefixes['dev'] = ['3.14.0-1.0.dev'];

      expect(await client.channelFor('3.14.0-1.0.dev'), Channel.dev);
      expect(
        server.requests,
        [
          contains('/channels/stable/release/3.14.0-1.0.dev/VERSION'),
          contains('/channels/beta/release/3.14.0-1.0.dev/VERSION'),
          contains('/channels/dev/release/3.14.0-1.0.dev/VERSION'),
        ],
      );
    });

    test('a version in more than one channel resolves to stable', () async {
      server.prefixes['stable'] = ['3.13.2'];
      server.prefixes['beta'] = ['3.13.2'];

      expect(await client.channelFor('3.13.2'), Channel.stable);
      expect(server.requests, hasLength(1));
    });

    test('a version in no channel names all three in its message', () async {
      expect(
        () => client.channelFor('9.9.9'),
        throwsA(isA<DartArchiveException>().having(
          (e) => e.message,
          'message',
          allOf(contains('stable'), contains('beta'), contains('dev')),
        )),
      );
    });
  });

  group('artifactFor', () {
    test('builds the documented download and checksum URLs', () {
      final artifact = client.artifactFor(
        channel: Channel.stable,
        version: '3.13.2',
        platform: const HostPlatform(os: 'macos', arch: 'arm64'),
      );

      expect(artifact.version, '3.13.2');
      expect(artifact.fileName, 'dartsdk-macos-arm64-release.zip');
      expect(
        artifact.archive.path,
        endsWith(
          '/channels/stable/release/3.13.2/sdk/dartsdk-macos-arm64-release.zip',
        ),
      );
      expect(artifact.checksum.toString(), '${artifact.archive}.sha256sum');
    });

    test('does no I/O', () {
      client.artifactFor(
        channel: Channel.beta,
        version: '3.14.0-172.2.beta',
        platform: const HostPlatform(os: 'linux', arch: 'x64'),
      );

      expect(server.requests, isEmpty);
    });
  });
}

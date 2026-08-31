import 'dart:convert';
import 'dart:typed_data';

import 'package:dvm/dvm.dart';
import 'package:dvm/dvm.dart' as dvm;
import 'package:dvm/src/archive/sdk_extractor.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

import 'fake_github_server.dart';

/// The alpha channel: `dvm update --alpha`, `--stable`, and what a plain
/// `dvm update` does when it is running on an alpha.
///
/// THE ONE THING TO KNOW BEFORE READING THESE. An alpha reports
/// `<version>+alpha.g<sha>`, and semver ignores build metadata for precedence,
/// so every alpha of `0.1.0` compares EQUAL to every other and to `0.1.0`
/// itself. An implementation that asks "is the published one newer?" therefore
/// reports "up to date" forever while sitting dozens of commits behind — it
/// looks like a working feature. `does not compare an alpha by version` below
/// is the test that fails when someone writes it that way.
void main() {
  late FakeGitHubServer server;
  late MemoryFileSystem fs;

  /// A commit an alpha was built from, and the one published after it.
  const installedCommit = 'c0687e6';
  const publishedCommit = '0ad7aad29d7ded5c35383f58fea42d637fad39d4';

  setUp(() async {
    server = await FakeGitHubServer.start();
    fs = MemoryFileSystem.test();
  });

  tearDown(() => server.close());

  Updater updaterFor({
    String currentVersion = '0.1.0',
    String currentBuildTag = '',
    Map<String, String> environment = const {},
  }) =>
      Updater(
        fileSystem: fs,
        hostPlatform: () => const HostPlatform(os: 'macos', arch: 'arm64'),
        environment: environment,
        apiBase: server.apiBase,
        isCompiled: true,
        currentVersion: currentVersion,
        currentBuildTag: currentBuildTag,
        modeApplier: const NoopModeApplier(),
      );

  File installedDvm([String path = '/usr/local/bin/dvm']) => fs.file(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(utf8.encode('the running dvm binary'));

  /// The response shape both channels are pointed at: one rolling prerelease
  /// and one stable release, exactly as `mrgnhnt96/dvm` publishes them.
  void publishBothChannels({String alphaCommit = publishedCommit}) {
    server
      ..publish(
        tag: 'alpha',
        prerelease: true,
        commit: alphaCommit,
        title: 'dvm alpha (${alphaCommit.substring(0, 7)})',
        assets: {'dvm-macos-arm64.zip': _zip(contents: 'the alpha binary')},
      )
      ..publish(
        tag: 'v0.1.0',
        assets: {'dvm-macos-arm64.zip': _zip(contents: 'the release binary')},
      );
  }

  group('channel selection', () {
    test(
        '--alpha takes the prerelease and a plain update takes the release, '
        'from the same response', () async {
      publishBothChannels();
      final binary = installedDvm();

      await updaterFor().update(
        executablePath: binary.path,
        channel: UpdateChannel.alpha,
      );
      expect(binary.readAsStringSync(), 'the alpha binary');

      // Same server, same releases, no flag.
      await updaterFor(currentVersion: '0.0.9').update(
        executablePath: binary.path,
      );
      expect(binary.readAsStringSync(), 'the release binary');
    });

    test(
        'a plain update never resolves to a prerelease, even when the '
        'prerelease is the only thing newer', () async {
      // The regression guard for the default channel. The alpha exists, is
      // newest, carries this platform's asset, and even has a version tag —
      // and the stable scan still must not see it.
      server
        ..publish(
          tag: 'v0.9.0',
          prerelease: true,
          assets: {'dvm-macos-arm64.zip': _zip(contents: 'a prerelease')},
        )
        ..publish(
          tag: 'alpha',
          prerelease: true,
          commit: publishedCommit,
          assets: {'dvm-macos-arm64.zip': _zip(contents: 'the alpha binary')},
        )
        ..publish(
          tag: 'v0.3.0',
          assets: {'dvm-macos-arm64.zip': _zip(contents: 'the release binary')},
        );

      final release = await updaterFor().latestRelease();

      expect(release.tag, 'v0.3.0');
      expect(release.isPrerelease, isFalse);
    });

    test(
        '--alpha refuses when nothing is published as a prerelease, rather '
        'than falling back to the release', () async {
      server.publish(
        tag: 'v0.3.0',
        assets: {'dvm-macos-arm64.zip': _zip()},
      );
      final binary = installedDvm();

      await expectLater(
        updaterFor().update(
          executablePath: binary.path,
          channel: UpdateChannel.alpha,
        ),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('PRERELEASE'),
              contains('deliberately NOT taken in its place'),
            ),
          ),
        ),
      );
      expect(binary.readAsStringSync(), 'the running dvm binary');
    });

    test('--alpha skips a draft prerelease', () async {
      server
        ..publish(
          tag: 'alpha-draft',
          draft: true,
          prerelease: true,
          commit: publishedCommit,
          assets: {'dvm-macos-arm64.zip': _zip(contents: 'a draft')},
        )
        ..publish(
          tag: 'alpha',
          prerelease: true,
          commit: publishedCommit,
          assets: {'dvm-macos-arm64.zip': _zip(contents: 'the alpha binary')},
        );

      expect((await updaterFor().latestAlphaRelease()).tag, 'alpha');
    });

    test('the alpha tag is not mangled into a version', () async {
      // `tag.substring(1)` on a non-`v` tag would make this `lpha`.
      publishBothChannels();
      final release = await updaterFor().latestAlphaRelease();

      expect(release.version, 'alpha');
      expect(release.label, 'alpha (0ad7aad)');
    });
  });

  group('is there a newer alpha', () {
    test(
        'does not compare an alpha by version: a different commit at the '
        'same version is an update', () async {
      // THE SEMVER TRAP. `0.1.0+alpha.gc0687e6` and the published
      // `0.1.0+alpha.g0ad7aad` are semver-EQUAL, and so is the `0.1.0` release
      // they were both cut from. Anything asking "is it greater?" installs
      // nothing here and says everything is fine.
      publishBothChannels();
      final binary = installedDvm();

      final outcome = await updaterFor(
        currentBuildTag: 'alpha.g$installedCommit',
      ).update(
        executablePath: binary.path,
        channel: UpdateChannel.alpha,
      );

      expect(outcome.status, UpdateStatus.installed);
      expect(outcome.from, '0.1.0+alpha.gc0687e6');
      expect(outcome.to, 'alpha (0ad7aad)');
      expect(binary.readAsStringSync(), 'the alpha binary');
    });

    test('says so and touches nothing when already on the published alpha',
        () async {
      publishBothChannels();
      final binary = installedDvm();

      final outcome = await updaterFor(
        // The same commit, abbreviated the way the build tag carries it.
        currentBuildTag: 'alpha.g0ad7aad',
      ).update(
        executablePath: binary.path,
        channel: UpdateChannel.alpha,
      );

      expect(outcome.status, UpdateStatus.upToDate);
      expect(binary.readAsStringSync(), 'the running dvm binary');
      expect(
        server.requests.where((path) => path.contains('/download/')),
        isEmpty,
      );
    });

    test(
        'reads the published commit from the title when target_commitish is '
        'a branch name', () async {
      // What GitHub returns for a release cut against an existing tag. "main"
      // is not a commit, and believing it would make every run an update.
      server.publish(
        tag: 'alpha',
        prerelease: true,
        commit: 'main',
        title: 'dvm alpha (0ad7aad)',
        assets: {'dvm-macos-arm64.zip': _zip(contents: 'the alpha binary')},
      );
      final binary = installedDvm();

      final outcome =
          await updaterFor(currentBuildTag: 'alpha.g0ad7aad').update(
        executablePath: binary.path,
        channel: UpdateChannel.alpha,
      );

      expect(outcome.status, UpdateStatus.upToDate);
    });

    test('installs when the published alpha names no commit at all', () async {
      // "Could not tell" must not read as "up to date" — that is the exact
      // failure this channel exists to fix.
      server.publish(
        tag: 'alpha',
        prerelease: true,
        assets: {'dvm-macos-arm64.zip': _zip(contents: 'the alpha binary')},
      );
      final binary = installedDvm();

      final outcome =
          await updaterFor(currentBuildTag: 'alpha.g0ad7aad').update(
        executablePath: binary.path,
        channel: UpdateChannel.alpha,
      );

      expect(outcome.status, UpdateStatus.installed);
      expect(binary.readAsStringSync(), 'the alpha binary');
    });

    test('a release build asking for --alpha installs it', () async {
      publishBothChannels();
      final binary = installedDvm();

      final outcome = await updaterFor().update(
        executablePath: binary.path,
        channel: UpdateChannel.alpha,
      );

      expect(outcome.status, UpdateStatus.installed);
      expect(outcome.from, '0.1.0');
      expect(binary.readAsStringSync(), 'the alpha binary');
    });
  });

  group('sameCommit', () {
    test('matches an abbreviation against the whole sha, either way round', () {
      expect(sameCommit('0ad7aad', publishedCommit), isTrue);
      expect(sameCommit(publishedCommit, '0ad7aad'), isTrue);
      expect(sameCommit(publishedCommit, publishedCommit), isTrue);
      expect(sameCommit('0AD7AAD', publishedCommit), isTrue);
    });

    test('does not match a different commit, or a non-commit', () {
      expect(sameCommit('c0687e6', publishedCommit), isFalse);
      expect(sameCommit('main', publishedCommit), isFalse);
      expect(sameCommit('', publishedCommit), isFalse);
      // Too short to be an identity rather than a coincidence.
      expect(sameCommit('0ad7aa', publishedCommit), isFalse);
    });
  });

  group('getting back off the channel', () {
    test(
        'a plain update on an alpha does not report up to date, and installs '
        'nothing', () async {
      // The stranding bug: `0.1.0+alpha.gc0687e6` vs the `0.1.0` release are
      // semver-equal, so this used to print "already up to date" and leave the
      // user on an alpha with no way back that the tool named.
      publishBothChannels();
      final binary = installedDvm();

      final outcome = await updaterFor(
        currentBuildTag: 'alpha.g$installedCommit',
      ).update(executablePath: binary.path);

      expect(outcome.status, UpdateStatus.alphaAheadOfStable);
      expect(outcome.isUpToDate, isFalse);
      expect(outcome.to, '0.1.0');
      expect(binary.readAsStringSync(), 'the running dvm binary');
    });

    test('--stable leaves the alpha for a release of the same version',
        () async {
      publishBothChannels();
      final binary = installedDvm();

      final outcome = await updaterFor(
        currentBuildTag: 'alpha.g$installedCommit',
      ).update(
        executablePath: binary.path,
        channel: UpdateChannel.stable,
      );

      expect(outcome.status, UpdateStatus.installed);
      expect(outcome.from, '0.1.0+alpha.gc0687e6');
      expect(outcome.to, '0.1.0');
      expect(binary.readAsStringSync(), 'the release binary');
    });

    test(
        'a plain update on an alpha DOES take a release that is genuinely '
        'ahead', () async {
      server
        ..publish(
          tag: 'alpha',
          prerelease: true,
          commit: publishedCommit,
          assets: {'dvm-macos-arm64.zip': _zip(contents: 'the alpha binary')},
        )
        ..publish(
          tag: 'v0.2.0',
          assets: {'dvm-macos-arm64.zip': _zip(contents: 'dvm 0.2.0')},
        );
      final binary = installedDvm();

      final outcome = await updaterFor(
        currentBuildTag: 'alpha.g$installedCommit',
      ).update(executablePath: binary.path);

      expect(outcome.status, UpdateStatus.installed);
      expect(outcome.to, '0.2.0');
      expect(binary.readAsStringSync(), 'dvm 0.2.0');
    });

    test('an explicit version still gets an alpha back to an exact release',
        () async {
      publishBothChannels();
      final binary = installedDvm();

      final outcome = await updaterFor(
        currentBuildTag: 'alpha.g$installedCommit',
      ).update(executablePath: binary.path, version: '0.1.0');

      expect(outcome.status, UpdateStatus.installed);
      expect(binary.readAsStringSync(), 'the release binary');
    });

    test('--stable on a release build already on the newest is up to date',
        () async {
      publishBothChannels();
      final binary = installedDvm();

      final outcome = await updaterFor().update(
        executablePath: binary.path,
        channel: UpdateChannel.stable,
      );

      expect(outcome.status, UpdateStatus.upToDate);
      expect(binary.readAsStringSync(), 'the running dvm binary');
    });
  });

  group('--check', () {
    test('with --alpha reports the alpha and installs nothing', () async {
      publishBothChannels();
      final binary = installedDvm();

      final outcome = await updaterFor(
        currentBuildTag: 'alpha.g$installedCommit',
      ).update(
        executablePath: binary.path,
        channel: UpdateChannel.alpha,
        check: true,
      );

      expect(outcome.status, UpdateStatus.available);
      expect(outcome.to, 'alpha (0ad7aad)');
      expect(binary.readAsStringSync(), 'the running dvm binary');
      expect(
        server.requests.where((path) => path.contains('/download/')),
        isEmpty,
      );
    });
  });

  group('the API', () {
    test('the alpha path sends GITHUB_TOKEN when there is one', () async {
      publishBothChannels();

      await updaterFor(environment: const {'GITHUB_TOKEN': 'a-token'})
          .latestAlphaRelease();

      expect(server.authorizations, everyElement('Bearer a-token'));
    });

    test('a rate-limited alpha lookup still names GITHUB_TOKEN', () async {
      server.failWith = 403;

      await expectLater(
        updaterFor().latestAlphaRelease(),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            allOf(contains('403'), contains('GITHUB_TOKEN')),
          ),
        ),
      );
    });
  });

  group('the command line', () {
    late StringBuffer out;
    late StringBuffer err;
    const executablePath = '/usr/local/bin/dvm';

    setUp(() {
      out = StringBuffer();
      err = StringBuffer();
      installedDvm(executablePath);
    });

    Future<int> runDvm(
      List<String> args, {
      String currentVersion = '0.1.0',
      String currentBuildTag = '',
    }) =>
        dvm.run(
          args,
          fileSystem: fs,
          environment: const {
            'DVM_HOME': '/dvm',
            'HOME': '/home/dev',
            'PATH': ''
          },
          platformVersion: '3.13.2 (stable) on "macos_arm64"',
          out: out,
          err: err,
          executablePath: executablePath,
          updater: updaterFor(
            currentVersion: currentVersion,
            currentBuildTag: currentBuildTag,
          ),
        );

    test('`dvm update --alpha` installs the alpha and names both builds',
        () async {
      publishBothChannels();

      expect(
          await runDvm(['update', '--alpha'],
              currentBuildTag: 'alpha.g$installedCommit'),
          0);
      expect(
        out.toString(),
        contains('Updated dvm 0.1.0+alpha.gc0687e6 -> alpha (0ad7aad)'),
      );
      expect(fs.file(executablePath).readAsStringSync(), 'the alpha binary');
    });

    test('`dvm update --alpha` on the newest alpha says so and stops',
        () async {
      publishBothChannels();

      expect(
          await runDvm(['update', '--alpha'],
              currentBuildTag: 'alpha.g0ad7aad'),
          0);
      expect(
        out.toString(),
        contains('dvm 0.1.0+alpha.g0ad7aad is already the newest alpha.'),
      );
      expect(
        fs.file(executablePath).readAsStringSync(),
        'the running dvm binary',
      );
    });

    test(
        '`dvm update` on an alpha names both ways out instead of saying '
        'everything is fine', () async {
      publishBothChannels();

      expect(
        await runDvm(['update'], currentBuildTag: 'alpha.g$installedCommit'),
        0,
      );
      expect(out.toString(), isNot(contains('up to date')));
      expect(out.toString(), contains('is an ALPHA build'));
      expect(out.toString(), contains('dvm update --alpha'));
      expect(out.toString(), contains('dvm update --stable'));
      expect(
        fs.file(executablePath).readAsStringSync(),
        'the running dvm binary',
      );
    });

    test('`dvm update --stable` says the alpha channel was left', () async {
      publishBothChannels();

      expect(
        await runDvm(['update', '--stable'],
            currentBuildTag: 'alpha.g$installedCommit'),
        0,
      );
      expect(out.toString(), contains('no longer on the alpha channel'));
      expect(fs.file(executablePath).readAsStringSync(), 'the release binary');
    });

    test('`dvm update --check --alpha` installs nothing and says how to',
        () async {
      publishBothChannels();

      expect(
        await runDvm(['update', '--check', '--alpha'],
            currentBuildTag: 'alpha.g$installedCommit'),
        0,
      );
      expect(out.toString(), contains('A newer dvm alpha is available'));
      expect(out.toString(), contains('Run `dvm update --alpha`'));
      expect(
        fs.file(executablePath).readAsStringSync(),
        'the running dvm binary',
      );
    });

    test('--alpha with a version is refused, naming both', () async {
      publishBothChannels();

      expect(await runDvm(['update', '--alpha', '0.1.0']), 1);
      expect(err.toString(), contains('two different things'));
      expect(err.toString(), contains('--alpha'));
      expect(err.toString(), contains('0.1.0'));
      expect(
        fs.file(executablePath).readAsStringSync(),
        'the running dvm binary',
      );
    });

    test('--alpha with --stable is a usage error', () async {
      expect(await runDvm(['update', '--alpha', '--stable']), usageExitCode);
      expect(err.toString(), contains('two different channels'));
    });

    test('`dvm doctor` says an alpha is an alpha, and how to leave', () async {
      // The exit code is not the subject: this filesystem has no shims and no
      // PATH, so doctor has plenty else to fail on. The build line is what is
      // being asserted, and it is the first thing printed.
      await runDvm(['doctor'], currentBuildTag: 'alpha.g0ad7aad');
      expect(out.toString(), contains('warn  build:'));
      expect(out.toString(), contains('0.1.0+alpha.g0ad7aad is an ALPHA'));
      expect(out.toString(), contains('dvm update --stable'));
    });
  });
}

Uint8List _zip({String contents = 'a new dvm binary'}) =>
    fakeReleaseZip(contents: contents);

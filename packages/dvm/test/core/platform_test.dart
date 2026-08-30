import 'package:dvm/dvm.dart';
import 'package:test/test.dart';

/// Shaped exactly like the real `Platform.version`.
String versionString(String os, String arch) =>
    '3.13.2 (stable) (Tue Aug 25 01:01:12 2026 -0700) on "${os}_$arch"';

void main() {
  group('HostPlatform.detect', () {
    test('reads the os and arch out of the Dart version string', () {
      final platform = HostPlatform.detect(versionString('macos', 'arm64'));

      expect(platform.os, 'macos');
      expect(platform.arch, 'arm64');
      expect(platform.archiveFileName, 'dartsdk-macos-arm64-release.zip');
      expect(
        platform.checksumFileName,
        'dartsdk-macos-arm64-release.zip.sha256sum',
      );
    });

    test('handles every published combination', () {
      const combinations = {
        'macos': ['x64', 'arm64'],
        'linux': ['x64', 'arm64', 'arm', 'riscv64'],
        'windows': ['x64', 'arm64'],
      };
      for (final entry in combinations.entries) {
        for (final arch in entry.value) {
          final platform = HostPlatform.detect(
            versionString(entry.key, arch),
          );
          expect(platform.isPublished, isTrue, reason: '$platform');
          expect(
            platform.archiveFileName,
            'dartsdk-${entry.key}-$arch-release.zip',
          );
        }
      }
    });

    test('strips the compressed-pointer suffix Dart reports', () {
      expect(
          HostPlatform.detect(versionString('linux', 'arm64c')).arch, 'arm64');
      expect(HostPlatform.detect(versionString('linux', 'x64c')).arch, 'x64');
    });

    test('detect itself does not throw on an unpublished host', () {
      // dvm --help and dvm doctor must still run somewhere dvm cannot install.
      final platform = HostPlatform.detect(versionString('macos', 'riscv64'));

      expect(platform.isPublished, isFalse);
    });

    test('asking for the archive on an unpublished host says what exists', () {
      final platform = HostPlatform.detect(versionString('linux', 'ia32'));

      expect(
        () => platform.archiveFileName,
        throwsA(
          isA<UnsupportedPlatformException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('linux/ia32'),
              contains('linux x64/arm64/arm/riscv64'),
            ),
          ),
        ),
      );
    });

    test('arm and riscv64 are linux-only', () {
      expect(
        HostPlatform.detect(versionString('macos', 'arm')).isPublished,
        isFalse,
      );
      expect(
        HostPlatform.detect(versionString('windows', 'riscv64')).isPublished,
        isFalse,
      );
    });

    test('detectSupported fails up front instead', () {
      expect(
        () => HostPlatform.detectSupported(versionString('macos', 'riscv64')),
        throwsA(isA<UnsupportedPlatformException>()),
      );
      expect(
        HostPlatform.detectSupported(versionString('macos', 'arm64')).arch,
        'arm64',
      );
    });

    test('an unparseable version string says so rather than guessing', () {
      expect(
        () => HostPlatform.detect('some other build of dart'),
        throwsA(
          isA<UnsupportedPlatformException>().having(
            (e) => e.message,
            'message',
            contains('does not end in'),
          ),
        ),
      );
    });
  });

  group('Channel', () {
    test('parses the three channel names and nothing else', () {
      expect(Channel.tryParse('stable'), Channel.stable);
      expect(Channel.tryParse('beta'), Channel.beta);
      expect(Channel.tryParse('dev'), Channel.dev);
      expect(Channel.tryParse('3.9.0'), isNull);
      expect(Channel.tryParse('work'), isNull);
      expect(Channel.tryParse('Stable'), isNull);
    });

    test('probes stable, then beta, then dev', () {
      expect(Channel.probeOrder, [Channel.stable, Channel.beta, Channel.dev]);
    });
  });
}

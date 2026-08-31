import 'dart:io';

import 'package:dvm/dvm.dart';
import 'package:test/test.dart';

/// The version this build reports has to be the one the release is cut at.
///
/// Three files carry it and all three have to agree: `pubspec.yaml`'s
/// `version:`, `kVersion` in `lib/src/gen/version.dart`, and the `v*` tag the
/// release workflow runs on. The workflow refuses a tag that disagrees with
/// the pubspec (`tool/stamp_version.sh`); this test catches the same drift on
/// a laptop, before anyone tags anything.
void main() {
  test('kVersion matches the version in pubspec.yaml', () {
    // `dart test` runs with the package root as the working directory.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match =
        RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec);

    expect(match, isNotNull, reason: 'pubspec.yaml has no version:');
    expect(
      kVersion,
      match!.group(1),
      reason: 'lib/src/gen/version.dart and pubspec.yaml disagree. '
          'Change both, or let tool/stamp_version.sh do it.',
    );
  });

  test('the CLI reports kVersion', () {
    expect(version(), kVersion);
  });

  // The other half of the same guarantee. `tool/stamp_build_tag.sh` writes this
  // constant during the ALPHA build only, and a stamped copy committed by
  // accident would make every ordinary build — and every release — report
  // `0.1.0+alpha.<somebody's commit>` from then on.
  test('kBuildTag is empty in the checkout', () {
    expect(
      kBuildTag,
      isEmpty,
      reason: 'lib/src/gen/version.dart carries a stamped kBuildTag. Only the '
          'alpha build stamps it, and it must never be committed: a release '
          'would then report itself as an alpha.',
    );
  });

  // buildVersion rather than version(), because kBuildTag is committed empty:
  // a test calling version() can only ever exercise the release half, and the
  // alpha half is the half nothing else in the suite reaches.
  test('buildVersion appends a build tag as semver build metadata', () {
    expect(buildVersion('0.1.0', 'alpha.g1a2b3c4'), '0.1.0+alpha.g1a2b3c4');
  });

  test('buildVersion leaves a version with no build tag alone', () {
    expect(buildVersion('0.1.0', ''), '0.1.0');
  });
}

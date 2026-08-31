import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file/file.dart';
import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';

import '../archive/sdk_extractor.dart';
import '../gen/version.dart';
import 'exceptions.dart';
import 'paths.dart';
import 'platform.dart';

/// The GitHub repository dvm publishes its own releases from.
const String releaseRepository = 'mrgnhnt96/dvm';

/// The rolling prerelease tag `.github/workflows/alpha.yml` publishes `main`
/// under. One tag, deleted and recreated on every push, so it always names the
/// newest commit and never names an older one — see that file's header for why
/// it is not a tag per commit.
const String alphaReleaseTag = 'alpha';

/// The build-metadata prefix `tool/stamp_build_tag.sh` stamps an alpha with:
/// `alpha.g<short sha>`, which `buildVersion` turns into the `+alpha.g1a2b3c4`
/// a user sees in `dvm --version`.
const String alphaBuildTagPrefix = 'alpha.g';

/// A git object name, abbreviated or whole. Seven is what `git rev-parse
/// --short=7` produces and what alpha.yml stamps; anything shorter is a
/// collision waiting to be mistaken for an identity.
final RegExp _commitPattern = RegExp(r'^[0-9a-f]{7,40}$');

/// Whether [a] and [b] name the same commit, either of them abbreviated.
///
/// A git abbreviation is a prefix of the whole sha, so a prefix match in either
/// direction is the whole comparison. **This, and not a version comparison, is
/// how the alpha channel decides whether there is anything to install** — see
/// [Updater.currentCommit].
///
/// Anything that is not a plausible object name answers false. Two unknowns are
/// not evidence of sameness, and "could not tell" must not read as "up to date".
bool sameCommit(String a, String b) {
  final left = a.toLowerCase();
  final right = b.toLowerCase();
  if (!_commitPattern.hasMatch(left) || !_commitPattern.hasMatch(right)) {
    return false;
  }
  return left.length < right.length
      ? right.startsWith(left)
      : left.startsWith(right);
}

/// [commit] abbreviated the way alpha.yml names it, for output.
String shortCommit(String commit) =>
    commit.length <= 7 ? commit : commit.substring(0, 7);

/// The name of the release asset carrying the binary for [platform].
///
/// **THIS IS A CONTRACT, NOT A DETAIL.** Three places construct this name and
/// they must agree forever: this function, `install.sh`, and
/// `tool/package_release_assets.sh` (which is what actually creates the file).
/// Renaming an asset breaks `dvm update` for every copy already installed —
/// those binaries are already compiled with the old name in them and cannot be
/// told otherwise. See ARCHITECTURE.md, "Distribution".
///
/// Throws [UnsupportedPlatformException] for a host dvm has no build for. Note
/// that this is a *narrower* set than [HostPlatform.publishedArchitectures]:
/// Dart publishes an SDK for linux/arm and linux/riscv64, dvm does not publish
/// a binary for them, so such a host can run dvm built from source but cannot
/// install or update it from a release.
String releaseAssetName(HostPlatform platform) {
  const supported = {
    'linux-x64',
    'linux-arm64',
    'macos-x64',
    'macos-arm64',
    'windows-x64',
  };
  final target = '${platform.os}-${platform.arch}';
  if (!supported.contains(target)) {
    throw UnsupportedPlatformException(
      'dvm does not publish a binary for $target. Released binaries are: '
      '${supported.join(', ')}. You can still build dvm from source with '
      '`dart compile exe bin/dvm.dart`.',
    );
  }
  return 'dvm-$target.zip';
}

/// The sha256 published beside [assetName]. Its body is `<hex>  <filename>`,
/// the format `sha256sum` and `shasum -a 256` both write and read.
String checksumAssetName(String assetName) => '$assetName.sha256';

/// The bare executable inside a release asset.
String executableNameFor(HostPlatform platform) =>
    platform.os == 'windows' ? 'dvm.exe' : 'dvm';

/// Something went wrong updating dvm itself.
class UpdateException extends DvmException {
  const UpdateException(super.message);
}

/// One published dvm release, reduced to what the updater needs.
class DvmRelease {
  const DvmRelease({
    required this.tag,
    required this.version,
    required this.assets,
    this.isPrerelease = false,
    this.commit,
  });

  /// The git tag, e.g. `v0.2.0` — or [alphaReleaseTag], which is not a version
  /// at all.
  final String tag;

  /// [tag] without its leading `v`, e.g. `0.2.0`. For a tag that is not a
  /// version this is the tag itself, so the alpha's is `alpha`.
  final String version;

  /// Asset name -> where to download it from.
  final Map<String, Uri> assets;

  /// Whether GitHub flags this as a prerelease. The stable channel never
  /// resolves to one and the alpha channel resolves to nothing else.
  final bool isPrerelease;

  /// The commit this release was built from, when it names one, lower-cased
  /// and possibly abbreviated. Null when nothing in the API response says.
  ///
  /// This is the alpha channel's whole basis for "is there something newer?" —
  /// see [Updater.currentCommit] for why a version comparison cannot be.
  final String? commit;

  /// How this release is named in output: a version for a release, and the tag
  /// plus its commit for the rolling alpha, whose tag is not a version and
  /// whose only identity is the commit it was built from.
  String get label {
    final at = commit;
    if (at == null || version != alphaReleaseTag) return version;
    return '$version (${shortCommit(at)})';
  }

  /// The download URL for [name], or null if this release does not carry it.
  Uri? assetUrl(String name) => assets[name];
}

/// What an update run concluded.
enum UpdateStatus {
  /// Already on what was asked for. Nothing was touched.
  upToDate,

  /// Something to install was found and deliberately not installed — `--check`.
  available,

  /// The binary on disk was replaced.
  installed,

  /// Running an alpha that no stable release is ahead of, so a bare
  /// `dvm update` has nowhere to go that is not a downgrade. Nothing was
  /// touched, and the caller names the two ways out.
  ///
  /// This is the case a plain update used to report as "already up to date":
  /// an alpha's version IS the release it was cut from, so the two compare
  /// equal while the codebases are dozens of commits apart.
  alphaAheadOfStable,
}

/// Which published dvm an update run is asking for.
///
/// Per invocation and never persisted. A stored channel would silently change
/// what a later bare `dvm update` does, months after anyone remembers setting
/// it; `dvm --version` and `dvm doctor` say which build is running instead.
enum UpdateChannel {
  /// Whatever is newest and is a step forward — a bare `dvm update`. It never
  /// moves backwards, and it never leaves the alpha channel on its own for a
  /// release that is not actually ahead.
  newest,

  /// The newest stable release, taken even when it is not a step forward —
  /// `--stable`, and the only way off an alpha. An alpha's version compares
  /// EQUAL to the release it was cut from, so nothing that asks "is the
  /// release newer?" can ever move it.
  stable,

  /// The newest published prerelease — `--alpha`, the rolling latest `main`.
  alpha,
}

/// What [Updater.update] did.
class UpdateOutcome {
  const UpdateOutcome({
    required this.from,
    required this.to,
    required this.status,
  });

  /// The version that was running, as the binary REPORTS it — so an alpha's
  /// `+alpha.g<sha>` is in here rather than the bare version it was cut from.
  final String from;

  /// What was resolved: a version, or `alpha (<sha>)` for the rolling alpha.
  final String to;

  final UpdateStatus status;

  /// Whether the binary on disk was replaced. False for `--check` and for an
  /// update that turned out to be a no-op.
  bool get installed => status == UpdateStatus.installed;

  bool get isUpToDate => status == UpdateStatus.upToDate;
}

/// dvm's view of its own GitHub releases: what is newest, and how to become it.
///
/// Modelled on zonai's `Versions` (`apps/zonai/lib/src/domain/versions.dart`),
/// which is the same job in a shipped tool. The deliberate differences are
/// commented where they occur; the biggest is that this one verifies the
/// asset's published sha256 before writing anything.
class Updater {
  Updater({
    required this.fileSystem,
    required HostPlatform Function() hostPlatform,
    required Map<String, String> environment,
    this.isCompiled = kIsCompiled,
    this.currentVersion = kVersion,
    this.currentBuildTag = kBuildTag,
    http.Client? httpClient,
    Uri? apiBase,
    ModeApplier? modeApplier,
  })  : _hostPlatform = hostPlatform,
        _environment = environment,
        _injectedHttp = httpClient,
        _apiBase = apiBase ?? defaultApiBase,
        _modeApplier = modeApplier ?? const ChmodModeApplier();

  /// The GitHub API root for [releaseRepository]. Trailing slash on purpose so
  /// `resolve('releases')` appends rather than replaces the last segment.
  static final Uri defaultApiBase =
      Uri.parse('https://api.github.com/repos/$releaseRepository/');

  final FileSystem fileSystem;

  /// Whether this is a release build. Everything that touches the network or
  /// the installed binary refuses when it is false — see [kIsCompiled].
  final bool isCompiled;

  /// The version this build reports, normally [kVersion].
  final String currentVersion;

  /// What this build is beyond its version, normally [kBuildTag]. Empty for
  /// every ordinary build; `alpha.g<short sha>` for one built by alpha.yml.
  final String currentBuildTag;

  /// The version this build reports on the command line, build tag included.
  ///
  /// The `from` of every [UpdateOutcome], because the bare [currentVersion] of
  /// an alpha is the release it was cut from and printing that would hide the
  /// fact that an alpha was replaced at all.
  String get reportedVersion => buildVersion(currentVersion, currentBuildTag);

  /// The commit this build was made from, or null when it is not an alpha.
  ///
  /// **THE ALPHA CHANNEL'S ORDERING PROBLEM, AND WHY THIS EXISTS.** An alpha
  /// reports `<version>+alpha.g<sha>`, and semver ignores build metadata for
  /// precedence: `0.1.0+alpha.gc0687e6` and `0.1.0+alpha.g0ad7aad` compare
  /// EQUAL to each other and to the `0.1.0` they were both cut from, however
  /// many commits apart they are. So `--alpha` cannot ask "is the published
  /// one greater than mine?" — the answer is no, forever, and the run reports
  /// "up to date" while doing nothing.
  ///
  /// It asks an IDENTITY question instead: is the published alpha a DIFFERENT
  /// commit from the one I was built from? Both sides carry that: this side in
  /// the build tag `tool/stamp_build_tag.sh` stamped, and the published side in
  /// [DvmRelease.commit]. [sameCommit] compares them.
  String? get currentCommit => currentBuildTag.startsWith(alphaBuildTagPrefix)
      ? currentBuildTag.substring(alphaBuildTagPrefix.length).toLowerCase()
      : null;

  /// Whether this build came from the alpha channel rather than a release.
  bool get isAlphaBuild => currentCommit != null;

  final HostPlatform Function() _hostPlatform;
  final Map<String, String> _environment;
  final http.Client? _injectedHttp;
  final Uri _apiBase;
  final ModeApplier _modeApplier;

  /// Built on first use, never at construction: `DvmContext.wire` makes an
  /// [Updater] on every single `dvm` invocation, including the `dvm exec dart`
  /// that the PATH shim runs, and that path is not allowed to pay for
  /// anything it does not use.
  late final http.Client _http = _injectedHttp ?? http.Client();

  /// Releases newest-first, matching what a `dvm update` would install.
  ///
  /// **Not `/releases/latest`.** GitHub's "latest" is simply the newest
  /// non-draft non-prerelease release of *any* kind, so the day this repo
  /// publishes a release for something other than the CLI, "latest" becomes a
  /// release with no `dvm-<os>-<arch>.zip` in it — the update check then
  /// reports a new version that `dvm update` cannot install. That is not
  /// hypothetical: it happened to zonai on 2026-08-10 (see the comment on its
  /// `_fetchLatestRelease`). Scanning instead, and requiring *this platform's
  /// asset to actually be present*, makes the answer true by construction.
  Future<DvmRelease> latestRelease() async {
    final assetName = releaseAssetName(_hostPlatform());
    final body = await _getJson(_apiBase.resolve('releases?per_page=100'));
    if (body is! List) {
      throw const UpdateException(
        'GitHub did not return a list of releases for dvm.',
      );
    }

    for (final entry in body) {
      final release = _parseRelease(entry);
      if (release == null) continue;
      if (release.assetUrl(assetName) == null) continue;
      return release;
    }

    throw UpdateException(
      'No published dvm release carries a $assetName. Looked at the '
      '${body.length} most recent releases of $releaseRepository.',
    );
  }

  /// The newest published PRERELEASE carrying this platform's asset.
  ///
  /// A SECOND PATH, NOT A WIDER FIRST ONE. [latestRelease] drops the alpha
  /// twice over — once on the `prerelease` flag and once because the tag is
  /// `alpha` rather than `v<x>.<y>.<z>` — and neither filter is relaxed by this
  /// existing. They are inverted here, for this path only, so the stable
  /// channel stays structurally unable to wander onto unreleased code.
  ///
  /// A WHITELIST WITH NO FALLBACK, exactly as `install.sh`'s `pick_tag` does
  /// it: when there is no prerelease this throws rather than handing back the
  /// newest release. `--alpha` asks for `main`, and installing something else
  /// underneath a success message answers a different question.
  Future<DvmRelease> latestAlphaRelease() async {
    final assetName = releaseAssetName(_hostPlatform());
    final body = await _getJson(_apiBase.resolve('releases?per_page=100'));
    if (body is! List) {
      throw const UpdateException(
        'GitHub did not return a list of releases for dvm.',
      );
    }

    for (final entry in body) {
      if (entry is! Map<String, Object?>) continue;
      // Spelled out here rather than folded into a flag on [_parseRelease]:
      // this pair of lines is the whitelist, and it is what makes an `--alpha`
      // run unable to resolve to a release. A draft is nobody's release.
      if (entry['draft'] == true) continue;
      if (entry['prerelease'] != true) continue;

      final release = _parseRelease(
        entry,
        allowPrerelease: true,
        requireVersionTag: false,
      );
      if (release == null) continue;
      if (release.assetUrl(assetName) == null) continue;
      return release;
    }

    throw UpdateException(
      'No published dvm PRERELEASE carries a $assetName, and --alpha installs '
      'nothing else.\n'
      'The newest stable release was deliberately NOT taken in its place: '
      '--alpha asks for the latest main. Run `dvm update` for a release.\n'
      'Check https://github.com/$releaseRepository/releases — if prereleases '
      'are listed there, this is usually the API rate limit; set GITHUB_TOKEN '
      'and try again.',
    );
  }

  /// The release tagged `v[version]`, whatever its position in the list.
  Future<DvmRelease> releaseForVersion(String version) async {
    final tag = version.startsWith('v') ? version : 'v$version';
    final body = await _getJson(_apiBase.resolve('releases/tags/$tag'));
    final release = _parseRelease(body, allowPrerelease: true);
    if (release == null) {
      throw UpdateException('$releaseRepository has no release tagged $tag.');
    }
    return release;
  }

  /// Whether [candidate] is a later release than the one running.
  ///
  /// Semver, not string comparison: `0.13.0` is newer than `0.9.0` and sorts
  /// below it as text. A development build (`0.1.0-dev`) is older than the
  /// release of the same number, which is what makes the notice fire the first
  /// time a real `0.1.0` is published.
  bool isNewerThanCurrent(String candidate) {
    try {
      return Version.parse(candidate) > Version.parse(currentVersion);
    } on FormatException {
      // A tag neither side can parse is not evidence of anything.
      return false;
    }
  }

  /// Downloads and installs a dvm release over [executablePath].
  ///
  /// With [check] the release is only resolved and reported — nothing is
  /// downloaded and nothing on disk is touched. [version] pins an explicit
  /// release instead of taking the newest one, which is how a user gets back
  /// off a bad release. [channel] chooses which published thing is newest; see
  /// [UpdateChannel].
  Future<UpdateOutcome> update({
    required String executablePath,
    String? version,
    bool check = false,
    UpdateChannel channel = UpdateChannel.newest,
  }) async {
    if (!isCompiled) {
      throw const UpdateException(
        'dvm is running from source, so there is no installed binary to '
        'replace. Update the checkout with git instead.',
      );
    }

    // REFUSED RATHER THAN RANKED, the way install.sh refuses `--alpha` with
    // DVM_VERSION: honouring one and dropping the other is a coin toss between
    // two different installs, and whichever way it lands the user is told the
    // update succeeded. `dvm update --stable 0.1.4` is NOT this case — both of
    // those name a stable release and they agree.
    if (channel == UpdateChannel.alpha && version != null) {
      throw UpdateException(
        '--alpha and an explicit version ask for two different things.\n'
        '  $version names one exact release tag.\n'
        '  --alpha asks for whichever prerelease is newest, which is the '
        'rolling `$alphaReleaseTag` tag and never a version.\n'
        'Nothing was installed. Drop one of them:\n'
        '  the newest alpha:  dvm update --alpha\n'
        '  exactly $version:  dvm update $version',
      );
    }

    if (channel == UpdateChannel.alpha) {
      return _updateToAlpha(executablePath: executablePath, check: check);
    }

    final release = version == null
        ? await latestRelease()
        : await releaseForVersion(version);

    // AN ALPHA CANNOT BE LEFT BY ACCIDENT. Its version IS the release it was
    // cut from, so on a bare `dvm update` the equality below would read as
    // "already up to date" (the old behaviour, which stranded the user) and
    // anything looser would silently replace unreleased work with an older
    // codebase. Only a release that is genuinely AHEAD is a step forward; when
    // it is not, nothing is touched and the caller names the two ways out.
    if (isAlphaBuild &&
        version == null &&
        channel == UpdateChannel.newest &&
        !isNewerThanCurrent(release.version)) {
      return UpdateOutcome(
        from: reportedVersion,
        to: release.version,
        status: UpdateStatus.alphaAheadOfStable,
      );
    }

    // An explicit version is allowed to go backwards; the automatic path is
    // not. Someone typing `dvm update 0.1.4` after a bad 0.1.5 means it.
    //
    // Against [reportedVersion], not [currentVersion]: `0.1.0` and
    // `0.1.0+alpha.g0ad7aad` are different builds, and a `--stable` run from
    // the second to the first is a real install rather than a no-op.
    if (release.version == reportedVersion) {
      return UpdateOutcome(
        from: reportedVersion,
        to: release.version,
        status: UpdateStatus.upToDate,
      );
    }
    if (check) {
      return UpdateOutcome(
        from: reportedVersion,
        to: release.version,
        status: UpdateStatus.available,
      );
    }

    await _installRelease(release: release, executablePath: executablePath);

    return UpdateOutcome(
      from: reportedVersion,
      to: release.version,
      status: UpdateStatus.installed,
    );
  }

  /// The `--alpha` half of [update]: move to the newest published alpha.
  ///
  /// The decision here is an IDENTITY comparison and deliberately not a version
  /// one — [currentCommit] says why at length. In short: every alpha of a given
  /// release compares semver-EQUAL to every other, so "is the published one
  /// newer?" answers no forever.
  Future<UpdateOutcome> _updateToAlpha({
    required String executablePath,
    required bool check,
  }) async {
    final release = await latestAlphaRelease();
    final running = currentCommit;
    final published = release.commit;

    // Both sides have to be known. A published alpha that names no commit, or
    // a build with no alpha stamp on it, is a "could not tell" — and reporting
    // that as "up to date" is exactly the failure this channel exists to fix,
    // so it falls through and installs.
    if (running != null &&
        published != null &&
        sameCommit(running, published)) {
      return UpdateOutcome(
        from: reportedVersion,
        to: release.label,
        status: UpdateStatus.upToDate,
      );
    }

    if (check) {
      return UpdateOutcome(
        from: reportedVersion,
        to: release.label,
        status: UpdateStatus.available,
      );
    }

    await _installRelease(release: release, executablePath: executablePath);

    return UpdateOutcome(
      from: reportedVersion,
      to: release.label,
      status: UpdateStatus.installed,
    );
  }

  /// Downloads [release]'s asset for this platform, verifies its published
  /// sha256, and puts it in place. Shared by both channels: an alpha is
  /// packaged by the same script as a release and is installed no differently.
  Future<void> _installRelease({
    required DvmRelease release,
    required String executablePath,
  }) async {
    final platform = _hostPlatform();
    final assetName = releaseAssetName(platform);
    final assetUrl = release.assetUrl(assetName);
    if (assetUrl == null) {
      throw UpdateException(
        'Release ${release.tag} has no $assetName, so there is no dvm binary '
        'in it for ${platform.os}-${platform.arch}.',
      );
    }

    final expected = await _publishedChecksum(release, assetName);
    final bytes = await _download(assetUrl, assetName);

    final actual = sha256.convert(bytes).toString();
    if (actual != expected) {
      // Nothing has been written at this point, and nothing will be. Say so:
      // the one thing a user needs to know here is that their working dvm is
      // still their working dvm.
      throw UpdateException(
        'The download of $assetName does not match the sha256 published with '
        'it.\n'
        '  expected: $expected\n'
        '  actual:   $actual\n'
        'dvm was NOT updated and the binary you are running is untouched. '
        'This is either a corrupted download or a tampered-with asset.',
      );
    }

    await _install(
      executablePath: executablePath,
      zipBytes: bytes,
      platform: platform,
    );
  }

  /// Releases the HTTP client. Safe to call when nothing was ever fetched.
  ///
  /// `IOClient.close()` closes the underlying `HttpClient` with `force: true`,
  /// which aborts in-flight requests instead of waiting for them. That is
  /// exactly what [VersionCheck] needs: without it, a hung request would keep
  /// the VM alive after the command it was checking for had finished.
  void close() {
    if (_injectedHttp != null) return;
    _http.close();
  }

  /// The sha256 published as a sibling asset.
  ///
  /// zonai does not do this at all — it trusts the TLS connection to GitHub.
  /// A version manager replaces the binary that every `dart` invocation on the
  /// machine goes through, so the extra round trip buys enough: the checksum
  /// is generated on the runner beside the binary and a mismatch means the two
  /// assets did not come from the same build.
  Future<String> _publishedChecksum(
    DvmRelease release,
    String assetName,
  ) async {
    final name = checksumAssetName(assetName);
    final url = release.assetUrl(name);
    if (url == null) {
      throw UpdateException(
        'Release ${release.tag} has no $name, so the download of $assetName '
        'cannot be verified. Refusing to install it.',
      );
    }

    final body = utf8.decode(await _download(url, name));
    final parts = body.trim().split(RegExp(r'\s+'));
    if (parts.length < 2 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(parts.first)) {
      throw UpdateException(
        '$name is not in the expected `<hex>  <filename>` form, so dvm '
        'cannot verify the download.',
      );
    }
    // A checksum naming a different asset would otherwise fail below as a
    // mismatch, which reads like corruption rather than a broken release.
    final named = parts[1].replaceFirst(RegExp(r'^\*'), '');
    if (named != assetName) {
      throw UpdateException(
        '$name is a checksum for "$named", not for "$assetName".',
      );
    }
    return parts.first;
  }

  /// Replaces the binary at [executablePath] with the one inside [zipBytes].
  Future<void> _install({
    required String executablePath,
    required Uint8List zipBytes,
    required HostPlatform platform,
  }) async {
    final entry = _executableEntry(zipBytes, platform);

    final executable = fileSystem.file(executablePath);
    final directory = executable.parent;
    final base = fileSystem.path.basename(executablePath);
    final incoming = fileSystem.file(
      fileSystem.path.join(directory.path, '$base.new'),
    );

    incoming.writeAsBytesSync(entry, flush: true);
    // Before the rename, so that whatever lands at [executablePath] is
    // runnable the instant it is there. Windows has no unix modes; there
    // executability comes from the extension.
    if (platform.os != 'windows') {
      await _modeApplier.apply({incoming.path: 0x1ED});
    }

    if (platform.os == 'windows') {
      await _installWindows(executable, incoming, directory, base);
      return;
    }

    // On POSIX this is all it takes, and the reason is the inode: `rename`
    // unlinks the old directory entry but the running process still holds the
    // old inode open, so replacing the binary underneath a running dvm is
    // safe. zonai renames the old one aside first as well; that only leaves a
    // `.old` file behind for nobody to clean up.
    incoming.renameSync(executable.path);
  }

  /// The Windows half of [_install].
  ///
  /// Windows refuses to *delete or overwrite* a running `.exe`, but it will
  /// happily *rename* one — the file stays mapped under its new name. So the
  /// running binary is moved aside and the new one takes its place; the
  /// leftover is deleted on a later run, once nothing has it open.
  Future<void> _installWindows(
    File executable,
    File incoming,
    Directory directory,
    String base,
  ) async {
    final aside = fileSystem.file(
      fileSystem.path.join(directory.path, '$base.old'),
    );

    // A leftover from the previous update. It is deletable now precisely
    // because the process that was running it has exited.
    if (aside.existsSync()) {
      try {
        aside.deleteSync();
      } on FileSystemException {
        // Still held by something. Not fatal: the rename below overwrites it.
      }
    }

    try {
      if (executable.existsSync()) executable.renameSync(aside.path);
      incoming.renameSync(executable.path);
    } on FileSystemException catch (error) {
      // Loudly, and with the old binary's whereabouts, rather than leaving
      // someone with a version manager that is half-installed.
      throw UpdateException(
        'Could not replace ${executable.path}: ${error.osError?.message ?? error.message}.\n'
        'The new binary is at ${incoming.path} and the previous one may be at '
        '${aside.path}. Close any running dvm and move it into place by hand.',
      );
    }
  }

  /// The dvm executable inside a release zip.
  Uint8List _executableEntry(Uint8List zipBytes, HostPlatform platform) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } on Object catch (error) {
      throw UpdateException('The release asset is not a readable zip: $error');
    }

    final wanted = executableNameFor(platform);
    for (final file in archive) {
      if (!file.isFile) continue;
      // Basename: the asset is flat by construction (see
      // tool/package_release_assets.sh), and taking the basename anyway stops
      // a nested entry from deciding where anything goes.
      if (fileSystem.path.basename(file.name) != wanted) continue;
      final bytes = file.readBytes();
      if (bytes == null || bytes.isEmpty) break;
      return Uint8List.fromList(bytes);
    }

    throw UpdateException(
      'The release asset does not contain a $wanted, so there is nothing to '
      'install from it.',
    );
  }

  Future<Uint8List> _download(Uri url, String what) async {
    final http.Response response;
    try {
      response = await _http.get(url, headers: _headers);
    } on http.ClientException catch (error) {
      throw UpdateException('Could not download $what: ${error.message}');
    }
    if (response.statusCode != 200) {
      throw UpdateException(
        'GitHub returned HTTP ${response.statusCode} for $what ($url).',
      );
    }
    return response.bodyBytes;
  }

  Future<Object?> _getJson(Uri url) async {
    final http.Response response;
    try {
      response = await _http.get(url, headers: _headers);
    } on http.ClientException catch (error) {
      throw UpdateException('Could not reach $url: ${error.message}');
    }
    if (response.statusCode != 200) {
      throw UpdateException(
        'GitHub returned HTTP ${response.statusCode} for $url.'
        '${response.statusCode == 403 ? ' This is usually the unauthenticated '
            'rate limit; set GITHUB_TOKEN and try again.' : ''}',
      );
    }
    try {
      return json.decode(response.body);
    } on FormatException catch (error) {
      throw UpdateException('$url did not return JSON: ${error.message}');
    }
  }

  /// A token is optional — dvm's repo is public. It is used when present
  /// because the unauthenticated API allows only 60 requests an hour per IP,
  /// which CI shares across every job on the runner.
  Map<String, String> get _headers {
    final token = _environment['GITHUB_TOKEN'] ?? _environment['GH_TOKEN'];
    return {
      'Accept': 'application/vnd.github+json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// A release object from the API, or null when it is not a dvm CLI release.
  ///
  /// [requireVersionTag] is the second of the two filters the stable channel
  /// relies on, and it stays on by default: a release scan that accepted any
  /// tag would resolve to the rolling `alpha`. Only [latestAlphaRelease] turns
  /// it off, because the alpha's tag is a channel name and not a version.
  DvmRelease? _parseRelease(
    Object? entry, {
    bool allowPrerelease = false,
    bool requireVersionTag = true,
  }) {
    if (entry is! Map<String, Object?>) return null;
    final isPrerelease = entry['prerelease'] == true;
    if (!allowPrerelease && (entry['draft'] == true || isPrerelease)) {
      return null;
    }

    final tag = entry['tag_name'];
    if (tag is! String) return null;
    final isVersionTag = RegExp(r'^v\d+\.\d+\.\d+').hasMatch(tag);
    if (requireVersionTag && !isVersionTag) return null;

    final assets = <String, Uri>{};
    final listed = entry['assets'];
    if (listed is List) {
      for (final asset in listed) {
        if (asset is! Map<String, Object?>) continue;
        final name = asset['name'];
        final url = asset['browser_download_url'] ?? asset['url'];
        if (name is! String || url is! String) continue;
        assets[name] = Uri.parse(url);
      }
    }

    return DvmRelease(
      tag: tag,
      // A tag that is not a version is its own name: the alpha's `version` is
      // `alpha`. Stripping a leading `v` unconditionally would make it `lpha`.
      version: isVersionTag ? tag.substring(1) : tag,
      assets: assets,
      isPrerelease: isPrerelease,
      commit: _commitOf(entry),
    );
  }

  /// The commit a release names, or null when nothing in it does.
  ///
  /// `target_commitish` FIRST, because for the rolling alpha it is the real
  /// thing: alpha.yml deletes the old tag and recreates the release with
  /// `--target "${GITHUB_SHA}"`, so GitHub stores and returns the full 40-hex
  /// sha of the commit that was actually built. Verified against the live
  /// `alpha` release, which returns
  /// `0ad7aad29d7ded5c35383f58fea42d637fad39d4`.
  ///
  /// It is only believed when it LOOKS like an object name, because that field
  /// is not always one: for a release created against an existing tag GitHub
  /// returns the branch, and `main` is not a commit. The release TITLE is the
  /// fallback — alpha.yml writes it as `dvm alpha (<short sha>)` — so the
  /// answer survives a change in how the release is cut.
  static String? _commitOf(Map<String, Object?> entry) {
    final target = entry['target_commitish'];
    if (target is String && _commitPattern.hasMatch(target.toLowerCase())) {
      return target.toLowerCase();
    }

    final title = entry['name'];
    if (title is String) {
      final match = RegExp(r'\(([0-9a-fA-F]{7,40})\)').firstMatch(title);
      if (match != null) return match.group(1)!.toLowerCase();
    }

    return null;
  }
}

/// The one-line "a newer dvm exists" notice ordinary commands print.
///
/// The hard requirement is that this NEVER blocks, slows or fails a command:
/// `dvm dart test` runs through the PATH shim on every keystroke-driven
/// rebuild, and a version notice that costs a network round trip there would
/// be a latency bug, not a feature. Three things make that true:
///
///  * a cache, so the network is touched at most once per [cacheTtl];
///  * [start] fires the request *beside* the command instead of before it, so
///    a slow command absorbs the check entirely;
///  * [report] waits only [reportBudget] for an answer and then closes the
///    client outright, so a hung request cannot delay the process exiting.
///
/// Every failure is swallowed. Being unable to check is not news.
class VersionCheck {
  VersionCheck({
    required this.updater,
    required this.paths,
    required this.out,
    this.enabled = true,
    this.cacheTtl = const Duration(hours: 24),
    this.networkTimeout = const Duration(milliseconds: 1500),
    this.reportBudget = const Duration(milliseconds: 400),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Updater updater;
  final DvmPaths paths;
  final StringSink out;

  /// False when `--no-version-check` was passed.
  final bool enabled;

  /// How long a recorded answer is reused before the network is consulted.
  /// A day-old notice is still a useful notice; a per-invocation round trip
  /// is not an acceptable price for a fresher one.
  final Duration cacheTtl;

  final Duration networkTimeout;
  final Duration reportBudget;
  final DateTime Function() _now;

  Future<String?>? _pending;

  /// The recorded answer, written even when the check failed so that an
  /// offline machine does not retry on every invocation.
  File get cacheFile => paths.fileSystem.file(paths.fileSystem.path.join(
        paths.cacheDir.path,
        'update-check.json',
      ));

  /// Begins the check. Returns immediately; nothing is awaited here.
  void start() {
    if (!enabled || !updater.isCompiled) return;
    _pending = _check().timeout(networkTimeout, onTimeout: () => null);
  }

  /// Prints the notice if an answer arrived in time. Never throws.
  Future<void> report() async {
    final pending = _pending;
    if (pending == null) return;

    // `timeout`, not a race against `Future.delayed`. Both give up after the
    // budget, but the delayed future stays pending when it LOSES, and a live
    // timer keeps the VM alive until it fires — measured at +0.4s on every
    // invocation, including cache hits that answered instantly. `timeout`
    // cancels its timer the moment the future completes.
    final latest = await pending.timeout(reportBudget, onTimeout: () => null);
    // Unconditional, and force-closing: if the budget expired, the request is
    // still in flight and would otherwise hold the process open on its own.
    updater.close();

    if (latest == null) return;
    out.writeln(
      'A new version of dvm is available: ${updater.currentVersion} -> '
      '$latest. Run `dvm update` to install it.',
    );
  }

  /// The newer version, or null for "no news, or could not tell".
  ///
  /// The cache records the newest PUBLISHED version rather than the verdict,
  /// so the comparison happens fresh every time. Storing the verdict instead
  /// would keep announcing an update for a day after it was installed.
  Future<String?> _check() async {
    try {
      final String? latest;
      // A fresh entry answers even when its answer is "the check failed":
      // that is what stops an offline machine retrying on every invocation.
      if (_readCache() case final cached?) {
        latest = cached.value;
      } else {
        // Stamped BEFORE the request, not only after it. [report] gives up
        // after [reportBudget] and the process then exits with the request
        // still in flight, so an answer that arrives late is never recorded —
        // and without this line a machine on a slow link pays the budget on
        // every single invocation, forever. Recording the attempt first caps
        // that at one invocation per TTL. A fast answer overwrites it below.
        _writeCache(null);
        latest = (await updater.latestRelease()).version;
        _writeCache(latest);
      }

      if (latest == null) return null;
      return updater.isNewerThanCurrent(latest) ? latest : null;
    } on Object {
      // Deliberately everything, including [DvmException] and whatever the
      // socket layer throws. A failed check is not an event a user asked for.
      try {
        _writeCache(null);
      } on Object {
        // A read-only or missing cache directory is not news either.
      }
      return null;
    }
  }

  _CachedAnswer? _readCache() {
    final file = cacheFile;
    if (!file.existsSync()) return null;

    final decoded = json.decode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) return null;

    final checkedAt = decoded['checkedAt'];
    if (checkedAt is! int) return null;
    final age = _now().difference(
      DateTime.fromMillisecondsSinceEpoch(checkedAt),
    );
    // A negative age means the clock moved backwards; treat it as stale
    // rather than trusting a stamp from the future forever.
    if (age.isNegative || age > cacheTtl) return null;

    final latest = decoded['latest'];
    // `null` is a recorded failure: fresh enough not to retry, but with no
    // answer in it, so the caller treats it as a miss with no network.
    return latest is String ? _CachedAnswer(latest) : const _CachedAnswer(null);
  }

  void _writeCache(String? latest) {
    // ~/.dvm/cache is documented as safe to delete at any time, which is
    // exactly the right home for this: losing it costs one extra request.
    paths.cacheDir.createSync(recursive: true);
    cacheFile.writeAsStringSync(
      json.encode({
        'checkedAt': _now().millisecondsSinceEpoch,
        'latest': latest,
      }),
    );
  }
}

class _CachedAnswer {
  const _CachedAnswer(this.value);

  /// The newer version recorded last time, or null for "there was none".
  final String? value;
}

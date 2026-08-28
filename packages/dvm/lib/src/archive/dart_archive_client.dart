import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';

import '../core/channel.dart';
import '../core/platform.dart';
import '../core/releases.dart';
import 'dart_archive_exception.dart';

/// The [ReleaseClient] for the `dart-archive` Google Cloud Storage bucket.
///
/// Two base URLs, because the bucket answers on two different services: object
/// bytes come from the storage host directly, while listing what is in a
/// channel needs the JSON API. Both are injectable so tests can point the whole
/// client at a local [HttpServer] instead of the network.
class DartArchiveClient implements ReleaseClient {
  DartArchiveClient({
    http.Client? httpClient,
    Uri? objectBase,
    Uri? listApi,
  })  : _injectedHttp = httpClient,
        _objectBase = objectBase ?? defaultObjectBase,
        _listApi = listApi ?? defaultListApi;

  /// Where `channels/<channel>/release/...` objects are served from.
  static final Uri defaultObjectBase =
      Uri.parse('https://storage.googleapis.com/dart-archive/');

  /// The GCS JSON API endpoint that enumerates a channel's release prefixes.
  static final Uri defaultListApi =
      Uri.parse('https://storage.googleapis.com/storage/v1/b/dart-archive/o');

  final http.Client? _injectedHttp;
  final Uri _objectBase;
  final Uri _listApi;

  /// Built on first use, not at construction. `DvmContext.wire` makes one of
  /// these on every `dvm` invocation, including the `dvm exec dart` the PATH
  /// shim runs, and that path is not allowed to pay for anything it does not
  /// use.
  late final http.Client _http = _injectedHttp ?? http.Client();

  @override
  Future<List<String>> listReleases(Channel channel) async {
    final prefix = 'channels/${channel.token}/release/';
    final url = _listApi.replace(
      queryParameters: <String, String>{
        'delimiter': '/',
        'prefix': prefix,
        'fields': 'prefixes',
      },
    );

    final body = await _getJson(url, 'the list of $channel releases');
    final prefixes = body['prefixes'];
    // An empty bucket listing omits `prefixes` entirely rather than sending an
    // empty list, so a missing key is "no releases", not a malformed response.
    if (prefixes == null) return const [];
    if (prefixes is! List) {
      throw DartArchiveException(
        '$url returned a "prefixes" that is not a list. The Dart archive is '
        'not answering the way dvm expects.',
      );
    }

    // Sorting semantically rather than lexically is the whole point: as strings
    // "3.9.0" sorts above "3.13.0", which would offer the user a two-year-old
    // SDK as the newest one.
    final versions = <Version>[];
    for (final entry in prefixes) {
      if (entry is! String) continue;
      final token = _tokenFromPrefix(entry, prefix);
      if (token == null) continue;
      // Drops `latest` and the ~28 Dart 1 build-number prefixes (`29803`),
      // which are not versions dvm can install.
      final version = tryParseRelease(token);
      if (version != null) versions.add(version);
    }

    versions.sort((a, b) => b.compareTo(a));
    return [for (final version in versions) version.toString()];
  }

  @override
  Future<String> latestVersion(Channel channel) async {
    final url = _objectUri('channels/${channel.token}/release/latest/VERSION');
    final body = await _getJson(url, 'the latest $channel version');
    final version = body['version'];
    if (version is! String || version.isEmpty) {
      throw DartArchiveException(
        '$url did not name a version. The Dart archive is not answering the '
        'way dvm expects.',
      );
    }
    return version;
  }

  @override
  Future<Channel> channelFor(String version) async {
    for (final channel in Channel.probeOrder) {
      final url = _objectUri(
        'channels/${channel.token}/release/$version/VERSION',
      );
      final response = await _get(url, 'Dart $version');
      if (response.statusCode == 200) return channel;
      if (response.statusCode != 404) {
        throw DartArchiveException(
            _httpFailure(url, response, 'Dart $version'));
      }
    }
    throw DartArchiveException(
      'Dart $version is not published in any channel '
      '(${Channel.probeOrder.map((c) => c.token).join(', ')}). '
      'Run `dvm list-remote` to see what is available.',
    );
  }

  @override
  ReleaseArtifact artifactFor({
    required Channel channel,
    required String version,
    required HostPlatform platform,
  }) {
    final fileName = platform.archiveFileName;
    final path = 'channels/${channel.token}/release/$version/sdk/$fileName';
    return ReleaseArtifact(
      version: version,
      fileName: fileName,
      archive: _objectUri(path),
      checksum: _objectUri('$path.sha256sum'),
    );
  }

  Uri _objectUri(String path) => _objectBase.resolve(path);

  /// The directory name inside a `channels/<c>/release/` prefix, or null if
  /// [entry] is not one.
  String? _tokenFromPrefix(String entry, String prefix) {
    if (!entry.startsWith(prefix)) return null;
    final token = entry.substring(prefix.length);
    return token.endsWith('/') ? token.substring(0, token.length - 1) : token;
  }

  Future<Map<String, Object?>> _getJson(Uri url, String what) async {
    final response = await _get(url, what);
    if (response.statusCode != 200) {
      throw DartArchiveException(_httpFailure(url, response, what));
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error) {
      throw DartArchiveException(
        'The Dart archive returned something that is not JSON when asked for '
        '$what: ${error.message}',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw DartArchiveException(
        'The Dart archive returned an unexpected response when asked for '
        '$what.',
      );
    }
    return decoded;
  }

  Future<http.Response> _get(Uri url, String what) async {
    try {
      return await _http.get(url);
    } on http.ClientException catch (error) {
      throw DartArchiveException(
        'Could not reach the Dart archive to look up $what: ${error.message}',
      );
    }
  }

  String _httpFailure(Uri url, http.Response response, String what) =>
      'The Dart archive returned HTTP ${response.statusCode} when asked for '
      '$what ($url).';
}

/// [token] as a version, or null when it is not one dvm can install.
///
/// The bucket carries a `latest` alias and ~28 Dart 1 build numbers (`29803`,
/// `41096`, …) alongside real releases. Neither has the `major.minor.patch`
/// shape, so a strict parse is the filter — no hand-maintained deny list to
/// fall out of date.
Version? tryParseRelease(String token) {
  try {
    return Version.parse(token);
  } on FormatException {
    return null;
  }
}

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file/file.dart';
import 'package:http/http.dart' as http;

import '../core/releases.dart';
import 'dart_archive_exception.dart';

/// Streams an SDK archive to disk and proves it arrived intact.
///
/// The bytes are hashed as they stream past rather than by re-reading the file
/// afterwards: these archives are ~225MB, and neither buffering one in memory
/// nor reading it twice is free.
class SdkDownloader {
  SdkDownloader({
    required this.fileSystem,
    required StringSink progress,
    bool progressIsTerminal = false,
    http.Client? httpClient,
  })  : _injectedHttp = httpClient,
        _progress = progress,
        _progressIsTerminal = progressIsTerminal;

  final FileSystem fileSystem;
  final StringSink _progress;

  /// Whether [_progress] is a terminal a human is watching.
  ///
  /// Defaults to false because that is the shape that survives being read by
  /// something other than a person; the composition root is the only place
  /// that can honestly answer this.
  final bool _progressIsTerminal;

  final http.Client? _injectedHttp;

  /// Built on first use; see [DartArchiveClient] for why that matters.
  late final http.Client _http = _injectedHttp ?? http.Client();

  /// Downloads [artifact] to [destination] and verifies its sha256.
  ///
  /// Throws [DartArchiveException] and deletes [destination] if the checksum does
  /// not match, so a corrupted or tampered archive is never handed on to be
  /// extracted.
  Future<void> download(ReleaseArtifact artifact, File destination) async {
    final expected = await _expectedChecksum(artifact);

    destination.parent.createSync(recursive: true);
    final actual = await _streamToFile(artifact.archive, destination);

    if (actual != expected) {
      // Deleting here rather than leaving it for the caller means the bad
      // bytes cannot be picked up by a later run that only checks existence.
      if (destination.existsSync()) destination.deleteSync();
      throw DartArchiveException(
        'The download of ${artifact.fileName} does not match its published '
        'sha256 checksum.\n'
        '  expected: $expected\n'
        '  actual:   $actual\n'
        'Nothing was installed. This is either a corrupted download or a '
        'tampered-with archive; run the install again.',
      );
    }
  }

  /// The hex sha256 the archive is published with.
  ///
  /// The body is `<hex> *<filename>`; the filename is checked too, because a
  /// checksum for a different platform's archive would otherwise fail later
  /// with a mismatch that reads like corruption.
  Future<String> _expectedChecksum(ReleaseArtifact artifact) async {
    final http.Response response;
    try {
      response = await _http.get(artifact.checksum);
    } on http.ClientException catch (error) {
      throw DartArchiveException(
        'Could not fetch the checksum for ${artifact.fileName}: '
        '${error.message}',
      );
    }
    if (response.statusCode != 200) {
      throw DartArchiveException(
        'The Dart archive returned HTTP ${response.statusCode} for the '
        'checksum of ${artifact.fileName} (${artifact.checksum}).',
      );
    }

    final parts = response.body.trim().split(RegExp(r'\s+'));
    if (parts.length < 2 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(parts.first)) {
      throw DartArchiveException(
        '${artifact.checksum} is not in the expected `<hex> *<filename>` '
        'form, so dvm cannot verify the download.',
      );
    }
    final named = parts[1].replaceFirst(RegExp(r'^\*'), '');
    if (named != artifact.fileName) {
      throw DartArchiveException(
        '${artifact.checksum} is a checksum for "$named", not for '
        '"${artifact.fileName}".',
      );
    }
    return parts.first;
  }

  /// Writes [url] into [destination], returning the hex sha256 of what arrived.
  Future<String> _streamToFile(Uri url, File destination) async {
    final http.StreamedResponse response;
    try {
      response = await _http.send(http.Request('GET', url));
    } on http.ClientException catch (error) {
      throw DartArchiveException(
        'Could not download $url: ${error.message}',
      );
    }
    if (response.statusCode != 200) {
      throw DartArchiveException(
        'The Dart archive returned HTTP ${response.statusCode} for $url.',
      );
    }

    final total = response.contentLength;
    final bar = _ProgressBar(
      sink: _progress,
      label: destination.basename,
      total: total,
      isTerminal: _progressIsTerminal,
    );

    Digest? digest;
    final hasher = sha256.startChunkedConversion(
      ChunkedConversionSink<Digest>.withCallback(
        (digests) => digest = digests.single,
      ),
    );

    final sink = destination.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        hasher.add(chunk);
        sink.add(chunk);
        received += chunk.length;
        bar.update(received);
      }
    } finally {
      await sink.close();
      hasher.close();
      bar.finish(received);
    }

    // startChunkedConversion's callback fires on close, which the finally
    // block above always reaches.
    return digest!.toString();
  }
}

/// Download progress, in whichever of two shapes the sink can read.
///
/// A terminal gets one line repainted with `\r`: a 225MB download is thousands
/// of chunks, and a scrollback full of percentages is worse than no progress at
/// all. Anything else — a redirected file, a CI log — gets discrete
/// newline-terminated lines every [_stepPercent]%, because a carriage return
/// there does not repaint anything: it concatenates all 101 states into a
/// single unreadable ~20KB line.
class _ProgressBar {
  _ProgressBar({
    required this.sink,
    required this.label,
    required this.total,
    required this.isTerminal,
  });

  final StringSink sink;
  final String label;
  final int? total;
  final bool isTerminal;

  /// How far the download has to move before a non-terminal sink is told
  /// again. Eleven lines describe a download; a thousand bury the log.
  static const int _stepPercent = 10;

  int _lastPercent = -1;

  void update(int received) {
    if (total == null || total == 0) return;
    final percent = _percentOf(received);

    if (isTerminal) {
      if (percent == _lastPercent) return;
      _lastPercent = percent;
      sink.write('\r${_line(received, percent)}');
      return;
    }

    // The first update always prints, so a log says a download started even if
    // it is then interrupted.
    if (_lastPercent >= 0 && percent - _lastPercent < _stepPercent) return;
    _lastPercent = percent;
    sink.writeln(_line(received, percent));
  }

  void finish(int received) {
    if (total == null || total == 0) {
      sink.writeln('  $label  ${_mb(received)} MB');
      return;
    }

    if (isTerminal) {
      update(received);
      // Ends the line the repaints have been rewriting, so whatever prints
      // next starts on its own.
      sink.writeln();
      return;
    }

    // The throttle must not be what decides whether the log records that the
    // download completed, so the last line is written regardless of step.
    final percent = _percentOf(received);
    if (percent == _lastPercent) return;
    _lastPercent = percent;
    sink.writeln(_line(received, percent));
  }

  int _percentOf(int received) => (received * 100 ~/ total!).clamp(0, 100);

  String _line(int received, int percent) =>
      '  $label  $percent%  (${_mb(received)} / ${_mb(total!)} MB)';

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
}

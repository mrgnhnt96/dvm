/// Builds the real site, then serves the built output at `/` and loads pages
/// out of it.
///
/// The second half is the point of this file. The site is published at
/// `https://dvm.mrgnhnt.com`, a GitHub Pages site on its own REPO-level custom
/// domain, so the site owns the domain root and every route hangs directly off
/// `/`. That is exactly what jaspr's static build emits: `<base href="/">` and
/// root-absolute references. The failure mode this site has is a **silent
/// 404**: a page builds, the HTML is intact, and a link simply does not
/// resolve — the build stays green and only a reader finds out.
///
/// Nothing short of actually serving the output and fetching what the pages
/// point at catches that, which is why this test builds and serves rather than
/// asserting over constants. It reads the references out of the served HTML, so
/// a reference this test has never heard of is still checked.
///
/// Both halves share one build, in one file, on purpose: `dart test` runs
/// separate files concurrently, and two `jaspr build` runs in the same
/// directory would fight over `build/` and `.dart_tool/`.
@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final buildDir = Directory('build/jaspr');
  var homePage = '';

  setUpAll(() async {
    // A full `jaspr build`, not `dart run build_runner build`: server-side
    // pre-rendering is a separate phase that can fail in ways build_runner
    // alone never exercises, and it is the phase that emits every page.
    //
    // `--port`, not the default: the "Preparing static rendering" phase starts
    // a real server and walks the route table against it. The default 8080 is
    // a busy port on a development machine, and a build that gets some other
    // server's 404 reports `Failed to generate route "/"` — which reads as a
    // broken site rather than as a taken port.
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();

    final result = await Process.run('dart', [
      'run',
      'jaspr_cli:jaspr',
      'build',
      '--port',
      '$port',
    ], workingDirectory: Directory.current.path);

    expect(result.exitCode, 0, reason: 'stdout:\n${result.stdout}\n\nstderr:\n${result.stderr}');
    homePage = File('${buildDir.path}/index.html').readAsStringSync();
  });

  group('the build', () {
    test('emits every page in the sidebar', () {
      // One `<route>/index.html` per content page, plus the root. A build that
      // silently stopped pre-rendering would leave the directories empty.
      for (final route in _routesFromContent()) {
        final page = route == '/' ? '${buildDir.path}/index.html' : '${buildDir.path}$route/index.html';
        expect(File(page).existsSync(), isTrue, reason: '$route did not reach the build output');
      }
    });

    test('copies web/ assets, which are copied rather than generated', () {
      final logo = File('${buildDir.path}/images/logo.svg');
      expect(logo.existsSync(), isTrue, reason: 'web/images/logo.svg did not reach the build output');
      expect(logo.readAsStringSync(), File('web/images/logo.svg').readAsStringSync());
    });

    // Establishes that the build's own output is already what the deployed
    // host needs, so the artifact is uploaded exactly as jaspr emits it. If
    // jaspr ever starts emitting something other than a domain root — a
    // relative base, or a configurable prefix — this test is the one that says
    // so, and the deploy pipeline is what would have to answer for it.
    test('emits a domain root, which is what the site is served from', () {
      expect(homePage, contains('<base href="/"/>'));
      expect(homePage, contains('href="/commands/install"'));
    });
  });

  group('served at the domain root', () {
    HttpServer? server;
    late Uri origin;

    setUpAll(() async {
      final started = await _serve(buildDir);
      server = started;
      origin = Uri.parse('http://${started.address.host}:${started.port}');
    });

    // Nullable, not `late`: if the setup above fails, `late` turns the teardown
    // into a second, louder LateInitializationError that buries the real one.
    tearDownAll(() => server?.close(force: true));

    test('the home page loads', () async {
      final response = await _get(origin.resolve('/'));
      expect(response.status, 200);
      expect(response.body, contains('<base href="/"/>'));
    });

    test('a path with no file behind it is a 404 — the server is real', () async {
      // If this ever returned 200, the server under test would answer anything
      // and every reference below would "resolve" no matter how broken it was.
      expect((await _get(origin.resolve('/no/such/page/'))).status, 404);
    });

    // The two kinds of page that fail differently. The home page catches a
    // broken root; a NESTED page catches a broken `<base>`, because that is
    // where a relative `src="main.client.dart.js"` would resolve to the wrong
    // directory rather than merely the wrong root.
    for (final route in const ['/', '/commands/install', '/guides/troubleshooting']) {
      test('every reference on $route resolves', () async {
        final url = origin.resolve(route == '/' ? '/' : '$route/');
        final page = await _get(url);
        expect(page.status, 200, reason: '$url did not load');

        final references = _referencesIn(page.body);
        expect(references, isNotEmpty, reason: 'no references found on $route — is the page empty?');

        final broken = <String>[];
        for (final reference in references) {
          // Resolved against the page's own URL and its <base>, exactly as a
          // browser would, so a relative reference is checked from where the
          // browser would actually ask for it.
          final target = origin.resolve('/').resolve(reference);
          final response = await _get(target);
          if (response.status != 200) broken.add('$reference -> $target (${response.status})');
        }
        expect(broken, isEmpty, reason: 'unresolvable references on $route');
      });
    }

    // The three pages above are fetched in full; this sweeps the rest. Every
    // root-absolute reference on EVERY built page must have a file behind it,
    // so a page nobody thought to list here cannot ship a dangling link.
    test('every root-absolute reference on every built page has a file behind it', () async {
      final offenders = <String>[];
      final pattern = RegExp(r'(?:href|src)="(/[^"]*)"');

      for (final file in buildDir.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.html')) continue;
        for (final match in pattern.allMatches(file.readAsStringSync())) {
          final reference = match.group(1)!;
          // Protocol-relative URLs start with `//` and belong to another
          // origin; they are correctly left alone.
          if (reference.startsWith('//')) continue;
          final target = origin.resolve(reference.split('#').first);
          if ((await _get(target)).status != 200) {
            offenders.add('${file.path}: ${match.group(0)} -> $target');
          }
        }
      }

      expect(offenders, isEmpty);
    });
  });
}

/// Every route the `content/` tree produces, derived from the filesystem rather
/// than from `navigation.dart` — `navigation_test.dart` already checks that the
/// two agree, and deriving both from one source here would make this test
/// unable to notice a page that never got built.
List<String> _routesFromContent() {
  final routes = <String>[];
  for (final file in Directory('content').listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.md')) continue;
    var route = file.path.substring('content'.length).replaceFirst(RegExp(r'\.md$'), '');
    if (route == '/index') route = '/';
    routes.add(route);
  }
  return routes;
}

/// Every `href`/`src` on a page, minus the external and non-fetchable ones.
List<String> _referencesIn(String html) {
  final references = <String>{};
  for (final match in RegExp(r'(?:href|src)="([^"]*)"').allMatches(html)) {
    final value = match.group(1)!;
    if (value.isEmpty) continue;
    if (value.startsWith('#')) continue;
    if (value.startsWith('//')) continue;
    if (value.startsWith('http://') || value.startsWith('https://')) continue;
    if (value.startsWith('data:') || value.startsWith('mailto:')) continue;
    references.add(value.split('#').first);
  }
  return references.toList();
}

typedef _Response = ({int status, String body});

Future<_Response> _get(Uri url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return (status: response.statusCode, body: body);
  } finally {
    client.close(force: true);
  }
}

/// A static file server that mounts [directory] at `/`, the way GitHub Pages
/// serves a site on its own custom domain.
Future<HttpServer> _serve(Directory directory) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final root = directory.absolute.path;

  server.listen((request) async {
    var relative = request.uri.path;
    if (relative.isEmpty) relative = '/';

    // Pages answers a directory with its index.html. The slashless form gets a
    // 301 onto the slashed one; that redirect is not what this test is about,
    // so both spellings are served directly.
    final candidates = [
      '$root$relative',
      if (relative.endsWith('/')) '$root${relative}index.html' else '$root$relative/index.html',
    ];

    for (final candidate in candidates) {
      final file = File(candidate);
      if (!file.existsSync()) continue;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = _contentTypeFor(candidate);
      await request.response.addStream(file.openRead());
      await request.response.close();
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  });

  return server;
}

ContentType _contentTypeFor(String path) {
  if (path.endsWith('.html')) return ContentType.html;
  if (path.endsWith('.css')) return ContentType('text', 'css', charset: 'utf-8');
  if (path.endsWith('.js')) return ContentType('text', 'javascript', charset: 'utf-8');
  if (path.endsWith('.svg')) return ContentType('image', 'svg+xml', charset: 'utf-8');
  if (path.endsWith('.json')) return ContentType.json;
  return ContentType.binary;
}

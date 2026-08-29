/// Unit tests for `tool/rebase_static_site.dart`.
///
/// The end-to-end check — build the real site, serve it under `/dvm/`, and load
/// pages out of it — lives in `apps/docs/test/base_path_test.dart`. This file
/// covers the cases that are cheap here and awkward there: the things that must
/// NOT be rewritten, and idempotence.
library;

import 'dart:io';

import 'package:test/test.dart';

import '../tool/rebase_static_site.dart';

void main() {
  group('normalizePrefix', () {
    test('accepts every spelling of the same prefix', () {
      for (final raw in ['dvm', '/dvm', '/dvm/', ' /dvm//  ']) {
        expect(normalizePrefix(raw), '/dvm', reason: raw);
      }
    });

    test('an empty prefix stays empty', () {
      expect(normalizePrefix('/'), '');
      expect(normalizePrefix(''), '');
    });
  });

  group('rebaseUrl', () {
    test('prefixes root-absolute paths', () {
      expect(rebaseUrl('/', '/dvm'), '/dvm/');
      expect(rebaseUrl('/commands/install', '/dvm'), '/dvm/commands/install');
      expect(rebaseUrl('/images/logo.svg', '/dvm'), '/dvm/images/logo.svg');
      expect(rebaseUrl('/commands/which#rule-4', '/dvm'),
          '/dvm/commands/which#rule-4');
    });

    // Each of these is a way to break a page that looks identical to a
    // successful rewrite until someone clicks the link.
    test('leaves everything that is not a root-absolute path alone', () {
      const untouched = [
        'https://github.com/mrgnhnt96/dvm',
        'http://example.com/x',
        '//fonts.example.com/style.css',
        'data:image/svg+xml;base64,AAAA',
        'mailto:nobody@example.com',
        '#everything-else',
        'main.client.dart.js',
        '../sibling/page',
        '',
      ];
      for (final url in untouched) {
        expect(rebaseUrl(url, '/dvm'), isNull, reason: url);
      }
    });

    test('is idempotent — a second run changes nothing', () {
      expect(rebaseUrl('/dvm/commands/install', '/dvm'), isNull);
      expect(rebaseUrl('/dvm', '/dvm'), isNull);
      // …but a path that merely starts with the same letters is not the prefix.
      expect(rebaseUrl('/dvmrc-format', '/dvm'), '/dvm/dvmrc-format');
    });
  });

  group('rebaseHtml', () {
    test('rewrites the base tag, which is what makes relative refs resolve',
        () {
      expect(rebaseHtml('<base href="/"/>', '/dvm'), '<base href="/dvm/"/>');
    });

    test('rewrites href and src, and leaves external URLs', () {
      const html = '<a href="/versions/dvmrc">x</a>'
          '<img src="/images/logo.svg"/>'
          '<a href="https://github.com/mrgnhnt96/dvm">gh</a>';
      expect(
        rebaseHtml(html, '/dvm'),
        '<a href="/dvm/versions/dvmrc">x</a>'
        '<img src="/dvm/images/logo.svg"/>'
        '<a href="https://github.com/mrgnhnt96/dvm">gh</a>',
      );
    });

    test('leaves the relative client bundle alone — the base tag handles it',
        () {
      expect(
        rebaseHtml('<script src="main.client.dart.js"></script>', '/dvm'),
        '<script src="main.client.dart.js"></script>',
      );
    });

    // The reason this file scans tags instead of running one regex over the
    // document. These pages are documentation, and documentation quotes markup.
    test('does not touch attribute-shaped text in a code block', () {
      const html =
          '<pre><code>dvm which  # prints href="/not-a-link"</code></pre>';
      expect(rebaseHtml(html, '/dvm'), html);
    });

    test('does not touch comments', () {
      const html = '<!-- href="/versions/dvmrc" -->';
      expect(rebaseHtml(html, '/dvm'), html);
    });

    test('leaves non-URL attributes alone even when they look like paths', () {
      const html = '<div class="/x" data-route="/commands/install"></div>';
      expect(rebaseHtml(html, '/dvm'), html);
    });

    test('rewrites CSS inside a <style> element', () {
      expect(
        rebaseHtml(
            '<style>a{background:url("/images/logo.svg")}</style>', '/dvm'),
        '<style>a{background:url("/dvm/images/logo.svg")}</style>',
      );
    });

    test('leaves a <script> body alone', () {
      const html = '<script>var re = "/commands/install";</script>';
      expect(rebaseHtml(html, '/dvm'), html);
    });

    test('handles single-quoted attributes and srcset lists', () {
      expect(
          rebaseHtml("<img src='/a.png'/>", '/dvm'), "<img src='/dvm/a.png'/>");
      expect(
        rebaseHtml(
            '<img srcset="/a.png 1x, /b.png 2x, https://x/c.png 3x"/>', '/dvm'),
        '<img srcset="/dvm/a.png 1x, /dvm/b.png 2x, https://x/c.png 3x"/>',
      );
    });

    // Regression. `</style>` used to be treated as a style tag too, so the
    // search for the next `</style` found nothing and the whole rest of the
    // document was run through the CSS rules — which rewrite `url()` and
    // nothing else. Every link after the first stylesheet survived untouched,
    // on a page whose `<base>` had been corrected: it looked right and 404'd on
    // the first click. The real document has a `<style>` in its `<head>`, so
    // this affected literally every page.
    test('a closing </style> does not swallow the rest of the document', () {
      const html = '<head><style>a{color:red}</style></head>'
          '<body><a href="/commands/install">x</a><img src="/images/logo.svg"/></body>';
      expect(
        rebaseHtml(html, '/dvm'),
        '<head><style>a{color:red}</style></head>'
        '<body><a href="/dvm/commands/install">x</a><img src="/dvm/images/logo.svg"/></body>',
      );
    });

    test('a closing </script> does not swallow the rest of the document', () {
      const html =
          '<script src="app.js"></script><a href="/commands/install">x</a>';
      expect(rebaseHtml(html, '/dvm'),
          '<script src="app.js"></script><a href="/dvm/commands/install">x</a>');
    });

    test('running it twice is the same as running it once', () {
      const html =
          '<base href="/"/><a href="/versions/dvmrc">x</a><img src="/images/logo.svg"/>';
      final once = rebaseHtml(html, '/dvm');
      expect(rebaseHtml(once, '/dvm'), once);
    });
  });

  group('rebaseCss', () {
    test('rewrites url() values, quoted or not', () {
      expect(rebaseCss('a{background:url(/images/logo.svg)}', '/dvm'),
          'a{background:url(/dvm/images/logo.svg)}');
      expect(rebaseCss("a{background:url('/x.png')}", '/dvm'),
          "a{background:url('/dvm/x.png')}");
    });

    test('leaves data: and remote URLs alone', () {
      const css =
          'a{background:url(data:image/svg+xml;base64,AAAA)}b{background:url(https://x/y.png)}';
      expect(rebaseCss(css, '/dvm'), css);
    });
  });

  group('jsProblemsIn', () {
    test('flags a root-absolute reference to something the build emitted', () {
      final problems = jsProblemsIn('fetch("/images/logo.svg")',
          {'images', 'main.client.dart.js'}, '/dvm');
      expect(problems, hasLength(1));
      expect(problems.single, contains('/images/logo.svg'));
    });

    test('says nothing about strings that are not emitted paths', () {
      // A minified dart2js bundle is full of these; treating them as URLs is
      // exactly why this script does not rewrite JavaScript.
      const js = r'var re = /^\/(\d+)$/; var s = "/etc/hosts"; var t = "/";';
      expect(jsProblemsIn(js, {'images', 'packages'}, '/dvm'), isEmpty);
    });

    test('says nothing about a reference that already carries the prefix', () {
      expect(jsProblemsIn('fetch("/dvm/images/logo.svg")', {'images'}, '/dvm'),
          isEmpty);
    });
  });

  group('rebaseDirectory', () {
    late Directory temp;

    setUp(() =>
        temp = Directory.systemTemp.createTempSync('rebase_static_site_test'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('rewrites html and css in place, counts what it changed, skips js',
        () {
      File('${temp.path}/index.html')
          .writeAsStringSync('<base href="/"/><a href="/versions/dvmrc">x</a>');
      File('${temp.path}/style.css')
          .writeAsStringSync('a{background:url(/images/logo.svg)}');
      File('${temp.path}/app.js').writeAsStringSync('var x = "harmless";');
      Directory('${temp.path}/images').createSync();

      final report = rebaseDirectory(temp, 'dvm');

      expect(report.jsProblems, isEmpty);
      expect(report.references, 3);
      expect(report.rewritten, hasLength(2));
      expect(File('${temp.path}/index.html').readAsStringSync(),
          '<base href="/dvm/"/><a href="/dvm/versions/dvmrc">x</a>');
      expect(File('${temp.path}/style.css').readAsStringSync(),
          'a{background:url(/dvm/images/logo.svg)}');
      expect(File('${temp.path}/app.js').readAsStringSync(),
          'var x = "harmless";');
    });

    // A real build output is not all text. This tree ships
    // `packages/timezone/data/latest_all.tzf`, and reading it as UTF-8 throws.
    test('does not read files it has no business reading', () {
      File('${temp.path}/index.html').writeAsStringSync('<a href="/a">x</a>');
      File('${temp.path}/data.tzf')
          .writeAsBytesSync([0xff, 0xfe, 0x00, 0x80, 0x81]);
      Directory('${temp.path}/.dart_tool').createSync();
      File('${temp.path}/.dart_tool/binary.bin')
          .writeAsBytesSync([0xff, 0xfe, 0x00]);

      final report = rebaseDirectory(temp, '/dvm');

      expect(report.references, 1);
      expect(File('${temp.path}/data.tzf').readAsBytesSync(),
          [0xff, 0xfe, 0x00, 0x80, 0x81]);
    });

    test('reports a js reference that would 404 under the prefix', () {
      File('${temp.path}/index.html').writeAsStringSync('<a href="/x">x</a>');
      File('${temp.path}/app.js')
          .writeAsStringSync('fetch("/images/logo.svg")');
      Directory('${temp.path}/images').createSync();

      expect(rebaseDirectory(temp, '/dvm').jsProblems, hasLength(1));
    });

    // Scoped deliberately: `packages/` is build_runner's dev-mode tree, no page
    // loads any of it, and the dev-compiler stack-trace mappers in there carry
    // the literal `"/packages"` as a source-map prefix rather than a URL.
    test('only checks the JavaScript the site actually loads', () {
      File('${temp.path}/index.html').writeAsStringSync('<a href="/a">x</a>');
      File('${temp.path}/main.client.dart.js').writeAsStringSync('var x = 1;');
      Directory('${temp.path}/packages/build_web_compilers')
          .createSync(recursive: true);
      File('${temp.path}/packages/build_web_compilers/mapper.js')
          .writeAsStringSync('i="/packages"+q;');
      Directory('${temp.path}/images').createSync();

      expect(rebaseDirectory(temp, '/dvm').jsProblems, isEmpty);
    });

    test('a second run over its own output changes nothing', () {
      final page = File('${temp.path}/index.html')
        ..writeAsStringSync('<base href="/"/><a href="/a">x</a>');

      rebaseDirectory(temp, '/dvm');
      final after = page.readAsStringSync();
      final second = rebaseDirectory(temp, '/dvm');

      expect(page.readAsStringSync(), after);
      expect(second.rewritten, isEmpty);
      expect(second.references, 0);
    });
  });
}

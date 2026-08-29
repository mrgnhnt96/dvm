/// Rewrites a built Jaspr static site so it can be served from a path prefix.
///
/// ```sh
/// dart run tool/rebase_static_site.dart --prefix /dvm apps/docs/build/jaspr
/// ```
///
/// ## Why this exists
///
/// The docs site is published at `https://mrgnhnt96.github.io/dvm/`, a GitHub
/// Pages PROJECT site, so every URL on it lives under `/dvm/`.
///
/// Jaspr resolves its base path from the incoming request at runtime
/// (`ServerAppBinding.basePath` is `request.handlerPath`), which works when a
/// server is answering. A **static** build has no request: it pre-renders every
/// page against a local server mounted at the root, so it emits `<base href="/">`
/// and root-absolute references — `href="/versions/dvmrc"`, `src="/images/logo.svg"`.
/// Served under `/dvm/`, every one of those is a 404, and `jaspr build` has no
/// option to change it (`dart run jaspr_cli:jaspr build --help` offers `--input`,
/// `--target`, `--port`, `--optimize`, `--sitemap-domain` and friends, and
/// nothing about a base path).
///
/// So the prefix is applied afterwards, to the built output. The prefix is an
/// argument rather than a constant here because the fallback, if this ever
/// proves fragile, is a custom domain — which means deleting this script and
/// writing a `CNAME`, and that should stay a one-line change.
///
/// ## What is rewritten, and what deliberately is not
///
/// * **HTML** — URL-bearing attributes ([_urlAttributes]) *inside tags only*.
///   Text content is copied through untouched, so a documentation page that
///   quotes `href="/foo"` inside a code block is not silently edited.
/// * **CSS** — `url(...)` values, both in `.css` files and inside `<style>`
///   elements in HTML.
/// * **JavaScript** — nothing is rewritten. There is no syntactic marker in JS
///   that says "this string is a URL", so a blind rewrite of `"/..."` literals
///   would corrupt unrelated data in a minified `dart2js` bundle. Instead the
///   script *checks*: if a top-level `.js` file mentions a root-absolute path
///   that matches something the build actually emitted, it fails loudly rather
///   than shipping a silent 404. Jaspr's own client bundle loads its deferred
///   parts relative to `document.currentScript` and reads its base path from
///   the `<base>` element, so in practice there is nothing here to rewrite —
///   this check is what keeps that true.
///
///   The check is scoped to the **top level** of the build, which is where the
///   client entrypoint and its `.part.js` siblings live and the only JS any
///   page loads. `build/jaspr/packages/` is build_runner's dev-mode tree and is
///   referenced by nothing in a release build; scanning it produced two false
///   positives — the dev-compiler stack-trace mappers, which contain the
///   literal `"/packages"` as a *source map* path prefix rather than a URL.
///
/// A URL is left alone when it is relative, protocol-relative (`//host/x`),
/// absolute with a scheme (`https:`, `data:`, `mailto:`), a bare fragment, or
/// already carries the prefix. Rewriting is therefore idempotent.
///
/// The `<base href="/">` rewrite is load-bearing twice over: it is what makes
/// the relative `src="main.client.dart.js"` resolve, and jaspr's *client*
/// binding derives `basePath` from `document.baseURI` whenever a `<base>`
/// element is present.
library;

import 'dart:io';

/// Attributes whose value is a single URL.
///
/// `srcset` is handled separately — its value is a comma-separated list of
/// `url descriptor` pairs, not one URL.
const Set<String> _urlAttributes = {
  'href',
  'src',
  'poster',
  'action',
  'formaction',
  'manifest',
  'data',
};

/// File extensions rewritten as HTML.
const Set<String> _htmlExtensions = {'.html', '.htm'};

/// The result of a run, so `main` and the tests can assert on the same numbers.
class RebaseReport {
  RebaseReport();

  /// Files whose contents changed.
  final List<String> rewritten = [];

  /// How many individual references were prefixed.
  int references = 0;

  /// `file: offending text` for every root-absolute reference found in JS.
  final List<String> jsProblems = [];
}

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options == null) exit(64); // EX_USAGE

  final directory = Directory(options.directory);
  if (!directory.existsSync()) {
    stderr.writeln(
        'rebase_static_site: ${directory.path} does not exist. Build the site first.');
    exit(1);
  }

  final report = rebaseDirectory(directory, options.prefix);

  if (report.jsProblems.isNotEmpty) {
    stderr
      ..writeln(
        'rebase_static_site: ${report.jsProblems.length} root-absolute '
        'reference(s) in JavaScript, which this script cannot safely rewrite:',
      )
      ..writeln();
    for (final problem in report.jsProblems) {
      stderr.writeln('  $problem');
    }
    stderr.writeln(
      '\nThese would 404 under ${options.prefix}/. Make the code emit a '
      'relative URL, or resolve it against `document.baseURI`.',
    );
    exit(1);
  }

  stdout.writeln(
    'Rebased ${report.references} reference(s) onto ${options.prefix}/ '
    'across ${report.rewritten.length} file(s) in ${directory.path}.',
  );

  // A build that produced no references to rewrite is far more likely to be an
  // empty or wrong directory than a site with no links in it, and reporting
  // success for it is exactly how a silent 404 reaches production.
  if (report.references == 0) {
    stderr.writeln(
      'rebase_static_site: nothing was rewritten. Is ${directory.path} really '
      'a built site?',
    );
    exit(1);
  }
}

/// Rewrites every HTML, CSS and JS file under [directory] in place.
RebaseReport rebaseDirectory(Directory directory, String rawPrefix) {
  final prefix = normalizePrefix(rawPrefix);
  final report = RebaseReport();
  final topLevel = _topLevelEntries(directory);

  for (final entity in directory.listSync(recursive: true)) {
    if (entity is! File) continue;
    final path = entity.path;
    // Build bookkeeping — `.dart_tool`, `.build.manifest` — is not part of the
    // served site, and the deploy workflow deletes it anyway.
    if (_isHidden(path, directory.path)) continue;

    final extension = _extensionOf(path);
    final isTopLevel = _parentOf(path) == directory.path;
    // The extension check comes FIRST, and reading comes after. A build output
    // is full of files that are not text at all: this tree carries
    // `packages/timezone/data/latest_all.tzf`, and reading it as UTF-8 throws
    // `FileSystemException: Failed to decode data using encoding 'utf-8'` —
    // which crashed this script before the extension was ever consulted.
    if (extension == '.js') {
      if (isTopLevel) {
        report.jsProblems.addAll(
          jsProblemsIn(entity.readAsStringSync(), topLevel, prefix)
              .map((problem) => '$path: $problem'),
        );
      }
      continue;
    }
    if (!_htmlExtensions.contains(extension) && extension != '.css') continue;

    final original = entity.readAsStringSync();
    final rewritten = _htmlExtensions.contains(extension)
        ? rebaseHtml(original, prefix, report)
        : rebaseCss(original, prefix, report);

    if (rewritten != original) {
      entity.writeAsStringSync(rewritten);
      report.rewritten.add(path);
    }
  }

  return report;
}

/// `dvm`, `/dvm` and `/dvm/` all mean the same thing: a leading slash and no
/// trailing one, so `'$prefix$rootAbsolutePath'` is always well formed.
String normalizePrefix(String raw) {
  var prefix = raw.trim();
  while (prefix.endsWith('/')) {
    prefix = prefix.substring(0, prefix.length - 1);
  }
  if (prefix.isEmpty) return '';
  return prefix.startsWith('/') ? prefix : '/$prefix';
}

/// [url] with [prefix] applied, or null when it must be left exactly as it is.
///
/// Returning null rather than the unchanged string is what lets the callers
/// count real rewrites — a count of zero is treated as a failure, because an
/// empty or wrong directory produces one.
String? rebaseUrl(String url, String prefix) {
  if (prefix.isEmpty) return null;
  final trimmed = url.trim();
  // Not root-absolute: relative paths, `#anchor`, `https://…`, `data:…`,
  // `mailto:…` and the empty string all land here.
  if (!trimmed.startsWith('/')) return null;
  // Protocol-relative — `//fonts.example.com/x` is another origin entirely.
  if (trimmed.startsWith('//')) return null;
  // Already done. Makes the whole script idempotent, which matters because a
  // failed deploy is normally retried by re-running the same steps.
  if (trimmed == prefix || trimmed.startsWith('$prefix/')) return null;
  return '$prefix$trimmed';
}

/// A `srcset` value with every URL in it prefixed, or null if none changed.
String? rebaseSrcset(String value, String prefix) {
  var changed = false;
  final candidates = value.split(',');
  final rebased = [
    for (final candidate in candidates)
      () {
        final match =
            RegExp(r'^(\s*)(\S+)(.*)$', dotAll: true).firstMatch(candidate);
        if (match == null) return candidate;
        final url = rebaseUrl(match.group(2)!, prefix);
        if (url == null) return candidate;
        changed = true;
        return '${match.group(1)}$url${match.group(3)}';
      }(),
  ];
  return changed ? rebased.join(',') : null;
}

/// [html] with every URL-bearing attribute inside a tag prefixed.
///
/// Written as a scanner rather than one big regex because a regex over the
/// whole document cannot tell an attribute from prose: these pages are
/// documentation, and documentation quotes markup. Text nodes are copied
/// through byte for byte.
String rebaseHtml(String html, String prefix, [RebaseReport? report]) {
  final output = StringBuffer();
  var index = 0;

  while (index < html.length) {
    final open = html.indexOf('<', index);
    if (open < 0) {
      output.write(html.substring(index));
      break;
    }
    output.write(html.substring(index, open));

    // Comments and CDATA-ish constructs are copied whole: `<!-- href="/x" -->`
    // is not a reference.
    if (html.startsWith('<!--', open)) {
      final end = html.indexOf('-->', open);
      final stop = end < 0 ? html.length : end + 3;
      output.write(html.substring(open, stop));
      index = stop;
      continue;
    }

    final tagEnd = _endOfTag(html, open);
    if (tagEnd < 0) {
      // An unterminated `<` — a literal less-than in text. Copy and move on.
      output.write(html.substring(open, open + 1));
      index = open + 1;
      continue;
    }

    final tag = html.substring(open, tagEnd + 1);
    output.write(_rebaseTag(tag, prefix, report));
    index = tagEnd + 1;

    // A `<style>` body is CSS, not markup, so it is handed to the CSS rules
    // rather than scanned for attributes. `<script>` bodies fall to the JS
    // policy: left alone, and checked by `jsProblemsIn` when they are files.
    //
    // `!isClosing` is load-bearing. Without it, `</style>` is also seen as a
    // style tag, the search for the *next* `</style` finds nothing, and the
    // entire remainder of the document is passed through the CSS rules — which
    // rewrite `url()` and nothing else. The result is a page whose `<base>` was
    // corrected and whose every link was not: it looks rewritten and 404s on
    // the first click.
    final name = _tagName(tag);
    final isClosing = RegExp(r'^<\s*/').hasMatch(tag);
    if (!isClosing && (name == 'style' || name == 'script')) {
      final close = _indexOfCaseInsensitive(html, '</$name', index);
      final bodyEnd = close < 0 ? html.length : close;
      final body = html.substring(index, bodyEnd);
      output.write(name == 'style' ? rebaseCss(body, prefix, report) : body);
      index = bodyEnd;
    }
  }

  return output.toString();
}

/// [css] with every `url(...)` value prefixed.
String rebaseCss(String css, String prefix, [RebaseReport? report]) {
  return css.replaceAllMapped(RegExp(r'''url\(\s*(['"]?)([^'")]*)\1\s*\)'''),
      (match) {
    final quote = match.group(1)!;
    final rebased = rebaseUrl(match.group(2)!, prefix);
    if (rebased == null) return match.group(0)!;
    report?.references++;
    return 'url($quote$rebased$quote)';
  });
}

/// Root-absolute references in [js] that name something this build actually
/// emitted at its top level.
///
/// Deliberately narrow. A minified bundle is full of strings that start with a
/// slash and are not URLs (regular expressions, most of all), so the only
/// occurrences worth failing on are the ones that would resolve to a real file
/// today and to a 404 under the prefix.
List<String> jsProblemsIn(
    String js, Set<String> topLevelEntries, String prefix) {
  final problems = <String>[];
  for (final entry in topLevelEntries) {
    for (final quote in const ['"', "'", '`']) {
      final needle = '$quote/$entry';
      var at = js.indexOf(needle);
      while (at >= 0) {
        // `"/dvm/images/logo.svg"` is already correct, and a build that is
        // rerun over its own output must not report it.
        if (!js.startsWith('$quote$prefix/', at)) {
          final end = (at + needle.length + 40).clamp(0, js.length);
          problems.add(js.substring(at, end).replaceAll('\n', ' '));
        }
        at = js.indexOf(needle, at + 1);
      }
    }
  }
  return problems;
}

/// The names directly inside the build directory — `images`, `packages`,
/// `main.client.dart.js`, and so on. Dot-prefixed bookkeeping is skipped.
Set<String> _topLevelEntries(Directory directory) {
  return {
    for (final entity in directory.listSync())
      if (!_basename(entity.path).startsWith('.')) _basename(entity.path),
  };
}

/// One tag's text, with its URL attributes rewritten.
String _rebaseTag(String tag, String prefix, RebaseReport? report) {
  return tag.replaceAllMapped(
      RegExp('''([a-zA-Z-]+)(\\s*=\\s*)("([^"]*)"|'([^']*)')'''), (match) {
    final name = match.group(1)!.toLowerCase();
    final between = match.group(2)!;
    final quoted = match.group(3)!;
    final quote = quoted[0];
    final value = quoted.substring(1, quoted.length - 1);

    final String? rebased;
    if (name == 'srcset') {
      rebased = rebaseSrcset(value, prefix);
    } else if (_urlAttributes.contains(name)) {
      rebased = rebaseUrl(value, prefix);
    } else {
      rebased = null;
    }

    if (rebased == null) return match.group(0)!;
    report?.references++;
    return '${match.group(1)}$between$quote$rebased$quote';
  });
}

/// The index of the `>` that closes the tag starting at [open], honouring
/// quoted attribute values, or -1 when there is none.
int _endOfTag(String html, int open) {
  String? quote;
  for (var i = open + 1; i < html.length; i++) {
    final char = html[i];
    if (quote != null) {
      if (char == quote) quote = null;
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (char == '>') return i;
  }
  return -1;
}

/// `<a href=…>` -> `a`, `</div>` -> `div`, `<!doctype html>` -> `!doctype`.
String _tagName(String tag) {
  final match = RegExp(r'^<\s*/?\s*([^\s/>]+)').firstMatch(tag);
  return match == null ? '' : match.group(1)!.toLowerCase();
}

int _indexOfCaseInsensitive(String haystack, String needle, int from) {
  final at = haystack.toLowerCase().indexOf(needle.toLowerCase(), from);
  return at;
}

/// `build/jaspr/index.html` -> `build/jaspr`.
String _parentOf(String path) {
  final slash = path.lastIndexOf(Platform.pathSeparator);
  return slash < 0 ? '' : path.substring(0, slash);
}

/// Whether any path segment below [root] starts with a dot.
bool _isHidden(String path, String root) {
  final relative = path.startsWith(root) ? path.substring(root.length) : path;
  return relative
      .split(Platform.pathSeparator)
      .any((segment) => segment.startsWith('.'));
}

String _basename(String path) {
  final slash = path.lastIndexOf(Platform.pathSeparator);
  return slash < 0 ? path : path.substring(slash + 1);
}

String _extensionOf(String path) {
  final name = _basename(path);
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? '' : name.substring(dot).toLowerCase();
}

/// Parsed command line, or null when usage was printed instead.
class _Options {
  _Options({required this.prefix, required this.directory});

  final String prefix;
  final String directory;

  static const String _usage =
      'Usage: dart run tool/rebase_static_site.dart --prefix <path> <build directory>\n'
      '\n'
      '  --prefix   The path the site will be served under, e.g. /dvm.\n'
      '\n'
      'Rewrites root-absolute references in the built HTML and CSS so the site\n'
      'works when it is not served from a domain root.';

  static _Options? parse(List<String> args) {
    String? prefix;
    final rest = <String>[];

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--help' || arg == '-h') {
        stdout.writeln(_usage);
        return null;
      }
      if (arg == '--prefix') {
        if (i + 1 >= args.length) {
          stderr.writeln(
              'rebase_static_site: --prefix needs a value.\n\n$_usage');
          return null;
        }
        prefix = args[++i];
        continue;
      }
      if (arg.startsWith('--prefix=')) {
        prefix = arg.substring('--prefix='.length);
        continue;
      }
      rest.add(arg);
    }

    if (prefix == null || normalizePrefix(prefix).isEmpty) {
      stderr.writeln('rebase_static_site: --prefix is required.\n\n$_usage');
      return null;
    }
    if (rest.length != 1) {
      stderr.writeln(
          'rebase_static_site: name exactly one build directory.\n\n$_usage');
      return null;
    }

    return _Options(prefix: normalizePrefix(prefix), directory: rest.single);
  }
}

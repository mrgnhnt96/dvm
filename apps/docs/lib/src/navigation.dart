/// The single source of truth for the docs site's information architecture.
///
/// Consumed by `main.server.dart` to render the sidebar, the breadcrumbs and
/// the prev/next links at the foot of every page.
///
/// The sidebar is GENERATED from this table rather than written out by hand.
/// A hand-maintained sidebar drifts from `content/` silently: adding a page and
/// forgetting to list it fails nothing, builds fine, and leaves a page nobody
/// can reach. `test/navigation_test.dart` is what makes that impossible — every
/// file under `content/` must appear here or in [unlistedRoutes], and every
/// entry here must name a file that exists.
///
/// Keep [navigation] ordered as a reading path: someone who starts at the top
/// and works down should never hit a page that depends on one below it. That
/// order is also what the prev/next links walk.
///
/// Regroup here rather than moving markdown files — a page's URL comes from its
/// path under `content/`, so moving one breaks every inbound link for the sake
/// of a sidebar heading.
library;

/// A single page entry in the sidebar.
final class NavItem {
  const NavItem(this.title, this.href, {this.summary});

  /// Link text. Kept short — the sidebar column is about 17rem.
  final String title;

  /// Root-absolute route, e.g. `/commands/install`.
  ///
  /// The site owns its domain root, so a route written here is the path the
  /// browser actually requests. See `site.dart` for where that is decided.
  final String href;

  /// One-line description, shown on the landing page's cards.
  final String? summary;
}

/// A collapsible group of [NavItem]s in the sidebar.
final class NavGroup {
  const NavGroup(this.title, {required this.icon, required this.items, this.summary});

  /// The group heading, also used as the breadcrumb's second segment.
  final String title;

  /// Inline SVG markup rendered before [title]. See [NavIcons].
  final String icon;

  /// One-line description of what the group covers.
  final String? summary;

  final List<NavItem> items;
}

/// Pages that sit above the grouped navigation.
const List<NavItem> topLevelNavigation = [
  NavItem('Introduction', '/', summary: 'What dvm is, and how the pieces fit together.'),
];

/// The grouped sidebar navigation, in reading order.
const List<NavGroup> navigation = [
  NavGroup(
    'Get Started',
    icon: NavIcons.rocket,
    summary: 'Install dvm, pin your first project, and put the shim on PATH.',
    items: [
      NavItem(
        'Installation',
        '/getting-started/installation',
        summary: 'One curl command, no Dart SDK required first.',
      ),
      NavItem(
        'Quick Start',
        '/getting-started/quick-start',
        summary: 'Install an SDK, pin a project, and watch `dart` follow it.',
      ),
      NavItem(
        'The Shim and Your PATH',
        '/getting-started/shell-setup',
        summary: 'What `dvm setup` writes, and the one line you add yourself.',
      ),
    ],
  ),
  NavGroup(
    'Pinning Versions',
    icon: NavIcons.pin,
    summary: 'How a project says which SDK it wants, and how dvm decides.',
    items: [
      NavItem(
        'The .dvmrc File',
        '/versions/dvmrc',
        summary: 'The file you commit, its format, and what a pin may contain.',
      ),
      NavItem(
        'Aliases and Channels',
        '/versions/aliases',
        summary: 'Name a version, and what `stable` means offline.',
      ),
      NavItem(
        'Resolution Order',
        '/versions/resolution-order',
        summary: 'The five rules, in order — the thing to read when dvm picks the wrong SDK.',
      ),
    ],
  ),
  NavGroup(
    'Command Reference',
    icon: NavIcons.terminal,
    summary: 'Every command dvm ships, with its real flags.',
    items: [
      NavItem('dvm install', '/commands/install', summary: 'Download, verify and install a Dart SDK.'),
      NavItem('dvm use', '/commands/use', summary: 'Pin a version for this project and write .dvmrc.'),
      NavItem('dvm list', '/commands/list', summary: 'List installed SDKs, marking the global and the project.'),
      NavItem('dvm list-remote', '/commands/list-remote', summary: 'List the releases available from the archive.'),
      NavItem('dvm remove', '/commands/remove', summary: 'Delete an installed SDK.'),
      NavItem('dvm alias', '/commands/alias', summary: 'Give a version a name, or list the names you have.'),
      NavItem('dvm unalias', '/commands/unalias', summary: 'Remove a named version.'),
      NavItem('dvm global', '/commands/global', summary: 'Set the version used when no .dvmrc applies.'),
      NavItem('dvm which', '/commands/which', summary: 'Print the resolved SDK and which rule chose it.'),
      NavItem('dvm dart', '/commands/dart', summary: 'Run dart from the resolved SDK.'),
      NavItem('dvm exec', '/commands/exec', summary: 'Run any command with the resolved SDK first on PATH.'),
      NavItem('dvm setup', '/commands/setup', summary: 'Install the shims and print the PATH line to add.'),
      NavItem('dvm migrate', '/commands/migrate', summary: 'Import SDKs from the older cbracken/dvm layout.'),
      NavItem('dvm doctor', '/commands/doctor', summary: 'Check PATH order, shim health, symlinks and config.'),
      NavItem('dvm update', '/commands/update', summary: 'Update dvm itself to the newest release.'),
    ],
  ),
  NavGroup(
    'Guides',
    icon: NavIcons.book,
    summary: 'The jobs that take more than one command.',
    items: [
      NavItem(
        'Updating dvm',
        '/guides/updating-dvm',
        summary: 'How a new dvm reaches your machine, and how to turn the notice off.',
      ),
      NavItem(
        'Migrating from cbracken/dvm',
        '/guides/migrating',
        summary: 'Move an existing ~/.dvm across without re-downloading anything.',
      ),
      NavItem(
        'Using dvm in CI',
        '/guides/ci',
        summary: 'Pin the SDK a build uses, without a shim or a shell profile.',
      ),
      NavItem(
        'Troubleshooting',
        '/guides/troubleshooting',
        summary: 'The failures that look like dvm doing nothing at all.',
      ),
    ],
  ),
];

/// Pages that intentionally live outside the sidebar.
///
/// `test/navigation_test.dart` checks every content page against [navigation]
/// and this set, so a new page that nobody linked fails the suite rather than
/// quietly becoming unreachable.
const Set<String> unlistedRoutes = <String>{};

/// Every navigable page, flattened into reading order.
List<NavItem> get flatNavigation => [
  ...topLevelNavigation,
  for (final group in navigation) ...group.items,
];

/// The group that owns [href], or null for a top-level or unlisted page.
NavGroup? groupFor(String href) {
  for (final group in navigation) {
    for (final item in group.items) {
      if (item.href == href) return group;
    }
  }
  return null;
}

/// The nav entry for [href], or null when the page is unlisted.
NavItem? itemFor(String href) {
  for (final item in flatNavigation) {
    if (item.href == href) return item;
  }
  return null;
}

/// The previous and next pages in reading order, for the page footer.
({NavItem? previous, NavItem? next}) neighborsOf(String href) {
  final flat = flatNavigation;
  final index = flat.indexWhere((item) => item.href == href);
  if (index < 0) return (previous: null, next: null);
  return (previous: index > 0 ? flat[index - 1] : null, next: index < flat.length - 1 ? flat[index + 1] : null);
}

/// Inline SVG icons for [NavGroup]s.
///
/// Lucide-style 24x24 strokes, so they inherit `currentColor` and line weight
/// from the sidebar text rather than needing their own colors.
abstract final class NavIcons {
  static const String _open =
      '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" '
      'stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">';

  static const rocket =
      '$_open<path d="M4.5 16.5c-1.5 1.26-2 5-2 5s3.74-.5 5-2c.71-.84.7-2.13-.09-2.91a2.18 2.18 0 0 0-2.91-.09z"/>'
      '<path d="m12 15-3-3a22 22 0 0 1 2-3.95A12.88 12.88 0 0 1 22 2c0 2.72-.78 7.5-6 11a22.35 22.35 0 0 1-4 2z"/>'
      '<path d="M9 12H4s.55-3.03 2-4c1.62-1.08 5 0 5 0"/><path d="M12 15v5s3.03-.55 4-2c1.08-1.62 0-5 0-5"/></svg>';

  static const pin =
      '$_open<path d="M12 17v5"/><path d="M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 '
      '1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 '
      '1 0 0 1 1 1z"/></svg>';

  static const terminal = '$_open<polyline points="4 17 10 11 4 5"/><line x1="12" x2="20" y1="19" y2="19"/></svg>';

  static const book =
      '$_open<path d="M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H19a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H6.5a1 1 0 0 1 0-5H20"/></svg>';
}

/// Where the docs site is deployed, and the one fact the whole build hinges on.
///
/// Kept separate from `navigation.dart` — that file is the site's information
/// architecture (what pages exist, in what order), this one is about the origin
/// those pages are served from.
library;

/// The path prefix the site is served under.
///
/// `https://mrgnhnt.com/dvm/` is a GitHub Pages PROJECT site, so the whole site
/// lives under `/dvm/` rather than at a domain root — the custom domain does
/// not change that, because it is the account's domain and this repo's site is
/// still one project under it.
///
/// Nothing in `lib/` or `content/` uses this: every route and link is written
/// root-absolute, as if the site owned the domain root, because that is what
/// jaspr's static build emits and what `jaspr serve` serves locally. The
/// prefix is applied to the BUILT OUTPUT by `tool/rebase_static_site.dart`, and
/// this constant exists so `test/base_path_test.dart` and the deploy workflow
/// are talking about the same string.
///
/// If this ever moves to a domain of its OWN — not the account's domain with a
/// project path under it — the change is: delete the rebase step from
/// `.github/workflows/deploy-docs.yml` and delete this. It was kept to one line
/// deliberately.
const String sitePathPrefix = '/dvm';

/// The canonical base URL of the deployed site, including [sitePathPrefix].
///
/// The custom domain comes from the ACCOUNT-level Pages configuration, not from
/// a `CNAME` file in this repository — do not add one, it is not what serves
/// this site. `gh api repos/mrgnhnt96/dvm/pages` reports the live value.
const String docsBaseUrl = 'https://mrgnhnt.com$sitePathPrefix';

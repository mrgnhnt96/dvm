#!/usr/bin/env bash
# Stamp a build tag into the binary — what this build IS, beyond its version.
#
# Usage: tool/stamp_build_tag.sh <build-tag>    # e.g. alpha.g1a2b3c4
#
# Writes kBuildTag in packages/dvm/lib/src/gen/version.dart, which `version()`
# appends to kVersion as semver build metadata: `0.1.0+alpha.g1a2b3c4`. That is
# the only thing that tells a user, a month later, that the dvm they are running
# came from `install.sh --alpha` and not from a release.
#
# WHY THIS IS NOT A SECOND ARGUMENT TO tool/stamp_version.sh. That script exists
# to REFUSE: a version the pubspec does not claim is not stamped, so a published
# binary cannot lie about its version and `dvm update` cannot end up comparing
# numbers that were never true. An alpha is built from main, where the pubspec
# says whatever the last release said — so the alpha build passes stamp_version.sh
# the pubspec's own version (which it can never refuse, and which is exactly what
# release.yml's dry run already does) and expresses "this is an alpha, from this
# commit" HERE instead. Two scripts, two questions, and the refusal keeps its
# original meaning rather than growing an exception.
#
# NOT CALLED BY THE RELEASE PATH, and that is the point: a release's kBuildTag
# stays the empty string that is committed to the repo, so `dvm --version` on a
# release is a bare version with nothing appended.
#
# Writes packages/dvm/lib/src/gen/version.dart. Does not commit.
set -euo pipefail

build_tag="${1:?build tag required (e.g. alpha.g1a2b3c4)}"

# Semver build metadata: dot-separated identifiers of [0-9A-Za-z-], each
# non-empty. Enforced rather than trusted because this string is pasted into a
# Dart single-quoted literal below — a quote or a backslash in it would produce
# a file that does not compile, and the failure would land in a release job
# rather than here.
if [[ ! "${build_tag}" =~ ^[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*$ ]]; then
  echo "stamp_build_tag: [${build_tag}] is not valid semver build metadata." >&2
  echo "Expected dot-separated identifiers of letters, digits and hyphens," >&2
  echo "for example: alpha.g1a2b3c4" >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gen_file="${root}/packages/dvm/lib/src/gen/version.dart"

if ! grep -q "^const String kBuildTag = '.*';$" "${gen_file}"; then
  echo "stamp_build_tag: no kBuildTag line in ${gen_file}." >&2
  echo "That constant is what version() appends; without it this would exit 0" >&2
  echo "having changed nothing, and the build would report itself as a release." >&2
  exit 1
fi

# Only the kBuildTag line is rewritten; every comment in that file is
# hand-written and stays.
tmp="$(mktemp)"
sed "s|^const String kBuildTag = '.*';\$|const String kBuildTag = '${build_tag}';|" \
  "${gen_file}" > "${tmp}"
mv "${tmp}" "${gen_file}"

if ! grep -q "^const String kBuildTag = '${build_tag}';\$" "${gen_file}"; then
  echo "stamp_build_tag: failed to write kBuildTag into ${gen_file}" >&2
  exit 1
fi

echo "Stamped kBuildTag = ${build_tag}"

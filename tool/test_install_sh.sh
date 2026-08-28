#!/bin/sh
# Tests the pure parts of install.sh: platform detection and release picking.
#
# install.sh is the one piece of dvm that is not Dart and therefore not covered
# by `dart test`, and it is also the piece that runs on a machine with nothing
# on it. It is sourced here in library mode (DVM_INSTALL_SH_LIB=1) so its
# functions can be called without downloading anything.
#
# `uname` is shadowed by a shell function below — a function beats an external
# command in POSIX name resolution, which is what makes host detection testable
# without a fleet of machines.
#
# Usage: sh tool/test_install_sh.sh
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
failures=0

check() {
  # check <label> <expected> <actual>
  if [ "$2" = "$3" ]; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    echo "       expected: [$2]"
    echo "       actual:   [$3]"
    failures=$((failures + 1))
  fi
}

DVM_INSTALL_SH_LIB=1
export DVM_INSTALL_SH_LIB
# shellcheck source=/dev/null
. "${root}/install.sh"

# --- platform detection -------------------------------------------------------

fake_uname_s="Linux"
fake_uname_m="x86_64"
uname() {
  case "${1:-}" in
    -s) echo "${fake_uname_s}" ;;
    -m) echo "${fake_uname_m}" ;;
    *) echo "${fake_uname_s}" ;;
  esac
}

target_for() {
  fake_uname_s="$1"
  fake_uname_m="$2"
  # In a subshell: detect_target calls die on an unsupported host, and die
  # exits.
  (detect_target) 2> /dev/null || echo "REFUSED"
}

check "linux x86_64"     "linux-x64"    "$(target_for Linux x86_64)"
check "linux aarch64"    "linux-arm64"  "$(target_for Linux aarch64)"
check "macos arm64"      "macos-arm64"  "$(target_for Darwin arm64)"
check "macos x86_64"     "macos-x64"    "$(target_for Darwin x86_64)"
check "windows refused"  "REFUSED"      "$(target_for MINGW64_NT-10.0 x86_64)"
check "freebsd refused"  "REFUSED"      "$(target_for FreeBSD amd64)"
check "riscv refused"    "REFUSED"      "$(target_for Linux riscv64)"

# --- picking a release --------------------------------------------------------

# Assets are abbreviated but the key order is the API's real one: tag_name,
# then draft, then prerelease, then assets. pick_tag depends on that order.
release() {
  # release <tag> <draft> <prerelease> <asset-name>
  printf '{"url":"x","id":1,"tag_name":"%s","name":"n","draft":%s,"prerelease":%s,"assets":[{"name":"%s","browser_download_url":"http://x/%s"}]}' \
    "$1" "$2" "$3" "$4" "$4"
}

releases() {
  printf '['
  first=1
  for entry in "$@"; do
    [ "${first}" = 1 ] || printf ','
    first=0
    printf '%s' "${entry}"
  done
  printf ']'
}

asset="dvm-macos-arm64.zip"

check "newest release wins" "v0.3.0" "$(
  releases \
    "$(release v0.3.0 false false "${asset}")" \
    "$(release v0.2.0 false false "${asset}")" \
    | pick_tag "${asset}"
)"

check "draft skipped" "v0.2.0" "$(
  releases \
    "$(release v0.9.0 true false "${asset}")" \
    "$(release v0.2.0 false false "${asset}")" \
    | pick_tag "${asset}"
)"

check "prerelease skipped" "v0.2.0" "$(
  releases \
    "$(release v0.9.0 false true "${asset}")" \
    "$(release v0.2.0 false false "${asset}")" \
    | pick_tag "${asset}"
)"

# The whole reason /releases/latest is not used: a newer release for something
# else takes the "latest" slot and carries no dvm binary at all.
check "release without our asset skipped" "v0.2.0" "$(
  releases \
    "$(release v0.4.0 false false "some-other-package.zip")" \
    "$(release v0.2.0 false false "${asset}")" \
    | pick_tag "${asset}"
)"

check "another platform's asset is not ours" "v0.2.0" "$(
  releases \
    "$(release v0.4.0 false false "dvm-linux-x64.zip")" \
    "$(release v0.2.0 false false "${asset}")" \
    | pick_tag "${asset}"
)"

check "nothing matching gives nothing" "" "$(
  releases "$(release v0.4.0 false false "dvm-linux-x64.zip")" | pick_tag "${asset}"
)"

check "no releases at all gives nothing" "" "$(printf '[]' | pick_tag "${asset}")"

# --- installing, end to end ---------------------------------------------------

# The download functions are shadowed to read from a fixture directory, so
# everything after the download — checksum verification, unzipping, the atomic
# move into place, the PATH advice — runs exactly as it does for a real install.
fixtures=""
fetch_file() {
  cp "${fixtures}/$(basename "$1")" "$2" 2> /dev/null \
    || die "could not download $1"
}

make_fixture() {
  # make_fixture <dir> <zip-entry-name> <checksum-mode>
  rm -rf "$1"
  mkdir -p "$1/build"
  printf '#!/bin/sh\necho dvm\n' > "$1/build/$2"
  (cd "$1/build" && zip -q -X "../dvm-${e2e_target}.zip" "$2")
  if [ "$3" = "bad" ]; then
    printf '%s  dvm-%s.zip\n' "0000000000000000000000000000000000000000000000000000000000000000" \
      "${e2e_target}" > "$1/dvm-${e2e_target}.zip.sha256"
  else
    (cd "$1" && (sha256sum "dvm-${e2e_target}.zip" 2> /dev/null \
      || shasum -a 256 "dvm-${e2e_target}.zip") > "dvm-${e2e_target}.zip.sha256")
  fi
}

if ! command -v zip > /dev/null 2>&1; then
  echo "skip install-into-place checks: no zip on this machine"
else
  fake_uname_s="Linux"
  fake_uname_m="x86_64"
  e2e_target="linux-x64"
  workdir="$(mktemp -d)"
  trap 'rm -rf "${workdir}"' EXIT INT TERM

  DVM_VERSION="0.2.0"
  export DVM_VERSION

  # Happy path.
  fixtures="${workdir}/good"
  make_fixture "${fixtures}" dvm ok
  DVM_HOME="${workdir}/home-good" \
    PATH="${PATH}" \
    output="$( (main) 2>&1 )" || output="MAIN FAILED: ${output}"

  check "installs the binary" "0" \
    "$([ -x "${workdir}/home-good/bin/dvm" ] && echo 0 || echo 1)"
  check "no temp file left behind" "1" \
    "$([ -e "${workdir}/home-good/bin/dvm.new" ] && echo 0 || echo 1)"
  check "tells the user about PATH" "0" \
    "$(echo "${output}" | grep -q "export PATH=\"${workdir}/home-good/bin:" \
      && echo 0 || echo 1)"

  # A checksum that does not match must abort before anything is written.
  fixtures="${workdir}/bad"
  make_fixture "${fixtures}" dvm bad
  if DVM_HOME="${workdir}/home-bad" output="$( (main) 2>&1 )"; then
    check "checksum mismatch refuses" "refused" "installed anyway"
  else
    check "checksum mismatch refuses" "refused" "refused"
  fi
  check "checksum mismatch says so" "0" \
    "$(echo "${output}" | grep -q "checksum mismatch" && echo 0 || echo 1)"
  check "checksum mismatch installs nothing" "1" \
    "$([ -e "${workdir}/home-bad/bin/dvm" ] && echo 0 || echo 1)"

  # An asset that is a zip but holds no dvm.
  fixtures="${workdir}/empty"
  make_fixture "${fixtures}" NOTES.txt ok
  if DVM_HOME="${workdir}/home-empty" output="$( (main) 2>&1 )"; then
    check "asset without a dvm refuses" "refused" "installed anyway"
  else
    check "asset without a dvm refuses" "refused" "refused"
  fi
  check "asset without a dvm installs nothing" "1" \
    "$([ -e "${workdir}/home-empty/bin/dvm" ] && echo 0 || echo 1)"

  unset DVM_VERSION
fi

# --- result -------------------------------------------------------------------

if [ "${failures}" -ne 0 ]; then
  echo "${failures} check(s) failed"
  exit 1
fi

echo "install.sh: all checks passed"

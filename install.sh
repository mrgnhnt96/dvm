#!/bin/sh
# Install dvm, the per-project Dart SDK version manager.
#
#   curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh
#
# POSIX sh on purpose, not bash: this is the FIRST thing that runs on a machine
# that may have nothing on it, and Debian's /bin/sh is dash, Alpine's is busybox
# ash, and neither is bash. Nothing below uses [[ ]], arrays, `local`, or ${x^^}.
#
# It fails loudly rather than partially. A version manager that half-installed is
# worse than one that did not install: the user gets a `dvm` on PATH that cannot
# do the one thing it exists for, and no message saying why.
#
# Environment:
#   DVM_VERSION   install this version instead of the newest release (0.2.0 or v0.2.0)
#   DVM_HOME      install under here instead of ~/.dvm
#   GITHUB_TOKEN  used if set; the API's unauthenticated limit is 60/hour/IP
set -eu

REPO="mrgnhnt96/dvm"
API="https://api.github.com/repos/${REPO}"
DOWNLOADS="https://github.com/${REPO}/releases/download"

die() {
  echo "dvm install: $*" >&2
  exit 1
}

info() {
  echo "$*"
}

need() {
  command -v "$1" > /dev/null 2>&1
}

# --- what are we installing for -----------------------------------------------

# The `<os>-<arch>` half of a release asset name.
#
# THESE FIVE ARE A CONTRACT shared with tool/package_release_assets.sh (which
# creates the assets) and releaseAssetName() in
# packages/dvm/lib/src/core/updater.dart (which is how an installed dvm updates
# itself). All three must spell them identically, forever.
detect_target() {
  detect_os="$(uname -s)"
  detect_arch="$(uname -m)"

  case "${detect_os}" in
    Linux) detect_os="linux" ;;
    Darwin) detect_os="macos" ;;
    MINGW* | MSYS* | CYGWIN* | Windows_NT)
      die "this script does not install on Windows. Download
  ${DOWNLOADS}/<tag>/dvm-windows-x64.zip
from https://github.com/${REPO}/releases and put dvm.exe on your PATH."
      ;;
    *)
      die "unsupported operating system: ${detect_os}.
dvm publishes binaries for Linux, macOS and Windows only."
      ;;
  esac

  case "${detect_arch}" in
    x86_64 | amd64) detect_arch="x64" ;;
    arm64 | aarch64) detect_arch="arm64" ;;
    *)
      die "unsupported CPU architecture: ${detect_arch}.
dvm publishes binaries for x86_64 and arm64 only. You can build it from source
with a Dart SDK: dart compile exe packages/dvm/bin/dvm.dart -o dvm"
      ;;
  esac

  case "${detect_os}-${detect_arch}" in
    linux-x64 | linux-arm64 | macos-x64 | macos-arm64) ;;
    *)
      die "no dvm binary is published for ${detect_os}-${detect_arch}."
      ;;
  esac

  echo "${detect_os}-${detect_arch}"
}

# --- fetching -----------------------------------------------------------------

# Prints a URL's body on stdout. curl and wget are both accepted because a
# minimal container reliably has exactly one of them.
fetch_text() {
  # Spelled out per branch rather than folding the header into a variable:
  # ${TOKEN:+-H "..."} is unquoted at expansion time, so the shell splits the
  # header on its spaces and curl receives four arguments instead of two.
  if need curl; then
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" "$1"
    else
      curl -fsSL "$1"
    fi
  elif need wget; then
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      wget -qO- --header="Authorization: Bearer ${GITHUB_TOKEN}" "$1"
    else
      wget -qO- "$1"
    fi
  else
    die "neither curl nor wget is installed, so nothing can be downloaded."
  fi
}

# Saves a URL to a path. Separate from fetch_text so the binary never goes
# through a shell variable, which would mangle it.
fetch_file() {
  if need curl; then
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" -o "$2" "$1" \
        || die "could not download $1"
    else
      curl -fsSL -o "$2" "$1" || die "could not download $1"
    fi
  elif need wget; then
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      wget -q --header="Authorization: Bearer ${GITHUB_TOKEN}" -O "$2" "$1" \
        || die "could not download $1"
    else
      wget -q -O "$2" "$1" || die "could not download $1"
    fi
  else
    die "neither curl nor wget is installed, so nothing can be downloaded."
  fi
}

# The newest release tag that actually carries "$1", reading the API's JSON on
# stdin.
#
# NOT /releases/latest. GitHub's "latest" is the newest non-draft non-prerelease
# release of any kind, so the day this repo publishes a release for something
# other than the CLI, "latest" is a release with no dvm binary in it and this
# script downloads a 404. ARCHITECTURE.md's "Distribution" section says the same.
#
# HOW THE PARSING WORKS, since there is no jq on a minimal machine. The response
# is one long line of JSON. awk splits it into one record per release by putting
# a newline before every "tag_name" key, which works because GitHub emits a
# release's keys in a fixed order: tag_name comes before draft, prerelease and
# assets, so each record carries its own flags and its own asset list and cannot
# borrow the next release's. Records are already newest-first, so the first one
# that survives the filters is the answer.
pick_tag() {
  pick_asset="$1"
  awk '{ gsub(/"tag_name"/, "\n&"); print }' \
    | grep '"tag_name"' \
    | grep -v '"draft"[[:space:]]*:[[:space:]]*true' \
    | grep -v '"prerelease"[[:space:]]*:[[:space:]]*true' \
    | grep -F "\"${pick_asset}\"" \
    | head -n 1 \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

# --- install ------------------------------------------------------------------

# Prints the sha256 of a file, as a bare hex digest.
sha256_of() {
  if need sha256sum; then
    sha256sum "$1" | cut -d' ' -f1
  elif need shasum; then
    shasum -a 256 "$1" | cut -d' ' -f1
  elif need openssl; then
    openssl dgst -sha256 "$1" | sed 's/.*= *//'
  else
    die "no sha256 tool found (looked for sha256sum, shasum and openssl), so
the download cannot be verified. Install one of them and run this again —
installing an unverified version manager is not something this script will do
quietly."
  fi
}

unpack() {
  if need unzip; then
    unzip -o -q "$1" -d "$2" || die "could not unzip $1"
  elif need python3; then
    python3 -m zipfile -e "$1" "$2" || die "could not unzip $1"
  else
    die "no unzip tool found (looked for unzip and python3). Install unzip and
run this again."
  fi
}

main() {
  target="$(detect_target)"
  asset="dvm-${target}.zip"

  if [ -n "${DVM_VERSION:-}" ]; then
    tag="v${DVM_VERSION#v}"
  else
    info "Looking up the newest dvm release..."
    tag="$(fetch_text "${API}/releases?per_page=100" | pick_tag "${asset}")"
    [ -n "${tag}" ] || die "could not find a published release carrying
${asset}. Check https://github.com/${REPO}/releases — if there are releases
there, this is probably the GitHub API rate limit; set GITHUB_TOKEN and retry."
  fi

  dvm_home="${DVM_HOME:-${HOME:?HOME is not set, and DVM_HOME was not set either}/.dvm}"
  bin_dir="${dvm_home}/bin"

  tmp="$(mktemp -d 2>/dev/null || mktemp -d -t dvm-install)"
  # Covers the failure paths too: `die` exits, and the trap still fires.
  trap 'rm -rf "${tmp}"' EXIT INT TERM

  info "Downloading ${asset} (${tag})..."
  fetch_file "${DOWNLOADS}/${tag}/${asset}" "${tmp}/${asset}"
  fetch_file "${DOWNLOADS}/${tag}/${asset}.sha256" "${tmp}/${asset}.sha256"

  expected="$(cut -d' ' -f1 < "${tmp}/${asset}.sha256")"
  actual="$(sha256_of "${tmp}/${asset}")"
  if [ "${expected}" != "${actual}" ]; then
    die "checksum mismatch for ${asset}.
  expected: ${expected}
  actual:   ${actual}
Nothing was installed. This is either a corrupted download or a tampered-with
asset; try again, and if it keeps happening do not install it."
  fi

  unpack "${tmp}/${asset}" "${tmp}/unpacked"
  [ -f "${tmp}/unpacked/dvm" ] || die "${asset} does not contain a dvm binary."

  mkdir -p "${bin_dir}"
  # Temp file then mv, so an interrupted copy cannot leave a truncated dvm at
  # the real path — and so replacing a running dvm keeps its inode alive.
  chmod 755 "${tmp}/unpacked/dvm"
  mv -f "${tmp}/unpacked/dvm" "${bin_dir}/dvm.new"
  mv -f "${bin_dir}/dvm.new" "${bin_dir}/dvm"

  info ""
  info "dvm ${tag} is installed at ${bin_dir}/dvm"
  info ""

  case ":${PATH}:" in
    *":${bin_dir}:"*)
      info "Next: run  dvm setup  to install the dart shim."
      ;;
    *)
      info "Add this to your shell startup file (~/.zshrc, ~/.bashrc, ...):"
      info ""
      info "  export PATH=\"${bin_dir}:\$PATH\""
      info ""
      info "Then start a new shell and run  dvm setup  to install the dart shim."
      ;;
  esac
}

# A seam for tool/test_install_sh.sh, which sources this file to exercise the
# pure functions (target detection, JSON parsing) without downloading anything.
if [ "${DVM_INSTALL_SH_LIB:-}" != "1" ]; then
  main "$@"
fi

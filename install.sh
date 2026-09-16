#!/bin/sh
# Install dvm, the per-project Dart SDK version manager.
#
#   curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh
#
# Options:
#   -h, --help    print the usage and exit
#
# PIPED INTO A SHELL, OPTIONS GO AFTER `-s --`. That is not this script's
# convention, it is sh's: without it the words are read as sh's own arguments.
#
#   curl -fsSL https://raw.githubusercontent.com/mrgnhnt96/dvm/main/install.sh | sh -s -- --help
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
# Named here so the usage can hand back the command that runs this script,
# rather than a second copy of the URL that can drift from the one above.
INSTALLER="https://raw.githubusercontent.com/${REPO}/main/install.sh"

die() {
  echo "dvm install: $*" >&2
  exit 1
}

info() {
  printf '%s\n' "$*"
}

# stdout remains a terminal when curl pipes the script into sh. Redirected
# output stays plain, and NO_COLOR / TERM=dumb disable styling.
color_enabled() {
  [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ -n "${TERM:-}" ] && [ "${TERM}" != dumb ]
}

styled() {
  style_code="$1"
  shift
  if color_enabled; then
    printf '\033[%sm%s\033[0m\n' "${style_code}" "$*"
  else
    info "$*"
  fi
}

need() {
  command -v "$1" > /dev/null 2>&1
}

# --- how to be asked for something else ---------------------------------------

# Written with `info` rather than a heredoc so `usage >&2` sends every line to
# stderr, which is where a usage error's usage belongs and a heredoc's `cat`
# would not follow.
usage() {
  info "Install dvm, the per-project Dart SDK version manager."
  info ""
  info "Usage:"
  info "  sh install.sh [options]"
  info "  curl -fsSL ${INSTALLER} | sh"
  info ""
  info "Options:"
  info "  -h, --help    print this and exit"
  info ""
  info "Environment:"
  info "  DVM_VERSION   install this exact version (0.2.0 or v0.2.0)"
  info "  DVM_HOME      install under here instead of ~/.dvm"
  info "  GITHUB_TOKEN  used if set; the API's unauthenticated limit is"
  info "                60/hour/IP"
}

# A flag this script does not understand. NOT ignored, which is the tempting
# thing to do in a script that is usually run with no arguments at all: a
# silently dropped flag installs something other than what was asked for and
# says the install worked, so the user reads a correct-looking success message
# for the opposite of what they typed.
#
# Exits 2 rather than 1 so a wrapper can tell "you typed it wrong" (nothing was
# attempted) from "the install failed" (something was).
usage_error() {
  echo "dvm install: $*" >&2
  echo "" >&2
  usage >&2
  exit 2
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
# DRAFTS AND PRERELEASES ARE EXCLUDED, and there is no way to ask for them. A
# prerelease is unreleased code that nobody chose to publish, and a release scan
# that could reach one would install it on a machine that never asked. Empty
# output is the honest answer when nothing qualifies, and the caller turns it
# into a refusal rather than falling back to something else.
#
# NOT /releases/latest. GitHub's "latest" is the newest non-draft non-prerelease
# release of any kind, so the day this repo publishes a release for something
# other than the CLI, "latest" is a release with no dvm binary in it and this
# script downloads a 404. ARCHITECTURE.md's "Distribution" section says the same.
#
# HOW THE PARSING WORKS, since there is no jq on a minimal machine. GitHub
# pretty-prints this response across tens of thousands of lines, so `tr` folds it
# into a single line FIRST and awk then splits it into one record per release by
# putting a newline before every "tag_name" key. That works because GitHub emits
# a release's keys in a fixed order: tag_name comes before draft, prerelease and
# assets, so each record carries its own flags and its own asset list and cannot
# borrow the next release's. Records are already newest-first, so the first one
# that survives the filters is the answer.
#
# THE `tr` IS LOAD-BEARING, and tool/test_install_sh.sh pins it with a
# pretty-printed fixture. Without it, every grep below sees a line carrying only
# "tag_name" — never the draft flag, never the asset names — so the asset filter
# matches nothing and this returns empty for every response GitHub actually
# sends. The caller reports that as "no release carries this asset", which reads
# like a rate limit on a machine where the releases are plainly there.
# `dvm update` never had this failure: updater.dart hands the body to a real
# JSON parser rather than to grep.
pick_tag() {
  pick_asset="$1"
  tr '\n' ' ' \
    | awk '{ gsub(/"tag_name"/, "\n&"); print }' \
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

# --- a `dvm` that is not the one we just installed -----------------------------
#
# The chicken-and-egg this section exists for: `dvm doctor` and `dvm setup`
# both detect a shadowing `dvm` correctly and completely — and a shadowing
# `dvm` is exactly what stops either of them from running. A shell function or
# alias is resolved before PATH is ever searched, so the binary this script
# just wrote is never reached, and the user sees an error from the OTHER dvm
# with nothing tying it back to their install. install.sh is the only thing
# that executes before the shadow can bite, so the scan has to live here too.
#
# It only ever REPORTS. `dvm setup --write-path-line` is the thing that edits a
# startup file, and it already refuses to write into a shadowed shell.

# Prints every shadowing line in the startup file "$1", as
# `<file>:<line>: <text>   (<what it is>)` — the same shape `dvm doctor` uses,
# so a user who sees both sees one answer twice rather than two answers.
#
# Silent for a file that is not there and for one that cannot be read. Both are
# ordinary — a fresh machine has few of these, and a root-owned .profile is
# readable by nobody — and neither is worth failing an install that worked.
scan_rc_file() {
  if [ ! -f "$1" ] || [ ! -r "$1" ]; then
    return 0
  fi

  # awk rather than a `while read` loop: awk counts the line number itself (NR),
  # and `read` mangles backslashes unless every call is `-r`, which is the kind
  # of detail that differs between dash and busybox ash.
  #
  # The patterns are the ones in scanForShadows() /  _classify() in
  # packages/dvm/lib/src/core/shell.dart. POSIX ERE has no \b, so each
  # word-boundary case is spelled as "end of line, or a character that cannot
  # continue an identifier".
  awk -v file="$1" '
    {
      text = $0
      sub(/^[ \t]+/, "", text)
      sub(/[ \t]+$/, "", text)

      # A commented-out definition is what a user leaves behind after fixing
      # this. Reporting it would send them back to a file already correct.
      if (text == "" || substr(text, 1, 1) == "#") next

      kind = ""
      if (text ~ /\.dvm\/scripts\/dvm$/ || text ~ /\.dvm\/scripts\/dvm[^A-Za-z0-9_]/) {
        kind = "a line sourcing the older cbracken/dvm shell script"
      } else if (text ~ /^alias[ \t]+dvm[ \t]*=/) {
        kind = "a shell alias named dvm"
      } else if (text ~ /^dvm[ \t]*\([ \t]*\)/) {
        kind = "a shell function named dvm"
      } else if (text ~ /^function[ \t]+dvm$/ || text ~ /^function[ \t]+dvm[^A-Za-z0-9_]/) {
        kind = "a shell function named dvm"
      }
      if (kind == "") next

      printf "%s:%d: %s   (%s)\n", file, NR, text, kind
    }
  ' "$1" 2> /dev/null || true
}

# Prints the shadowing lines across every startup file under the home "$1".
#
# The candidate list is rcCandidates in packages/dvm/lib/src/core/shell.dart,
# and deliberately is not narrowed by $SHELL: a `dvm` function left in .zshrc
# is what breaks a zsh login even when the shell running this script is not zsh.
scan_startup_files() {
  [ -n "$1" ] || return 0

  for rc_name in .zshrc .zshenv .zprofile .zlogin .bashrc .bash_profile \
    .bash_login .profile .config/fish/config.fish; do
    scan_rc_file "$1/${rc_name}"
  done
}

# Prints the older cbracken/dvm's leftovers under the dvm home "$1".
#
# That tool keeps its SDKs in `darts/`, its shell function in `scripts/dvm` and
# per-project setups in `environments/`, all inside the same ~/.dvm this script
# installs into. Their presence is a warning and not a failure: they sit
# alongside a working install, and `dvm migrate` imports them.
scan_legacy_install() {
  if [ -f "$1/scripts/dvm" ]; then
    echo "$1/scripts/dvm  (sourcing this is what defines the function)"
  fi
  for legacy_name in darts environments; do
    if [ -d "$1/${legacy_name}" ]; then
      echo "$1/${legacy_name}"
    fi
  done
  return 0
}

# Warnings shown before the closing actions. "$1" holds shadowing lines
# from scan_startup_files and "$2" is the dvm home.
#
# The shadow scan is done by the CALLER and passed in rather than repeated
# here: main has to know the answer BEFORE it prints the next step, because
# the next step is different when a shadow is present, and scanning twice
# invites the two answers to drift.
#
# Prints nothing when there is nothing to say, and NEVER changes the exit
# status: the binary is on disk and it is good. Refusing to install over a
# startup file this script is not going to edit would be a worse outcome than a
# warning, so this warns loudly and returns 0.
warn_about_shadows() {
  shadow_lines="$1"
  legacy_lines="$(scan_legacy_install "$2")"

  if [ -n "${shadow_lines}" ]; then
    info ""
    styled '1;33' "!! Your shell already defines its own \`dvm\`."
    info "A function or alias wins over PATH; setup refuses to write until it is removed."
    echo "${shadow_lines}" | sed 's/^/  /'
  fi

  if [ -n "${legacy_lines}" ]; then
    info ""
    styled '1;33' "!! An older dvm (cbracken/dvm) shares $2:"
    info ""
    echo "${legacy_lines}" | sed 's/^/   /'
    info ""
    info "   Nothing of it was touched. Once the \`dvm\` command reaches the"
    info "   binary above, import its SDKs with:  dvm migrate"
  fi

  return 0
}

# Shared by both installers. Keep commands last, after warnings and context.
# The absolute binary path works before the user has configured PATH.
print_next_steps() {
  steps_shadow_lines="$1"
  steps_dvm_home="$2"
  steps_bin_dir="$3"

  info ""
  if [ -n "${steps_shadow_lines}" ]; then
    styled '1' "Next steps: shell startup files to clear first"
    info "  1. comment out the line(s) listed above"
    info "  2. start a new shell"
    info "  3. run setup, then open a new terminal:"
    info ""
    styled '1;36' "  ${steps_bin_dir}/dvm setup --write-path-line"
    return 0
  fi

  case ":${PATH}:" in
    *":${steps_bin_dir}:"*) steps_path="${steps_dvm_home}/shims" ;;
    *) steps_path="${steps_dvm_home}/shims:${steps_bin_dir}" ;;
  esac

  info "Setup creates the dart shim. Choose how to add it to PATH below."
  info ""
  styled '1' "Manual option (no startup-file edits by dvm):"
  info "Add this line to your shell startup file (sh/bash/zsh):"
  styled '36' "  export PATH=\"${steps_path}:\$PATH\""
  info "Then create the shim:"
  styled '36' "  ${steps_bin_dir}/dvm setup"
  info ""
  styled '1;32' "Next step — recommended"
  info "One command finishes the setup, backing up your startup file first."
  info "Run this, then open a new terminal:"
  info ""
  styled '1;36' "  ${steps_bin_dir}/dvm setup --write-path-line"
}

main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h | --help)
        usage
        return 0
        ;;
      *)
        # Positional arguments land here too, deliberately: this script takes
        # none, and `sh install.sh 0.2.0` is a real mistake to make. The usage
        # printed alongside names DVM_VERSION, which is what that user wanted.
        usage_error "unknown option: $1"
        ;;
    esac
    shift
  done

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
  styled '1;32' "dvm ${tag} is installed at ${bin_dir}/dvm"

  # Scanned BEFORE anything is printed, because the answer changes the message:
  # a shadowed shell gets a pointer at the fix instead of the one-step command,
  # and scanning twice would invite the two answers to drift.
  shadow_lines="$(scan_startup_files "${HOME:-}")"

  warn_about_shadows "${shadow_lines}" "${dvm_home}" "${bin_dir}/dvm"
  print_next_steps "${shadow_lines}" "${dvm_home}" "${bin_dir}"

}

# A seam for tool/test_install_sh.sh, which sources this file to exercise the
# pure functions (target detection, JSON parsing) without downloading anything.
if [ "${DVM_INSTALL_SH_LIB:-}" != "1" ]; then
  main "$@"
fi

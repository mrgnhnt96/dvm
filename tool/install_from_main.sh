#!/bin/sh
# Build dvm from the local checkout and install it the way install.sh would,
# so the install-and-setup flow can be exercised against code that is not
# released yet.
#
#   sh tool/install_from_main.sh
#
# WHAT THIS IS NOT. It is not `curl -fsSL .../install.sh | sh` against main, and
# it cannot be: install.sh downloads a published GitHub RELEASE asset, and main
# is not a release. The newest release is v0.1.0, which predates the shadow
# scan, the verbose flag and the --write-path-line hint. So the real installer
# would hand you the old binary and none of the behaviour you want to look at.
#
# What it does instead: compiles the checkout, puts the binary exactly where
# install.sh puts it, and then calls install.sh's OWN functions to report. The
# target detection, the shadow scan and the whole closing message below are the
# shipped code, sourced from install.sh rather than reimplemented here — if they
# are wrong, this prints wrong, which is the point of running it.
#
# It used to carry a hand-copied closing message, with a comment saying so. That
# copy went stale the day install.sh's message was rewritten: install.sh started
# offering one absolute-path command that finishes the setup, this still printed
# the old three-step guidance, and following it left ~/.dvm/shims off PATH — a
# correct install that looked broken. A comment saying "this is a copy" is not a
# guard, so there is now a check in tool/test_install_sh.sh that fails if the
# prose reappears here.
#
# Environment:
#   DVM_HOME   install under here instead of ~/.dvm
set -eu

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
install_sh="${repo_root}/install.sh"

[ -f "${install_sh}" ] || {
  echo "install-from-main: no install.sh above this script (${install_sh})." >&2
  echo "Run it from inside the dvm checkout." >&2
  exit 1
}

command -v dart > /dev/null 2>&1 || {
  echo "install-from-main: no dart on PATH, and this builds from source." >&2
  echo "A Dart SDK is required. (Yes: bootstrapping a Dart version manager" >&2
  echo "from source needs a Dart. The released installer does not.)" >&2
  exit 1
}

# install.sh's real functions: detect_target, scan_startup_files,
# print_next_steps, warn_about_shadows, info.
# DVM_INSTALL_SH_LIB=1 is the seam at the bottom of install.sh that skips main().
DVM_INSTALL_SH_LIB=1
export DVM_INSTALL_SH_LIB
# shellcheck source=../install.sh
. "${install_sh}"

dvm_home="${DVM_HOME:-${HOME:?HOME is not set, and DVM_HOME was not set either}/.dvm}"
bin_dir="${dvm_home}/bin"

# Reported, not used to pick a download — it is the one line that says out loud
# what this machine is, the same way a real install does.
target="$(detect_target)"

commit="$(git -C "${repo_root}" rev-parse --short HEAD 2> /dev/null || echo unknown)"
branch="$(git -C "${repo_root}" rev-parse --abbrev-ref HEAD 2> /dev/null || echo unknown)"
dirty=""
if ! git -C "${repo_root}" diff --quiet 2> /dev/null; then
  dirty=" (with uncommitted changes)"
fi

info "Building dvm from ${branch} @ ${commit}${dirty} for ${target}..."

tmp="$(mktemp -d 2>/dev/null || mktemp -d -t dvm-from-main)"
trap 'rm -rf "${tmp}"' EXIT INT TERM

# NO -D__DVM_COMPILED__=true, and that is deliberate rather than an omission.
# kIsCompiled gates everything that replaces the binary on disk or asks GitHub
# what the newest release is (see packages/dvm/lib/src/gen/version.dart). Set it
# here and this build starts comparing itself against published releases — where
# the newest is the OLDER v0.1.0 — so `dvm update` becomes a way to silently
# throw away the build you are trying to test. Left false, this binary knows it
# came from source and leaves itself alone.
#
# The cost, stated: `dvm update` and the version notice cannot be exercised from
# this build. They need a real release.
dart compile exe "${repo_root}/packages/dvm/bin/dvm.dart" -o "${tmp}/dvm" \
  || {
    echo "install-from-main: the build failed; nothing was installed." >&2
    exit 1
  }

mkdir -p "${bin_dir}"
# Temp then mv, the same two steps install.sh takes: an interrupted copy must
# not leave a truncated dvm at the real path, and replacing a running dvm has to
# keep its inode alive.
chmod 755 "${tmp}/dvm"
mv -f "${tmp}/dvm" "${bin_dir}/dvm.new"
mv -f "${bin_dir}/dvm.new" "${bin_dir}/dvm"

info ""
info "dvm (${branch} @ ${commit}) is installed at ${bin_dir}/dvm"

# From here down it is install.sh's closing sequence, in install.sh's order and
# with install.sh's arguments: scan first, because the answer changes the
# message, then the next steps, then the warning last so it is what stays on
# screen. Three calls, no wording of its own.
shadow_lines="$(scan_startup_files "${HOME:-}")"

print_next_steps "${shadow_lines}" "${dvm_home}" "${bin_dir}"

warn_about_shadows "${shadow_lines}" "${dvm_home}" "${bin_dir}/dvm"

info ""
info "To check what it thinks of your machine at any point:"
info ""
info "  ${bin_dir}/dvm doctor"
info "  ${bin_dir}/dvm -v doctor      # the same, with the resolution walk"

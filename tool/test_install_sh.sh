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

# A tag that LOOKS like a prerelease but is not flagged as one. This is the
# shape of the very first release: packages/dvm/pubspec.yaml says 0.1.0-dev, and
# the publish step passes no --prerelease, so GitHub records prerelease: false.
# The filter above is on the FLAG and never on the tag string, so this is picked
# — which is the answer to "would a 0.1.0-dev release be installable at all".
# Pinned as a test because reading the greps invites the opposite conclusion.
check "dev-suffixed tag is picked when the flag is false" "v0.1.0-dev" "$(
  releases "$(release v0.1.0-dev false false "${asset}")" | pick_tag "${asset}"
)"

# ...and the flag, when it IS set, is what does the skipping.
check "dev-suffixed tag is skipped when the flag is true" "" "$(
  releases "$(release v0.1.0-dev false true "${asset}")" | pick_tag "${asset}"
)"

# --- picking a release, as GitHub ACTUALLY sends it ---------------------------

# Everything above is one line of JSON, and the real API is not: GitHub
# pretty-prints /releases across tens of thousands of lines. That difference
# used to be invisible here and fatal in production — pick_tag matched nothing
# on a real response, and install.sh reported it as "no release carries this
# asset", which reads like a rate limit. The `tr` in pick_tag is what handles
# it; these fixtures are the reason it cannot quietly go away again.
#
# Indentation and key order below are copied from a real
# api.github.com/repos/.../releases body.
release_pretty() {
  # release_pretty <tag> <draft> <prerelease> <asset-name>
  printf '  {\n'
  printf '    "url": "https://api.github.com/repos/x/y/releases/1",\n'
  printf '    "id": 1,\n'
  printf '    "tag_name": "%s",\n' "$1"
  printf '    "name": "some release title",\n'
  printf '    "draft": %s,\n' "$2"
  printf '    "prerelease": %s,\n' "$3"
  printf '    "assets": [\n'
  printf '      {\n'
  printf '        "name": "%s",\n' "$4"
  printf '        "browser_download_url": "http://x/%s"\n' "$4"
  printf '      }\n'
  printf '    ]\n'
  printf '  }'
}

releases_pretty() {
  printf '[\n'
  first=1
  for entry in "$@"; do
    [ "${first}" = 1 ] || printf ',\n'
    first=0
    printf '%s' "${entry}"
  done
  printf '\n]\n'
}

check "pretty: newest release wins" "v0.3.0" "$(
  releases_pretty \
    "$(release_pretty v0.3.0 false false "${asset}")" \
    "$(release_pretty v0.2.0 false false "${asset}")" \
    | pick_tag "${asset}"
)"

check "pretty: draft skipped" "v0.2.0" "$(
  releases_pretty \
    "$(release_pretty v0.9.0 true false "${asset}")" \
    "$(release_pretty v0.2.0 false false "${asset}")" \
    | pick_tag "${asset}"
)"

check "pretty: prerelease skipped" "v0.2.0" "$(
  releases_pretty \
    "$(release_pretty v0.9.0 false true "${asset}")" \
    "$(release_pretty v0.2.0 false false "${asset}")" \
    | pick_tag "${asset}"
)"

check "pretty: release without our asset skipped" "v0.2.0" "$(
  releases_pretty \
    "$(release_pretty v0.4.0 false false "some-other-package.zip")" \
    "$(release_pretty v0.2.0 false false "${asset}")" \
    | pick_tag "${asset}"
)"

check "pretty: another platform's asset is not ours" "v0.2.0" "$(
  releases_pretty \
    "$(release_pretty v0.4.0 false false "dvm-linux-x64.zip")" \
    "$(release_pretty v0.2.0 false false "${asset}")" \
    | pick_tag "${asset}"
)"

check "pretty: dev-suffixed tag is picked when the flag is false" "v0.1.0-dev" "$(
  releases_pretty "$(release_pretty v0.1.0-dev false false "${asset}")" \
    | pick_tag "${asset}"
)"

check "pretty: nothing matching gives nothing" "" "$(
  releases_pretty "$(release_pretty v0.4.0 false false "dvm-linux-x64.zip")" \
    | pick_tag "${asset}"
)"

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
  #
  # HOME is pinned to an empty directory rather than inherited. main now scans
  # the startup files BEFORE it chooses what to print — a shadow changes the
  # message — so a maintainer whose own ~/.zshrc sources the older cbracken/dvm
  # would otherwise see a different branch here than CI does.
  e2e_home="${workdir}/e2e-home"
  mkdir -p "${e2e_home}"
  fixtures="${workdir}/good"
  make_fixture "${fixtures}" dvm ok
  HOME="${e2e_home}" \
    DVM_HOME="${workdir}/home-good" \
    PATH="${PATH}" \
    output="$( (main) 2>&1 )" || output="MAIN FAILED: ${output}"

  check "installs the binary" "0" \
    "$([ -x "${workdir}/home-good/bin/dvm" ] && echo 0 || echo 1)"
  check "no temp file left behind" "1" \
    "$([ -e "${workdir}/home-good/bin/dvm.new" ] && echo 0 || echo 1)"
  check "tells the user about PATH" "0" \
    "$(echo "${output}" \
      | grep -q "export PATH=\"${workdir}/home-good/shims:${workdir}/home-good/bin:" \
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

  # A zip holding dvm inside a directory rather than at the root.
  # tool/package_release_assets.sh zips from inside the binary's directory so the
  # asset is flat, and install.sh looks for exactly "${tmp}/unpacked/dvm" — so a
  # nested one installs nothing. updater.dart:434 takes the basename and would
  # survive it, which is precisely why this asymmetry is worth a test: a change
  # that nested the asset would keep `dvm update` working and silently break
  # every FIRST install, and no unit test on either side would notice.
  fixtures="${workdir}/nested"
  rm -rf "${fixtures}"
  mkdir -p "${fixtures}/build/dvm-${e2e_target}"
  printf '#!/bin/sh\necho dvm\n' > "${fixtures}/build/dvm-${e2e_target}/dvm"
  (cd "${fixtures}/build" && zip -q -X -r "../dvm-${e2e_target}.zip" \
    "dvm-${e2e_target}")
  (cd "${fixtures}" && (sha256sum "dvm-${e2e_target}.zip" 2> /dev/null \
    || shasum -a 256 "dvm-${e2e_target}.zip") > "dvm-${e2e_target}.zip.sha256")

  if DVM_HOME="${workdir}/home-nested" output="$( (main) 2>&1 )"; then
    check "nested asset refuses" "refused" "installed anyway"
  else
    check "nested asset refuses" "refused" "refused"
  fi
  check "nested asset installs nothing" "1" \
    "$([ -e "${workdir}/home-nested/bin/dvm" ] && echo 0 || echo 1)"

  unset DVM_VERSION
fi


# --- a shadowing dvm ----------------------------------------------------------

# The failure this covers, exactly as it happened: install.sh finished cleanly,
# told the user to run `dvm setup`, and `dvm setup` ran the OLDER cbracken/dvm
# because ~/.zshrc:107 sources its shell script and a function beats PATH. The
# scan below is what turns "bad option: -t" into a file and a line number.
shadow_home="$(mktemp -d)"
mkdir -p "${shadow_home}/.config/fish"

# A .zshrc whose 107th line is the one that bit the user. Every line before it
# is filler so the reported number has to be counted and cannot be guessed.
i=1
while [ "${i}" -lt 107 ]; do
  echo "# filler line ${i}"
  i=$((i + 1))
done > "${shadow_home}/.zshrc"
printf '%s\n' '[ -s "$HOME/.dvm/scripts/dvm" ] && . "$HOME/.dvm/scripts/dvm"' \
  >> "${shadow_home}/.zshrc"

check "legacy source line is found" "0" \
  "$(scan_rc_file "${shadow_home}/.zshrc" | grep -q 'sourcing the older cbracken/dvm' \
    && echo 0 || echo 1)"

# The whole point of the message: a file AND a line, not "found something".
check "legacy source line reports .zshrc:107" "${shadow_home}/.zshrc:107" \
  "$(scan_rc_file "${shadow_home}/.zshrc" | sed -n 's/^\([^ ]*:[0-9]*\):.*/\1/p')"

check "legacy source line quotes the line itself" "0" \
  "$(scan_rc_file "${shadow_home}/.zshrc" \
    | grep -qF '. "$HOME/.dvm/scripts/dvm"' && echo 0 || echo 1)"

# A function definition, in each of the spellings that actually appear.
for definition in 'dvm() {' 'dvm () {' 'dvm(){' 'function dvm {' 'function dvm() {'; do
  printf '%s\n  echo hi\n}\n' "${definition}" > "${shadow_home}/.bashrc"
  check "function definition [${definition}] is found" "0" \
    "$(scan_rc_file "${shadow_home}/.bashrc" | grep -q 'a shell function named dvm' \
      && echo 0 || echo 1)"
done

printf 'alias dvm="~/bin/dvm"\n' > "${shadow_home}/.bash_profile"
check "alias is found" "0" \
  "$(scan_rc_file "${shadow_home}/.bash_profile" | grep -q 'a shell alias named dvm' \
    && echo 0 || echo 1)"
check "alias reports its line" "${shadow_home}/.bash_profile:1" \
  "$(scan_rc_file "${shadow_home}/.bash_profile" | sed -n 's/^\([^ ]*:[0-9]*\):.*/\1/p')"

# FALSE POSITIVES. A startup file that merely mentions dvm is the common case,
# and warning about it sends the user to edit a file that is already correct.
cat > "${shadow_home}/.profile" << 'CLEAN'
# dvm lives in ~/.dvm/bin
export PATH="$HOME/.dvm/bin:$PATH"
dvm use 3.5.0
alias dvmx="dvm --verbose"
# dvm() { echo the old one; }
# alias dvm=nope
echo "run dvm setup"
DVM_HOME="$HOME/.dvm"
CLEAN
check "a clean startup file warns about nothing" "" \
  "$(scan_rc_file "${shadow_home}/.profile")"

# Missing and unreadable files are ordinary, not errors.
check "a missing startup file is silent" "" \
  "$(scan_rc_file "${shadow_home}/.does-not-exist")"

printf 'dvm() { echo hi; }\n' > "${shadow_home}/.zprofile"
chmod 000 "${shadow_home}/.zprofile"
if [ -r "${shadow_home}/.zprofile" ]; then
  # Running as root, where chmod 000 does not make a file unreadable.
  echo "skip unreadable-file check: this user can read a 000 file"
else
  check "an unreadable startup file is silent" "" \
    "$(scan_rc_file "${shadow_home}/.zprofile")"
  check "an unreadable startup file does not fail the run" "0" \
    "$(scan_rc_file "${shadow_home}/.zprofile" > /dev/null 2>&1; echo $?)"
fi
chmod 644 "${shadow_home}/.zprofile"

# The whole-home sweep reaches every candidate, and .zprofile is readable again.
check "the sweep reaches .zshrc, .bashrc, .bash_profile and .zprofile" "4" \
  "$(scan_startup_files "${shadow_home}" | wc -l | tr -d ' ')"

check "the sweep on a home with no startup files is silent" "" \
  "$(scan_startup_files "$(mktemp -d)")"

check "the sweep with no home at all is silent" "" "$(scan_startup_files "")"

# --- the older cbracken/dvm sharing ~/.dvm ------------------------------------

legacy_home="$(mktemp -d)/.dvm"
mkdir -p "${legacy_home}/scripts" "${legacy_home}/darts" "${legacy_home}/environments"
printf 'dvm() { echo old; }\n' > "${legacy_home}/scripts/dvm"

check "legacy install is detected" "3" \
  "$(scan_legacy_install "${legacy_home}" | wc -l | tr -d ' ')"
check "legacy install names the script" "0" \
  "$(scan_legacy_install "${legacy_home}" | grep -q "scripts/dvm" && echo 0 || echo 1)"
check "a dvm home with none of it is silent" "" \
  "$(scan_legacy_install "$(mktemp -d)")"

# --- the closing message ------------------------------------------------------

if ! command -v zip > /dev/null 2>&1; then
  echo "skip closing-message checks: no zip on this machine"
else
  fake_uname_s="Linux"
  fake_uname_m="x86_64"
  e2e_target="linux-x64"
  msgdir="$(mktemp -d)"
  fixtures="${msgdir}/good"
  make_fixture "${fixtures}" dvm ok

  DVM_VERSION="0.2.0"
  export DVM_VERSION

  # A home with nothing shadowing dvm in it.
  clean_home="${msgdir}/clean-home"
  mkdir -p "${clean_home}"
  printf 'export PATH="$HOME/bin:$PATH"\n' > "${clean_home}/.zshrc"

  clean_status=0
  clean_out="$(HOME="${clean_home}" DVM_HOME="${msgdir}/clean-dvm" main 2>&1)" \
    || clean_status=$?

  check "a clean install still exits 0" "0" "${clean_status}"
  check "a clean install prints no shadow warning" "1" \
    "$(echo "${clean_out}" | grep -q 'already defines its own' && echo 0 || echo 1)"

  # OPTION A — one command, by the absolute path this script just wrote. dvm
  # does not have to be on PATH to be RUN, which is the whole reason the setup
  # collapses to one step. Asserted as the FULL command: naming the flag alone
  # would pass on the old three-step message, which named it too.
  check "a clean install offers the one absolute-path command" "0" \
    "$(echo "${clean_out}" \
      | grep -q "${msgdir}/clean-dvm/bin/dvm setup --write-path-line" \
      && echo 0 || echo 1)"

  # OPTION B — one line, for someone who would rather dvm did not edit their
  # files. ONE line covering BOTH directories, not one line each: two lines is
  # two things to paste and two chances to paste only the first.
  check "a clean install offers one combined export line" "0" \
    "$(echo "${clean_out}" \
      | grep -q "export PATH=\"${msgdir}/clean-dvm/shims:${msgdir}/clean-dvm/bin:" \
      && echo 0 || echo 1)"

  # THE REGRESSION GUARD, and the reason it is asserted as literal text: a
  # startup-file line that assigns an EXPANDED absolute PATH discards
  # everything PATH held before it — silently, on every login, erasing whatever
  # the user's own earlier lines added. The line must end with the six
  # characters `$PATH` and a quote, unexpanded. Single quotes below so this
  # test's own shell does not expand it either.
  check "the export line keeps \$PATH literal" "0" \
    "$(echo "${clean_out}" | grep -q 'export PATH="[^"]*:\$PATH"' \
      && echo 0 || echo 1)"
  check "the export line did not bake in an expanded PATH" "1" \
    "$(echo "${clean_out}" | grep -q "export PATH=\"[^\"]*:/usr/bin" \
      && echo 0 || echo 1)"

  # Absolute paths throughout: the point is a line that can be pasted without
  # thinking, and `$HOME/.dvm/...` is a line the reader has to resolve first.
  check "a clean install prints no ~ or \$HOME in its paths" "1" \
    "$(echo "${clean_out}" | grep -q 'PATH="\$HOME\|PATH="~' && echo 0 || echo 1)"

  # The other branch of the same case: ~/.dvm/bin is already on PATH. The
  # SHIMS half can still be missing, so this branch is not "nothing to do" —
  # it is the same two options, shrunk to the half that is still needed.
  onpath_out="$(HOME="${clean_home}" DVM_HOME="${msgdir}/onpath-dvm" \
    PATH="${msgdir}/onpath-dvm/bin:${PATH}" main 2>&1)"

  check "the already-on-PATH branch still offers the one command" "0" \
    "$(echo "${onpath_out}" \
      | grep -q "${msgdir}/onpath-dvm/bin/dvm setup --write-path-line" \
      && echo 0 || echo 1)"
  check "the already-on-PATH branch offers the shims line" "0" \
    "$(echo "${onpath_out}" \
      | grep -q "export PATH=\"${msgdir}/onpath-dvm/shims:" \
      && echo 0 || echo 1)"
  # ...and does NOT re-add the directory that is already there.
  check "the already-on-PATH branch does not re-add bin" "1" \
    "$(echo "${onpath_out}" | grep -q "shims:${msgdir}/onpath-dvm/bin:" \
      && echo 0 || echo 1)"
  check "the already-on-PATH line keeps \$PATH literal" "0" \
    "$(echo "${onpath_out}" | grep -q 'export PATH="[^"]*:\$PATH"' \
      && echo 0 || echo 1)"

  # The same install into a home that has the user's .zshrc:107 in it.
  shadowed_home="${msgdir}/shadowed-home"
  mkdir -p "${shadowed_home}"
  i=1
  while [ "${i}" -lt 107 ]; do
    echo "# filler line ${i}"
    i=$((i + 1))
  done > "${shadowed_home}/.zshrc"
  printf '%s\n' '[ -s "$HOME/.dvm/scripts/dvm" ] && . "$HOME/.dvm/scripts/dvm"' \
    >> "${shadowed_home}/.zshrc"

  shadow_status=0
  shadow_out="$(HOME="${shadowed_home}" DVM_HOME="${msgdir}/shadow-dvm" main 2>&1)" \
    || shadow_status=$?

  # The binary is good and on disk; a warning is not a reason to fail.
  check "a shadowed install still exits 0" "0" "${shadow_status}"
  check "a shadowed install still installs the binary" "0" \
    "$([ -x "${msgdir}/shadow-dvm/bin/dvm" ] && echo 0 || echo 1)"

  check "a shadowed install says the shell defines its own dvm" "0" \
    "$(echo "${shadow_out}" | grep -q 'already defines its own' && echo 0 || echo 1)"
  check "a shadowed install names the file and the line" "0" \
    "$(echo "${shadow_out}" | grep -q "${shadowed_home}/.zshrc:107:" && echo 0 || echo 1)"
  check "a shadowed install says to comment the line out" "0" \
    "$(echo "${shadow_out}" | grep -q 'comment out the line' && echo 0 || echo 1)"
  check "a shadowed install says to start a new shell" "0" \
    "$(echo "${shadow_out}" | grep -q 'start a new shell' && echo 0 || echo 1)"

  # --write-path-line REFUSES while a shadow is present (the `blocked:` guard in
  # setup_command.dart), so the message must order it after the fix rather than
  # hand the user a flag that is guaranteed to decline.
  check "a shadowed install defers --write-path-line" "0" \
    "$(echo "${shadow_out}" | grep -q 'refuses to write' && echo 0 || echo 1)"
  check "a shadowed install orders the fix first" "0" \
    "$(echo "${shadow_out}" | grep -q '1. comment out the line' && echo 0 || echo 1)"

  # And the command is step 3 of that fix, not the headline. A shadowed shell
  # is exactly where `--write-path-line` refuses, so leading with the one-step
  # command would be handing the user something guaranteed to decline.
  check "a shadowed install names the command as step 3" "0" \
    "$(echo "${shadow_out}" \
      | grep -q "${msgdir}/shadow-dvm/bin/dvm setup --write-path-line" \
      && echo 0 || echo 1)"
  check "a shadowed install does not lead with the one command" "1" \
    "$(echo "${shadow_out}" | grep -q 'One command finishes the setup' \
      && echo 0 || echo 1)"
  # Nor does it hand out an export line to paste while the shadow is live: the
  # shadow beats PATH, so the line would change nothing.
  check "a shadowed install hands out no export line" "1" \
    "$(echo "${shadow_out}" | grep -q 'export PATH=' && echo 0 || echo 1)"
  check "a shadowed install says what to clear first" "0" \
    "$(echo "${shadow_out}" | grep -q 'startup files to clear' && echo 0 || echo 1)"

  # The legacy layout is a warning with its own remedy, not part of the failure.
  legacy_dvm="${msgdir}/legacy-dvm"
  mkdir -p "${legacy_dvm}/scripts" "${legacy_dvm}/darts"
  printf 'dvm() { echo old; }\n' > "${legacy_dvm}/scripts/dvm"

  legacy_status=0
  legacy_out="$(HOME="${clean_home}" DVM_HOME="${legacy_dvm}" main 2>&1)" \
    || legacy_status=$?

  check "a legacy-sharing install still exits 0" "0" "${legacy_status}"
  check "a legacy-sharing install says so" "0" \
    "$(echo "${legacy_out}" | grep -q 'older dvm (cbracken/dvm) shares' && echo 0 || echo 1)"
  check "a legacy-sharing install points at dvm migrate" "0" \
    "$(echo "${legacy_out}" | grep -q 'dvm migrate' && echo 0 || echo 1)"

  unset DVM_VERSION
  rm -rf "${msgdir}"
fi

rm -rf "${shadow_home}"
# --- result -------------------------------------------------------------------

if [ "${failures}" -ne 0 ]; then
  echo "${failures} check(s) failed"
  exit 1
fi

echo "install.sh: all checks passed"

#!/usr/bin/env bash
# Preview the installer output without installing or changing any files.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DVM_INSTALL_SH_LIB=1
source "${repo_root}/install.sh"

# Force colors for this preview, including terminals without TERM configured.
color_enabled() { return 0; }

preview_home="${DVM_HOME:-${HOME}/.dvm}"
preview_version="$(sed -n 's/^version: *//p' "${repo_root}/packages/dvm/pubspec.yaml")"
styled '1;32' "dvm v${preview_version} is installed at ${preview_home}/bin/dvm"
print_next_steps "" "${preview_home}" "${preview_home}/bin"

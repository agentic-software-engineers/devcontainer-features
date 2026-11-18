#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"

# Options (uppercased by the CLI): VERSION, STATEDIR.
FEATURE=opencode
VERSION="$(option VERSION latest)"

# Accept only options in the feature's format, before anything is installed.
require_version '^(latest|v?[0-9]+(\.[0-9]+){0,2})$'
# Name the oldest release with the files this feature installs.
MIN_VERSION=2.2.0
# Resolve the latest release from the project's git tags.
PACKAGES+=(git)
# The tool's searches rely on ripgrep.
PACKAGES+=(ripgrep)

# Resolve the request to a release, its archive and its checksum list.
resolve_version() {
  tag="$(release_tag github anomalyco/opencode "$VERSION")"
  local base="https://github.com/anomalyco/opencode/releases/download/$tag"
  url="$base/opencode-linux-$(arch_name x86_64=x64 aarch64=arm64).tar.gz"
  checksums="$base/SHA256SUMS"
}

# Install the binary on the PATH.
install_program() {
  untar
  install_bin "$tmp/opencode"
}

# Write the login profile: the config and the database in the state dir, when set.
profile() {
  if [ -n "$STATE_DIR" ]; then
    echo "export OPENCODE_CONFIG_DIR=\"$STATE_DIR\""
    echo "export OPENCODE_DB=\"$STATE_DIR/opencode.db\""
  fi
}

feature_main

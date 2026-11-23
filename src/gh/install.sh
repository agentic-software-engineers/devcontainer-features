#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"

# Options (uppercased by the CLI): VERSION, STATEDIR.
FEATURE=gh
VERSION="$(option VERSION latest)"

# Accept only options in the feature's format, before anything is installed.
require_version '^(latest|v?[0-9]+(\.[0-9]+){0,2})$'
# Name the oldest release with the files this feature installs.
MIN_VERSION="$(arch_name x86_64= aarch64=0.5.6)"
# Resolve the latest release from the project's git tags.
PACKAGES+=(git)

# Resolve the request to a release, its archive and its checksum list.
resolve_version() {
  tag="$(release_tag github cli/cli "$VERSION")"
  local base="https://github.com/cli/cli/releases/download/$tag"
  # Name the assets by the bare version inside the tagged release.
  url="$base/gh_${tag#v}_linux_$(arch_name x86_64=amd64 aarch64=arm64).tar.gz"
  checksums="$base/gh_${tag#v}_checksums.txt"
}

# Install the binary on the PATH.
install_program() {
  untar
  install_bin "$tmp/bin/gh"
}

# Write the login profile: the config and sign-in in the state dir, when set.
profile() {
  if [ -n "$STATE_DIR" ]; then echo "export GH_CONFIG_DIR=\"$STATE_DIR\""; fi
}

feature_main

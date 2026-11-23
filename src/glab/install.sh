#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"

# Options (uppercased by the CLI): VERSION, STATEDIR.
FEATURE=glab
VERSION="$(option VERSION latest)"

# Accept only options in the feature's format, before anything is installed.
require_version '^(latest|v?[0-9]+\.[0-9]+\.[0-9]+)$'
# Name the oldest release with the files this feature installs.
MIN_VERSION=1.47.0
# Resolve the latest release from the project's git tags.
PACKAGES+=(git)

# Resolve the request to a release, its archive and its checksum list.
resolve_version() {
  tag="$(release_tag gitlab.com gitlab-org/cli "$VERSION")"
  local base="https://gitlab.com/gitlab-org/cli/-/releases/$tag/downloads"
  # Name the assets by the bare version inside the tagged release.
  url="$base/glab_${tag#v}_linux_$(arch_name x86_64=amd64 aarch64=arm64).tar.gz"
  checksums="$base/checksums.txt"
}

# Install the binary on the PATH.
install_program() {
  untar
  install_bin "$tmp/bin/glab"
}

# Write the login profile: the config and sign-in in the state dir, when set.
profile() {
  if [ -n "$STATE_DIR" ]; then echo "export GLAB_CONFIG_DIR=\"$STATE_DIR\""; fi
}

feature_main

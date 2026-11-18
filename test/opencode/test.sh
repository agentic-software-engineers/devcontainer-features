#!/bin/bash
set -e

# Import the test library
source dev-container-features-test-lib

# opencode is on the PATH of a login shell, which reads the feature's profile.
check "opencode on PATH" bash -lc "command -v opencode"

# opencode reports its version.
check "opencode version" bash -lc "opencode --version"

# The single binary sits with the other local programs.
check "opencode installed as a single binary" test -x /usr/local/bin/opencode

# ripgrep is on the PATH, so the tool's searches need no download.
check "ripgrep on PATH" bash -lc "command -v rg"

# Updates keep the vendor default, which o3s hardens through its env.
check "updates left at the vendor default" bash -lc '[ -z "${OPENCODE_DISABLE_AUTOUPDATE:-}" ]'

# The config dir keeps the vendor default when no state dir is set.
check "config dir left at the vendor default" bash -lc '[ -z "${OPENCODE_CONFIG_DIR:-}" ]'

# Report result
reportResults

#!/bin/bash
set -e

# Import the test library
source dev-container-features-test-lib

# Use a login shell, which reads the feature's profile.
check "gh on PATH" bash -lc "command -v gh"
check "gh version" bash -lc "gh --version"
# The single binary sits with the other local programs.
check "gh installed as a single binary" test -x /usr/local/bin/gh
# The feature keeps the tool's own defaults, which o3s hardens through its env.
check "telemetry left at the vendor default" bash -lc '[ -z "${GH_TELEMETRY:-}" ]'
check "config dir left at the vendor default" bash -lc '[ -z "${GH_CONFIG_DIR:-}" ]'

# Report result
reportResults

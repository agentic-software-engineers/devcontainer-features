#!/bin/bash
set -e

# Import the test library
source dev-container-features-test-lib

# Use a login shell, which reads the feature's profile.
check "glab on PATH" bash -lc "command -v glab"
check "glab version" bash -lc "glab --version"
# The single binary sits with the other local programs.
check "glab installed as a single binary" test -x /usr/local/bin/glab
# The feature keeps the tool's own defaults, which o3s hardens through its env.
check "telemetry left at the vendor default" bash -lc '[ -z "${GLAB_SEND_TELEMETRY:-}" ]'
check "config dir left at the vendor default" bash -lc '[ -z "${GLAB_CONFIG_DIR:-}" ]'

# Report result
reportResults

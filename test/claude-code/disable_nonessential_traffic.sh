#!/bin/bash
set -e

# Import the test library
source dev-container-features-test-lib

# With the option on, the login profile keeps telemetry and other optional traffic off.
check "nonessential traffic disabled" bash -lc '[ "$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" = 1 ]'

# Report result
reportResults

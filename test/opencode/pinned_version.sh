#!/bin/bash
set -e

# Import the test library
source dev-container-features-test-lib

# The pinned release is the one installed.
check "pinned to 2.3.2" bash -lc "opencode --version | grep -qwF 'v2.3.2'"

# Report result
reportResults

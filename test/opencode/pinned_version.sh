#!/bin/bash
set -e

# Import the test library
source dev-container-features-test-lib

# The pinned release is the one installed.
check "pinned to 2.4.1" bash -lc "opencode --version | grep -qwF 'v2.4.1'"

# Report result
reportResults

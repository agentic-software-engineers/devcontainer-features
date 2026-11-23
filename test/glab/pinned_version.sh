#!/bin/bash
set -e

# Import the test library
source dev-container-features-test-lib

check "pinned to 1.131.0" bash -lc "glab --version | grep -qwF 'glab 1.131.0'"

# Report result
reportResults

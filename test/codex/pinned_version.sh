#!/bin/bash
set -e

# Import the test library
source dev-container-features-test-lib

check "pinned to 0.169.0" bash -lc "codex --version | grep -qwF '0.169.0'"

# Report result
reportResults

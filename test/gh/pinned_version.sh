#!/bin/bash
set -e

# Import the test library
source dev-container-features-test-lib

check "pinned to 2.105.0" bash -lc "gh --version | grep -qwF 'gh version 2.105.0'"

# Report result
reportResults

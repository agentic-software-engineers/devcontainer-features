#!/bin/bash
set -e

# Import the test library
source dev-container-features-test-lib

check "pinned to 2.104.0" bash -lc "gh --version | grep -qwF 'gh version 2.104.0'"

# Report result
reportResults

#!/bin/bash
set -e

# Import the test library
source dev-container-features-test-lib

check "pinned to 158.0.8127.88" bash -c "chrome-headless-shell --version | grep -qwF '158.0.8127.88'"

# Report result
reportResults

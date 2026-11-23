#!/bin/bash
set -e

# Import the test library
source dev-container-features-test-lib

# The newest release of the requested line is installed, whichever patch that is.
check "resolved the 0.15 line" bash -c "tea --version | sed 's/\x1b\[[0-9;]*m//g' | grep -qE '(^|[^0-9.])0\.15\.[0-9]+'"

# Report result
reportResults

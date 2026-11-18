#!/bin/bash
set -e

# Import the test library
source dev-container-features-test-lib

# The newest release of the requested line is installed, whichever patch that is.
check "resolved the 2.2 line" bash -lc "opencode --version | grep -qE '(^|[^0-9.])2\.2\.[0-9]+'"

# Report result
reportResults

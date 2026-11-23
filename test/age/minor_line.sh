#!/bin/bash
set -e

# Import the test library
source dev-container-features-test-lib

# The newest release of the requested line is installed, whichever patch that is.
check "resolved the 1.2 line" bash -c "age --version | grep -qE '(^|[^0-9.])v1\.2\.[0-9]+'"

# Report result
reportResults

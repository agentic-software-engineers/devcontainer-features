#!/bin/bash
set -e

# Import the test library
source dev-container-features-test-lib

# The newest release of the requested line is installed, whichever patch that is.
check "resolved the 3.12 line" bash -c "sops --version --disable-version-check | grep -qE '(^|[^0-9.])3\.12\.[0-9]+'"

# Report result
reportResults

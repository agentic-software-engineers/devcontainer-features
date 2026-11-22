#!/bin/bash
set -e

# Import the test library
source dev-container-features-test-lib

# The newest release of each requested line is installed, whichever patch that is.
check "kind resolved the 0.32 line" bash -lc "kind version | grep -qE '(^|[^0-9.])v?0\.32\.[0-9]+'"
check "kubectl resolved the 1.36 line" bash -lc "kubectl version --client | grep -qE '(^|[^0-9.])v?1\.36\.[0-9]+'"

# Report result
reportResults

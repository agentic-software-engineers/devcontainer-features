#!/bin/bash
set -e

# Import the test library
source dev-container-features-test-lib

KIND="0.33.0"
KUBECTL="1.37.2"

check "kind pinned to $KIND" bash -lc "kind version | grep -qwF 'v$KIND'"
check "kubectl pinned to $KUBECTL" bash -lc "kubectl version --client | grep -qwF 'v$KUBECTL'"

# Report result
reportResults

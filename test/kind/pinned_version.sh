#!/bin/bash
set -e

# Import the test library
source dev-container-features-test-lib

check "kind pinned to 0.33.0" bash -lc "kind version | grep -qwF 'v0.33.0'"
check "kubectl pinned to 1.37.2" bash -lc "kubectl version --client | grep -qwF 'v1.37.2'"

# Report result
reportResults

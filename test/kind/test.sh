#!/bin/bash
set -e

# Import the test library
source dev-container-features-test-lib

# kind is on the PATH and reports its version.
check "kind on PATH" bash -lc "command -v kind"
check "kind version" bash -lc "kind version"

# kubectl is on the PATH and reports its client version.
check "kubectl on PATH" bash -lc "command -v kubectl"
check "kubectl version" bash -lc "kubectl version --client"

# Both single binaries sit with the other local programs.
check "kind installed as a single binary" test -x /usr/local/bin/kind
check "kubectl installed as a single binary" test -x /usr/local/bin/kubectl

# Report result
reportResults

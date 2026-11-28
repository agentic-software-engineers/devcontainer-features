#!/bin/bash
set -e

# Import the test library
source dev-container-features-test-lib

ENGINE="29.10.1"
BUILDX="0.39.1"
COMPOSE="5.8.1"

check "engine pinned to $ENGINE" bash -c "docker --version | grep -qwF '$ENGINE'"
check "buildx pinned to $BUILDX" bash -c "docker buildx version | grep -qwF 'v$BUILDX'"
check "compose pinned to $COMPOSE" bash -c "docker compose version | grep -qwF 'v$COMPOSE'"

# Report result
reportResults

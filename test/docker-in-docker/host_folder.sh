#!/bin/bash
set -e

# Import the test library
source dev-container-features-test-lib

# Wait for the background daemon, reaching it through the published name.
check "daemon reachable" bash -c 'for _ in $(seq 30); do docker info >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1'
# The daemon serves the socket in its runtime folder.
check "own socket answers" bash -c '[ -S "/run/user/$(id -u)/docker.sock" ]'
# A folder mounted where the shared socket once went stays empty, so the daemon serves its own socket alone.
check "the mounted host folder stays empty" bash -c '[ -z "$(ls -A /run/docker-host)" ]'
# Show the daemon's log when a check fails.
check "nested container runs" bash -c 'docker run --rm hello-world || { echo "--- dockerd.log ---" >&2; cat /tmp/dockerd.log >&2; exit 1; }'

# Report result
reportResults

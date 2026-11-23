#!/bin/bash
set -e

# Import the test library
source dev-container-features-test-lib

# Run as a non-root dev user, whose home keeps the state dir theirs across a UID remap.
check "state dir pre-created" test -d /home/ubuntu/.local/state/glab
check "state dir writable by the dev user" bash -c 'touch /home/ubuntu/.local/state/glab/.probe && rm /home/ubuntu/.local/state/glab/.probe'
check "the folders above the state dir belong to the dev user" bash -c '[ "$(stat -c %U /home/ubuntu/.local /home/ubuntu/.local/state | sort -u)" = ubuntu ]'

# Run the hook as a container create does.
/usr/local/libexec/glab/init.sh

check "GLAB_CONFIG_DIR exported" bash -lc '[ "$GLAB_CONFIG_DIR" = /home/ubuntu/.local/state/glab ]'

# A global config change lands in the state dir, where the sign-in lives too.
check "config writes land in the state dir" \
  bash -lc 'glab config set --global editor vim && grep -q "editor: vim" /home/ubuntu/.local/state/glab/config.yml'

# The hook keeps the state dir private to the dev user.
check "state dir private to the dev user" \
  bash -c '[ -z "$(find /home/ubuntu/.local/state/glab -maxdepth 0 -perm /g+rwx,o+rwx)" ]'

# This scenario keeps the state dir on the container filesystem, which the hook warns about.
check "the hook reports the unmounted state dir" \
  bash -c '/usr/local/libexec/glab/init.sh 2>&1 >/dev/null | grep -q "on the container filesystem"'

# A path outside the home proves the guard rejects what it should.
check "a state dir outside the home is refused" \
  bash -c '! /usr/local/libexec/glab/state-dir.sh glab /var/glab'
check "the refusal names the home" \
  bash -c '/usr/local/libexec/glab/state-dir.sh glab /var/glab 2>&1 | grep -q "must be inside /home/ubuntu"'

# Report result
reportResults

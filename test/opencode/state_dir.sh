#!/bin/bash
set -e

# Import the test library
source dev-container-features-test-lib

# The build creates the state dir for the dev user.
check "state dir pre-created" test -d /home/ubuntu/.local/state/opencode

# The dev user can write to the state dir.
check "state dir writable by the dev user" bash -c 'touch /home/ubuntu/.local/state/opencode/.probe && rm /home/ubuntu/.local/state/opencode/.probe'

# The folders above the state dir belong to the dev user.
check "the folders above the state dir belong to the dev user" bash -c '[ "$(stat -c %U /home/ubuntu/.local /home/ubuntu/.local/state | sort -u)" = ubuntu ]'

# Run the hook as a container create does.
/usr/local/libexec/opencode/init.sh

# The config dir points at the state dir.
check "OPENCODE_CONFIG_DIR exported" bash -lc '[ "$OPENCODE_CONFIG_DIR" = /home/ubuntu/.local/state/opencode ]'

# The database, which holds sessions and sign-ins, sits in the state dir.
check "OPENCODE_DB exported" bash -lc '[ "$OPENCODE_DB" = /home/ubuntu/.local/state/opencode/opencode.db ]'

# The hook keeps the state dir private to the dev user.
check "state dir private to the dev user" \
  bash -c '[ -z "$(find /home/ubuntu/.local/state/opencode -maxdepth 0 -perm /g+rwx,o+rwx)" ]'

# The hook warns about a state dir on the container filesystem.
check "the hook reports the unmounted state dir" \
  bash -c '/usr/local/libexec/opencode/init.sh 2>&1 >/dev/null | grep -q "on the container filesystem"'

# The guard refuses a state dir outside the home.
check "a state dir outside the home is refused" \
  bash -c '! /usr/local/libexec/opencode/state-dir.sh opencode /var/opencode'

# The refusal names the home.
check "the refusal names the home" \
  bash -c '/usr/local/libexec/opencode/state-dir.sh opencode /var/opencode 2>&1 | grep -q "must be inside /home/ubuntu"'

# Report result
reportResults

#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"

# Options (uppercased by the CLI): VERSION, STATEDIR, DISABLENONESSENTIALTRAFFIC.
FEATURE=claude-code
VERSION="$(option VERSION latest)"
DISABLE_NONESSENTIAL_TRAFFIC="$(option DISABLENONESSENTIALTRAFFIC false)"

# Accept only options in the feature's format, before anything is installed.
require_version '^(latest|stable|[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?)$'
require_version '^(true|false)$' "$DISABLE_NONESSENTIAL_TRAFFIC" disableNonessentialTraffic

# Hand the requested version to the vendor installer, which fetches and checks the tool itself.
resolve_version() {
  tag="$VERSION"
  delegated="the vendor installer checks each download against its release manifest"
}

# Run the vendor installer as the dev user, who owns the result.
install_program() {
  as_user "curl -fsSL https://claude.ai/install.sh | bash -s -- '$VERSION'"
}

# Write the login profile: the tool's PATH, the state dir when set, and the traffic switch when on.
profile() {
  echo 'export PATH="$HOME/.local/bin:$PATH"'
  if [ -n "$STATE_DIR" ]; then echo "export CLAUDE_CONFIG_DIR=\"$STATE_DIR\""; fi
  if [ "$DISABLE_NONESSENTIAL_TRAFFIC" = true ]; then echo 'export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1'; fi
}

# Confirm the tool runs for the dev user.
confirm() {
  as_user "claude --version"
}

feature_main

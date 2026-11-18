#!/usr/bin/env bash
# Keep every feature's description equal to its line in the README, which names each feature once.
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"

python3 -I - "$root" <<'PY'
import json, pathlib, re, sys

root = pathlib.Path(sys.argv[1])
readme = root / "README.md"
# Read each row's description by the feature id its image names.
rows = {}
for line in (readme.read_text() if readme.exists() else "").splitlines():
    match = re.match(r"\| [^|]+ \| (.+?) \| `ghcr\.io/hansehart/devcontainer-features/([a-z0-9-]+)` \|", line)
    # Keep the rows that name a feature's image.
    if match:
        rows[match.group(2)] = match.group(1)
problems, checked = [], 0
# Compare each feature's description with its row.
for path in sorted(root.glob("src/*/devcontainer-feature.json")):
    checked += 1
    feature = f"src/{path.parent.name}"
    description = json.loads(path.read_text()).get("description")
    # Name a feature the README leaves out, and one whose description differs.
    if path.parent.name not in rows:
        problems.append(f"{feature}: needs a README row")
    elif description != rows[path.parent.name]:
        problems.append(f"{feature}: the description differs from its README line")
# Report every problem found.
for problem in problems:
    print(problem, file=sys.stderr)
print(f"{checked} features checked")
sys.exit(1 if problems else 0)
PY

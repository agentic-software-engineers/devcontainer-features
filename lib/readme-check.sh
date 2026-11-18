#!/usr/bin/env bash
# Keep every feature's description equal to its line in the README, which names each feature once.
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
command -v jq >/dev/null || { echo "the README check needs jq" >&2; exit 1; }

readme="$root/README.md"
# Read an absent README as an empty one, so every feature is named as missing.
if [ ! -f "$readme" ]; then readme=/dev/null; fi

problems=0
checked=0
# Compare each feature's description with its row, found by the image the row names.
for path in "$root"/src/*/devcontainer-feature.json; do
  checked=$((checked + 1))
  id="$(basename "$(dirname "$path")")"
  row="\\| [^|]+ \\| (.+) \\| \`ghcr\\.io/hansehart/devcontainer-features/$id\` \\|"
  # Name a feature the README leaves out, and one whose description differs.
  if ! grep -qE "^$row" "$readme"; then
    echo "src/$id: needs a README row" >&2
    problems=$((problems + 1))
  elif [ "$(jq -r '.description // ""' "$path")" != "$(sed -nE "s#^$row.*#\\1#p" "$readme" | head -n1)" ]; then
    echo "src/$id: the description differs from its README line" >&2
    problems=$((problems + 1))
  fi
done

echo "$checked features checked"
[ "$problems" -eq 0 ]

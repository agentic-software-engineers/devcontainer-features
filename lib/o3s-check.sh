#!/usr/bin/env bash
# Keep every feature's o3s metadata in one shape: lists of entries that each carry a name and
# a description, plus the fields their kind needs.
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
command -v jq >/dev/null || { echo "the o3s check needs jq" >&2; exit 1; }

problems=0
checked=0
# Check each feature's o3s section.
for path in "$root"/src/*/devcontainer-feature.json; do
  checked=$((checked + 1))
  feature="src/$(basename "$(dirname "$path")")"
  # Name a missing section, a section out of shape, and every entry that misses a field its kind
  # needs beside its name and description.
  found="$(jq -r --arg feature "$feature" '
    .customizations.o3s as $o3s
    | {hosts: ["ports"], env: ["value"], files: ["target"]} as $needs
    | if $o3s == null then "\($feature): needs an o3s section"
      else
        ($o3s | keys_unsorted[] | select($needs[.] == null)
          | "\($feature): \(.) sits beside the sections hosts, env and files"),
        ($needs | to_entries[] | .key as $kind | .value as $fields | ($o3s[$kind] // []) as $entries
          | if ($entries | type) != "array" then "\($feature): \($kind) must be a list"
            else $entries | to_entries[] | .key as $i | .value as $entry
              | (["name", "description"] + $fields)[]
              | select(($entry[.] // "") | . == "" or . == [] or . == 0 or . == false)
              | "\($feature): \($kind)[\($i)] needs a \(.)"
            end)
      end' "$path")"
  # Report the problems this feature has.
  if [ -n "$found" ]; then
    echo "$found" >&2
    problems=$((problems + $(wc -l <<<"$found")))
  fi
done

echo "$checked features checked"
[ "$problems" -eq 0 ]

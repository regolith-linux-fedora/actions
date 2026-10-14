#!/usr/bin/env bash
#
# Install the Fedora workflow stubs into a package repository:
#
#   tools/install-fedora-workflows.sh <repo-dir>
#
# Copies templates/fedora/*.yml into <repo-dir>/.github/workflows/. Safe to run
# again: unchanged stubs are left alone, outdated ones are replaced. Upstream's
# Debian workflows are not touched.

set -euo pipefail

if [ $# -ne 1 ] || [ ! -d "$1" ]; then
  echo "Usage: $0 <repo-dir>" >&2
  exit 1
fi

TEMPLATES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../templates/fedora" && pwd)"
TARGET="$1/.github/workflows"

mkdir -p "$TARGET"

for template in "$TEMPLATES"/*.yml; do
  name="$(basename "$template")"
  if [ -f "$TARGET/$name" ] && cmp -s "$template" "$TARGET/$name"; then
    echo "unchanged: .github/workflows/$name"
  elif [ -f "$TARGET/$name" ]; then
    cp "$template" "$TARGET/$name"
    echo "updated:   .github/workflows/$name"
  else
    cp "$template" "$TARGET/$name"
    echo "added:     .github/workflows/$name"
  fi
done

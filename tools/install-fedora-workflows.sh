#!/usr/bin/env bash
#
# Install the Fedora workflow stubs into a package repository:
#
#   tools/install-fedora-workflows.sh [--name <package>] <repo-dir>
#
# Copies templates/fedora/*.yml into <repo-dir>/.github/workflows/. Safe to run
# again: unchanged stubs are left alone, outdated ones are replaced. Upstream's
# Debian workflows are not touched.
#
# --name sets the package name the stubs pass to the reusable workflows, for a
# repository whose name differs from the package (and its voulage package
# model entry). Without it they use the repository name.

set -euo pipefail

usage() {
  echo "Usage: $0 [--name <package>] <repo-dir>" >&2
  exit 1
}

PACKAGE=""
if [ "${1:-}" = "--name" ]; then
  [ $# -ge 2 ] && [ -n "$2" ] || usage
  PACKAGE="$2"
  shift 2
fi
if [ $# -ne 1 ] || [ ! -d "$1" ]; then
  usage
fi

TEMPLATES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../templates/fedora" && pwd)"
TARGET="$1/.github/workflows"

mkdir -p "$TARGET"

# Print a stub: the template, with the package name passed on when given.
stub() {
  if [ -z "$PACKAGE" ]; then
    cat "$1"
  else
    awk -v pkg="$PACKAGE" '
      /^    secrets: inherit$/ {
        print "    # The package (and its voulage package model entry) is " pkg ","
        print "    # not the repository name."
        print "    with:"
        print "      name: " pkg
      }
      { print }
    ' "$1"
  fi
}

for template in "$TEMPLATES"/*.yml; do
  name="$(basename "$template")"
  if [ -f "$TARGET/$name" ] && stub "$template" | cmp -s - "$TARGET/$name"; then
    echo "unchanged: .github/workflows/$name"
  elif [ -f "$TARGET/$name" ]; then
    stub "$template" > "$TARGET/$name"
    echo "updated:   .github/workflows/$name"
  else
    stub "$template" > "$TARGET/$name"
    echo "added:     .github/workflows/$name"
  fi
done

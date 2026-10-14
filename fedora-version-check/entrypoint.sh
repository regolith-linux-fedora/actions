#!/usr/bin/env bash

set -e

cd "${PACKAGE_PATH:-.}"

SPEC="${PACKAGE_NAME}.spec"
if [ ! -f "$SPEC" ]; then
  specs=(*.spec)
  if [ "${#specs[@]}" -ne 1 ] || [ ! -f "${specs[0]}" ]; then
    echo "Error: ${SPEC} not found"
    exit 1
  fi
  SPEC="${specs[0]}"
fi

spec_version=$(rpmspec -q --srpm --qf '%{version}' "$SPEC")

if [ ! -f debian/changelog ]; then
  echo "No debian/changelog, nothing to compare ${SPEC} version ${spec_version} with."
  # shellcheck disable=SC2086
  echo "spec-version=${spec_version}" >> $GITHUB_OUTPUT
  exit 0
fi

# First line: <source> (<version>) <distribution>; urgency=<urgency>
full_version=$(head -n1 debian/changelog | sed -E 's/^[^ ]+ \(([^)]+)\).*/\1/')

# Drop the epoch and the Debian revision, keep the upstream version
debian_version="${full_version#*:}"
if [[ "$debian_version" == *-* ]]; then
  debian_version="${debian_version%-*}"
fi

echo "Spec version:            ${spec_version} (${SPEC})"
echo "debian/changelog version: ${full_version} (upstream ${debian_version})"

# shellcheck disable=SC2086
echo "spec-version=${spec_version}" >> $GITHUB_OUTPUT
# shellcheck disable=SC2086
echo "debian-version=${debian_version}" >> $GITHUB_OUTPUT

if [ "$spec_version" != "$debian_version" ]; then
  echo "::error file=${SPEC}::Version ${spec_version} doesn't match debian/changelog upstream version ${debian_version}"
  exit 1
fi

echo -e "\033[0;32mVersions match.\033[0m"

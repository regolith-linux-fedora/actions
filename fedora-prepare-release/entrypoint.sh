#!/usr/bin/env bash

set -e

if [ -z "$VOULAGE_PATH" ]; then
  echo "error: VOULAGE_PATH is empty"
  exit 1
fi
if [ ! -d "$VOULAGE_PATH" ]; then
  echo "error: voulage repo not found"
  exit 1
fi

RELEASE_EXISTS=""
RELEASE_VERSION=""
MODELS_MATCHED=0

find_spec() {
  if [ -f "${PACKAGE_NAME}.spec" ]; then
    echo "${PACKAGE_NAME}.spec"
    return 0
  fi

  local specs=(*.spec)
  if [ "${#specs[@]}" -eq 1 ] && [ -f "${specs[0]}" ]; then
    echo "${specs[0]}"
    return 0
  fi

  return 1
}

generate_tag_name() {
  local spec version_release

  if ! spec=$(find_spec); then
    echo -e "\033[0;31m${PACKAGE_NAME}.spec not found.\033[0m"
    return 1
  fi

  # %{?dist} is not part of the release tag
  version_release=$(rpmspec -q --srpm --define "dist %{nil}" --qf '%{version}-%{release}' "$spec")

  # same character clean up as prepare-release, so the tag is a valid git ref
  RELEASE_VERSION=$(echo "fedora/v${version_release}" | sed 's/:/./g' | sed 's/[\~\^\?\[\*]/-/g')
}

process_model() {
  # model_sub_path is empty, or a codename ending with a slash (e.g. 43/)
  local model_sub_path=$1

  echo -e "\033[0;34mProcessing '${PACKAGE_NAME}' in 'unstable/fedora/${model_sub_path}'\033[0m"

  if ! get_model "unstable/fedora/${model_sub_path}"; then
    echo "Skip further processing."
    echo ""
    return
  fi

  MODELS_MATCHED=$((MODELS_MATCHED + 1))

  if ! update_model "testing/fedora/${model_sub_path}"; then
    echo -e "\033[0;31mUpdate package at 'testing/fedora/${model_sub_path}' failed.\033[0m"
    echo ""
    return
  fi

  echo ""
}

get_model() {
  # stage_path ends with a slash (e.g. unstable/fedora/, unstable/fedora/43/)
  local stage_path=$1

  local model_file="stage/${stage_path%/}/package-model.json"

  if [ ! -f "$model_file" ]; then
    echo "error: $model_file not found"
    return 1
  fi

  echo "Looking for package in model..."

  packages=$(jq -r '.packages' "$model_file")
  has_package=$(echo "$packages" | jq 'has("'"${PACKAGE_NAME}"'")')

  if [ "$has_package" == "true" ]; then
    package=$(echo "$packages" | jq -r '.["'"${PACKAGE_NAME}"'"]')

    # Package is explictly set to null. Skip it.
    if [ "$package" == "null" ]; then
      echo "Package is explicitly set to null."
      return 1
    else
      ref=$(echo "$package" | jq -r '.ref')

      if [ "$ref" != "$PACKAGE_REF" ]; then
        echo "Model ref ($ref) and requested ref ($PACKAGE_REF) don't match."
        return 1
      fi

      echo "Package found."
      return 0
    fi
  else
    echo "Package not found."
    return 1
  fi
}

update_model() {
  # stage_path ends with a slash (e.g. testing/fedora/, testing/fedora/43/)
  local stage_path=$1

  local model_path="stage/${stage_path%/}/"
  local model_file="${model_path%/}/package-model.json"

  echo "Updating package in '${stage_path}'."

  if [ ! -d "$model_path" ] || [ ! -f "$model_file" ]; then
    echo "Warning: Model file '${stage_path}' not found."
    return 1
  fi

  jq -S '.packages.["'"${PACKAGE_NAME}"'"].ref="'"$RELEASE_VERSION"'" | .packages.["'"${PACKAGE_NAME}"'"].source="'"$PACKAGE_REPO"'" ' "$model_file" > "$model_file.tmp"

  if cmp -s "$model_file" "$model_file.tmp"; then
    rm "$model_file.tmp"
  else
    mv "$model_file.tmp" "$model_file"
  fi

  echo "Updated package ref to '${RELEASE_VERSION}'."
}

main() {
  if ! generate_tag_name; then
    exit 1
  fi

  echo "Package name: ${PACKAGE_NAME}"
  echo "Package repo: ${PACKAGE_REPO}"
  echo "Package ref : ${PACKAGE_REF}"
  echo "Release name: ${RELEASE_VERSION}"
  echo ""

  echo -e "\033[0;34mLooking for release '${RELEASE_VERSION}' in ${PACKAGE_REPO}\033[0m"

  # current tag does exist in the repository, do not recreate it again
  if [ "$(git tag --list "${RELEASE_VERSION}" | wc -l)" != 0 ] ; then
    RELEASE_EXISTS=true
    echo "Release exists! Do not recreate it again!"

    return
  fi

  RELEASE_EXISTS=false
  echo "Release not found!"
  echo ""

  pushd "$VOULAGE_PATH" >/dev/null || exit 1

  # process package-models at distro level
  process_model ""

  # process package-models at codename level
  for dir in stage/unstable/fedora/*/; do
    codename=$(echo "$dir" | cut -d/ -f4)

    process_model "$codename/"
  done

  popd >/dev/null || exit 1

  # Only branches that a Fedora unstable model builds from are released
  if [ "$MODELS_MATCHED" -eq 0 ]; then
    RELEASE_EXISTS=skip
    echo "No Fedora unstable model builds ${PACKAGE_NAME} from ${PACKAGE_REF}, not releasing."
  fi
}

main

# shellcheck disable=SC2086
echo "release-exists=${RELEASE_EXISTS}" >> $GITHUB_OUTPUT

# shellcheck disable=SC2086
echo "release-version=${RELEASE_VERSION}" >> $GITHUB_OUTPUT

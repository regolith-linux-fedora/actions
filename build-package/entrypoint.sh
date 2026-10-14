#!/usr/bin/env bash

set -eo pipefail

if [ -z "$VOULAGE_PATH" ]; then
  echo "Error: VOULAGE_PATH is empty"
  exit 1
fi
if [ ! -d "$VOULAGE_PATH" ]; then
  echo "Error: voulage repo not found"
  exit 1
fi
if [ ! -f "$VOULAGE_PATH/.github/scripts/ci-build.sh" ]; then
  echo "Error: voulage ci-build.sh script not found"
  exit 1
fi

export DEBEMAIL="${GPG_EMAIL}"
export DEBFULLNAME="${GPG_NAME}"

EXTENSION="ext-debian.sh"
if [ "$DISTRO" == "fedora" ]; then
  EXTENSION="ext-rpm.sh"

  # ext-rpm.sh submits to COPR only when asked to
  if [ "$BUILD_ONLY" == "false" ]; then
    export COPR_PUBLISH="yes"
  fi
fi

echo -e "\033[0;34mBuilding ${PACKAGE_NAME} for ${DISTRO}/${CODENAME} (stage=${STAGE} arch=${ARCH} component=${COMPONENT})...\033[0m"

# working directories
WORKSPACE_PATH=$(realpath "$(realpath "$WORKSPACE_PATH")/../")
WORKING_DIR=$(realpath "/build/")

# raw build log file
TARGET_ID="${DISTRO}-${CODENAME}-${STAGE}-${ARCH}"
RAW_BUILD_LOG="${WORKING_DIR}/buildlog/BUILD_LOG_${TARGET_ID}.raw.txt"

"${VOULAGE_PATH}/.github/scripts/ci-build.sh" \
  --build-only "${BUILD_ONLY}" \
  --package-name "${PACKAGE_NAME}" \
  --extension "${EXTENSION}" \
  --pkg-build-path "${WORKSPACE_PATH}" \
  --pkg-publish-path "${WORKING_DIR}/publish" \
  --distro "${DISTRO}" \
  --codename "${CODENAME}" \
  --stage "${STAGE}" \
  --suite "${SUITE}" \
  --component "${COMPONENT}" \
  --arch "${ARCH}" \
  | tee -a "${RAW_BUILD_LOG}"

# generate changelog and sourcelog
if [ "$BUILD_ONLY" == "false" ]; then
  echo "::group::Generating buildlogs"
  touch "${WORKING_DIR}/buildlog/CHANGELOG_${TARGET_ID}.txt"
  if grep "^CHLOG:" "${RAW_BUILD_LOG}" >/dev/null; then
    grep "^CHLOG:" "${RAW_BUILD_LOG}" | cut -c 7- > "${WORKING_DIR}/buildlog/CHANGELOG_${TARGET_ID}.txt"
  fi
  echo -e "\033[0;34mGenerated ${WORKING_DIR}/buildlog/CHANGELOG_${TARGET_ID}.txt successfully.\033[0m"

  touch "${WORKING_DIR}/buildlog/SOURCELOG_${TARGET_ID}.txt"
  if [ "$DISTRO" == "fedora" ]; then
    # COPR builds from the source RPM, there are no shared sources to rebuild
    rm "${WORKING_DIR}/buildlog/SOURCELOG_${TARGET_ID}.txt"
  elif grep "^SRCLOG:" "${RAW_BUILD_LOG}" >/dev/null; then
    grep "^SRCLOG:" "${RAW_BUILD_LOG}" | cut -c 8- > "${WORKING_DIR}/buildlog/SOURCELOG_${TARGET_ID}.txt"
  else
    # sourcelog is empty, this means the version is brand new and
    # we're going to force create one to unify the .orig.tar.gz file
    # between parallel running jobs

    pushd "$WORKSPACE_PATH/$PACKAGE_NAME" >/dev/null

    debian_package_name=$(dpkg-parsechangelog --show-field Source)
    full_version=$(dpkg-parsechangelog --show-field Version)
    debian_version="${full_version%-*}"

    debian_package_name_indicator="${debian_package_name:0:1}"
    if [ "${debian_package_name:0:3}" == "lib" ]; then
      debian_package_name_indicator="${debian_package_name:0:4}"
    fi

    popd >/dev/null

    echo "$DISTRO=$CODENAME=$SUITE=${debian_package_name_indicator}=${debian_package_name}=${debian_package_name}_${debian_version}=${debian_package_name}_${debian_version}.orig.tar.gz" > "${WORKING_DIR}/buildlog/SOURCELOG_${TARGET_ID}.txt"
  fi
  if [ -f "${WORKING_DIR}/buildlog/SOURCELOG_${TARGET_ID}.txt" ]; then
    echo -e "\033[0;34mGenerated ${WORKING_DIR}/buildlog/SOURCELOG_${TARGET_ID}.txt successfully.\033[0m"
  fi
  echo "::endgroup::"
fi

# list the generated files for debugging purposes
if [ "$BUILD_ONLY" == "false" ]; then
  echo "::group::Listing content of publish folder"
  find "${WORKING_DIR}/publish"
  echo "::endgroup::"
fi

# cleanup build log
rm "${RAW_BUILD_LOG}"

# print changelog and sourcelog for debugging purposes
if [ "$BUILD_ONLY" == "false" ]; then
  echo "::group::Printing changelog"
  cat "${WORKING_DIR}/buildlog/CHANGELOG_${TARGET_ID}.txt"
  echo "::endgroup::"

  if [ -f "${WORKING_DIR}/buildlog/SOURCELOG_${TARGET_ID}.txt" ]; then
    echo "::group::Printing sourcelog"
    cat "${WORKING_DIR}/buildlog/SOURCELOG_${TARGET_ID}.txt"
    echo "::endgroup::"
  fi
fi

# shellcheck disable=SC2086
echo "publish-path=${WORKING_DIR}/publish/" >> $GITHUB_OUTPUT

# shellcheck disable=SC2086
echo "buildlog-path=${WORKING_DIR}/buildlog/" >> $GITHUB_OUTPUT

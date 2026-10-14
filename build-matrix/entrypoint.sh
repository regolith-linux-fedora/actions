#!/usr/bin/env bash

set -e

if [ "$MATRIX_TYPE" != "package" ] && [ "$MATRIX_TYPE" != "platform" ]; then
  echo "Error: unknown matrix type ($MATRIX_TYPE)"
  exit 1
fi

if [ "$MATRIX_TYPE" == "package" ]; then
  if [ -z "$PACKAGE_NAME" ]; then
    echo "Error: package name is missing"
    exit 1
  fi
  if [ -z "$PACKAGE_REF" ]; then
    echo "Error: package ref is missing"
    exit 1
  fi
fi

if [ -z "$VOULAGE_PATH" ]; then
  echo "Error: VOULAGE_PATH is empty"
  exit 1
fi
if [ ! -d "$VOULAGE_PATH" ]; then
  echo "Error: voulage repo not found"
  exit 1
fi

if [ ! -d "$VOULAGE_PATH/stage" ]; then
  echo "Error: $VOULAGE_PATH/stage doesn't exist"
  exit 1
fi
if [ ! -d "$VOULAGE_PATH/stage/$BUILD_STAGE" ]; then
  echo "Error: $VOULAGE_PATH/stage/$BUILD_STAGE doesn't exist"
  exit 1
fi

FEDORA_CI_IMAGE="${FEDORA_CI_IMAGE:-ghcr.io/regolith-linux-fedora/ci-fedora}"

includes=()
error_msg=""
STAGE_MODEL_PACKAGE_REF="n/a"
DISTRO_MODEL_PACKAGE_REF="n/a"

process_model() {
  process_level="$1"
  model_file="$2"

  error_msg=""

  if [ -z "$process_level" ]; then
    error_msg="process level is empty (e.g. package, distro)"
    return 1
  fi
  if [ -z "$model_file" ]; then
    error_msg="model file is empty"
    return 1
  fi

  if [ ! -f "$model_file" ]; then
    error_msg="model file cannot be found"
    return 1
  fi

  packages=$(jq -r '.packages' "$model_file")
  has_package=$(echo "$packages" | jq 'has("'"${PACKAGE_NAME}"'")')

  # Package is listed in package-model.json file.
  #
  # This could mean either of:
  #  - the package ref gets overridden
  #  - the package should be completely skipped
  if [ "$has_package" == "true" ]; then
    package=$(echo "$packages" | jq -r '.["'"${PACKAGE_NAME}"'"]')

    # Package is explictly set to null. Ignore it.
    if [ "$package" == "null" ]; then
      error_msg="Skipped (model is explicitly set to null)"
      return 1
    else
      ref=$(echo "$package" | jq -r '.ref')

      if [ "$process_level" == "stage" ]; then
        STAGE_MODEL_PACKAGE_REF="$ref"
      fi
      if [ "$process_level" == "distro-root" ]; then
        DISTRO_MODEL_PACKAGE_REF="$ref"
      fi

      # Package ref is different that the ref we are executing this on.
      # Note: this is only needed on distro level.
      if [ "$process_level" == "distro" ]; then
        if [ "$ref" != "$PACKAGE_REF" ]; then
          error_msg="Ignored (request ref: $PACKAGE_REF, model ref: $ref)"
          return 1
        fi
      fi
    fi
  else
    if [ "$process_level" == "stage" ]; then
      # Don't 'return 1' here!
      echo "  - package not found in stage model (it might exist in distro level)"
      echo ""
    elif [ "$process_level" == "distro" ]; then
      # Codename doesn't explicitly override the stage or distro model. We
      # just need to make sure the inherited ref is the same as requested ref.
      if [ "$DISTRO_MODEL_PACKAGE_REF" != "$PACKAGE_REF" ]; then
        error_msg="Ignored (request ref: $PACKAGE_REF, model ref: $DISTRO_MODEL_PACKAGE_REF)"
        return 1
      fi
    fi
  fi

  return 0
}

main() {
  echo "Supported distro/codename:"

  pushd "$VOULAGE_PATH" >/dev/null || exit 1

  if [ "$MATRIX_TYPE" == "package" ]; then
    if ! process_model "stage" "stage/$BUILD_STAGE/package-model.json"; then
      echo "  - $error_msg"
      return
    fi
  fi

  for dir in stage/"$BUILD_STAGE"/*/*/; do
    distro=$(echo "$dir" | cut -d/ -f3)
    codename=$(echo "$dir" | cut -d/ -f4)

    if [ -n "$FILTER_DISTRO" ] && [ "$FILTER_DISTRO" != "$distro" ]; then
      continue
    fi
    if [ -n "$FILTER_CODENAME" ] && [ "$FILTER_CODENAME" != "$codename" ]; then
      continue
    fi

    # An optional distro level model (e.g. stage/unstable/fedora/package-model.json)
    # sits between the stage and the codename models, as in voulage's merge.
    DISTRO_MODEL_PACKAGE_REF="$STAGE_MODEL_PACKAGE_REF"
    if [ "$MATRIX_TYPE" == "package" ] && [ -f "stage/$BUILD_STAGE/$distro/package-model.json" ]; then
      if ! process_model "distro-root" "stage/$BUILD_STAGE/$distro/package-model.json"; then
        echo "  - $distro/$codename: $error_msg"
        continue
      fi
    fi

    # Skip for this distro/codename pair.
    #
    # Possible reasons:
    #  - it is explictly set to "null" in package-model
    #  - it points to some other "ref" in package model
    if [ "$MATRIX_TYPE" == "package" ]; then
      if ! process_model "distro" "stage/$BUILD_STAGE/$distro/$codename/package-model.json"; then
        echo "  - $distro/$codename: $error_msg"
        continue
      fi
    fi

    echo "  - $distro/$codename: OK"

    for arch in $BUILD_ARCH; do
      if [ "$distro" == "fedora" ]; then
        # Fedora builds run in the Port Org's images; Rawhide is a canary
        # target whose failures must not fail the run.
        canary="false"
        if [ "$codename" == "rawhide" ]; then
          canary="true"
        fi
        includes+=("$(jq -n -c --arg distro "$distro" --arg codename "$codename" --arg arch "$arch" \
          --arg container "${FEDORA_CI_IMAGE}:${codename}-${arch}" --argjson canary "$canary" '$ARGS.named')")
      else
        includes+=("$(jq -n -c --arg distro "$distro" --arg codename "$codename" --arg arch "$arch" '$ARGS.named')")
      fi
    done
  done

  popd >/dev/null || exit 1
}

main

# shellcheck disable=SC2086
echo "includes=$(jq -n -c "[$(printf '%s\n' "${includes[@]}" | paste -sd,)]" '$ARGS.named')" >> $GITHUB_OUTPUT

# shellcheck disable=SC2086
echo "runners=$(jq -n -c "$(jq -n -c --arg amd64 "ubuntu-24.04" --arg arm64 "ubuntu-24.04-arm" '$ARGS.named')" '$ARGS.named')" >> $GITHUB_OUTPUT

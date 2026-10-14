#!/bin/bash
#
# Regenerate README with list of actions and their description.

PWD="$(dirname "$(readlink -f "$0")")"
REPO_ROOT="$(realpath "$PWD/../../")"

echo "| Name⠀⠀⠀⠀⠀⠀⠀⠀⠀| Description |" >> tmp.md
echo "|----------------|-------------|" >> tmp.md

for dir in "$REPO_ROOT"/*; do
    if [ ! -d "$dir" ]; then
        continue
    fi

    # only action folders (skip e.g. docs/, templates/, tools/)
    if [ ! -f "$dir/action.yml" ] && [ ! -f "$dir/_action.yml" ]; then
        continue
    fi

    action_name="$(basename "$dir")"
    action_title="n/a"
    action_description="n/a"

    if [ -f "$dir/action.yml" ]; then
        action_title="$(yq '.name' "$dir/action.yml")"
        action_description="$(yq '.description' "$dir/action.yml")"
    fi
    if [ -f "$dir/_action.yml" ]; then
        action_title="$(yq '.name' "$dir/_action.yml")"
        action_description="$(yq '.description' "$dir/_action.yml")"
    fi

    # action specific temp files
    echo "# $action_title" > "$dir/tmp.md"
    echo "" >> "$dir/tmp.md"
    echo "$action_description" >> "$dir/tmp.md"

    # update action README
    sed -i -ne '/<!-- AUTO_GENERATE_START -->/ {p; r '"$dir"'/tmp.md' -e ':a; n; /<!-- AUTO_GENERATE_END -->/ {p; b}; ba}; p' "$dir/README.md"

    # cleanup action temp file
    rm -f "$dir/tmp.md"

    # append table row to repostiroy temp file
    echo "| \`$action_name\` | $(echo "$action_description" | tr '\n' ' ') |" >> tmp.md
done

# update repository README
sed -i -ne '/<!-- AUTO_GENERATE_START -->/ {p; r tmp.md' -e ':a; n; /<!-- AUTO_GENERATE_END -->/ {p; b}; ba}; p' "$REPO_ROOT/README.md"

# cleanup repository temp file
rm -f tmp.md

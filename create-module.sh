#!/bin/bash
set -e

MODULE_NAME="open-webview.zip"
TOOLS="tools.tar"
ROOT_DIR="$(pwd)"
OVERLAY_DIR="overlays"
TOOLS_DIR="common/tools"

compress() {
    local type="$1"
    local output="$2"
    shift 2
    local input=("$@")
    echo "compressing $output..."
    7z a -t"$type" -r "$output" "${input[@]}" >& /dev/null
}

echo "deleting old files..."
rm -f "$MODULE_NAME"
rm -f "$TOOLS_DIR/${TOOLS}.xz"
rm -f "$OVERLAY_DIR"/*.zip "$OVERLAY_DIR"/*.idsig

echo "zipping tools..."
cd "$TOOLS_DIR/tools"
compress tar "$TOOLS" *
compress xz "${TOOLS}.xz" "$TOOLS"
rm -f "$TOOLS"
mv -f "${TOOLS}.xz" ../
cd "$ROOT_DIR"

echo -e "creating module zip..."
7z a -tzip -r $MODULE_NAME * -xr!.git* -xr!img -xr!common/tools/tools \
    -xr!overlays/src -xr!overlays/keys -xr!overlays/build.sh \
    -x!*.md -x!create-module.* >& /dev/null
echo "done!"

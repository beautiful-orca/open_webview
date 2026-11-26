#!/bin/bash
set -e

MODULE_NAME="open-webview.zip"
ROOT_DIR="$(pwd)"
OVERLAY_DIR="overlays"
TOOLS_DIR="common/tools"

echo "deleting old files..."
rm -f "$MODULE_NAME"
rm -f "$OVERLAY_DIR"/*.zip "$OVERLAY_DIR"/*.idsig

# The tool binaries are committed compressed (common/tools/tools.tar.xz) to keep
# the repo small; the raw common/tools/tools/ tree is a gitignored local artifact
# rebuilt by scripts/install-binaries.sh. Fail loudly if the archive is missing.
if [ ! -f "$TOOLS_DIR/tools.tar.xz" ]; then
    echo "error: $TOOLS_DIR/tools.tar.xz not found — run scripts/install-binaries.sh first" >&2
    exit 1
fi

echo -e "creating module zip..."
7z a -tzip -r $MODULE_NAME * -xr!.git* -xr!img -xr!common/tools/tools \
    -xr!overlays/src -xr!overlays/keys -xr!overlays/build.sh \
    -x!*.md -x!create-module.* >& /dev/null
echo "done!"

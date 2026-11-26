$MODULE_NAME = "open-webview.zip"
$ROOT_DIR = Get-Location
$OVERLAY_DIR = "overlays"
$TOOLS_DIR = "common/tools"

Write-Host "Deleting old files..."
if (Test-Path $MODULE_NAME) {
    Remove-Item -Force $MODULE_NAME
}
Get-ChildItem -Path "$OVERLAY_DIR" -Filter "*.zip" | Remove-Item -Force
Get-ChildItem -Path "$OVERLAY_DIR" -Filter "*.idsig" | Remove-Item -Force
Write-Host "Old files deleted!"

# The tool binaries are committed compressed (common/tools/tools.tar.xz) to keep
# the repo small; the raw common/tools/tools/ tree is a gitignored local artifact
# rebuilt by scripts/install-binaries.sh. Fail loudly if the archive is missing.
if (-not (Test-Path "$TOOLS_DIR\tools.tar.xz")) {
    Write-Error "$TOOLS_DIR\tools.tar.xz not found — run scripts/install-binaries.sh first"
    exit 1
}

Write-Host "Creating module zip..."
& 7z.exe a -tzip -r $MODULE_NAME * `
    "-xr!.git*" "-xr!img" "-xr!common/tools/tools" `
    "-xr!overlays/src" "-xr!overlays/keys" "-xr!overlays/build.sh" `
    "-x!*.md" "-x!create-module.*" | Out-Null
Write-Host "Module zip created!"
Write-Host "Done!"

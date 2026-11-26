#!/bin/bash
# Build the prebuilt static RRO shipped as overlays/WebviewOverlay.apk.
#
#   ./overlays/build.sh [output.apk]
#
# Requires aapt2, apksigner and an android.jar — all from the Android SDK build-tools
# and platforms directories. No third-party binary, and no 16 KB alignment requirement:
# this runs on the build machine, never on the device (§13.2).
#   AAPT2=/path/to/aapt2 ANDROID_JAR=/path/to/android.jar ./overlays/build.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/src"
KEYS="$HERE/keys"
OUT="${1:-$HERE/WebviewOverlay.apk}"

AAPT2="${AAPT2:-aapt2}"
ANDROID_JAR="${ANDROID_JAR:-${ANDROID_HOME:-$HOME/Android/Sdk}/platforms/android-35/android.jar}"

command -v "$AAPT2" >/dev/null 2>&1 || [ -x "$AAPT2" ] || {
    echo "error: aapt2 not found; set AAPT2=/path/to/aapt2" >&2; exit 1; }
command -v apksigner >/dev/null 2>&1 || {
    echo "error: apksigner not found; install Android build-tools" >&2; exit 1; }
[ -f "$ANDROID_JAR" ] || {
    echo "error: android.jar not found; set ANDROID_JAR=/path/to/android.jar" >&2; exit 1; }
[ -f "$KEYS/testkey.pk8" ] && [ -f "$KEYS/testkey.x509.pem" ] || {
    echo "error: missing overlays/keys/testkey.{pk8,x509.pem} (see §12.5)" >&2; exit 1; }

# versionCode from the provider list content. Any change to the list changes the
# versionCode, which is what forces a changed overlay to be re-scanned once
# post-fs-data.sh stops clearing /data/resource-cache (§8.4).
VC=$(( 0x$(sha256sum "$SRC/res/xml/config_webview_packages.xml" | cut -c1-7) ))
[ "$VC" -gt 0 ] || VC=1

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

"$AAPT2" compile --dir "$SRC/res" -o "$WORK/compiled.zip"
"$AAPT2" link \
    -o "$WORK/unsigned.apk" \
    -I "$ANDROID_JAR" \
    --manifest "$SRC/AndroidManifest.xml" \
    --version-code "$VC" \
    --version-name "1.$VC" \
    "$WORK/compiled.zip"

# Sign with the AOSP testkey the module already ships, so the overlay's signer
# identity is unchanged from the install-time build path (§12.4).
# apksigner is required; zipsigner is no longer shipped (§12.9).
apksigner sign \
    --key "$KEYS/testkey.pk8" \
    --cert "$KEYS/testkey.x509.pem" \
    --min-sdk-version 26 \
    --v1-signing-enabled true \
    --v2-signing-enabled true \
    --out "$OUT" "$WORK/unsigned.apk"

echo "built $OUT"
echo "  versionCode $VC"
echo "  sha256 $(sha256sum "$OUT" | cut -d' ' -f1)"

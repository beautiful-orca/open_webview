#!/system/bin/sh
# Update the installed WebView to the current upstream build for the provider
# this module installed. No re-flash, no reboot: pm install creates a /data/app
# update on top of the module's system copy, and WebViewUpdateService
# re-evaluates the provider on the package change. Every failure path leaves
# the currently installed WebView untouched.
#
# Magisk runs this as `cd /data/adb/modules/<id> && sh ./action.sh`, so MODDIR
# resolves to "." — do not cd, and keep every path relative to the module dir.
MODDIR=${0%/*}
STATE="$MODDIR/.webview"
LOG="$MODDIR/action.log"
# /data/local/tmp, not the module dir: pm reads the APK as root and hands an
# fd to system_server, which cannot read under /data/adb.
TMP=/data/local/tmp/open_webview_update.apk

# $ARCH is set by the installer, not here. The install copies the target
# architecture's curl to the fixed path bin/curl before cleanup() removes
# common/, so no architecture resolution is needed.
CURL_BIN="$MODDIR/bin/curl"
[ -x "$CURL_BIN" ] || { echo "! No curl at $CURL_BIN. Re-flash the module."; exit 1; }

say() { echo "$*"; echo "[$(date "+%H:%M:%S")] $*" >>"$LOG"; }
die() { say "! $*"; exit 1; }
short() { echo "$1" | cut -c1-12; }

# One run at a time: two concurrent taps would write the same $TMP path.
mkdir "$MODDIR/.action.lock" 2>/dev/null || { echo "Another update is already running."; exit 0; }
trap 'rm -f "$TMP"; rmdir "$MODDIR/.action.lock" 2>/dev/null' EXIT

[ -f "$MODDIR/providers.sh" ] || die "No $MODDIR/providers.sh. Re-flash the module."
. "$MODDIR/providers.sh"

[ -f "$STATE" ] || die "No $STATE. Re-flash the module."
state_get() { grep "^$1=" "$STATE" 2>/dev/null | head -n1 | cut -d= -f2-; }

VW_PROVIDER=$(state_get VW_PROVIDER)
VW_VARIANT=$(state_get VW_VARIANT)
VW_PACKAGE=$(state_get VW_PACKAGE)
VW_SHA_INSTALLED=$(state_get VW_SHA_INSTALLED)
VW_VERSION=$(state_get VW_VERSION)

[ -n "$VW_PROVIDER" ] && [ -n "$VW_VARIANT" ] ||
	die "This install predates the update button. Re-flash the module once."
[ -n "$VW_PACKAGE" ] || die "No package recorded in $STATE."

say "Provider:  $VW_PROVIDER ($VW_VARIANT)"
say "Installed: ${VW_VERSION:-unknown} $(short "$VW_SHA_INSTALLED")"

# Resolve the upstream release in this shell first, so cromite_latest's cache
# serves both provider_sha and provider_url below (one API call, not two).
provider_prefetch "$VW_PROVIDER" "$VW_VARIANT" ||
	die "Could not resolve the upstream release. Nothing downloaded."

# Fail closed when the upstream hash cannot be read: an unverified "update"
# is how a silent no-verification path comes back.
UP_SHA=$(provider_sha "$VW_PROVIDER" "$VW_VARIANT")
[ -n "$UP_SHA" ] || die "Could not read the upstream hash. Nothing downloaded."
say "Upstream:  $(short "$UP_SHA")"

# The sha256 is the comparison key, not the version name: the upstream ref is
# a branch, and the prebuilt is replaced on it without the ref moving.
[ "$UP_SHA" = "$VW_SHA_INSTALLED" ] && { say "Already up to date."; exit 0; }

FREE=$(df -k /data | awk 'NR==2 {print $4}')
[ "${FREE:-0}" -ge 700000 ] ||
	die "Need about 700 MB free on /data, $(( ${FREE:-0} / 1024 )) MB available."

URL=$(provider_url "$VW_PROVIDER" "$VW_VARIANT") || die "Could not resolve the download URL."
say "Downloading $URL"
dl "$URL" "$TMP" || die "Download failed. The installed WebView is untouched."
chmod 0644 "$TMP"

GOT=$(sha256_of "$TMP" | cut -d' ' -f1)
[ "$GOT" = "$UP_SHA" ] || die "Hash mismatch: got $GOT, expected $UP_SHA."

say "Installing $VW_PACKAGE..."
# pm install prints Success or Failure [...], and that output is the result,
# not $?. -r is the default (replaceExisting), kept as documentation of
# intent; -R would break this and -d (downgrade) is deliberately absent.
# --install-location 1 matches the installer's own pm install call.
OUT=$(pm install -r --install-location 1 "$TMP" 2>&1)
echo "$OUT"
case $OUT in
*INSTALL_FAILED_UPDATE_INCOMPATIBLE*)
	say "The installed copy is signed by a different key. Removing it first."
	pm uninstall "$VW_PACKAGE" >/dev/null 2>&1
	OUT=$(pm install -r --install-location 1 "$TMP" 2>&1)
	echo "$OUT"
	# The uninstall dropped the user choice with the package.
	cmd webviewupdate set-webview-implementation "$VW_PACKAGE" >/dev/null 2>&1
	;;
esac
case $OUT in
*Success*) ;;
*) die "Install failed. The previous WebView is still in place." ;;
esac

NEW_VERSION=$(dumpsys package "$VW_PACKAGE" 2>/dev/null |
	sed -n 's/.*versionName=\([^ ]*\).*/\1/p' | head -n1)

for kv in "VW_SHA_INSTALLED=$UP_SHA" "VW_VERSION=$NEW_VERSION"; do
	key=${kv%%=*}
	if grep -q "^$key=" "$STATE"; then
		sed -i "s|^$key=.*|$kv|" "$STATE"
	else
		echo "$kv" >>"$STATE"
	fi
done

say "Updated to ${NEW_VERSION:-$UP_SHA}."
say "No reboot needed. Apps that were already running keep the old WebView until restarted."

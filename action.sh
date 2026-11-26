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

say() { echo "$*"; echo "[$(date "+%H:%M:%S")] $*" >>"$LOG"; }
# Every failure ends here: hand the update log to the user and point at the
# issue tracker, with the caveat that a fix is not guaranteed — the same
# contract the installer's abort() prints.
die() {
	say "! $*"
	if [ -f "$LOG" ] && cp "$LOG" /sdcard/action.log 2>/dev/null; then
		say "Update log saved to /sdcard/action.log"
	fi
	say "To report this error, open an issue on GitHub and include the log:"
	say "https://github.com/beautiful-orca/open_webview/issues"
	say "There is no guarantee that a reported issue can be fixed."
	exit 1
}
short() { echo "$1" | cut -c1-12; }

# $ARCH is set by the installer, not here. The install copies the target
# architecture's curl to the fixed path bin/curl before cleanup() removes
# common/, so no architecture resolution is needed.
CURL_BIN="$MODDIR/bin/curl"
[ -x "$CURL_BIN" ] || die "No curl at $CURL_BIN. Re-flash the module."

# One run at a time: two concurrent taps would write the same $TMP path.
mkdir "$MODDIR/.action.lock" 2>/dev/null || { say "Another update is already running."; exit 0; }
trap 'rm -f "$TMP"; rmdir "$MODDIR/.action.lock" 2>/dev/null' EXIT

[ -f "$MODDIR/providers.sh" ] || die "No $MODDIR/providers.sh. Re-flash the module."
. "$MODDIR/providers.sh"

# Surface fetch()'s DNS-ladder progress: stderr reaches the action output in
# the Magisk app, and the log keeps a copy. stdout must stay clean here — the
# hash is captured via $( ) — so progress goes to stderr + log only.
fetch_progress() {
	echo "  $*" >&2
	echo "[$(date "+%H:%M:%S")] $*" >>"$LOG"
}

[ -f "$STATE" ] || die "No $STATE. Re-flash the module."
state_get() { grep "^$1=" "$STATE" 2>/dev/null | head -n1 | cut -d= -f2-; }
state_set() {
	local key=$1 kv="$1=$2"
	if grep -q "^$key=" "$STATE" 2>/dev/null; then
		sed -i "s|^$key=.*|$kv|" "$STATE"
	else
		echo "$kv" >>"$STATE"
	fi
}

VW_PROVIDER=$(state_get VW_PROVIDER)
VW_VARIANT=$(state_get VW_VARIANT)
VW_PACKAGE=$(state_get VW_PACKAGE)
VW_SHA_INSTALLED=$(state_get VW_SHA_INSTALLED)
VW_VERSION=$(state_get VW_VERSION)

[ -n "$VW_PROVIDER" ] && [ -n "$VW_VARIANT" ] ||
	die "This install predates the update button. Re-flash the module once."
[ -n "$VW_PACKAGE" ] || die "No package recorded in $STATE."

say "Provider:  $VW_PROVIDER ($VW_VARIANT)"
# VW_VERSION in $STATE is empty on a fresh install: dumpsys could not see the
# module's system copy before the first reboot. This button only runs once the
# module is mounted, so read the version live — and backfill $STATE when it was
# still empty, so later runs show it without the lookup.
INSTALLED_VERSION=$(dumpsys package "$VW_PACKAGE" 2>/dev/null |
	sed -n 's/.*versionName=\([^ ]*\).*/\1/p' | head -n1)
[ -n "$INSTALLED_VERSION" ] && [ -z "$VW_VERSION" ] && state_set VW_VERSION "$INSTALLED_VERSION"
say "Installed: ${INSTALLED_VERSION:-${VW_VERSION:-unknown}} $(short "$VW_SHA_INSTALLED")"

# Resolve the upstream release in this shell first, so cromite_latest's cache
# serves both provider_sha and provider_url below (one API call, not two).
# This is the one network call before the download: say what it is, and let
# fetch_progress() name the DNS rung while it runs.
say "Checking upstream $VW_PROVIDER release..."
say "  Querying the upstream API for the current build hash..."
provider_prefetch "$VW_PROVIDER" "$VW_VARIANT" ||
	die "Could not resolve the upstream release. Nothing downloaded."
# GitHub providers (Cromite, Thorium) resolve a release tag here; Vanadium
# tracks a GitLab branch, so for it only the hash below is meaningful.
[ -n "$GH_LATEST_TAG" ] && say "Upstream release: $GH_LATEST_TAG"

# Fail closed when the upstream hash cannot be read: an unverified "update"
# is how a silent no-verification path comes back.
UP_SHA=$(provider_sha "$VW_PROVIDER" "$VW_VARIANT")
[ -n "$UP_SHA" ] || die "Could not read the upstream hash. Nothing downloaded."
say "Upstream:  $(short "$UP_SHA")"

# The sha256 is the comparison key, not the version name: the upstream ref is
# a branch, and the prebuilt is replaced on it without the ref moving.
[ "$UP_SHA" = "$VW_SHA_INSTALLED" ] && { say "Already up to date: installed ${INSTALLED_VERSION:-${VW_VERSION:-unknown}} matches upstream. Nothing downloaded."; exit 0; }

FREE=$(df -k /data | awk 'NR==2 {print $4}')
[ "${FREE:-0}" -ge 700000 ] ||
	die "Need about 700 MB free on /data, $(( ${FREE:-0} / 1024 )) MB available."

URL=$(provider_url "$VW_PROVIDER" "$VW_VARIANT") || die "Could not resolve the download URL."
say "Downloading $URL"
dl "$URL" "$TMP" || die "Download failed. The installed WebView is untouched."
chmod 0644 "$TMP"

say "Verifying checksum..."
GOT=$(sha256_of "$TMP" | cut -d' ' -f1)
[ "$GOT" = "$UP_SHA" ] || die "Hash mismatch: got $GOT, expected $UP_SHA."
say "Checksum OK ($(wc -c <"$TMP") bytes)"

# Channel-independent check, Vanadium only: the upstream sha256 travels the
# same TLS channel as the APK, so it only detects transfer corruption. The
# signer certificate pin ships inside the module, so an APK not signed with
# GrapheneOS's key is rejected here. apk_signer_cert_sha() lives in
# providers.sh; pm install verifies the cryptographic signature itself.
if [ "$VW_PROVIDER" = "vanadium" ]; then
	say "Verifying signer certificate..."
	CERT=$(apk_signer_cert_sha "$TMP") ||
		die "Could not read the APK signing block. The installed WebView is untouched."
	[ "$CERT" = "$GRAPHENEOS_CERT_SHA256" ] ||
		die "Signer certificate mismatch: got ${CERT:-<none>}, expected $GRAPHENEOS_CERT_SHA256. The installed WebView is untouched."
	say "Signer cert OK ($GRAPHENEOS_CERT_SHA256)"
fi

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

state_set VW_SHA_INSTALLED "$UP_SHA"
state_set VW_VERSION "$NEW_VERSION"

say "Updated to ${NEW_VERSION:-$UP_SHA}."
say "No reboot needed. Apps that were already running keep the old WebView until restarted."
say "Run this action button again anytime to check for a newer upstream build."

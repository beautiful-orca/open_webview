#!/system/bin/sh
# The provider registry (PROVIDERS, available_providers), the download helpers
# (dl, sha256_of, get_sha_gitlab*) and the upstream resolution
# (provider_url, provider_sha, cromite_latest) live in providers.sh at the
# module root, shared with action.sh. ANDROID_VANADIUM_VERSION is set there.
OVERLAY_APK_FILE="WebviewOverlay.apk"
CONFIG_FILE="$MODPATH"/.webview
LOG="$MODPATH"/webview.log
# Downloads go to /data, not $TMPDIR: Magisk sets TMPDIR=/dev/tmp, a tmpfs,
# so downloading there costs RAM (~843 MB peak with the old extra copies).
DL_DIR=/data/local/tmp/open_webview
IS_MINIMAL_INSTALLATION=0
# When set, the upstream checksum is being resolved in the background and is
# read from this file before the integrity check (see vanadium()).
VW_SHA_FILE=""

# CURL_BIN is set by functions.sh to $MODPATH/bin/curl before this file is
# sourced, so the helpers below resolve through the same copy action.sh uses.
. "$MODPATH/providers.sh"

# Show fetch()'s DNS-ladder progress live in the installer console: ui_print
# writes to Magisk's OUTFD, not stdout, so the lines stay visible even from
# inside the $( ) substitutions that capture the hash or URL — and the log
# keeps a copy. Without this, a dead first rung stalls the console in silence
# (Cromite/Thorium resolve the release synchronously; Vanadium's checksum
# resolves in the background during the download).
fetch_progress() {
	ui_print "  $*"
	echo "[$(date "+%H:%M:%S")] $*" >>$LOG 2>/dev/null
}

MENU_TIMEOUT=15

# Vanadium publishes two arm64 prebuilts: `arm64` (189,406,104 B) and
# `arm64-multilib` (281,009,321 B). The multilib one carries armeabi-v7a
# libraries so 32-bit apps on a 64-bit device can load the WebView
# in-process; without it those apps fail with the lib/multilib error
# (issue #3). A device that cannot run 32-bit code at all never loads those
# libraries, so it gets the smaller APK. An empty abilist keeps today's
# behaviour — the one direction where a wrong answer would be harmful.
vanadium_abi() {
	local abilist
	abilist=$(getprop ro.product.cpu.abilist)
	case $abilist in
	"") echo "arm64-multilib" ;;
	*armeabi-v7a*) echo "arm64-multilib" ;;
	*) echo "arm64" ;;
	esac
}

vanadium() {
	local prebuilt=$1
	# On arm64, refine the registry's default per device.
	if [[ "$ARCH" = "arm64" ]]; then
		prebuilt=$(vanadium_abi)
	fi
	VW_VARIANT=$prebuilt
	# provider_url for vanadium is a pure string — no network. The checksum is
	# the only pre-download network call, so resolve it in the background and
	# let a slow DNS ladder overlap the download instead of leaving the console
	# silent after the selection. VW_SHA stays empty until
	# download_install_webview() waits for it and still fails closed there.
	VW_APK_URL=$(provider_url vanadium "$prebuilt")
	VW_TRICHROME_APK_URL=""
	VW_SHA=""
	VW_SHA_FILE="$TMPDIR/open_webview.sha"
	rm -f "$VW_SHA_FILE"
	( provider_sha vanadium "$prebuilt" >"$VW_SHA_FILE" 2>/dev/null ) &
	ui_print "  Resolving upstream checksum in the background..."
	# Always system/app: /system/app is scanned on every ROM, and the stock
	# WebView's own path is found via cmd package dump in replace_old_webview()
	# (§8.10, §10.8).
	VW_SYSTEM_PATH=system/app/VanadiumWebview
	VW_PACKAGE="app.vanadium.webview"
	OVERLAY_APK_FILE="WebviewOverlay.apk"
}
cromite() {
	# The registry only offers Cromite on arm64 (the other arches carry
	# ChromePublic.apk, a browser), so $1 is arm64_SystemWebView.apk here;
	# guard against an empty variant anyway.
	local asset_name=$1
	if [[ -z "$asset_name" ]]; then
		echo "[$(date "+%H:%M:%S")] cromite called without an asset name" >>$LOG
		ui_print "  Internal error: no Cromite asset for this device."
		clean_up 1
	fi
	VW_VARIANT=$asset_name
	# One releases/latest call resolves both the tag and the asset digest;
	# prefetch in this shell so the two command substitutions below hit the
	# cromite_latest cache instead of paying the API call twice.
	provider_prefetch cromite "$asset_name" || {
		echo "[$(date "+%H:%M:%S")] Could not resolve the latest Cromite release" >>$LOG
		ui_print "  Could not resolve the latest Cromite release."
		clean_up 1
	}
	VW_APK_URL=$(provider_url cromite "$asset_name")
	VW_TRICHROME_APK_URL=""
	VW_SHA=$(provider_sha cromite "$asset_name")
	if [[ -z "$VW_SHA" ]]; then
		echo "[$(date "+%H:%M:%S")] No sha256 digest for $asset_name in the latest Cromite release" >>$LOG
		ui_print "  Could not fetch the Cromite checksum."
		ui_print "  Refusing to install an unverified WebView."
		clean_up 1
	fi
	VW_SYSTEM_PATH=system/app/CromiteWebview
	VW_PACKAGE="com.android.webview"
	OVERLAY_APK_FILE=""
}
thorium() {
	# The registry maps arm64/arm to the SystemWebView release assets; guard
	# against an empty variant anyway.
	local asset_name=$1
	if [[ -z "$asset_name" ]]; then
		echo "[$(date "+%H:%M:%S")] thorium called without an asset name" >>$LOG
		ui_print "  Internal error: no Thorium asset for this device."
		clean_up 1
	fi
	VW_VARIANT=$asset_name
	# One releases/latest call resolves both the tag and the asset digest;
	# prefetch in this shell so the two command substitutions below hit the
	# github_latest cache instead of paying the API call twice.
	provider_prefetch thorium "$asset_name" || {
		echo "[$(date "+%H:%M:%S")] Could not resolve the latest Thorium release" >>$LOG
		ui_print "  Could not resolve the latest Thorium release."
		clean_up 1
	}
	VW_APK_URL=$(provider_url thorium "$asset_name")
	VW_TRICHROME_APK_URL=""
	VW_SHA=$(provider_sha thorium "$asset_name")
	if [[ -z "$VW_SHA" ]]; then
		echo "[$(date "+%H:%M:%S")] No sha256 digest for $asset_name in the latest Thorium release" >>$LOG
		ui_print "  Could not fetch the Thorium checksum."
		ui_print "  Refusing to install an unverified WebView."
		clean_up 1
	fi
	# com.thorium.webview is not a stock WebView package, so the overlay entry
	# shipped in WebviewOverlay.apk is what makes it selectable.
	VW_SYSTEM_PATH=system/app/ThoriumWebview
	VW_PACKAGE="com.thorium.webview"
	OVERLAY_APK_FILE="WebviewOverlay.apk"
}
# Print to the installer console and to webview.log in one call, so the two
# cannot drift. Every value the install resolves goes through here.
say() {
	ui_print "  $1"
	# $MODPATH can be wiped mid-install (e.g. a second install run starts while
	# this one is downloading); recreate it so the log write cannot fail.
	mkdir -p "$MODPATH" 2>/dev/null
	echo "[$(date "+%H:%M:%S")] $1" >>$LOG
}

# Print and log what the install resolved, before anything is downloaded. A
# failed install is diagnosed from webview.log, so the values that decide the
# download and the target paths have to be in it before the first byte moves.
print_install_summary() {
	local dest=${DL_DIR:-$TMPDIR}

	say "Provider:     ${VW_PROVIDER:-unknown}${VW_VARIANT:+ ($VW_VARIANT)}"
	say "Architecture: $ARCH, API $API"
	say "Package:      $VW_PACKAGE"
	say "Download:     $VW_APK_URL"
	[[ -n "$VW_TRICHROME_APK_URL" ]] && say "Library:      $VW_TRICHROME_APK_URL"
	say "Saved to:     $dest/webview.apk"
	say "Installs to:  $VW_SYSTEM_PATH/webview.apk"
	if [[ -n "$OVERLAY_APK_FILE" ]]; then
		say "Overlay:      ${OVERLAY_PATH:-(resolved after download)/}$OVERLAY_APK_FILE"
	else
		say "Overlay:      none"
	fi
	if [[ -n "$VW_SHA" ]]; then
		say "Checksum:     $VW_SHA"
	elif [[ -n "${VW_SHA_FILE:-}" ]]; then
		say "Checksum:     resolving in background..."
	else
		say "Checksum:     not verified"
	fi
	if [[ "${VW_PROVIDER:-}" = "vanadium" ]]; then
		say "Signer pin:   $GRAPHENEOS_CERT_SHA256 (GrapheneOS cert)"
	fi
}

download_file() {
	ui_print "  Downloading $1..."
	echo "[$(date "+%H:%M:%S")] Downloading file: $1 from source: $2" >>$LOG

	local out="$DL_DIR/$1"
	# The DNS ladder lives in dl() (providers.sh), shared with action.sh. It
	# tests curl's exit status, not the output file: an interrupted transfer
	# leaves a partial file behind, and -f alone accepts it.
	if ! dl "$2" "$out"; then
		echo "[$(date "+%H:%M:%S")] Download failed" >>$LOG
		ui_print ""
		ui_print "  !!! Download failed !!!"
		ui_print ""
		clean_up 1
	fi
	# The download can take minutes; if $MODPATH was wiped meanwhile (e.g. a
	# second install run started concurrently), recreate it so the log writes
	# below cannot fail.
	mkdir -p "$MODPATH" 2>/dev/null

	# A finished transfer can still be a broken file: a captive portal or proxy
	# error page answers 200 with HTML, and a truncated zip has no central
	# directory. unzip -t rejects both, and needs no extra binary. When a
	# provider checksum is available it is the authoritative gate (it runs in
	# download_install_webview right after this), so a zip-test failure is only
	# fatal on its own when there is no checksum to fall back on — busybox
	# unzip has false-negatived on valid APKs before.
	ui_print "  Verifying download..."
	if ! unzip -t "$out" >/dev/null 2>&1; then
		local got_size got_sha
		got_size=$(wc -c <"$out" 2>/dev/null)
		got_sha=$(sha256_of "$out" 2>/dev/null | cut -d' ' -f1)
		if [[ -n "$VW_SHA" ]]; then
			echo "[$(date "+%H:%M:%S")] Zip test failed (size=${got_size:-?} sha256=${got_sha:-?}); the checksum will decide" >>$LOG
			ui_print "  Zip test inconclusive, verifying checksum..."
		else
			echo "[$(date "+%H:%M:%S")] Downloaded file is not a valid zip (size=${got_size:-?} sha256=${got_sha:-?})" >>$LOG
			rm -f "$out"
			ui_print ""
			ui_print "  !!! Downloaded file is not a valid APK !!!"
			ui_print ""
			clean_up 1
		fi
	fi
	# system_server has to be able to open the APK (pm install reads it).
	chmod 0644 "$out"
	echo "[$(date "+%H:%M:%S")] File downloaded: $out" >>$LOG
}
# sha256_of() lives in providers.sh, shared with action.sh.
check_integrity() {
	local file=$1 expected=$2 calculated

	if [[ ! -f "$file" ]]; then
		echo "[$(date "+%H:%M:%S")] Integrity: file missing: $file" >>$LOG
		ui_print "  Integrity check failed: download missing"
		clean_up 1
	fi
	# 64 lowercase hex, checked with a glob because busybox ash has no =~.
	case $expected in
	"" | *[!0-9a-f]*)
		echo "[$(date "+%H:%M:%S")] Integrity: malformed hash: $expected" >>$LOG
		ui_print "  Integrity check failed: no usable checksum"
		clean_up 1
		;;
	esac
	if [[ "${#expected}" -ne 64 ]]; then
		echo "[$(date "+%H:%M:%S")] Integrity: hash is ${#expected} chars" >>$LOG
		ui_print "  Integrity check failed: no usable checksum"
		clean_up 1
	fi

	calculated=$(sha256_of "$file" | cut -d' ' -f1)
	if [[ -z "$calculated" ]]; then
		echo "[$(date "+%H:%M:%S")] Integrity: cannot compute sha256" >>$LOG
		ui_print "  Integrity check failed: sha256sum not found"
		clean_up 1
	fi
	echo "[$(date "+%H:%M:%S")] SHA256SUM calculated: $calculated" >>$LOG
	echo "[$(date "+%H:%M:%S")] SHA256SUM expected: $expected" >>$LOG

	if [[ "$calculated" = "$expected" ]]; then
		echo "[$(date "+%H:%M:%S")] Integrity checked" >>$LOG
		ui_print "  Integrity checked!"
	else
		echo "[$(date "+%H:%M:%S")] Integrity not checked" >>$LOG
		ui_print "  Integrity not checked!"
		clean_up 1
	fi
}
# Only the package this module provides needs its stock copy blanked: two APKs
# cannot claim the same package name. Vanadium's package is not preinstalled, so
# this is a no-op for it.
replace_old_webview() {
	echo "[$(date "+%H:%M:%S")] Blanking the stock copy of $VW_PACKAGE" >>$LOG
	local code_path
	code_path=$(cmd package dump "$VW_PACKAGE" 2>/dev/null | grep codePath | head -n 1)
	code_path=${code_path##*codePath=}
	# A codePath under /data/app is a user-installed update. Magisk mounts only
	# system/, vendor/, product/ and system_ext/, so a .replace there is inert;
	# the update has to be uninstalled first, then codePath re-read — the package
	# reverts to its factory (system) copy.
	# case, not [[ == ]]: busybox ash pathname-expands the right-hand side of
	# [[ == ]], so with any /data/app entry present the test dies with
	# "unknown operand" and the branch is silently skipped.
	case $code_path in
	/data/app/*)
		echo "[$(date "+%H:%M:%S")] $VW_PACKAGE has an update in $code_path; uninstalling the update" >>$LOG
		ui_print "  Removing the installed update of $VW_PACKAGE..."
		pm uninstall "$VW_PACKAGE" >/dev/null 2>&1
		code_path=$(cmd package dump "$VW_PACKAGE" 2>/dev/null | grep codePath | head -n 1)
		code_path=${code_path##*codePath=}
		;;
	esac
	[[ -z "$code_path" ]] && return
	echo "[$(date "+%H:%M:%S")] Webview replaced: $code_path" >>$LOG
	ui_print "  Replacing stock $VW_PACKAGE at $code_path"
	mktouch "$MODPATH"$code_path/.replace
}
copy_webview_file() {
	echo "[$(date "+%H:%M:%S")] Copy webview.apk from: $DL_DIR  -  to: $VW_SYSTEM_PATH" >>$LOG
	cp_ch "$DL_DIR"/webview.apk "$MODPATH"/$VW_SYSTEM_PATH/webview.apk
}
install_webview() {
	echo "[$(date "+%H:%M:%S")] Install webview" >>$LOG
	ui_print "  Installing webview..."
	mktouch "$MODPATH"/$VW_SYSTEM_PATH/.replace
	copy_webview_file
	if [[ -f "$DL_DIR"/trichrome.apk ]]; then
		su -c pm install --install-location 1 "$DL_DIR"/trichrome.apk >&2
	fi
}
download_install_webview() {
	# Fail in the first second if /data cannot hold the APK plus headroom.
	mkdir -p "$DL_DIR"
	mkdir -p "$MODPATH" 2>/dev/null
	chmod 0755 "$DL_DIR"
	local avail
	avail=$(df -k /data | awk 'NR==2 {print $4}')
	if [[ "${avail:-0}" -lt 400000 ]]; then
		echo "[$(date "+%H:%M:%S")] Not enough free space on /data: ${avail:-unknown} KB available, need ~400 MB" >>$LOG
		ui_print "  Not enough free space on /data: need ~400 MB."
		clean_up 1
	fi

	download_file webview.apk $VW_APK_URL

	if [[ ! -z "$VW_TRICHROME_APK_URL" ]]; then
		download_file trichrome.apk $VW_TRICHROME_APK_URL
	fi

	# The checksum fetch started in the provider function overlaps the download;
	# collect it now. Still fail closed: an unverified WebView is never installed.
	if [[ -n "${VW_SHA_FILE:-}" ]]; then
		wait
		VW_SHA=$(cat "$VW_SHA_FILE" 2>/dev/null)
		rm -f "$VW_SHA_FILE"
		VW_SHA_FILE=""
		if [[ -z "$VW_SHA" ]]; then
			echo "[$(date "+%H:%M:%S")] No content_sha256 for prebuilt/$VW_VARIANT/VanadiumWebView.apk" >>$LOG
			ui_print "  Could not fetch the upstream checksum."
			ui_print "  Refusing to install an unverified WebView."
			clean_up 1
		fi
		say "Checksum:     $VW_SHA"
	fi

	if [[ ! -z "$VW_SHA" ]]; then
		ui_print "  Checking integrity..."
		check_integrity "$DL_DIR/webview.apk" "$VW_SHA"
	else
		ui_print "  No checksum available, skipping integrity check"
		echo "[$(date "+%H:%M:%S")] No checksum for $VW_PACKAGE, integrity not checked" >>$LOG
	fi

	# Channel-independent check, Vanadium only: the content_sha256 above is
	# fetched from the same server and TLS channel as the APK, so it proves
	# only that the transfer was not corrupted. The signer certificate pin
	# ships inside the module zip, so an APK that was not signed with
	# GrapheneOS's key carries a different certificate and is rejected here.
	# apk_signer_cert_sha() lives in providers.sh. The platform verifies the
	# actual cryptographic signature at pm install / boot, and the overlay's
	# <signature> entry keeps WebViewUpdateService on this same certificate.
	if [[ "$VW_PROVIDER" = "vanadium" ]]; then
		ui_print "  Verifying signer certificate..."
		local cert_sha
		cert_sha=$(apk_signer_cert_sha "$DL_DIR/webview.apk")
		if [[ -z "$cert_sha" ]]; then
			echo "[$(date "+%H:%M:%S")] Signer: no v2/v3 signing block in the downloaded APK" >>$LOG
			ui_print "  Signer certificate could not be read."
			ui_print "  Refusing to install an unverified WebView."
			clean_up 1
		fi
		if [[ "$cert_sha" != "$GRAPHENEOS_CERT_SHA256" ]]; then
			echo "[$(date "+%H:%M:%S")] Signer: got $cert_sha, expected $GRAPHENEOS_CERT_SHA256" >>$LOG
			ui_print "  Signer certificate mismatch."
			ui_print "  Refusing to install a WebView not signed by GrapheneOS."
			clean_up 1
		fi
		say "Signer cert:  $cert_sha (GrapheneOS key)"
	fi
	replace_old_webview
	install_webview
}
create_overlay() {
	echo "[$(date "+%H:%M:%S")] Create overlay" >>$LOG
	ui_print "  Installing overlay..."
	cp_ch "$MODPATH"/overlays/$OVERLAY_APK_FILE "$MODPATH"/common/$OVERLAY_APK_FILE
}
find_overlay_path() {
	echo "[$(date "+%H:%M:%S")] Finding overlay path" >>$LOG
	# Probe the real mount points, not the /system/<part> aliases: from Android 10
	# /product, /vendor, /odm and /system_ext are separate mounts and /system/<part>
	# is only a compatibility symlink that some ROMs omit. The module path stays
	# under system/ because that is the tree Magisk mounts.
	# Order is unchanged from the original, with /vendor inserted immediately before
	# its /system/vendor alias, so a device that resolves today keeps the same path.
	local real module
	for candidate in \
		"/product/overlay:system/product/overlay/" \
		"/system_ext/overlay:system/system_ext/overlay/" \
		"/system/overlay:system/overlay/" \
		"/vendor/overlay:system/vendor/overlay/" \
		"/system/vendor/overlay:system/vendor/overlay/"; do
		real=${candidate%%:*}
		module=${candidate#*:}
		if [[ -d "$real" ]]; then
			OVERLAY_PATH=$module
			echo "[$(date "+%H:%M:%S")] Overlay path: $real -> $module" >>$LOG
			return
		fi
	done
	# /system/overlay is scanned on every Android version and force_overlay creates
	# it in the module, so this is a fallback rather than an abort. Reaching it means
	# the ROM has no overlay directory at all, which no supported device does.
	OVERLAY_PATH=system/overlay/
	echo "[$(date "+%H:%M:%S")] No overlay dir found, falling back to /system/overlay" >>$LOG
	ui_print "  No overlay directory found, using /system/overlay."
}
force_overlay() {
	echo "[$(date "+%H:%M:%S")] Forcing overlay" >>$LOG
	mkdir -p "$MODPATH"/$OVERLAY_PATH
	echo "[$(date "+%H:%M:%S")] Copy $OVERLAY_APK_FILE  -  to: $OVERLAY_PATH" >>$LOG
	cp_ch "$MODPATH"/common/$OVERLAY_APK_FILE "$MODPATH"/$OVERLAY_PATH
}
create_config_file() {
	# State for the update button (action.sh): provider+variant select the
	# upstream asset, the installed hash is the comparison key, the version is
	# display only. The old RESET/IS_REINSTALL/OVERLAY_PATH/OVERLAY_APK_FILE/
	# VW_OVERLAY_PACKAGE keys were only read by post-fs-data.sh, which no
	# longer ships. dumpsys sees the provider package only once the module's
	# system copy is mounted at next boot, so on a fresh install VW_VERSION
	# stays empty and action.sh fills it in on the first update.
	VW_VERSION=$(dumpsys package "$VW_PACKAGE" 2>/dev/null |
		sed -n 's/.*versionName=\([^ ]*\).*/\1/p' | head -n1)
	echo "VW_PROVIDER=${VW_PROVIDER}" >>$CONFIG_FILE
	echo "VW_VARIANT=${VW_VARIANT}" >>$CONFIG_FILE
	echo "VW_PACKAGE=${VW_PACKAGE}" >>$CONFIG_FILE
	echo "VW_SHA_INSTALLED=${VW_SHA}" >>$CONFIG_FILE
	echo "VW_VERSION=${VW_VERSION}" >>$CONFIG_FILE
}
clean_up() {
	if [[ "$1" -eq 1 ]]; then
		echo "[$(date "+%H:%M:%S")] Abort installation" >>$LOG 2>/dev/null
		# abort() copies the log to /sdcard and prints where to report the
		# error; it guards on the log existing because $MODPATH (and with it
		# $LOG) can already be gone — e.g. a concurrent install wiped
		# modules_update mid-run.
		abort "  Installation failed — aborting..."
	fi

	ui_print "  Cleaning up..."
	[ -n "$DL_DIR" ] && rm -rf "$DL_DIR" 2>/dev/null
	echo "[$(date "+%H:%M:%S")] Installation success" >>$LOG
}

if [[ "$API" -lt 29 ]]; then
	ui_print "  Your android version is not supported"
	ui_print "  Minimum android version supported: 10"
	clean_up 1
fi

# The header quotes module.prop instead of a literal, so it cannot go stale.
MODULE_VERSION=$(sed -n 's/^version=//p' "$MODPATH/module.prop" 2>/dev/null | head -n 1)
MODULE_VERSION_CODE=$(sed -n 's/^versionCode=//p' "$MODPATH/module.prop" 2>/dev/null | head -n 1)
mkdir -p "$MODPATH" 2>/dev/null
echo "# open-webview ${MODULE_VERSION:-unknown} (${MODULE_VERSION_CODE:-?})" > $LOG
echo -e "# Author: @f3ffo (Github)\n" >>$LOG
echo "[$(date "+%H:%M:%S")] Brand: $(getprop ro.product.system.brand)" >>$LOG
echo "[$(date "+%H:%M:%S")] Device: $(getprop ro.product.system.device)" >>$LOG
echo "[$(date "+%H:%M:%S")] Manufacter: $(getprop ro.product.system.manufacter)" >>$LOG
echo "[$(date "+%H:%M:%S")] Model: $(getprop ro.product.system.model)" >>$LOG
echo "[$(date "+%H:%M:%S")] Arch: $ARCH" >>$LOG
echo "[$(date "+%H:%M:%S")] System name: $(getprop ro.product.system.name)" >>$LOG
echo -e "[$(date "+%H:%M:%S")] Android Version: $(getprop ro.system.build.version.release)\n" >>$LOG

if [[ ! "$BOOTMODE" ]]; then
	echo "[$(date "+%H:%M:%S")] Install through recovery NOT supported!" >>$LOG
	ui_print "  Installing through recovery NOT supported!"
	ui_print "  Install this module via Magisk Manager"
	clean_up 1
fi

AVAILABLE=$(available_providers)
# Quote it: busybox ash word-splits inside [[ ]], so an unquoted multi-line
# $AVAILABLE makes the test fail with "sh: <line>: unknown operand".
if [[ -z "$AVAILABLE" ]]; then
	echo "[$(date "+%H:%M:%S")] No provider available for arch=$ARCH api=$API" >>$LOG
	ui_print "  No WebView provider is available for $ARCH."
	clean_up 1
fi

total=$(echo "$AVAILABLE" | wc -l)
ui_print "  Available WebView providers:"
echo "$AVAILABLE" | while IFS= read -r line; do
	ui_print "    $(echo "$line" | cut -d'|' -f2)"
done

# One cycle: Vol+ selects the highlighted provider and installs straight away,
# Vol- advances to the next (wrapping at the end), timeout keeps the highlight
# as an unconfirmed default. A defaulted choice must be confirmed before
# anything is downloaded — silence is not consent.
index=1
confirmed=0
while true; do
	line=$(echo "$AVAILABLE" | sed -n "${index}p")
	VW_PROVIDER=$(echo "$line" | cut -d'|' -f1)
	label=$(echo "$line" | cut -d'|' -f2)
	VW_VARIANT=$(echo "$line" | cut -d'|' -f3)
	ui_print ""
	ui_print "  $label  ($index/$total)"
	ui_print "    Vol+ = select, Vol- = next   (${MENU_TIMEOUT}s)"
	chooseport $MENU_TIMEOUT
	sel=$?
	if [[ "$sel" -eq 0 ]]; then
		confirmed=1
		break
	elif [[ "$sel" -eq 1 ]]; then
		index=$(( index + 1 ))
		[ $index -gt $total ] && index=1
	else
		break
	fi
done

if [[ "$confirmed" -ne 1 ]]; then
	ui_print ""
	ui_print "  No selection made. Default: $label"
	ui_print "    Install $label?  Vol+ = yes, Vol- = no   (${MENU_TIMEOUT}s)"
	chooseport $MENU_TIMEOUT
	if [[ "$?" -ne 0 ]]; then
		echo "[$(date "+%H:%M:%S")] No webview selected" >>$LOG
		abort "No webview selected!"
	fi
fi

# Instant on-screen confirmation: the provider call below resolves the
# upstream checksum over the network before the summary prints, so without
# this the console sits silent right after the keypress.
ui_print ""
ui_print "  >> $label selected — installing..."
echo "[$(date "+%H:%M:%S")] Selected $VW_PROVIDER ($VW_VARIANT) for $ARCH" >>$LOG
"$VW_PROVIDER" "$VW_VARIANT"

if [[ -f "$CONFIG_FILE" ]]; then
	echo "[$(date "+%H:%M:%S")] Remove old config file" >>$LOG
	rm -rf $CONFIG_FILE
fi

# Probe the overlay path before the download: it reads the filesystem only,
# and a missing overlay directory must not cost the whole download.
if [[ ! -z "$OVERLAY_APK_FILE" ]]; then
	find_overlay_path
fi

print_install_summary

if [[ "$IS_MINIMAL_INSTALLATION" -eq 0 ]]; then
	download_install_webview
fi

# Only install the overlay if the webview supports it
if [[ ! -z "$OVERLAY_APK_FILE" ]]; then
	create_overlay
	force_overlay
	if [[ ! -f "$MODPATH"/$OVERLAY_PATH$OVERLAY_APK_FILE ]]; then
		echo "[$(date "+%H:%M:%S")] Overlay file missing in path: $OVERLAY_PATH" >>$LOG
		ui_print "  Missing overlay apk file"
		clean_up 1
	fi
fi

# The user choice is checked before the overlay's list order, so this is what
# pins the provider when a stale Developer-options choice or a leftover provider
# from a previous install would otherwise win. Self-healing on uninstall: the
# setting then points at a missing package and list order takes over.
ui_print "  Selecting $VW_PACKAGE as the WebView provider"
cmd webviewupdate set-webview-implementation "$VW_PACKAGE" >/dev/null 2>&1 ||
	echo "[$(date "+%H:%M:%S")] Could not set the provider; list order will decide" >>$LOG

create_config_file
clean_up 0

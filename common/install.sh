#!/system/bin/sh
SKIP_INSTALLATION=1
# To get the latest Vanadium version change ANDROID_VANADIUM_VERSION to the current version of https://gitlab.com/grapheneos/platform_external_vanadium
# Check the URL of the prebuilt folder, eg. https://gitlab.com/grapheneos/platform_external_vanadium/-/tree/16-qpr2/prebuilt?ref_type=heads, 16-qpr2 is latest version
ANDROID_VANADIUM_VERSION=17
OVERLAY_APK_FILE="WebviewOverlay.apk"
CONFIG_FILE="$MODPATH"/.webview
LOG="$MODPATH"/webview.log
IS_MINIMAL_INSTALLATION=0

get_version_github() {
	local repo=$1
    local asset_name=$2

	echo "[$(date "+%H:%M:%S")] Get correct github versione using repo=${repo} and asset_name=${asset_name}" >>$LOG

	"$CURL_BIN" -fsSL --connect-timeout 15 --max-time 60 --retry 3 --retry-delay 3 \
		"https://api.github.com/repos/$repo/releases" | \
    awk -v asset_name="$asset_name" '
        BEGIN { tag_name = "" }
        /"tag_name":/ { tag_name = $2; gsub(/"|,/, "", tag_name) }
        /"name":/ { name = $2; gsub(/"|,/, "", name) }
        name == asset_name { print tag_name; exit }
    '
}
get_sha_gitlab_lfs() {
	"$CURL_BIN" -fsSL --connect-timeout 15 --max-time 60 --retry 3 --retry-delay 3 \
		"https://gitlab.com/api/v4/projects/$1/repository/files/$2" 2>/dev/null |
		grep 'oid sha256:' |
		cut -d":" -f2
}
get_sha_gitlab() {
	"$CURL_BIN" -fsSL --connect-timeout 15 --max-time 60 --retry 3 --retry-delay 3 \
		"https://gitlab.com/api/v4/projects/$1/repository/files/$2" 2>/dev/null |
		grep 'content_sha256:' |
		cut -d":" -f2
}
get_system_path_according_to_rom() {
	local is_los=$(getprop | grep -o -c "lineage")

	if [[ $is_los -gt 0 ]]; then
		echo "system/product/app"
	else
		echo "system/app"
	fi
}

vanadium() {
	VW_APK_URL=https://gitlab.com/api/v4/projects/40905333/repository/files/prebuilt%2F${1}%2FVanadiumWebView.apk/raw?ref=${ANDROID_VANADIUM_VERSION}
	VW_TRICHROME_APK_URL=""
	# VW_SHA=$(get_sha_gitlab "40905333" "prebuilt%2F${1}%2FVanadiumWebView.apk?ref=${ANDROID_VANADIUM_VERSION}")
	VW_SHA=""
	VW_SYSTEM_PATH=$(get_system_path_according_to_rom)/VanadiumWebview
	VW_PACKAGE="app.vanadium.webview"
	OVERLAY_APK_FILE="WebviewOverlay.apk"
}
cromite() {
	# Cromite publishes arm64_SystemWebView.apk only: arm, x86 and x86_64 releases
	# carry ChromePublic.apk, which is a browser, not a WebView provider.
	if [[ $ARCH != "arm64" ]]; then
		echo "[$(date "+%H:%M:%S")] Cromite webview is arm64 only, arch is: $ARCH" >>$LOG
		ui_print "  Cromite only publishes an arm64 WebView."
		ui_print "  Your architecture is $ARCH."
		clean_up 1
	fi
	local asset_name="arm64_SystemWebView.apk"
	VW_APK_URL=https://github.com/uazo/cromite/releases/download/$(get_version_github "uazo/cromite" "$asset_name")/$asset_name
	VW_TRICHROME_APK_URL=""
	VW_SHA=""
	VW_SYSTEM_PATH="$(get_system_path_according_to_rom)/CromiteWebview"
	VW_PACKAGE="com.android.webview"
	OVERLAY_APK_FILE=""
}
download_file() {
	ui_print "  Downloading $1..."
	echo "[$(date "+%H:%M:%S")] Downloading file: $1 from source: $2" >>$LOG

	local out="$TMPDIR/$1"
	local base="--connect-timeout 15 --max-time 1800 --retry 5 --retry-delay 3 --retry-connrefused -fsSL"
	local dns_flag ok=0
	rm -f "$out"
	# Download ladder: direct DNS to a public resolver first (bionic's
	# getaddrinfo goes through netd's dnsproxyd, which refuses non-app UIDs),
	# then DoH over TCP:443, then the system resolver. Per-attempt flags,
	# because $CURL_BIN carries no alias any more. --retry-all-errors is
	# deliberately absent: it would retry a 404.
	for dns_flag in "--dns-servers 1.1.1.1,1.0.0.1" "--doh-url https://1.1.1.1/dns-query" ""; do
		# Test curl's exit status, not the output file: an interrupted transfer
		# leaves a partial file behind, and both -f and -s accept it.
		if "$CURL_BIN" $base $dns_flag "$2" -o "$out"; then
			ok=1
			break
		fi
		rm -f "$out"
	done
	if [[ $ok -ne 1 ]]; then
		echo "[$(date "+%H:%M:%S")] Download failed" >>$LOG
		ui_print ""
		ui_print "  !!! Download failed !!!"
		ui_print ""
		clean_up 1
	fi

	# A finished transfer can still be a broken file: a captive portal or proxy
	# error page answers 200 with HTML, and a truncated zip has no central
	# directory. unzip -t rejects both, and needs no extra binary.
	ui_print "  Verifying download..."
	if ! unzip -t "$out" >/dev/null 2>&1; then
		rm -f "$out"
		echo "[$(date "+%H:%M:%S")] Downloaded file is not a valid zip" >>$LOG
		ui_print ""
		ui_print "  !!! Downloaded file is not a valid APK !!!"
		ui_print ""
		clean_up 1
	fi
	echo "[$(date "+%H:%M:%S")] File downloaded: $out" >>$LOG
}
check_integrity() {
	if [ -f "/sbin/sha256sum" ]; then
		echo "[$(date "+%H:%M:%S")] SHA256SUM calculated with magisk lib" >>$LOG
		SHA_FILE_CALCULATED=$(/sbin/sha256sum $1 | cut -d' ' -f1)
	else
		echo "[$(date "+%H:%M:%S")] SHA256SUM calculated with system native lib" >>$LOG
		SHA_FILE_CALCULATED=$(sha256sum $1 | cut -d' ' -f1)
	fi
	
	echo "[$(date "+%H:%M:%S")] SHA256SUM calculated: $SHA_FILE_CALCULATED" >>$LOG
	echo "[$(date "+%H:%M:%S")] SHA256SUM from file: $2" >>$LOG

	if [[ $SHA_FILE_CALCULATED = $2 ]]; then
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
	code_path=${code_path##*=}
	# A codePath under /data/app is a user-installed update. Magisk mounts only
	# system/, vendor/, product/ and system_ext/, so a .replace there is inert;
	# the update has to be uninstalled first, then codePath re-read — the package
	# reverts to its factory (system) copy.
	if [[ "$code_path" == /data/app/* ]]; then
		echo "[$(date "+%H:%M:%S")] $VW_PACKAGE has an update in $code_path; uninstalling the update" >>$LOG
		ui_print "  Removing the installed update of $VW_PACKAGE..."
		pm uninstall "$VW_PACKAGE" >/dev/null 2>&1
		code_path=$(cmd package dump "$VW_PACKAGE" 2>/dev/null | grep codePath | head -n 1)
		code_path=${code_path##*=}
	fi
	[[ -z $code_path ]] && return
	echo "[$(date "+%H:%M:%S")] Webview replaced: $code_path" >>$LOG
	ui_print "  Replacing stock $VW_PACKAGE at $code_path"
	mktouch "$MODPATH"$code_path/.replace
}
extract_lib() {
	echo "[$(date "+%H:%M:%S")] Extracting lib from downloaded webview as zip" >>$LOG
	mkdir -p "$MODPATH"/$VW_SYSTEM_PATH/lib/arm64 "$MODPATH"/$VW_SYSTEM_PATH/lib/arm
	echo "[$(date "+%H:%M:%S")] Copying from $TMPDIR/webview/lib/arm64-v8a/ to $MODPATH/$VW_SYSTEM_PATH/lib/arm64" >>$LOG
	cp -rf "$TMPDIR"/webview/lib/arm64-v8a/* "$MODPATH"/$VW_SYSTEM_PATH/lib/arm64
	echo "[$(date "+%H:%M:%S")] Copying from $TMPDIR/webview/lib/armeabi-v7a/ to $MODPATH/$VW_SYSTEM_PATH/lib/arm" >>$LOG
	cp -rf "$TMPDIR"/webview/lib/armeabi-v7a/* "$MODPATH"/$VW_SYSTEM_PATH/lib/arm
}
copy_webview_file() {
	echo "[$(date "+%H:%M:%S")] Copy webview.apk from: $TMPDIR  -  to: $VW_SYSTEM_PATH" >>$LOG
	cp_ch "$TMPDIR"/webview.apk "$MODPATH"/$VW_SYSTEM_PATH/webview.apk
	cp_ch "$TMPDIR"/webview.apk "$TMPDIR"/webview.zip
}
install_webview() {
	echo "[$(date "+%H:%M:%S")] Install webview" >>$LOG
	ui_print "  Installing webview..."
	mktouch "$MODPATH"/$VW_SYSTEM_PATH/.replace
	copy_webview_file
	if [[ -f "$TMPDIR"/trichrome.apk ]]; then
		su -c pm install --install-location 1 "$TMPDIR"/trichrome.apk >&2
	fi
	mkdir -p "$TMPDIR"/webview
	unzip -qo "$TMPDIR"/webview.zip -d "$TMPDIR"/webview >&2
	extract_lib
}
download_install_webview() {
	download_file webview.apk $VW_APK_URL

	if [[ ! -z $VW_TRICHROME_APK_URL ]]; then
		download_file trichrome.apk $VW_TRICHROME_APK_URL
	fi

	if [[ ! -z $VW_SHA ]]; then
		ui_print "  Checking integrity..."
		check_integrity webview.apk $VW_SHA
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
		if [[ -d $real ]]; then
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
	# The old RESET/IS_REINSTALL/OVERLAY_PATH/OVERLAY_APK_FILE/VW_OVERLAY_PACKAGE
	# keys were only read by post-fs-data.sh, which no longer ships.
	echo "VW_PACKAGE=${VW_PACKAGE}" >>$CONFIG_FILE
}
clean_up() {
	if [[ $1 -eq 1 ]]; then
		echo "[$(date "+%H:%M:%S")] Abort installation" >>$LOG
		ui_print ""
		cp_ch $LOG /sdcard/
		abort "  Aborting..."
	fi

	ui_print "  Cleaning up..."
	echo "[$(date "+%H:%M:%S")] Installation success" >>$LOG
}

if [[ $API -lt 29 ]]; then
	ui_print "  Your android version is not supported"
	ui_print "  Minimum android version supported: 10"
	clean_up 1
fi

echo "# open-webview v2.5.2" > $LOG
echo -e "# Author: @f3ffo (Github)\n" >>$LOG
echo "[$(date "+%H:%M:%S")] Brand: $(getprop ro.product.system.brand)" >>$LOG
echo "[$(date "+%H:%M:%S")] Device: $(getprop ro.product.system.device)" >>$LOG
echo "[$(date "+%H:%M:%S")] Manufacter: $(getprop ro.product.system.manufacter)" >>$LOG
echo "[$(date "+%H:%M:%S")] Model: $(getprop ro.product.system.model)" >>$LOG
echo "[$(date "+%H:%M:%S")] Arch: $ARCH" >>$LOG
echo "[$(date "+%H:%M:%S")] System name: $(getprop ro.product.system.name)" >>$LOG
echo -e "[$(date "+%H:%M:%S")] Android Version: $(getprop ro.system.build.version.release)\n" >>$LOG

if [[ ! $BOOTMODE ]]; then
	echo "[$(date "+%H:%M:%S")] Install through recovery NOT supported!" >>$LOG
	ui_print "  Installing through recovery NOT supported!"
	ui_print "  Install this module via Magisk Manager"
	clean_up 1
fi

ui_print "  Choose between:"
if [[ $IS64BIT ]]; then
	if [[ $API -ge 29 ]] && [[ $API -lt 33 ]]; then
		ui_print "    Cromite"
	elif [[ $API -ge 33 ]]; then
		ui_print "    Vanadium, Cromite"
	fi
fi
sleep 3
ui_print ""
ui_print "  Select: [Vol+ = yes, Vol- = no]"


if [[ $IS64BIT ]]; then
	if [[ $API -ge 33 ]] && [[ $SKIP_INSTALLATION -eq 1 ]]; then
		SKIP_INSTALLATION=0
		ui_print "  -> Vanadium"
		if chooseport 3; then
			if [[ $ARCH = "arm64" ]]; then
				echo "[$(date "+%H:%M:%S")] Select vanadium for arm64" >>$LOG
				vanadium "arm64-multilib"
			else
				echo "[$(date "+%H:%M:%S")] Select vanadium for x86_64" >>$LOG
				vanadium "x86_64"
			fi
		else
			SKIP_INSTALLATION=1
		fi
	fi
	if [[ $API -ge 29 ]] && [[ $SKIP_INSTALLATION -eq 1 ]]; then
		SKIP_INSTALLATION=0
		ui_print "  -> Cromite"
		if chooseport 3; then
			echo "[$(date "+%H:%M:%S")] Select cromite" >>$LOG
			cromite
		else
			SKIP_INSTALLATION=1
		fi
	fi
fi

if [[ $SKIP_INSTALLATION -eq 1 ]]; then
	echo "[$(date "+%H:%M:%S")] No webview selected" >>$LOG
	abort "No webview selected!"
fi

if [[ -f $CONFIG_FILE ]]; then
	echo "[$(date "+%H:%M:%S")] Remove old config file" >>$LOG
	rm -rf $CONFIG_FILE
fi

# Probe the overlay path before the download: it reads the filesystem only,
# and a missing overlay directory must not cost the whole download.
if [[ ! -z $OVERLAY_APK_FILE ]]; then
	find_overlay_path
fi

if [[ $IS_MINIMAL_INSTALLATION -eq 0 ]]; then
	ui_print "  CPU architecture: ${ARCH}"
	download_install_webview
fi

# Only install the overlay if the webview supports it
if [[ ! -z $OVERLAY_APK_FILE ]]; then
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

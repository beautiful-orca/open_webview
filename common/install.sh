#!/system/bin/sh
# To get the latest Vanadium version change ANDROID_VANADIUM_VERSION to the current version of https://gitlab.com/grapheneos/platform_external_vanadium
# Check the URL of the prebuilt folder, eg. https://gitlab.com/grapheneos/platform_external_vanadium/-/tree/16-qpr2/prebuilt?ref_type=heads, 16-qpr2 is latest version
ANDROID_VANADIUM_VERSION=17
OVERLAY_APK_FILE="WebviewOverlay.apk"
CONFIG_FILE="$MODPATH"/.webview
LOG="$MODPATH"/webview.log
# Downloads go to /data, not $TMPDIR: Magisk sets TMPDIR=/dev/tmp, a tmpfs,
# so downloading there costs RAM (~843 MB peak with the old extra copies).
DL_DIR=/data/local/tmp/open_webview
IS_MINIMAL_INSTALLATION=0

# id | label | min_api | arch:variant ...
# Order is the menu order; the first entry is the default when nobody answers.
# Keys are $ARCH after the x64->x86_64 normalisation in customize.sh, i.e. ABI
# names. The variant is provider-specific: Vanadium's is a prebuilt directory,
# Cromite's is a release asset filename.
PROVIDERS='
vanadium|Vanadium|29|arm64:arm64-multilib x86_64:x86_64
cromite|Cromite|29|arm64:arm64_SystemWebView.apk
'
MENU_TIMEOUT=15

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
	# Read only the JSON prefix that holds the hash: the files API returns the
	# whole file base64-encoded (374 MB for a 281 MB APK), and content_sha256
	# sits at byte ~130, so 4 KB is ample headroom. The old
	# grep 'content_sha256:' never matched — the JSON is
	# "content_sha256":"…", with a quote before the colon.
	"$CURL_BIN" -fsSL --connect-timeout 15 --max-time 60 --retry 3 --retry-delay 3 \
		"https://gitlab.com/api/v4/projects/$1/repository/files/$2" 2>/dev/null |
		head -c 4096 |
		grep -o '"content_sha256":"[a-f0-9]*' | cut -d'"' -f4
}
# Prints "id|label|variant" for every provider this device can run, in registry order.
available_providers() {
	local id label min_api variants v
	while IFS='|' read -r id label min_api variants; do
		[ -z "$id" ] && continue
		[[ $API -ge $min_api ]] || continue
		for v in $variants; do
			case $v in
			"$ARCH":*) echo "$id|$label|${v#*:}" ;;
			esac
		done
	done <<EOF
$PROVIDERS
EOF
}

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
	if [[ $ARCH = "arm64" ]]; then
		prebuilt=$(vanadium_abi)
	fi
	VW_VARIANT=$prebuilt
	VW_APK_URL=https://gitlab.com/api/v4/projects/40905333/repository/files/prebuilt%2F${prebuilt}%2FVanadiumWebView.apk/raw?ref=${ANDROID_VANADIUM_VERSION}
	VW_TRICHROME_APK_URL=""
	VW_SHA=$(get_sha_gitlab "40905333" "prebuilt%2F${prebuilt}%2FVanadiumWebView.apk?ref=${ANDROID_VANADIUM_VERSION}")
	if [[ -z $VW_SHA ]]; then
		echo "[$(date "+%H:%M:%S")] No content_sha256 for prebuilt/${prebuilt}/VanadiumWebView.apk" >>$LOG
		ui_print "  Could not fetch the Vanadium checksum."
		ui_print "  Refusing to install an unverified WebView."
		clean_up 1
	fi
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
	if [[ -z $asset_name ]]; then
		echo "[$(date "+%H:%M:%S")] cromite called without an asset name" >>$LOG
		ui_print "  Internal error: no Cromite asset for this device."
		clean_up 1
	fi
	VW_APK_URL=https://github.com/uazo/cromite/releases/download/$(get_version_github "uazo/cromite" "$asset_name")/$asset_name
	VW_TRICHROME_APK_URL=""
	VW_SHA=""
	VW_SYSTEM_PATH=system/app/CromiteWebview
	VW_PACKAGE="com.android.webview"
	OVERLAY_APK_FILE=""
}
# Print to the installer console and to webview.log in one call, so the two
# cannot drift. Every value the install resolves goes through here.
say() {
	ui_print "  $1"
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
	[[ -n $VW_TRICHROME_APK_URL ]] && say "Library:      $VW_TRICHROME_APK_URL"
	say "Saved to:     $dest/webview.apk"
	say "Installs to:  $VW_SYSTEM_PATH/webview.apk"
	if [[ -n $OVERLAY_APK_FILE ]]; then
		say "Overlay:      ${OVERLAY_PATH:-(resolved after download)/}$OVERLAY_APK_FILE"
	else
		say "Overlay:      none"
	fi
	say "Checksum:     ${VW_SHA:-not verified}"
}

download_file() {
	ui_print "  Downloading $1..."
	echo "[$(date "+%H:%M:%S")] Downloading file: $1 from source: $2" >>$LOG

	local out="$DL_DIR/$1"
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
	# system_server has to be able to open the APK (pm install reads it).
	chmod 0644 "$out"
	echo "[$(date "+%H:%M:%S")] File downloaded: $out" >>$LOG
}
# sha256sum is a busybox applet, so it is on PATH in the installer under Magisk,
# KernelSU and APatch. /sbin only exists up to Android 10: from Android 11 Magisk
# mounts its tmpfs at /debug_ramdisk, so the old /sbin probe always missed.
sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1"
	elif [ -x "$MAGISKTMP/busybox" ]; then
		"$MAGISKTMP/busybox" sha256sum "$1"
	else
		return 1
	fi
}
check_integrity() {
	local file=$1 expected=$2 calculated

	if [[ ! -f $file ]]; then
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
	if [[ ${#expected} -ne 64 ]]; then
		echo "[$(date "+%H:%M:%S")] Integrity: hash is ${#expected} chars" >>$LOG
		ui_print "  Integrity check failed: no usable checksum"
		clean_up 1
	fi

	calculated=$(sha256_of "$file" | cut -d' ' -f1)
	if [[ -z $calculated ]]; then
		echo "[$(date "+%H:%M:%S")] Integrity: cannot compute sha256" >>$LOG
		ui_print "  Integrity check failed: sha256sum not found"
		clean_up 1
	fi
	echo "[$(date "+%H:%M:%S")] SHA256SUM calculated: $calculated" >>$LOG
	echo "[$(date "+%H:%M:%S")] SHA256SUM expected: $expected" >>$LOG

	if [[ $calculated = $expected ]]; then
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
	chmod 0755 "$DL_DIR"
	local avail
	avail=$(df -k /data | awk 'NR==2 {print $4}')
	if [[ ${avail:-0} -lt 400000 ]]; then
		echo "[$(date "+%H:%M:%S")] Not enough free space on /data: ${avail:-unknown} KB available, need ~400 MB" >>$LOG
		ui_print "  Not enough free space on /data: need ~400 MB."
		clean_up 1
	fi

	download_file webview.apk $VW_APK_URL

	if [[ ! -z $VW_TRICHROME_APK_URL ]]; then
		download_file trichrome.apk $VW_TRICHROME_APK_URL
	fi

	if [[ ! -z $VW_SHA ]]; then
		ui_print "  Checking integrity..."
		check_integrity "$DL_DIR/webview.apk" "$VW_SHA"
	else
		ui_print "  No checksum available, skipping integrity check"
		echo "[$(date "+%H:%M:%S")] No checksum for $VW_PACKAGE, integrity not checked" >>$LOG
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
	[ -n "$DL_DIR" ] && rm -rf "$DL_DIR" 2>/dev/null
	echo "[$(date "+%H:%M:%S")] Installation success" >>$LOG
}

if [[ $API -lt 29 ]]; then
	ui_print "  Your android version is not supported"
	ui_print "  Minimum android version supported: 10"
	clean_up 1
fi

# The header quotes module.prop instead of a literal, so it cannot go stale.
MODULE_VERSION=$(sed -n 's/^version=//p' "$MODPATH/module.prop" 2>/dev/null | head -n 1)
MODULE_VERSION_CODE=$(sed -n 's/^versionCode=//p' "$MODPATH/module.prop" 2>/dev/null | head -n 1)
echo "# open-webview ${MODULE_VERSION:-unknown} (${MODULE_VERSION_CODE:-?})" > $LOG
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

AVAILABLE=$(available_providers)
if [[ -z $AVAILABLE ]]; then
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
	if [[ $sel -eq 0 ]]; then
		confirmed=1
		break
	elif [[ $sel -eq 1 ]]; then
		index=$(( index + 1 ))
		[ $index -gt $total ] && index=1
	else
		break
	fi
done

if [[ $confirmed -ne 1 ]]; then
	ui_print ""
	ui_print "  No selection made. Default: $label"
	ui_print "    Install $label?  Vol+ = yes, Vol- = no   (${MENU_TIMEOUT}s)"
	chooseport $MENU_TIMEOUT
	if [[ $? -ne 0 ]]; then
		echo "[$(date "+%H:%M:%S")] No webview selected" >>$LOG
		abort "No webview selected!"
	fi
fi

echo "[$(date "+%H:%M:%S")] Selected $VW_PROVIDER ($VW_VARIANT) for $ARCH" >>$LOG
"$VW_PROVIDER" "$VW_VARIANT"

if [[ -f $CONFIG_FILE ]]; then
	echo "[$(date "+%H:%M:%S")] Remove old config file" >>$LOG
	rm -rf $CONFIG_FILE
fi

# Probe the overlay path before the download: it reads the filesystem only,
# and a missing overlay directory must not cost the whole download.
if [[ ! -z $OVERLAY_APK_FILE ]]; then
	find_overlay_path
fi

print_install_summary

if [[ $IS_MINIMAL_INSTALLATION -eq 0 ]]; then
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

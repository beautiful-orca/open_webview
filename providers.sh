#!/system/bin/sh
# Shared provider registry and download helpers. Sourced by common/install.sh
# (install path) and action.sh (update button). Both callers set CURL_BIN
# before sourcing, and both point it at the same copy: $MODPATH/bin/curl,
# written by functions.sh before install.sh runs.
# Nothing here may read installer-only variables ($MODPATH, $LOG) or depend
# on $ARCH/$API at source time; available_providers() reads those when called.

# To get the latest Vanadium prebuilts, change ANDROID_VANADIUM_VERSION to the
# current default branch of https://gitlab.com/grapheneos/platform_external_vanadium
# (the branch shown at the top of that page, e.g. .../-/tree/<branch>/prebuilt).
# The module tracks a branch, not a tag: GrapheneOS replaces the prebuilt on it
# roughly weekly, so the hash is re-read on every install and update and nothing
# else is pinned in this repo. .github/workflows/vanadium-branch.yml opens a PR
# when the default branch moves, so this comment stays valid across bumps.
ANDROID_VANADIUM_VERSION=17
GITLAB_VANADIUM=40905333

# Cache for github_latest(): one releases/latest call per repo+asset.
GH_LATEST_KEY=""
GH_LATEST_TAG=""
GH_LATEST_SHA=""

# id | label | min_api | arch:variant ...
# Order is the menu order; the first entry is the default when nobody answers.
# Keys are $ARCH after the x64->x86_64 normalisation in customize.sh, i.e. ABI
# names. The variant is provider-specific: Vanadium's is a prebuilt directory,
# Cromite's and Thorium's are GitHub release asset filenames.
PROVIDERS='
vanadium|Vanadium|29|arm64:arm64-multilib x86_64:x86_64
cromite|Cromite|29|arm64:arm64_SystemWebView.apk
thorium|Thorium|29|arm64:SystemWebView_arm64.apk arm:SystemWebView_arm32.apk
'

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

# dl <url> <outfile> — the download ladder: direct DNS to a public resolver
# first (bionic's getaddrinfo goes through netd's dnsproxyd, which refuses
# non-app UIDs), then DoH over TCP:443, then the system resolver. Per-attempt
# flags, because $CURL_BIN carries no alias. --retry-all-errors is
# deliberately absent: it would retry a 404. Tests curl's exit status, not
# the output file: an interrupted transfer leaves a partial file behind, and
# both -f and -s accept it. Returns 0 only when an attempt succeeded.
dl() {
	local url=$1 out=$2 dns_flag
	local base="--connect-timeout 15 --max-time 1800 --retry 5 --retry-delay 3 --retry-connrefused -fsSL"
	rm -f "$out"
	for dns_flag in "--dns-servers 1.1.1.1,1.0.0.1" "--doh-url https://1.1.1.1/dns-query" ""; do
		if "$CURL_BIN" $base $dns_flag "$url" -o "$out"; then
			return 0
		fi
		rm -f "$out"
	done
	return 1
}

# sha256sum is a busybox applet, so it is on PATH in the installer under Magisk,
# KernelSU and APatch, and in the Magisk console's standalone mode. /sbin only
# exists up to Android 10: from Android 11 Magisk mounts its tmpfs at
# /debug_ramdisk, so the old /sbin probe always missed.
sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1"
	elif [ -x "$MAGISKTMP/busybox" ]; then
		"$MAGISKTMP/busybox" sha256sum "$1"
	else
		return 1
	fi
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
get_sha_gitlab_lfs() {
	"$CURL_BIN" -fsSL --connect-timeout 15 --max-time 60 --retry 3 --retry-delay 3 \
		"https://gitlab.com/api/v4/projects/$1/repository/files/$2" 2>/dev/null |
		grep 'oid sha256:' |
		cut -d":" -f2
}

# The GitHub repo a provider's release assets come from.
provider_repo() {
	case $1 in
	cromite) echo "uazo/cromite" ;;
	thorium) echo "gz83/thorium" ;;
	esac
}

# One releases/latest call returning both the tag and the asset digest, cached
# per repo+asset in GH_LATEST_*. Replaces get_version_github(), which fetched
# the whole release list just to find one tag. The name-before-digest ordering
# in GitHub's asset JSON is not contractual — the 64-hex length check is what
# turns a reordering into a loud failure instead of a silent skip.
github_latest() {
	local repo=$1 want=$2 json
	local key="$repo/$want"
	[ "$GH_LATEST_KEY" = "$key" ] && [ -n "$GH_LATEST_SHA" ] && return 0
	json=$("$CURL_BIN" -sfL --connect-timeout 15 --max-time 60 \
		"https://api.github.com/repos/$repo/releases/latest") || return 1
	GH_LATEST_TAG=$(printf '%s\n' "$json" |
		sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)
	GH_LATEST_SHA=$(printf '%s\n' "$json" | awk -v want="$want" '
		/"name": *"/ { n = $0; sub(/.*"name": *"/, "", n); sub(/".*/, "", n) }
		/"digest": *"sha256:/ {
			d = $0; sub(/.*sha256:/, "", d); sub(/".*/, "", d)
			if (n == want) { print d; exit }
		}')
	if [ ${#GH_LATEST_SHA} -eq 64 ] && [ -n "$GH_LATEST_TAG" ]; then
		GH_LATEST_KEY=$key
		return 0
	fi
	return 1
}

# Warm the upstream cache in the caller's shell. Callers resolve url/sha
# through command substitution, which forks — without this, provider_url and
# provider_sha would each pay the API call again.
provider_prefetch() {
	case $1 in
	cromite|thorium)
		github_latest "$(provider_repo "$1")" "$2" || return 1
		;;
	esac
}

# The upstream download URL for a provider's variant. Returns 1 when the
# provider is unknown or its release cannot be resolved.
provider_url() {
	local repo
	case $1 in
	vanadium)
		echo "https://gitlab.com/api/v4/projects/$GITLAB_VANADIUM/repository/files/prebuilt%2F${2}%2FVanadiumWebView.apk/raw?ref=${ANDROID_VANADIUM_VERSION}"
		;;
	cromite|thorium)
		repo=$(provider_repo "$1")
		github_latest "$repo" "$2" || return 1
		echo "https://github.com/$repo/releases/download/$GH_LATEST_TAG/$2"
		;;
	esac
}

# The upstream sha256 for a provider's variant. Empty when it cannot be read;
# callers fail closed on that rather than skipping verification.
provider_sha() {
	local repo
	case $1 in
	vanadium)
		get_sha_gitlab "$GITLAB_VANADIUM" \
			"prebuilt%2F${2}%2FVanadiumWebView.apk?ref=${ANDROID_VANADIUM_VERSION}"
		;;
	cromite|thorium)
		repo=$(provider_repo "$1")
		github_latest "$repo" "$2" || return 1
		echo "$GH_LATEST_SHA"
		;;
	esac
}

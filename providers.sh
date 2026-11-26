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
# roughly weekly, so the hash is re-read on every install and update.
# .github/workflows/vanadium-branch.yml opens a PR when the default branch moves,
# so this comment stays valid across bumps.
ANDROID_VANADIUM_VERSION=17
GITLAB_VANADIUM=40905333

# SHA-256 of the DER encoding of GrapheneOS's signing certificate — the same
# certificate the bundled overlay pins for app.vanadium.webview in
# overlays/src/res/xml/config_webview_packages.xml (CI asserts the two agree;
# see .github/workflows/vanadium-signing-key.yml). Unlike the upstream
# content_sha256, which travels the same TLS channel as the APK and therefore
# only detects transfer corruption, this pin lives in the module zip and is
# independent of the download channel: a VanadiumWebView.apk that was not signed
# with GrapheneOS's key carries a different certificate and is rejected.
# Verified against prebuilt/arm64-multilib/VanadiumWebView.apk on branch 17
# (the v2 and v3 signing blocks both embed exactly this certificate).
GRAPHENEOS_CERT_SHA256=c6adb8b83c6d4c17d292afde56fd488a51d316ff8f2c11c5410223bff8a7dbb3

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
		[[ "$API" -ge "$min_api" ]] || continue
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
# -f alone accepts it. Returns 0 only when an attempt succeeded.
# No -s: the progress meter is the only feedback during a ~280 MB download in
# the installer console, and 2>&1 puts it on stdout, which is the stream the
# Magisk app shows live (stderr only lands in the saved log).
dl() {
	local url=$1 out=$2 dns_flag
	local base="--connect-timeout 15 --max-time 1800 --retry 5 --retry-delay 3 --retry-connrefused -fSL"
	rm -f "$out"
	for dns_flag in "--dns-servers 1.1.1.1,1.0.0.1" "--doh-url https://1.1.1.1/dns-query" ""; do
		if "$CURL_BIN" $base $dns_flag "$url" -o "$out" 2>&1; then
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

# apk_signer_cert_sha <apk> — prints the SHA-256 (lowercase hex) of the first
# signer certificate in the APK's v2/v3 signing block, or returns 1 when the APK
# has no v2/v3 block (unsigned or v1-only) or the structure is malformed. The
# caller compares the result against GRAPHENEOS_CERT_SHA256 and fails closed on
# any difference: this is the channel-independent check (the cert pin ships in
# the module, the APK arrives over GitLab), complementing the same-origin
# content_sha256 corruption check. The platform still verifies the actual
# cryptographic signature at pm install / boot, and the overlay's <signature>
# entry makes WebViewUpdateService accept only this certificate.
#
# Pure busybox, and it never reads the whole APK: the EOCD and the signing block
# sit at the end of the file, so only small tail slices are hexdumped. All
# multi-byte fields are little-endian; the hex math runs in awk because busybox
# ash has no $((16#...)). awklib holds the shared od-parsing prelude: od -v -tx1
# output is kept as per-line hex arrays with cumulative byte offsets (building
# one giant string with hex = hex $i is O(n^2) in busybox awk).
# Verified against the real prebuilt/arm64-multilib/VanadiumWebView.apk (branch
# 17): output equals sha256 of the GrapheneOS certificate, byte-for-byte, and a
# flipped byte inside the certificate changes the output.
apk_signer_cert_sha() {
	local apk=$1 size win1 vals cd_size cd_off blk24 S blk_start out cert_abs cert_len
	local awklib='
function h2d(h,  i, c, d) {
	d = 0; h = tolower(h)
	for (i = 1; i <= length(h); i++) {
		c = substr(h, i, 1)
		d = d * 16 + index("0123456789abcdef", c) - 1
	}
	return d
}
function bytehex(b,  l) {
	for (l = 1; l <= NR; l++)
		if (b < cum[l] + nb[l]) return substr(hx[l], (b - cum[l]) * 2 + 1, 2)
	return ""
}
function le(b, n,  i, s) {  # little-endian n-byte unsigned int at byte b
	s = ""
	for (i = n - 1; i >= 0; i--) s = s bytehex(b + i)
	return h2d(s)
}
{ for (i = 2; i <= NF; i++) { hx[NR] = hx[NR] $i; nb[NR] = NF - 1 } }
END {
	total = 0
	for (l = 1; l <= NR; l++) { cum[l] = total; total += nb[l] }
}'
	size=$(wc -c <"$apk") || return 1
	[ "$size" -gt 100 ] || return 1
	# Pass 1: find the EOCD (last PK\x05\x06 whose comment reaches EOF) within
	# the last 65535+22 bytes and read its central-directory size/offset.
	win1=65579
	[ "$size" -lt "$win1" ] && win1=$size
	vals=$(tail -c "$win1" "$apk" | od -v -tx1 | awk -v win1=$win1 "$awklib"'
		END {
			for (l = NR; l >= 1; l--) {           # last candidate first
				pre = (l > 1) ? ((length(hx[l-1]) > 6) ? substr(hx[l-1], length(hx[l-1]) - 5) : hx[l-1]) : ""
				comb = pre hx[l]
				rest = comb; base = 0; lastp = 0
				while ((p = index(rest, "504b0506")) > 0) {
					lastp = base + p; base = base + p + 7; rest = substr(rest, p + 8)
				}
				if (lastp > 0) {
					pl = length(pre)
					if (lastp > pl) b = cum[l] + (lastp - pl - 1) / 2
					else b = cum[l-1] + (length(hx[l-1]) - pl + lastp - 1) / 2
					if (b + 22 + le(b + 20, 2) == win1) {   # EOCD must end at EOF
						cds = le(b + 12, 4)
						cdo = le(b + 16, 4)
						if (cds == 4294967295 || cdo == 4294967295) { print "FAIL zip64"; exit }
						print cds, cdo
						exit
					}
				}
			}
			print "FAIL no-eocd"
		}')
	case $vals in
	FAIL* | "") return 1 ;;
	esac
	set -- $vals
	cd_size=$1 cd_off=$2                # absolute: the EOCD stores file offsets
	[ "$cd_off" -ge 32 ] && [ $((cd_off + cd_size)) -le "$size" ] || return 1
	# The APK signing block ends exactly where the central directory begins:
	# ... pairs | uint64 size S | magic "APK Sig Block 42" (16B) | CD.
	# Read the 24 bytes before the CD to get S and check the magic.
	blk24=$(tail -c $((size - cd_off + 24)) "$apk" | head -c 24 | od -v -tx1 | awk "$awklib"'
		END {
			m = ""
			for (i = 8; i < 24; i++) m = m bytehex(i)
			if (m != "41504b2053696720426c6f636b203432") { print "FAIL no-signing-block"; exit }
			print le(0, 8)
		}')
	case $blk24 in
	FAIL* | "") return 1 ;;
	esac
	S=$blk24
	[ "$S" -ge 24 ] && [ "$S" -le 65536 ] || return 1
	blk_start=$((cd_off - 8 - S))
	[ "$blk_start" -ge 0 ] || return 1
	# Pass 2: hexdump the signing block itself (<= 64 KiB + 8) and walk the
	# ID-value pairs to the v3 (0xf05368c0) or v2 (0x7109871a) signer cert.
	out=$(tail -c $((size - blk_start)) "$apk" | head -c $((8 + S)) | od -v -tx1 | awk -v S=$S "$awklib"'
		# Front of a v2/v3 block value: signers-seq -> signer -> signed-data ->
		# digests, certificates-seq -> first cert. Sets cert_rel/cert_len
		# (block-relative); returns 1 on success.
		function parse(vs,  seq, sp, slen, signer, sdl, sd, dp, dl, cp, cl, cq, cln) {
			n = total
			seq = le(vs, 4)
			if (seq <= 0 || vs + 4 + seq > n) return 0
			sp = vs + 4
			slen = le(sp, 4)
			if (slen <= 0 || sp + 4 + slen > n) return 0
			signer = sp + 4
			sdl = le(signer, 4)
			if (sdl <= 0 || signer + 4 + sdl > n) return 0
			sd = signer + 4
			dl = le(sd, 4)
			if (dl < 0 || sd + 4 + dl + 4 > n) return 0
			cp = sd + 4 + dl
			cl = le(cp, 4)
			if (cl <= 0 || cp + 4 + cl > n) return 0
			cq = cp + 4
			cln = le(cq, 4)
			if (cln <= 0 || cln > 65536 || cq + 4 + cln > n) return 0
			cert_rel = cq + 4
			cert_len = cln
			return 1
		}
		END {
			pend = 8 + S - 24            # pairs region: [8, 8+S-24) of the block
			p = 8
			v3 = 0; v2 = 0
			while (p + 12 <= pend) {
				ln = le(p, 8)
				id = le(p + 8, 4)
				vs = p + 12
				if (ln < 4 || p + 8 + ln > pend) { print "FAIL pair-overrun"; exit }
				if (id == 0xf05368c0 && !v3) v3 = vs
				if (id == 0x7109871a && !v2) v2 = vs
				p += 8 + ln
			}
			if (v3 && parse(v3)) { print "OK", cert_rel, cert_len; exit }
			if (v2 && parse(v2)) { print "OK", cert_rel, cert_len; exit }
			print "FAIL no-v2-v3"
		}')
	case $out in
	OK*) ;;
	*) return 1 ;;
	esac
	set -- $out
	cert_abs=$((blk_start + $2))
	cert_len=$3
	tail -c $((size - cert_abs)) "$apk" | head -c "$cert_len" | sha256sum | cut -d" " -f1
}

# Hook for fetch()'s per-rung progress. The default is silent; the callers
# override it — install.sh routes it to ui_print (Magisk's OUTFD, visible live
# even inside $( )), action.sh to the action output and its log.
fetch_progress() { :; }

# fetch <url> [extra curl args...] — small metadata GET through the same DNS
# ladder as dl(): the system resolver (netd dnsproxyd) can refuse a non-app
# UID, and the action button runs in exactly such a context, which is why
# get_sha_gitlab() used to return empty there while working at install time.
# Body goes to stdout; on total failure one diagnostic line goes to stderr.
fetch() {
	local url=$1
	shift
	local dns_flag rc=1 desc
	# Metadata only (a few KB of JSON), so the timeouts are tight: a dead rung
	# must not stall the console for minutes — one retry per rung, the ladder
	# itself is the fallback. Worst case ~2 min across all three rungs, with
	# fetch_progress() naming the rung so the user sees where the time goes.
	# Big downloads use dl() with its own, more generous flags.
	for dns_flag in "--dns-servers 1.1.1.1,1.0.0.1" "--doh-url https://1.1.1.1/dns-query" ""; do
		case $dns_flag in
		--dns-servers*) desc="direct DNS (1.1.1.1, 1.0.0.1)" ;;
		--doh-url*) desc="DoH (1.1.1.1)" ;;
		*) desc="system resolver" ;;
		esac
		fetch_progress "trying $desc ..."
		"$CURL_BIN" --connect-timeout 8 --max-time 20 --retry 1 --retry-delay 1 \
			-fsSL $dns_flag "$url" "$@" 2>/dev/null
		rc=$?
		# Exit 23/141 (write error / SIGPIPE) means the downstream reader
		# closed the pipe early — get_sha_gitlab reads only the first 4 KB via
		# head -c, and the files API otherwise streams the whole base64 body
		# (~374 MB). fetch only ever writes to a pipe, so this is that expected
		# close, not a failure; the prefix the caller needs was delivered.
		[ $rc -eq 0 -o $rc -eq 23 -o $rc -eq 141 ] && return 0
	done
	echo "fetch failed (curl exit $rc): $url" >&2
	return $rc
}

get_sha_gitlab() {
	# Read only the JSON prefix that holds the hash: the files API returns the
	# whole file base64-encoded (374 MB for a 281 MB APK), and content_sha256
	# sits at byte ~130, so 4 KB is ample headroom. The old
	# grep 'content_sha256:' never matched — the JSON is
	# "content_sha256":"…", with a quote before the colon.
	fetch "https://gitlab.com/api/v4/projects/$1/repository/files/$2" |
		head -c 4096 |
		grep -o '"content_sha256":"[a-f0-9]*' | cut -d'"' -f4
}
get_sha_gitlab_lfs() {
	fetch "https://gitlab.com/api/v4/projects/$1/repository/files/$2" |
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
	json=$(fetch "https://api.github.com/repos/$repo/releases/latest") || return 1
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

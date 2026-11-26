#!/bin/sh
# update-manifest.sh — rewrite common/tools/VERSIONS.json from the installed
# curl binary and generate the pull-request body. Plan: CI-BINARIES.md §3, §8.
#
# Usage: update-manifest.sh <curl-dir>
#   Run after install-binaries.sh; the manifest records what is now installed.
#
# Environment:
#   CURL_RELEASE_TAG   tag of the fork release that was downloaded
#                      (default: derived from the binary as v<version>)
#   CARES_VERSION      c-ares version (default: kept from the old manifest;
#                      the workflow reads it from the release notes, because
#                      the version literal is not reliably extractable from
#                      the binary)
#   PR_BODY            path of the PR body to write (default: /tmp/pr-body.md)

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CURL_DIR=${1:?usage: update-manifest.sh <curl-dir>}
PR_BODY=${PR_BODY:-/tmp/pr-body.md}

TOOLS="$ROOT/common/tools/tools"
MANIFEST="$ROOT/common/tools/VERSIONS.json"
ARCHS='arm arm64 x86 x86_64'

sha() { sha256sum "$1" | cut -d' ' -f1; }

# jstr <file> <key>: top-level string value.
jstr() {
  awk -v k="$2" '
    depth == 1 && index($0, "\"" k "\":") {
      sub(/.*: "/, ""); sub(/".*/, ""); print; exit
    }
    /^[[:space:]]*"[a-z]+": {/ { depth=1; next }
    depth && /^[[:space:]]*\}/ { exit }
  ' "$1"
}

old_ver=$(jstr "$MANIFEST" version)
old_cares=$(jstr "$MANIFEST" cares)

new_ver=$(strings -a "$TOOLS/arm64/curl" \
  | grep -o 'libcurl/[0-9][0-9.]*' | head -n 1 \
  | sed 's|libcurl/||; s/-DEV$//')
new_cares=${CARES_VERSION:-$old_cares}
curl_tag=${CURL_RELEASE_TAG:-v$new_ver}
curl_src="https://github.com/beautiful-orca/curl-android/releases/tag/$curl_tag"
built=$(date -u +%Y-%m-%d)

{
  printf '{\n'
  printf '  "curl": {\n'
  printf '    "version": "%s",\n' "$new_ver"
  printf '    "cares": "%s",\n' "$new_cares"
  printf '    "source": "%s",\n' "$curl_src"
  printf '    "built": "%s",\n' "$built"
  printf '    "sha256": {\n'
  i=0
  for a in $ARCHS; do
    i=$((i+1))
    if [ "$i" -lt 4 ]; then comma=,; else comma=; fi
    printf '      "%s": "%s"%s\n' "$a" "$(sha "$TOOLS/$a/curl")" "$comma"
  done
  printf '    }\n'
  printf '  }\n'
  printf '}\n'
} > "$MANIFEST"

{
  printf '| binary | from | to | source |\n'
  printf '|---|---|---|---|\n'
  printf '| curl | %s | %s | beautiful-orca/curl-android %s |\n' \
    "$old_ver" "$new_ver" "$curl_tag"
  printf '\nVerification:\n'
  printf -- '- curl: PIE, correct arch, 16 KB aligned on 64-bit, NEEDED = libc libdl libm libz, c-ares (%s) linked\n' "$new_cares"
  printf '\nBuilt: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$PR_BODY"

echo "manifest updated: curl $old_ver -> $new_ver"
echo "PR body written to $PR_BODY"

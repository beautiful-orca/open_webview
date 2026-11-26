#!/bin/sh
# verify-binaries.sh — verification gate for the update-binaries workflow.
# Plan: CI-BINARIES.md §6. Nothing is installed or committed unless every
# check passes; if any gate fails the job fails and no PR is opened.
#
# Scope: curl only. aapt2/zipsigner are deliberately not covered — PROJECT-NOTES
# §13.6 decides aapt2 comes from the SDK's build-tools on the build machine and
# §12.9 deletes the bundled aapt2/zipsigner copies, so there is nothing to keep
# current here.
#
# Usage: verify-binaries.sh <curl-dir>
#   <curl-dir>  directory with curl-<abi> files and SHA256SUMS, as published
#               by beautiful-orca/curl-android
#
# ABI mapping: arm64-v8a <-> arm64, armeabi-v7a <-> arm, x86 <-> x86,
# x86_64 <-> x86_64. riscv64 has no directory in this repo and is not gated.

set -u

fail() { echo "FAIL: $*" >&2; exit 1; }

CURL_DIR=${1:?usage: verify-binaries.sh <curl-dir>}
ABIS='arm64-v8a armeabi-v7a x86 x86_64'

check_elf() { # $1 = file, $2 = abi
  f=$1; abi=$2
  file "$f" | grep -q 'pie executable' || fail "$f is not a PIE executable"
  case "$abi" in
    arm64-v8a|x86_64)
      readelf -lW "$f" | awk '/LOAD/{print $NF}' | sort -u | grep -qx '0x4000' \
        || fail "$f is not 16 KB aligned" ;;
  esac
}

check_arch() { # $1 = file, $2 = abi
  f=$1; abi=$2
  case "$abi" in
    arm64-v8a)    want='AArch64' ;;
    armeabi-v7a)  want='ARM' ;;
    x86)          want='Intel 80386' ;;
    x86_64)       want='Advanced Micro Devices X86-64' ;;
  esac
  readelf -hW "$f" | grep -q "Machine:.*$want" \
    || fail "$f is not $want ($abi)"
}

echo "== curl =="
for abi in $ABIS; do
  f="$CURL_DIR/curl-$abi"
  [ -f "$f" ] || fail "missing $f"
  check_elf "$f" "$abi"
  check_arch "$f" "$abi"
  need=$(readelf -dW "$f" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p' | sort | tr '\n' ' ')
  [ "$need" = 'libc.so libdl.so libm.so libz.so ' ] \
    || fail "$f NEEDED is '$need', expected only platform libs"
  # The only reliable proof the resolver is c-ares: the 'c-ares/%s' format
  # string is present exactly when c-ares is linked. curl --version's
  # AsynchDNS flag is set by both backends and tells you nothing.
  strings -a "$f" | grep -q 'c-ares/' \
    || fail "$f has no c-ares; --dns-servers will not work"
  echo "ok: curl-$abi"
done
[ -f "$CURL_DIR/SHA256SUMS" ] || fail "missing $CURL_DIR/SHA256SUMS"
(cd "$CURL_DIR" && sha256sum -c SHA256SUMS) || fail "SHA256SUMS check failed"

echo "all gates passed"

#!/bin/sh
# install-binaries.sh — copy verified curl artifacts into common/tools/.
# Pipeline: common/tools/README.md. Run after verify-binaries.sh has passed.
#
# Usage: install-binaries.sh <curl-dir>
#
# Maps upstream ABI names to this repo's tool directories:
#   arm64-v8a -> arm64, armeabi-v7a -> arm, x86 -> x86, x86_64 -> x86_64.
# riscv64 has no directory here and is skipped. The raw tools/ tree is a gitignored
# local artifact; this script also repacks it into common/tools/tools.tar.xz, which
# is the committed form (repo-size hygiene, PROJECT-NOTES §4.3f) and what
# create-module.sh ships in the module zip.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CURL_DIR=${1:?usage: install-binaries.sh <curl-dir>}
TOOLS="$ROOT/common/tools/tools"

archs=
for abi in arm64-v8a armeabi-v7a x86 x86_64; do
  case "$abi" in
    arm64-v8a)   arch=arm64 ;;
    armeabi-v7a) arch=arm ;;
    x86)         arch=x86 ;;
    x86_64)      arch=x86_64 ;;
  esac
  install -m 0755 "$CURL_DIR/curl-$abi" "$TOOLS/$arch/curl"
  archs="$archs $arch"
  echo "installed $arch/curl"
done

# Pack the raw tree into the committed archive (deterministic member order and
# ownership so diffs stay minimal). The arch dirs are named explicitly — never
# pack "." itself: that stores members as "./arm64/..." while the install-time
# extraction asks for the literal member "arm64/", which tar never matches
# against a "./"-prefixed name, so nothing extracts and the curl smoke test
# fails the install.
# shellcheck disable=SC2086
tar -C "$TOOLS" --sort=name --owner=0 --group=0 --numeric-owner -cf - $archs \
    | xz -9 -T0 -c > "$ROOT/common/tools/tools.tar.xz"
echo "packed $ROOT/common/tools/tools.tar.xz"

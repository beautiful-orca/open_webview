#!/bin/sh
# install-binaries.sh — copy verified curl artifacts into common/tools/.
# Plan: CI-BINARIES.md §5. Run after verify-binaries.sh has passed.
#
# Usage: install-binaries.sh <curl-dir>
#
# Maps upstream ABI names to this repo's tool directories:
#   arm64-v8a -> arm64, armeabi-v7a -> arm, x86 -> x86, x86_64 -> x86_64.
# riscv64 has no directory here and is skipped. common/tools/tools.tar.xz is a
# packaging artifact (gitignored, rebuilt by create-module.sh), so it is not
# regenerated here.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CURL_DIR=${1:?usage: install-binaries.sh <curl-dir>}
TOOLS="$ROOT/common/tools/tools"

for abi in arm64-v8a armeabi-v7a x86 x86_64; do
  case "$abi" in
    arm64-v8a)   arch=arm64 ;;
    armeabi-v7a) arch=arm ;;
    x86)         arch=x86 ;;
    x86_64)      arch=x86_64 ;;
  esac
  install -m 0755 "$CURL_DIR/curl-$abi" "$TOOLS/$arch/curl"
  echo "installed $arch/curl"
done

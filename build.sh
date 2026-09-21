#!/bin/sh
set -eu
cd "$(dirname "$0")"
: "${THEOS:?Set THEOS to a current Theos installation}"
xcrun --sdk iphoneos --show-sdk-path >/dev/null
MAKE=${MAKE:-make}
"$MAKE" clean
"$MAKE" package FINALPACKAGE=1 "$@"

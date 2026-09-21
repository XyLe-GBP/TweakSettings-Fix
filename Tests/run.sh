#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
: "${THEOS:?Set THEOS to your Theos directory}"
mkdir -p build/tests
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation Tests/preference_support.m -o build/tests/preference_support
build/tests/preference_support
xcrun --sdk macosx clang -Wall -Wextra -Werror -I "$THEOS/vendor/include/libroot" Tests/utility.c -o build/tests/utility
build/tests/utility 2>build/tests/utility-expected-errors.log
sh -n build.sh layout/DEBIAN/postinst layout/DEBIAN/postrm
python3 Tests/validate_resources.py

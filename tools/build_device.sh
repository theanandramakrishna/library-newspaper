#!/bin/bash
#
# Build the app for the legacy iPad (iPad3,1 / iOS 9.3.5 / armv7) and install it.
#
# Requires an older Xcode that still supports armv7 and iOS 9:
#   - macOS 11 Big Sur  + Xcode 12.5.1
#   - macOS 12 Monterey + Xcode 13.2.1
#
# Usage:
#   tools/build_device.sh                # build + install
#   tools/build_device.sh --build-only   # build the .ipa and stop
#
# Signing: set DEVELOPMENT_TEAM if the project has no team configured, e.g.
#   DEVELOPMENT_TEAM=ABCDE12345 tools/build_device.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_ONLY=0
if [ "${1:-}" = "--build-only" ]; then
    BUILD_ONLY=1
fi

INSTALLER="/tmp/legacy-ios-kit/bin/macos/ideviceinstaller"
if [ ! -x "$INSTALLER" ]; then
    INSTALLER="$(command -v ideviceinstaller || true)"
fi

echo "==> Building for armv7 / iOS 9.3"
xcodebuild -project LibraryNewspaper.xcodeproj \
    -target LibraryNewspaper \
    -sdk iphoneos \
    -configuration Release \
    IPHONEOS_DEPLOYMENT_TARGET=9.3 \
    ARCHS=armv7 \
    VALID_ARCHS=armv7 \
    ONLY_ACTIVE_ARCH=NO \
    ${DEVELOPMENT_TEAM:+DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"} \
    build

APP="build/Release-iphoneos/LibraryNewspaper.app"
if [ ! -d "$APP" ]; then
    echo "Build did not produce $APP" >&2
    exit 1
fi

echo "==> Packaging IPA"
rm -rf build/Payload build/LibraryNewspaper.ipa
mkdir -p build/Payload
cp -R "$APP" build/Payload/
(cd build && /usr/bin/zip -qry LibraryNewspaper.ipa Payload)
rm -rf build/Payload

echo "==> Built build/LibraryNewspaper.ipa"
if [ "$BUILD_ONLY" = "1" ]; then
    exit 0
fi

if [ -z "$INSTALLER" ]; then
    echo "ideviceinstaller not found at /tmp/legacy-ios-kit/bin/macos/ideviceinstaller or on PATH" >&2
    exit 1
fi

echo "==> Installing with $INSTALLER"
"$INSTALLER" -i build/LibraryNewspaper.ipa

echo "==> Done. Launch 'News Reader' on the iPad."

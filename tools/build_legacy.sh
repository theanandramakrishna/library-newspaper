#!/bin/bash
#
# Build LibraryNewspaper for the legacy iPad (iPad3,1 / iOS 9.3.5 / armv7) and,
# unless --build-only is given, install it with ideviceinstaller.
#
# Why Objective-C and a hand-written build:
#   Current Xcode cannot emit armv7 binaries (its SDK starts at iOS 12 and has
#   no 32-bit slices), and the Swift toolchains that still carry an armv7
#   runtime have no Swift overlays for UIKit/Foundation without the matching
#   old Xcode SDK. Objective-C only needs the SDK's headers and .tbd stubs, so
#   this script compiles the app directly with clang against a legacy SDK.
#
# Usage:
#   tools/build_legacy.sh                # build + install
#   tools/build_legacy.sh --build-only   # build build/legacy/LibraryNewspaper.ipa
#
# Environment:
#   LEGACY_SDK    path to the SDK (default: /tmp/legacy-sdks/iPhoneOS11.4.sdk)
#   INSTALLER     ideviceinstaller path (default: ideviceinstaller on PATH)
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_ONLY=0
if [ "${1:-}" = "--build-only" ]; then
    BUILD_ONLY=1
fi

SDK="${LEGACY_SDK:-/tmp/legacy-sdks/iPhoneOS11.4.sdk}"
if [ ! -d "$SDK" ]; then
    SDK="$(tools/provision_sdk.sh)"
fi
if [ ! -d "$SDK/System/Library/Frameworks/UIKit.framework" ]; then
    echo "No usable SDK at $SDK" >&2
    exit 1
fi

TARGET="armv7-apple-ios9.3"
MIN_OS="9.3"
CLANG=(xcrun --sdk iphoneos clang)
FRAMEWORKS=(-framework UIKit -framework Foundation -framework CoreGraphics -framework ImageIO -framework Security)

BUILD="build/legacy"
APP="$BUILD/Payload/LibraryNewspaper.app"

echo "==> Compiling for $TARGET with $SDK"
rm -rf "$BUILD"
mkdir -p "$BUILD/obj" "$APP"

OBJECTS=()
for source in LibraryNewspaper/*.m; do
    name="$(basename "${source%.m}")"
    object="$BUILD/obj/$name.o"
    "${CLANG[@]}" -target "$TARGET" -isysroot "$SDK" -fobjc-arc -fmodules -w \
        -O2 -DNDEBUG -I LibraryNewspaper \
        -F "$SDK/System/Library/Frameworks" \
        -c "$source" -o "$object"
    OBJECTS+=("$object")
done

echo "==> Linking"
"${CLANG[@]}" -target "$TARGET" -isysroot "$SDK" -fobjc-arc -w \
    -F "$SDK/System/Library/Frameworks" \
    "${OBJECTS[@]}" "${FRAMEWORKS[@]}" \
    -o "$APP/LibraryNewspaper"

echo "==> Assembling the app bundle"
cp LibraryNewspaper/Info.plist "$APP/Info.plist"
printf 'APPL????' > "$APP/PkgInfo"
xcrun ibtool --errors --warnings --notices \
    --module LibraryNewspaper --target-device ipad \
    --minimum-deployment-target "$MIN_OS" \
    --compile "$APP/LaunchScreen.storyboardc" \
    LibraryNewspaper/LaunchScreen.storyboard >/dev/null
plutil -convert binary1 "$APP/Info.plist"

echo "==> Signing (ad-hoc, with keychain entitlements)"
codesign -f -s - --entitlements tools/legacy-entitlements.plist "$APP"

rm -f "$BUILD/LibraryNewspaper.ipa"
(cd "$BUILD" && /usr/bin/zip -qry LibraryNewspaper.ipa Payload)

file "$APP/LibraryNewspaper"
echo "==> Built $BUILD/LibraryNewspaper.ipa"

if [ "$BUILD_ONLY" = "1" ]; then
    exit 0
fi

INSTALLER="${INSTALLER:-$(command -v ideviceinstaller || true)}"
if [ -z "$INSTALLER" ] || [ ! -x "$INSTALLER" ]; then
    echo "ideviceinstaller not found; install it with 'brew install ideviceinstaller'" >&2
    exit 1
fi

echo "==> Installing with $INSTALLER"
# ideviceinstaller 1.2.x uses subcommands; the old "-i" flag was removed.
"$INSTALLER" install "$BUILD/LibraryNewspaper.ipa"

echo "==> Done. Launch 'News Reader' on the iPad."

#!/bin/bash
#
# Provision the legacy iOS SDK used to build for the iPad 3 (armv7 / iOS 9.3).
#
# Apple no longer ships an SDK that can produce armv7 binaries in current Xcode.
# The community mirror github.com/theos/sdks keeps extracted device SDKs whose
# .tbd stubs still contain armv7 slices and whose headers are complete.
#
# Usage:
#   tools/provision_sdk.sh            # iPhoneOS11.4.sdk (default)
#   tools/provision_sdk.sh 9.3        # another version, if you need it
#
# Environment:
#   LEGACY_SDKS   where to clone the mirror (default: /tmp/legacy-sdks)
#
set -euo pipefail

VERSION="${1:-11.4}"
DEST="${LEGACY_SDKS:-/tmp/legacy-sdks}"
SDK_NAME="iPhoneOS${VERSION}.sdk"

if [ -d "$DEST/$SDK_NAME" ]; then
    echo "$DEST/$SDK_NAME"
    exit 0
fi

echo "==> Cloning theos/sdks (sparse) into $DEST" >&2
mkdir -p "$DEST"
if [ ! -d "$DEST/.git" ]; then
    git clone --filter=blob:none --no-checkout https://github.com/theos/sdks.git "$DEST" >&2
fi

cd "$DEST"
git sparse-checkout init --cone >&2
git sparse-checkout add "$SDK_NAME" >&2
git checkout >&2

if [ ! -d "$DEST/$SDK_NAME" ]; then
    echo "Could not check out $SDK_NAME" >&2
    exit 1
fi

echo "$DEST/$SDK_NAME"

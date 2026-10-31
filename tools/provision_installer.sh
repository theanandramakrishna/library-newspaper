#!/bin/bash
#
# Provision the legacy iOS installer at the path AGENTS.md expects:
#   /tmp/legacy-ios-kit/bin/macos/ideviceinstaller
#
# Homebrew builds libimobiledevice + ideviceinstaller from source on this Mac,
# which takes a few minutes. /tmp is cleared on reboot, so re-run this (or just
# the symlink step) after a restart.
#
set -euo pipefail

if ! command -v ideviceinstaller >/dev/null 2>&1; then
    echo "==> Installing ideviceinstaller with Homebrew (this compiles its deps)"
    brew install ideviceinstaller
fi

BIN="$(command -v ideviceinstaller)"
KIT="/tmp/legacy-ios-kit/bin/macos"
mkdir -p "$KIT"
ln -sf "$BIN" "$KIT/ideviceinstaller"

echo "==> $KIT/ideviceinstaller -> $BIN"
"$KIT/ideviceinstaller" --version 2>&1 | head -1

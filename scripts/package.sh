#!/usr/bin/env bash
# Builds a universal Salah.app and zips it for a GitHub release:
#   scripts/package.sh   →   build/Salah-<version>-macOS.zip
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" App/SalahMac/Info.plist)
UNIVERSAL=1 scripts/build-app.sh
ZIP="build/Salah-$VERSION-macOS.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/Salah.app "$ZIP"
echo "Packaged $ZIP"
lipo -archs build/Salah.app/Contents/MacOS/Salah

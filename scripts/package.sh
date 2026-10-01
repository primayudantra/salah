#!/usr/bin/env bash
# Builds a universal Salah.app and zips it for a GitHub release:
#   scripts/package.sh                 →   build/Salah-<version>-macOS.zip
#   TAG_SUFFIX=-beta.1 scripts/package.sh  →  build/Salah-<version>-beta.1-macOS.zip
#
# TAG_SUFFIX only renames the zip; the app's own CFBundleShortVersionString stays plain
# (e.g. "1.3.0"), matching the eventual stable release. Publish betas as a GitHub prerelease
# (`gh release create --prerelease`) with a matching git tag (e.g. v1.3.0-beta.1): the in-app
# updater only ever offers the latest non-draft, non-prerelease release, so a beta is never
# pushed to anyone automatically — people who want to try one download it from Releases.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" App/SalahMac/Info.plist)
UNIVERSAL=1 scripts/build-app.sh
ZIP="build/Salah-$VERSION${TAG_SUFFIX:-}-macOS.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/Salah.app "$ZIP"
echo "Packaged $ZIP"
lipo -archs build/Salah.app/Contents/MacOS/Salah

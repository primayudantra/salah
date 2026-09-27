#!/usr/bin/env bash
# Builds build/Salah.app from the SwiftPM targets (no Xcode project needed).
#
#   scripts/build-app.sh            # release build for this Mac's architecture, ad-hoc signed
#   UNIVERSAL=1 scripts/build-app.sh  # Apple Silicon + Intel in one app
#   SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh
#
# The CLI is bundled at Salah.app/Contents/Helpers/salah.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=${CONFIG:-release}
SIGN_IDENTITY=${SIGN_IDENTITY:--}
UNIVERSAL=${UNIVERSAL:-0}
APP=build/Salah.app

if [[ "$UNIVERSAL" == "1" ]]; then
  # Build each architecture separately and merge with lipo (works with Command Line Tools alone).
  BIN=build/universal
  mkdir -p "$BIN"
  for arch in arm64 x86_64; do
    for product in SalahMac salah; do
      swift build -c "$CONFIG" --product "$product" --triple "$arch-apple-macosx14.0" --scratch-path ".build/$arch"
    done
  done
  for product in SalahMac salah; do
    lipo -create -output "$BIN/$product" \
      ".build/arm64/$CONFIG/$product" ".build/x86_64/$CONFIG/$product" 2>/dev/null \
    || lipo -create -output "$BIN/$product" \
      ".build/arm64/arm64-apple-macosx/$CONFIG/$product" ".build/x86_64/x86_64-apple-macosx/$CONFIG/$product"
  done
else
  swift build -c "$CONFIG" --product SalahMac
  swift build -c "$CONFIG" --product salah
  BIN=$(swift build -c "$CONFIG" --show-bin-path)
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp App/SalahMac/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/SalahMac" "$APP/Contents/MacOS/Salah"
cp "$BIN/salah" "$APP/Contents/Helpers/salah"
cp -R App/SalahMac/Resources/Fonts "$APP/Contents/Resources/Fonts"
cp App/SalahMac/Resources/Sounds/*.caf "$APP/Contents/Resources/"
cp App/SalahMac/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

SIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  SIGN_ARGS+=(--options runtime --timestamp)
fi
codesign "${SIGN_ARGS[@]}" "$APP/Contents/Helpers/salah"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"

echo "Built $APP"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "Ad-hoc signed. For distribution, set SIGN_IDENTITY to a Developer ID and notarize (see README)."
fi

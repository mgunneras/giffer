#!/bin/bash
# Builds build/Giffer.app (universal) with ffmpeg bundled, plus build/Giffer.zip for sharing.
# Run ./build-ffmpeg.sh once first. "./build.sh install" also copies the app to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Giffer.app
rm -rf "$APP" build/Giffer.zip
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos14 Sources/*.swift -o "build/Giffer-$arch"
done
lipo -create build/Giffer-arm64 build/Giffer-x86_64 -output "$APP/Contents/MacOS/Giffer"
rm build/Giffer-arm64 build/Giffer-x86_64
cp Info.plist "$APP/Contents/Info.plist"

if [ -x vendor/ffmpeg/ffmpeg ]; then
  cp vendor/ffmpeg/ffmpeg vendor/ffmpeg/ffprobe "$APP/Contents/Helpers/"
  cp -R vendor/ffmpeg/licenses "$APP/Contents/Resources/licenses"
  cp vendor/ffmpeg/VERSION "$APP/Contents/Resources/bundled-versions.txt"
else
  echo "warning: vendor/ffmpeg missing, the app will need a system ffmpeg (run ./build-ffmpeg.sh)" >&2
fi

if [ ! -f build/AppIcon.icns ] || [ make-icon.swift -nt build/AppIcon.icns ]; then
  swift make-icon.swift build/icon.png
  SET=build/AppIcon.iconset
  rm -rf "$SET" && mkdir -p "$SET"
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon.png --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) build/icon.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp build/icon.png "$APP/Contents/Resources/Artwork.png"      # square artwork, shown in the About window
mkdir -p "$APP/Contents/Resources/licenses"
cp assets/fonts/Jost-OFL.txt "$APP/Contents/Resources/licenses/Jost-OFL.txt"

# Ad-hoc signature. Set SIGN_ID to a "Developer ID Application: ..." identity for a shareable, notarisable build.
SIGN_ID="${SIGN_ID:--}"
for helper in "$APP"/Contents/Helpers/*; do
  [ -e "$helper" ] && codesign --force --options runtime --sign "$SIGN_ID" "$helper"
done
codesign --force --options runtime --sign "$SIGN_ID" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP ($(du -sh "$APP" | cut -f1))"

ditto -c -k --keepParent "$APP" build/Giffer.zip
echo "Packaged build/Giffer.zip ($(du -h build/Giffer.zip | cut -f1))"

if [ "${1:-}" = "install" ]; then
  rm -rf /Applications/Giffer.app
  cp -R "$APP" /Applications/Giffer.app
  echo "Installed /Applications/Giffer.app"
fi

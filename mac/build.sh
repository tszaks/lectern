#!/bin/bash
# Builds dist/Lectern.app (runs on Intel and Apple-chip Macs, macOS 12 or newer)
# and dist/Lectern.zip to send to another Mac.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=dist/Lectern.app
rm -rf "$APP" dist/Lectern.zip
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SDK=$(xcrun --show-sdk-path --sdk macosx)
for arch in x86_64 arm64; do
  xcrun swiftc -O -swift-version 5 -sdk "$SDK" -target "$arch-apple-macos12.0" \
    -framework AppKit -framework WebKit -framework Network \
    mac/Sources/*.swift -o "dist/Lectern-$arch"
done
lipo -create dist/Lectern-x86_64 dist/Lectern-arm64 -output "$APP/Contents/MacOS/Lectern"
rm dist/Lectern-x86_64 dist/Lectern-arm64

cp mac/Info.plist "$APP/Contents/"
cp -R app "$APP/Contents/Resources/app"          # the same web pages the Node version uses
cp mac/shortcuts/*.shortcut "$APP/Contents/Resources/"
chmod 644 "$APP/Contents/Resources/"*.shortcut
cp mac/Lectern.icns "$APP/Contents/Resources/"

codesign --force --deep --sign - "$APP"           # "ad-hoc" signature (no Apple developer account)
ditto -c -k --keepParent "$APP" dist/Lectern.zip
lipo -info "$APP/Contents/MacOS/Lectern"
du -sh "$APP" dist/Lectern.zip

#!/bin/bash
# Makes mac/Lectern.icns from make-icon.swift (all sizes from 16 to 1024).
set -euo pipefail
cd "$(dirname "$0")"
TMP=$(mktemp -d)
xcrun swift make-icon.swift "$TMP/icon-1024.png"
SET="$TMP/Lectern.iconset"; mkdir "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon-1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon-1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o ../Lectern.icns
cp "$TMP/icon-1024.png" preview-1024.png

rm -rf "$TMP"
echo "made mac/Lectern.icns"

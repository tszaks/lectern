#!/bin/bash
# Builds Lectern, signs it with the Developer ID, has Apple notarize it, and staples the result,
# so it opens on any Mac with no "unidentified developer" warning.
# Makes dist/Lectern.app and dist/Lectern.zip (the zip is what you send to another Mac).
set -euo pipefail
cd "$(dirname "$0")/.."

# Your own signing details live outside the repo, in ~/.lectern-release.env, for example:
#   IDENTITY="Developer ID Application: Your Company (TEAMID)"
#   ASC_KEY="$HOME/path/to/AuthKey_XXXX.p8"   ASC_KEY_ID="XXXXXXXXXX"   ASC_ISSUER="xxxxxxxx-xxxx-..."
[ -f "$HOME/.lectern-release.env" ] && source "$HOME/.lectern-release.env"
: "${IDENTITY:?Set IDENTITY (your Developer ID Application certificate name) in ~/.lectern-release.env}"
: "${ASC_KEY:?Set ASC_KEY (path to your App Store Connect API key .p8) in ~/.lectern-release.env}"
: "${ASC_KEY_ID:?Set ASC_KEY_ID in ~/.lectern-release.env}"
: "${ASC_ISSUER:?Set ASC_ISSUER in ~/.lectern-release.env}"
KEY="$ASC_KEY"; KEY_ID="$ASC_KEY_ID"; ISSUER="$ASC_ISSUER"
APP=dist/Lectern.app

bash mac/build.sh

# Sign with the hardened runtime and a secure timestamp (Apple requires both for notarization).
codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# Send to Apple and wait for the answer.
rm -f dist/Lectern-notarize.zip
ditto -c -k --keepParent "$APP" dist/Lectern-notarize.zip
xcrun notarytool submit dist/Lectern-notarize.zip --key "$KEY" --key-id "$KEY_ID" --issuer "$ISSUER" --wait
rm -f dist/Lectern-notarize.zip

# Attach Apple's approval to the app, so it opens even without internet.
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"

rm -f dist/Lectern.zip
ditto -c -k --keepParent "$APP" dist/Lectern.zip
du -sh "$APP" dist/Lectern.zip

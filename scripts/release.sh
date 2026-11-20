#!/bin/bash
# Build, sign, notarize and verify both direct-download packages.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check-release.py
: "${CODESIGN_IDENTITY:?Set your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set the name of your configured notarytool keychain profile}"
[[ "$CODESIGN_IDENTITY" == 'Developer ID Application: '* ]] || { echo 'Developer ID Application signing is required.' >&2; exit 1; }
xcrun --find notarytool >/dev/null
xcrun --find stapler >/dev/null
bash scripts/test.sh
bash scripts/build.sh
app="${VOICE_SEED_BUILD_DIR:-dist}/こえのたね.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
receipts=".build/notarization/$version"
mkdir -p "$receipts"
notarize() {
    local file="$1"
    local name="$2"
    xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$receipts/$name.json"
    python3 - "$receipts/$name.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    sys.exit('Apple did not accept this notarization. See ' + sys.argv[1])
print('Notarization accepted: ' + result['id'])
PY
}
ditto -c -k --keepParent "$app" "$receipts/submission.zip"
notarize "$receipts/submission.zip" app
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict "$app"
spctl --assess --type execute --verbose=2 "$app"
bash scripts/package-app.sh
bash scripts/package-dmg.sh
dmg="dist/voice-seed-$version-macos-arm64.dmg"
codesign --force --sign "$CODESIGN_IDENTITY" --timestamp "$dmg"
notarize "$dmg" dmg
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
codesign --verify --strict "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
cp "$dmg" dist/voice-seed-macos-arm64.dmg
(
    cd dist
    shasum -a 256 "voice-seed-$version-macos-arm64.zip" voice-seed-macos-arm64.zip \
        "voice-seed-$version-macos-arm64.dmg" voice-seed-macos-arm64.dmg \
        "voice-seed-$version-source.zip" > "voice-seed-$version-SHA256SUMS.txt"
)
printf 'Signed, notarized and verified app and DMG: %s\n' "$version"

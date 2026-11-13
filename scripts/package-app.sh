#!/bin/bash
# Package the Mac app and its setup instructions.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check-release.py
app="${VOICE_SEED_BUILD_DIR:-dist}/こえのたね.app"
[[ -x "$app/Contents/MacOS/VoiceSeed" ]] || { echo 'Run bash scripts/build.sh first.' >&2; exit 1; }
cmp Resources/Info.plist "$app/Contents/Info.plist"
cmp Resources/PublicAppInfo.json "$app/Contents/Resources/PublicAppInfo.json"
codesign --verify --deep --strict "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
archive="voice-seed-${version}-macos-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/$archive"
cp "dist/$archive" dist/voice-seed-macos-arm64.zip
python3 scripts/export-source.py
(
    cd dist
    shasum -a 256 "$archive" voice-seed-macos-arm64.zip "voice-seed-${version}-source.zip" > "voice-seed-${version}-SHA256SUMS.txt"
)
printf 'Packaged app: dist/%s\n' "$archive"
echo 'Disclose the signing status and include the per-app first-open instructions when publishing.'

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="${VOICE_SEED_BUILD_DIR:-dist}"
mkdir -p .build/module-cache "$output"
bash scripts/fetch-sparkle.sh
sparkle="$PWD/.build/dependencies/sparkle-2.10.1"
app="$output/こえのたね.app"
stage=$(mktemp -d "$PWD/.build/bundle.XXXXXX")
trap 'rm -rf "$stage"' EXIT
bundle="$stage/こえのたね.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$bundle/Contents/Frameworks"
swiftc -target arm64-apple-macosx26.0 -swift-version 5 -O -parse-as-library \
    -F "$sparkle" -framework Sparkle -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' \
    -module-cache-path "$PWD/.build/module-cache" Sources/*.swift \
    -o "$bundle/Contents/MacOS/VoiceSeed"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/PublicAppInfo.json Resources/SparkleLicense.txt PRIVACY.md THIRD_PARTY_NOTICES.md "$bundle/Contents/Resources/"
ditto "$sparkle/Sparkle.framework" "$bundle/Contents/Frameworks/Sparkle.framework"
if [[ -f LICENSE ]]; then cp LICENSE "$bundle/Contents/Resources/LICENSE.txt"; fi
identity="${CODESIGN_IDENTITY:--}"
if [[ "$identity" == '-' ]]; then
    codesign --force --sign - --identifier jp.ainotane.voice-seed "$bundle"
else
    if [[ "$identity" != 'Developer ID Application: '* ]]; then
        echo 'Use an explicit Developer ID Application identity, or leave CODESIGN_IDENTITY unset for local development.' >&2
        exit 1
    fi
    codesign --force --deep --sign "$identity" --options runtime --timestamp "$bundle/Contents/Frameworks/Sparkle.framework"
    codesign --force --sign "$identity" --options runtime --timestamp \
        --entitlements Resources/Release.entitlements --identifier jp.ainotane.voice-seed "$bundle"
fi
codesign --verify --deep --strict "$bundle"
# Replace only this generated build after compilation and signing succeed.
if [[ -e "$app" ]]; then mv "$app" "$stage/previous.app"; fi
mv "$bundle" "$app"
printf 'Built: %s/%s\n' "$PWD" "$app"

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache dist
app="dist/こえのたね.app"
stage=$(mktemp -d "$PWD/.build/bundle.XXXXXX")
trap 'rm -rf "$stage"' EXIT
bundle="$stage/こえのたね.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
swiftc -target arm64-apple-macosx26.0 -swift-version 5 -O -parse-as-library \
    -module-cache-path "$PWD/.build/module-cache" Sources/*.swift \
    -o "$bundle/Contents/MacOS/VoiceSeed"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/AppLinks.plist PRIVACY.md THIRD_PARTY_NOTICES.md "$bundle/Contents/Resources/"
if [[ -f LICENSE ]]; then cp LICENSE "$bundle/Contents/Resources/LICENSE.txt"; fi
identity="${CODESIGN_IDENTITY:--}"
if [[ "$identity" == '-' ]]; then
    codesign --force --sign - --identifier jp.ainotane.voice-seed "$bundle"
else
    if [[ "$identity" != 'Developer ID Application: '* ]]; then
        echo 'Use an explicit Developer ID Application identity, or leave CODESIGN_IDENTITY unset for local development.' >&2
        exit 1
    fi
    codesign --force --sign "$identity" --options runtime --timestamp \
        --entitlements Resources/Release.entitlements --identifier jp.ainotane.voice-seed "$bundle"
fi
codesign --verify --deep --strict "$bundle"
# Replace only this generated build after compilation and signing succeed.
if [[ -e "$app" ]]; then mv "$app" "$stage/previous.app"; fi
mv "$bundle" "$app"
printf 'Built: %s/%s\n' "$PWD" "$app"

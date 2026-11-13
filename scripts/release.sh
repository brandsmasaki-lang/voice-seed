#!/bin/bash
# Creates a public binary only after Developer ID signing, notarization and Gatekeeper checks.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check-release.py
: "${CODESIGN_IDENTITY:?Set your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set the name of your already configured notarytool keychain profile}"
[[ "$CODESIGN_IDENTITY" == 'Developer ID Application: '* ]] || { echo 'Developer ID Application signing is required.' >&2; exit 1; }
xcrun --find notarytool >/dev/null
xcrun --find stapler >/dev/null
bash scripts/test.sh
bash scripts/build.sh
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
app='dist/こえのたね.app'
staging=$(mktemp -d "$PWD/.build/notary.XXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto -c -k --keepParent "$app" "$staging/submission.zip"
xcrun notarytool submit "$staging/submission.zip" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$staging/result.json"
python3 - "$staging/result.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    sys.exit('Notarization was not accepted. Check the submission in notarytool before releasing.')
PY
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict "$app"
spctl --assess --type execute --verbose=2 "$app"
archive="dist/voice-seed-${version}-macos-arm64.zip"
ditto -c -k --keepParent "$app" "$archive"
python3 scripts/export-source.py
(
    cd dist
    shasum -a 256 "voice-seed-${version}-macos-arm64.zip" "voice-seed-${version}-source.zip" > "voice-seed-${version}-SHA256SUMS.txt"
)
printf 'Signed, notarized and assessed: %s\n' "$archive"
echo 'Run the clean-Mac acceptance checklist in docs/RELEASING.md before publishing.'

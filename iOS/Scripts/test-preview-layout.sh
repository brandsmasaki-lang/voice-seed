#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
voice_seed_preview_device=${1:?Pass the isolated test simulator UUID}
voice_seed_layout_kind=${2:-preview}
case "$voice_seed_layout_kind" in
  preview) voice_seed_layout_sources=(Keyboard/DictationPreviewView.swift Tests/PreviewLayoutTests.swift) ;;
  correction) voice_seed_layout_sources=(Core/DictationCorrection.swift Keyboard/DictationPreviewView.swift Keyboard/CorrectionStrip.swift Tests/CorrectionLayoutTests.swift) ;;
  *) echo "Use preview or correction" >&2; exit 2 ;;
esac
voice_seed_layout_id="jp.ainotane.${voice_seed_layout_kind}-layout-qa"
voice_seed_preview_app="$PWD/.build/${voice_seed_layout_kind}-${voice_seed_preview_device}.app"
mkdir -p "$voice_seed_preview_app" .build/smoke
cat > "$voice_seed_preview_app/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>${voice_seed_layout_id}</string>
<key>CFBundleExecutable</key><string>PreviewLayoutQA</string>
<key>CFBundleName</key><string>PreviewLayoutQA</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>LSRequiresIPhoneOS</key><true/>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict><key>UIApplicationSupportsMultipleScenes</key><false/><key>UISceneConfigurations</key><dict/></dict>
</dict></plist>
PLIST
voice_seed_preview_sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator swiftc -sdk "$voice_seed_preview_sdk" -target "$(uname -m)-apple-ios26.0-simulator" -parse-as-library \
  "${voice_seed_layout_sources[@]}" -o "$voice_seed_preview_app/PreviewLayoutQA"
codesign --force --sign - "$voice_seed_preview_app"
xcrun simctl install "$voice_seed_preview_device" "$voice_seed_preview_app"
voice_seed_preview_data=$(xcrun simctl get_app_container "$voice_seed_preview_device" "$voice_seed_layout_id" data)
voice_seed_result="$voice_seed_preview_data/Documents/${voice_seed_layout_kind}-results.json"
rm -f "$voice_seed_result"
xcrun simctl launch --terminate-running-process "$voice_seed_preview_device" "$voice_seed_layout_id"
for attempt in {1..30}; do
  if [ -f "$voice_seed_result" ]; then break; fi
  sleep 1
done
voice_seed_output=".build/smoke/${voice_seed_layout_kind}-${voice_seed_preview_device}"
if [ "$voice_seed_layout_kind" = preview ]; then cp "$voice_seed_result" .build/smoke/preview-results.json; fi
cp "$voice_seed_result" "$voice_seed_output.json"
python3 - "$voice_seed_output.json" <<'PYTEST'
import json
import sys
result = json.load(open(sys.argv[1]))
assert result["passed"], result
print("PASS:", result["cases"], "layout cases")
PYTEST
xcrun simctl io "$voice_seed_preview_device" screenshot "$voice_seed_output.png"
if [ "$voice_seed_layout_kind" = preview ]; then cp "$voice_seed_output.png" .build/smoke/preview-layout.png; fi

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/smoke
xcrun simctl list runtimes -j > .build/smoke/runtimes.json
voice_seed_ci_runtime=$(python3 - <<'PY'
import json
items=json.load(open('.build/smoke/runtimes.json'))['runtimes']
options=[x for x in items if x.get('isAvailable') and x.get('platform')=='iOS' and int(x['version'].split('.')[0])>=26]
if not options:
    options=[x for x in items if x.get('isAvailable') and '.iOS-' in x['identifier'] and int(x['version'].split('.')[0])>=26]
options=[x for x in options if not x.get('supportedDeviceTypes') or any(
    d['identifier']=='com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max' for d in x['supportedDeviceTypes'])]
if not options: raise SystemExit('No iOS 26+ simulator runtime installed')
print(sorted(options,key=lambda x:tuple(map(int,x['version'].split('.'))))[-1]['identifier'])
PY
)
voice_seed_ci_device=$(xcrun simctl create VoiceSeedSyntheticCI com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max "$voice_seed_ci_runtime")
trap 'xcrun simctl shutdown "$voice_seed_ci_device" >/dev/null 2>&1 || true; xcrun simctl delete "$voice_seed_ci_device" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$voice_seed_ci_device"
xcrun simctl bootstatus "$voice_seed_ci_device" -b
xcrun simctl install "$voice_seed_ci_device" ".build/DerivedData/Build/Products/Debug-iphonesimulator/こえのたね.app"
xcrun simctl launch "$voice_seed_ci_device" jp.ainotane.voice-seed.ios --synthetic-ui
# This is an isolated simulator smoke test, not a real microphone or keyboard acceptance test.
sleep 3
xcrun simctl io "$voice_seed_ci_device" screenshot .build/smoke/initial-setup.png
xcrun simctl terminate "$voice_seed_ci_device" jp.ainotane.voice-seed.ios
xcrun simctl launch "$voice_seed_ci_device" jp.ainotane.voice-seed.ios --synthetic-ui --synthetic-keyboard-return
sleep 3
xcrun simctl io "$voice_seed_ci_device" screenshot .build/smoke/keyboard-return.png
python3 - <<PY
import json
json.dump({'simulator':'iPhone 16 Pro Max','runtime':'$voice_seed_ci_runtime','syntheticUI':True,'realMicrophoneTested':False,'physicalDeviceTested':False},open('.build/smoke/verification.json','w'),indent=2)
PY

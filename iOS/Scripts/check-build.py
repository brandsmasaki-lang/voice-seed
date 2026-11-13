#!/usr/bin/env python3
import hashlib
import plistlib
from pathlib import Path
import sys

root = Path(__file__).resolve().parent.parent
products = Path(sys.argv[1])
app = products / "こえのたね.app"
extension = app / "PlugIns/VoiceSeedKeyboard.appex"
app_info = plistlib.loads((app / "Info.plist").read_bytes())
keyboard_info = plistlib.loads((extension / "Info.plist").read_bytes())
assert (app / app_info["CFBundleExecutable"]).is_file()
assert (extension / keyboard_info["CFBundleExecutable"]).is_file()
assert app_info["CFBundleShortVersionString"] == "0.1.0"
assert keyboard_info["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.keyboard-service"
assert keyboard_info["NSExtension"]["NSExtensionAttributes"]["RequestsOpenAccess"]
assert "audio" in app_info["UIBackgroundModes"]
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
assert digest(root / "Assets.xcassets/AppIcon.appiconset/AppIcon.png") == digest(root.parent / "Resources/AppIcon1024.png")
assert digest(root / "Assets.xcassets/BrandIcon.imageset/BrandIcon.png") == digest(root.parent / "Resources/AppIcon1024.png")
assert (app / "THIRD_PARTY_NOTICES.txt").is_file()
print("iPhone simulator app, embedded keyboard, privacy metadata and unchanged PC icon: OK")

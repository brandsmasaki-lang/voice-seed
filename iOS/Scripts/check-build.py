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
assert plistlib.loads((app / "Settings.bundle/Root.plist").read_bytes())["PreferenceSpecifiers"]
assert (app / app_info["CFBundleExecutable"]).is_file()
assert (extension / keyboard_info["CFBundleExecutable"]).is_file()
assert app_info["CFBundleShortVersionString"] == keyboard_info["CFBundleShortVersionString"] == "0.2.1"
assert app_info["CFBundleVersion"] == keyboard_info["CFBundleVersion"] == "40"
assert app_info["CFBundleDisplayName"] == keyboard_info["CFBundleDisplayName"] == "オトナの音声入力 こえのたね"
assert app_info["UIDeviceFamily"] == [1, 2]
assert keyboard_info["UIDeviceFamily"] == [1, 2]
assert set(app_info["UISupportedInterfaceOrientations~ipad"]) == {
    "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
    "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"
}
assert keyboard_info["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.keyboard-service"
assert keyboard_info["NSExtension"]["NSExtensionAttributes"]["RequestsOpenAccess"]
assert "audio" in app_info["UIBackgroundModes"]
assert app_info["ITSAppUsesNonExemptEncryption"] is False
for bundle in [app, extension]:
    privacy = plistlib.loads((bundle / "PrivacyInfo.xcprivacy").read_bytes())
    reasons = {item["NSPrivacyAccessedAPIType"]: item["NSPrivacyAccessedAPITypeReasons"] for item in privacy["NSPrivacyAccessedAPITypes"]}
    assert "35F9.1" in reasons["NSPrivacyAccessedAPICategorySystemBootTime"]
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
icon = (root / "Assets.xcassets/AppIcon.appiconset/AppIcon.png").read_bytes()
assert icon[:8] == b"\x89PNG\r\n\x1a\n"
assert int.from_bytes(icon[16:20], "big") == 1024 and int.from_bytes(icon[20:24], "big") == 1024
assert icon[25] == 2, "App Store icon must be RGB without an alpha channel"
assert digest(root / "Assets.xcassets/BrandIcon.imageset/BrandIcon.png") == digest(root.parent / "Resources/AppIcon1024.png")
assert (app / "THIRD_PARTY_NOTICES.txt").is_file()
print("iPhone/iPad app, orientations, embedded keyboard, privacy metadata and opaque store icon: OK")

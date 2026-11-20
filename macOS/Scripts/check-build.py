#!/usr/bin/env python3
"""Check the signed sandboxed bundle before an App Store export."""
import hashlib
from pathlib import Path
import plistlib
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
app = Path(sys.argv[1])
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
assert info["CFBundleIdentifier"] == "jp.ainotane.koenotane.ios"
assert info["ITSAppUsesNonExemptEncryption"] is False
assert info["LSApplicationCategoryType"] == "public.app-category.productivity"
assert not any(key.startswith("SU") for key in info)
executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
symbols = subprocess.check_output(["nm", "-u", str(executable)], text=True)
for forbidden in ("AXUIElement", "AXIsProcessTrusted", "AXIsProcessTrustedWithOptions", "SPUStandardUpdaterController"):
    assert forbidden not in symbols, forbidden
libraries = subprocess.check_output(["otool", "-L", str(executable)], text=True)
assert "Sparkle.framework" not in libraries
entitlements = plistlib.loads(subprocess.check_output(["codesign", "-d", "--entitlements", ":-", str(app)], stderr=subprocess.DEVNULL))
for key in ("com.apple.security.app-sandbox", "com.apple.security.device.audio-input", "com.apple.security.files.user-selected.read-write"):
    assert entitlements[key] is True, key
assert not any("temporary-exception" in key for key in entitlements)
resources = app / "Contents/Resources"
assert hashlib.sha256((resources / "PRIVACY.md").read_bytes()).digest() == hashlib.sha256((root / "PRIVACY.md").read_bytes()).digest()
assert (resources / "LICENSE").is_file()
privacy = plistlib.loads((resources / "PrivacyInfo.xcprivacy").read_bytes())
assert privacy["NSPrivacyTracking"] is False and not privacy["NSPrivacyCollectedDataTypes"]
print("Mac App Store bundle: sandbox, permissions, privacy and no AX/Sparkle APIs: OK")

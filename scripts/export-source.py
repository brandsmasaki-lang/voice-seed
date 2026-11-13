#!/usr/bin/env python3
"""Create a clean initial GitHub import; preserve the private development repository."""
import hashlib
import importlib.util
import json
import plistlib
import sys
import zipfile
from public_source import ROOT, public_files

spec = importlib.util.spec_from_file_location("release_check", ROOT / "scripts/check-release.py")
release_check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release_check)
errors = release_check.check()
if errors:
    sys.exit("Cannot export public source:\n- " + "\n- ".join(errors))

version = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())["CFBundleShortVersionString"]
destination = ROOT / "dist" / f"voice-seed-{version}-source.zip"
destination.parent.mkdir(exist_ok=True)
files = public_files()
prefix = f"voice-seed-{version}/"
manifest = {}
with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for path in files:
        relative = path.relative_to(ROOT).as_posix()
        data = path.read_bytes()
        manifest[relative] = hashlib.sha256(data).hexdigest()
        item = zipfile.ZipInfo(prefix + relative, date_time=(2026, 1, 1, 0, 0, 0))
        item.create_system = 3
        item.external_attr = (0o100755 if path.suffix in (".sh", ".command") else 0o100644) << 16
        item.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(item, data)
    item = zipfile.ZipInfo(prefix + "SOURCE_MANIFEST.json", date_time=(2026, 1, 1, 0, 0, 0))
    item.create_system = 3
    item.external_attr = 0o100644 << 16
    archive.writestr(item, json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n")
print(f"Public source: {destination.name} ({len(files)} files; no Git history, preferences, recordings or internal QA)")

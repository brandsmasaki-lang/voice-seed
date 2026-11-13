#!/usr/bin/env python3
"""Check release metadata and the exact export inventory; does not contact any service."""
import plistlib
import json
import base64
import re
import sys
from urllib.parse import urlparse
from public_source import ROOT, public_files


def check(root=ROOT):
    errors = []
    try:
        # Validate the entire inventory before opening even the metadata files.
        files = public_files(root)
        info = plistlib.loads((root / "Resources/Info.plist").read_bytes())
        if not re.fullmatch(r"\d+\.\d+\.\d+", info.get("CFBundleShortVersionString", "")):
            errors.append("Use a major.minor.patch version in Info.plist.")
        if not re.fullmatch(r"[1-9]\d*", info.get("CFBundleVersion", "")):
            errors.append("Use a positive build number in Info.plist.")
        if info.get("LSMinimumSystemVersion") != "26.0":
            errors.append("Review compatibility documentation when changing the minimum macOS version.")
        public_info = json.loads((root / "Resources/PublicAppInfo.json").read_text())
        if public_info.get("schemaVersion") != 1:
            errors.append("Unsupported public display configuration schema.")
        links = {link["id"]: link["url"] for link in public_info["links"]}
        for key in ("Website", "X", "LINE", "GitHub", "Products"):
            value = links.get(key, "")
            url = urlparse(value)
            if (url.scheme != "https" or not url.hostname or url.username or url.password
                    or url.hostname.endswith((".example", ".invalid")) or url.hostname == "example.com"):
                errors.append(f"Set a confirmed public HTTPS URL for {key} in PublicAppInfo.json.")
            elif key == "GitHub" and (url.hostname != "github.com" or len(url.path.strip('/').split('/')) != 2):
                errors.append("GitHub must link to this app's repository, not a generic profile.")
        if info.get("SUFeedURL") != "https://ai-no-tane.com/lp/koenotane/appcast.xml":
            errors.append("Unexpected application update feed.")
        if len(base64.b64decode(info.get("SUPublicEDKey", ""), validate=True)) != 32:
            errors.append("A 32-byte public update verification key is required.")
        license_file = root / "LICENSE"
        if not license_file.is_file():
            errors.append("Choose and add the open-source LICENSE before export.")
        elif not any(text in license_file.read_text() for text in ("MIT License", "GNU GENERAL PUBLIC LICENSE")):
            errors.append("Review the selected LICENSE and update release checks for that license.")
        for path in files:
            if path.suffix.lower() in (".png", ".icns"):
                continue
            text = path.read_text(encoding="utf-8")
            if re.search(r"/" + r"Users/[^/\s]+/", text):
                errors.append(f"Local home path in public file: {path.relative_to(root)}")
            # A focused accidental-secret check, not a substitute for reviewing every exported file.
            if re.search(r"(?:ghp_|github_pat_)[A-Za-z0-9_]{30,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----", text):
                errors.append(f"Possible credential in public file: {path.relative_to(root)}")
    except (OSError, ValueError, TypeError) as exc:
        errors.append(str(exc))
    return list(dict.fromkeys(errors))


if __name__ == "__main__":
    errors = check()
    if errors:
        print("Release preparation is incomplete:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        sys.exit(1)
    print("Release metadata and public source inventory: OK (no service access)")

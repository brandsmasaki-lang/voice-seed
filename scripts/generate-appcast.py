#!/usr/bin/env python3
"""Sign the published archive using this app's Keychain key; output a public Sparkle feed."""
import base64
import email.utils
import json
from pathlib import Path
import plistlib
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
archive = ROOT / 'dist' / f'voice-seed-{version}-macos-arm64.zip'
if not archive.is_file():
    raise SystemExit('Run scripts/package-app.sh first.')
tool = ROOT / '.build/dependencies/sparkle-2.10.1/bin/sign_update'
account = 'jp.ainotane.voice-seed.updates'
signed = subprocess.run([str(tool), '--account', account, '-p', str(archive)], capture_output=True, text=True)
if signed.returncode:
    raise SystemExit('Update signing failed. Check access to the dedicated signing key in Keychain.')
signature = signed.stdout.strip()
if len(base64.b64decode(signature, validate=True)) != 64:
    raise SystemExit('Invalid update signature.')
verified = subprocess.run([str(tool), '--account', account, '--verify', str(archive), signature], capture_output=True)
if verified.returncode:
    raise SystemExit('Signature verification failed.')
sparkle = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', sparkle)
rss = ET.Element('rss', {'version': '2.0'})
channel = ET.SubElement(rss, 'channel')
ET.SubElement(channel, 'title').text = info['CFBundleDisplayName']
ET.SubElement(channel, 'link').text = 'https://ai-no-tane.com/lp/koenotane/'
ET.SubElement(channel, 'language').text = 'ja'
item = ET.SubElement(channel, 'item')
ET.SubElement(item, 'title').text = f"{info['CFBundleDisplayName']} {version}"
ET.SubElement(item, 'pubDate').text = email.utils.formatdate(usegmt=True)
ET.SubElement(item, f'{{{sparkle}}}version').text = info['CFBundleVersion']
ET.SubElement(item, f'{{{sparkle}}}shortVersionString').text = version
ET.SubElement(item, f'{{{sparkle}}}minimumSystemVersion').text = info['LSMinimumSystemVersion']
public_info = json.loads((ROOT / 'Resources/PublicAppInfo.json').read_text())
ET.SubElement(item, 'description').text = public_info['latest']['notes']
ET.SubElement(item, 'enclosure', {
    'url': f'https://github.com/brandsmasaki-lang/voice-seed/releases/download/v{version}/{archive.name}',
    'length': str(archive.stat().st_size), 'type': 'application/octet-stream',
    f'{{{sparkle}}}edSignature': signature, f'{{{sparkle}}}os': 'macos',
})
ET.indent(rss, space='  ')
destination = ROOT / 'dist/appcast.xml'
ET.ElementTree(rss).write(destination, encoding='utf-8', xml_declaration=True)
print(f'Verified update signature and generated {destination.name} for {version} (build {info["CFBundleVersion"]}).')
